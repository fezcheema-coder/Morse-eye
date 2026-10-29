"""Send a screenshot to an AI and get back a short reply.

Providers:
  claude      - Anthropic's Claude, through the official SDK
  everything else uses the "OpenAI-compatible" chat API that most providers
  offer: OpenAI, Gemini, Grok (xAI), Groq, Mistral, OpenRouter, Together,
  and local servers such as Ollama and LM Studio. Any other compatible
  service works with provider "custom" plus a base_url.
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request

from .capture import MEDIA_TYPE
from .encoder import Code

# name -> (base_url, env var holding the API key, default vision model)
# Model names change often; set "model" in config.json to whatever your provider currently offers.
PROVIDERS: dict[str, tuple[str, str, str]] = {
    "claude":     ("",                                                         "ANTHROPIC_API_KEY",  "claude-opus-5-5"),
    "openai":     ("https://api.openai.com/v1",                                "OPENAI_API_KEY",     "gpt-4o-mini"),
    "gemini":     ("https://generativelanguage.googleapis.com/v1beta/openai",  "GEMINI_API_KEY",     "gemini-2.5-flash"),
    "xai":        ("https://api.x.ai/v1",                                      "XAI_API_KEY",        "grok-4"),
    "groq":       ("https://api.groq.com/openai/v1",                           "GROQ_API_KEY",       "meta-llama/llama-4-scout-17b-16e-instruct"),
    "mistral":    ("https://api.mistral.ai/v1",                                "MISTRAL_API_KEY",    "mistral-medium-latest"),
    "openrouter": ("https://openrouter.ai/api/v1",                             "OPENROUTER_API_KEY", "openai/gpt-4o-mini"),
    "together":   ("https://api.together.xyz/v1",                              "TOGETHER_API_KEY",   "meta-llama/Llama-4-Scout-17B-16E-Instruct"),
    "ollama":     ("http://localhost:11434/v1",                                "",                   "llama3.2-vision"),
    "lmstudio":   ("http://localhost:1234/v1",                                 "",                   ""),
    "custom":     ("",                                                         "AI_API_KEY",         ""),
}


def system_prompt(code: Code, max_chars: int) -> str:
    parts = [
        "You are looking at a screenshot of the user's screen. Your reply will be "
        "blinked out on a keyboard LED, so it must be extremely short.",
        f"Reply in at most {max_chars} characters. Plain text only: no markdown, "
        "no emoji, no quotes around the answer.",
        f"Only use these characters (plus spaces): {code.allowed_chars}",
    ]
    if code.words:
        parts.append("You may also use these whole words: " + ", ".join(code.words))
    if code.ai_instructions:
        parts.append(code.ai_instructions)
    return "\n".join(parts)


def resolve(ai_cfg: dict) -> dict:
    """Merge a provider preset with the user's overrides from config.json."""
    # "backend" is the older name for "provider"
    name = ai_cfg.get("provider") or ai_cfg.get("backend") or "claude"
    if name not in PROVIDERS:
        raise ValueError(f"unknown provider {name!r}; choose one of: {', '.join(PROVIDERS)}")
    base_url, key_env, model = PROVIDERS[name]
    key_env = ai_cfg.get("api_key_env", key_env)
    resolved = {
        "provider": name,
        "base_url": ai_cfg.get("base_url") or base_url,
        # "claude_model" / "ollama_model" are older config names
        "model": ai_cfg.get("model") or ai_cfg.get(f"{name}_model") or model,
        "api_key": os.environ.get(key_env, "") if key_env else "",
        "key_env": key_env,
    }
    if not resolved["model"]:
        raise ValueError(f"set ai.model in config.json for provider {name!r}")
    if name != "claude" and not resolved["base_url"]:
        raise ValueError("set ai.base_url in config.json for the 'custom' provider")
    if key_env and not resolved["api_key"] and name != "custom":
        raise ValueError(f"no API key: put {key_env}=... in the .env file (or run install.command)")
    return resolved


def ask_claude(image: bytes, prompt: str, system: str, model: str, effort: str) -> str:
    import anthropic

    client = anthropic.Anthropic()
    response = client.beta.messages.create(
        model=model,
        max_tokens=16000,
        system=system,
        output_config={"effort": effort},
        # If a safety classifier declines, re-run on Anthropic's recommended fallback model.
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        messages=[{
            "role": "user",
            "content": [
                {"type": "image", "source": {
                    "type": "base64", "media_type": MEDIA_TYPE,
                    "data": base64.standard_b64encode(image).decode("ascii"),
                }},
                {"type": "text", "text": prompt},
            ],
        }],
    )
    if response.stop_reason == "refusal":
        return "ERROR"
    return "".join(b.text for b in response.content if b.type == "text").strip()


def _post_chat(base_url: str, api_key: str, payload: dict) -> dict:
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    req = urllib.request.Request(base_url.rstrip("/") + "/chat/completions",
                                 data=json.dumps(payload).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        raise ChatError(e.code, f"{base_url} returned HTTP {e.code}: {detail}") from None


class ChatError(RuntimeError):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


def ask_openai_compatible(image: bytes, prompt: str, system: str, base_url: str,
                          model: str, api_key: str) -> str:
    image_url = f"data:{MEDIA_TYPE};base64," + base64.standard_b64encode(image).decode("ascii")

    def payload(separate_system: bool) -> dict:
        text = prompt if separate_system else f"{system}\n\n{prompt}"
        messages = [{"role": "user", "content": [
            {"type": "text", "text": text},
            {"type": "image_url", "image_url": {"url": image_url}},
        ]}]
        if separate_system:
            messages.insert(0, {"role": "system", "content": system})
        return {"model": model, "messages": messages}

    try:
        data = _post_chat(base_url, api_key, payload(separate_system=True))
    except ChatError as e:
        # Some vision models (e.g. on Groq) reject a system message next to an image;
        # retry once with the instructions folded into the user message.
        if e.status != 400:
            raise
        data = _post_chat(base_url, api_key, payload(separate_system=False))
    content = data["choices"][0]["message"]["content"]
    if isinstance(content, list):  # some providers return content parts
        content = "".join(p.get("text", "") for p in content if isinstance(p, dict))
    return (content or "").strip()


def ask(image: bytes, prompt: str, code: Code, ai_cfg: dict) -> str:
    system = system_prompt(code, ai_cfg.get("max_chars", 40))
    p = resolve(ai_cfg)
    if p["provider"] == "claude":
        return ask_claude(image, prompt, system, p["model"], ai_cfg.get("effort", "low"))
    return ask_openai_compatible(image, prompt, system, p["base_url"], p["model"], p["api_key"])
