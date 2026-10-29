import json

import pytest

from morse_eye import ai


def test_resolve_preset(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    p = ai.resolve({"provider": "openai"})
    assert p["base_url"] == "https://api.openai.com/v1"
    assert p["api_key"] == "sk-test"
    assert p["model"]


def test_resolve_overrides_and_legacy_names(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "k")
    assert ai.resolve({"provider": "groq", "model": "my-model"})["model"] == "my-model"
    assert ai.resolve({"backend": "ollama", "ollama_model": "llava"})["model"] == "llava"


def test_missing_key_is_a_clear_error(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    with pytest.raises(ValueError, match="GEMINI_API_KEY"):
        ai.resolve({"provider": "gemini"})


def test_local_providers_need_no_key():
    assert ai.resolve({"provider": "ollama"})["api_key"] == ""


def test_custom_needs_base_url():
    with pytest.raises(ValueError, match="base_url"):
        ai.resolve({"provider": "custom", "model": "m"})


def test_openai_compatible_request(monkeypatch):
    sent = {}

    class Resp:
        def __enter__(self): return self
        def __exit__(self, *a): pass
        def read(self):
            return json.dumps({"choices": [{"message": {"content": " HELLO "}}]}).encode()

    def fake_urlopen(req, timeout):
        sent["url"] = req.full_url
        sent["auth"] = req.get_header("Authorization")
        sent["body"] = json.loads(req.data)
        return Resp()

    monkeypatch.setattr(ai.urllib.request, "urlopen", fake_urlopen)
    out = ai.ask_openai_compatible(b"png", "what?", "sys", "https://x.test/v1/", "m", "key")
    assert out == "HELLO"
    assert sent["url"] == "https://x.test/v1/chat/completions"
    assert sent["auth"] == "Bearer key"
    user = sent["body"]["messages"][1]["content"]
    assert user[1]["image_url"]["url"].startswith("data:image/jpeg;base64,")
