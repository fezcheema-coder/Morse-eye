#!/bin/bash
# Morse Eye installer for macOS. Double-click this file in Finder.
set -e
cd "$(dirname "$0")"

echo "== Morse Eye setup =="

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))'; then
  echo "Python 3.9+ is needed. macOS will now offer to install the Command Line Tools (includes Python)."
  xcode-select --install || true
  echo "Run this installer again when that finishes."
  read -n 1 -s -r -p "Press any key to close."; exit 1
fi

echo "-> Creating Python environment..."
python3 -m venv .venv
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements.txt

[ -f config.json ] || cp config.example.json config.json

# Older installs saved a Claude key in .api_key; move it into .env
if [ -f .api_key ]; then
  printf 'ANTHROPIC_API_KEY=%s\n' "$(cat .api_key)" >> .env && rm .api_key
fi

echo
echo "Which AI do you want to use?"
echo "   1) Claude (Anthropic)       6) Mistral"
echo "   2) OpenAI (ChatGPT)         7) OpenRouter (hundreds of models, one key)"
echo "   3) Google Gemini            8) Together AI"
echo "   4) Grok (xAI)               9) Ollama (on-device, free, no key)"
echo "   5) Groq                    10) LM Studio (on-device, free, no key)"
echo "  11) Other OpenAI-compatible service (you give the URL)"
read -r -p "Choose 1-11 [1]: " choice
case "${choice:-1}" in
  1) provider=claude ;;     2) provider=openai ;;   3) provider=gemini ;;
  4) provider=xai ;;        5) provider=groq ;;     6) provider=mistral ;;
  7) provider=openrouter ;; 8) provider=together ;; 9) provider=ollama ;;
  10) provider=lmstudio ;;  11) provider=custom ;;
  *) echo "Not a valid choice, using Claude."; provider=claude ;;
esac

base_url=""
if [ "$provider" = "custom" ]; then
  read -r -p "Base URL (ending in /v1, e.g. https://api.example.com/v1): " base_url
fi

# Look up the preset's key variable and default model
read -r key_env default_model < <(.venv/bin/python -c "
from morse_eye.ai import PROVIDERS
_, env, model = PROVIDERS['$provider']
print(env or '-', model or '-')")

read -r -p "Model name [${default_model/#-/none}]: " model
[ -z "$model" ] && [ "$default_model" != "-" ] && model="$default_model"

.venv/bin/python - "$provider" "$model" "$base_url" <<'PY'
import json, sys
provider, model, base_url = sys.argv[1:]
cfg = json.load(open("config.json"))
ai = cfg.setdefault("ai", {})
for old in ("backend", "claude_model", "ollama_model", "ollama_url"):
    ai.pop(old, None)
ai.update(provider=provider, model=model, base_url=base_url)
json.dump(cfg, open("config.json", "w"), indent=2)
PY

if [ "$key_env" != "-" ]; then
  read -r -s -p "Paste your $provider API key (input hidden, Enter to keep the saved one): " key; echo
  if [ -n "$key" ]; then
    touch .env && chmod 600 .env
    grep -v "^$key_env=" .env > .env.tmp || true
    printf '%s=%s\n' "$key_env" "$key" >> .env.tmp
    mv .env.tmp .env && chmod 600 .env
    echo "Saved as $key_env in .env (only readable by you)."
  fi
fi

if [ "$provider" = "ollama" ]; then
  if command -v ollama >/dev/null 2>&1; then
    ollama pull "$model"
  else
    echo "Install Ollama from https://ollama.com/download, open it once, then run:"
    echo "   ollama pull $model"
    open "https://ollama.com/download"
  fi
elif [ "$provider" = "lmstudio" ]; then
  echo "In LM Studio: load a vision model, then start the local server (Developer tab)."
fi

echo
echo "-> Testing the Caps Lock light: you should see SOS blink now."
.venv/bin/python -m morse_eye --test "SOS" --wpm 15 || echo "(LED test failed, see message above)"

echo
echo "Last step: give Terminal these permissions in the window that opens:"
echo "  - Screen Recording   - Input Monitoring   - Accessibility"
echo "Then quit and reopen Terminal."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo
echo "Done! Double-click 'Morse Eye.command' to start it."
read -n 1 -s -r -p "Press any key to close."
