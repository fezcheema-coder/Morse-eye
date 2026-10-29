# Morse Eye — Python command-line version (older)

> The main app is now the native Mac app in `../MacApp`. This folder is the earlier command-line version, kept for reference.

Press a key combo and Morse Eye takes a screenshot, sends it to an AI (Claude, OpenAI,
Gemini, Grok, any OpenAI-compatible service, or a model running on your Mac), then blinks the AI's short answer on your keyboard: either the
**Caps Lock LED** or the **keyboard backlight**. Answers use Morse code or any code you define.

```
⌘⌥⇧M  →  screenshot  →  AI  →  "2 NEW EMAILS"  →  ..--- / -. . .-- / . -- .- .. .-.. ...  on Caps Lock
```

## Quick install

1. Unzip `morse-eye.zip`.
2. **Right-click `install.command` → Open**, then click **Open** again. This is needed the
   first time because the file isn't from the App Store.
3. Follow the prompts: pick your AI provider, paste its API key, watch for SOS on Caps Lock.
   Run the installer again any time to switch provider.
4. Switch on the three permissions in the System Settings windows it opens, then reopen Terminal.
5. Double-click **`Morse Eye.command`** whenever you want it running.

## Manual setup

```bash
cd morse-eye
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp config.example.json config.json
```

Then pick an AI: set `ai.provider` (and optionally `ai.model`) in `config.json`, and put the
key in a file named `.env` in the project folder (see [AI providers](#ai-providers)).

**Grant permissions.** In System Settings → Privacy & Security, allow your terminal app
(Terminal, iTerm, etc.) under:

- **Screen Recording**: needed for screenshots
- **Input Monitoring** and **Accessibility**: needed for the global hotkeys

Restart the terminal after you grant them.

## Run

```bash
python -m morse_eye
```

First, try the LED on its own (no screenshot, no AI):

```bash
python -m morse_eye --test "SOS"
python -m morse_eye --test "SOS" --device backlight
python -m morse_eye --test "SOS" --device console --wpm 8
```

Default hotkeys (change them in `config.json`):

| Keys | Action |
|---|---|
| ⌘⌥⇧M | "Briefly, what is on this screen?" |
| ⌘⌥⇧E | "Is there an error or warning visible?" |
| ⌘⌥⇧T | "What time or date is shown on screen?" |
| ⌘⌥⇧R | Replay the last answer |
| ⌘⌥⇧X | Stop blinking |

You can add as many hotkeys as you want. Each one has its own prompt. Key names follow
[pynput's format](https://pynput.readthedocs.io/en/latest/keyboard.html#global-hotkeys):
`<cmd>`, `<alt>` (Option), `<ctrl>`, `<shift>`, then letters.

Each message starts with `-.-.-` (start) and ends with `.-.-.` (end), so you can tell
when the answer begins and ends. You can remove these in the code file.

## AI providers

Set `ai.provider` in `config.json` and put the API key in `.env`, for example
`OPENAI_API_KEY=sk-...`. The installer does both for you.

| `provider` | Key in `.env` | Default model |
|---|---|---|
| `claude` | `ANTHROPIC_API_KEY` | `claude-opus-5-5` |
| `openai` | `OPENAI_API_KEY` | `gpt-4o-mini` |
| `gemini` | `GEMINI_API_KEY` | `gemini-2.5-flash` |
| `xai` (Grok) | `XAI_API_KEY` | `grok-4` |
| `groq` | `GROQ_API_KEY` | `meta-llama/llama-4-scout-17b-16e-instruct` |
| `mistral` | `MISTRAL_API_KEY` | `mistral-medium-latest` |
| `openrouter` | `OPENROUTER_API_KEY` | `openai/gpt-4o-mini` |
| `together` | `TOGETHER_API_KEY` | `meta-llama/Llama-4-Scout-17B-16E-Instruct` |
| `ollama` | none (runs on your Mac) | `llama3.2-vision` |
| `lmstudio` | none (runs on your Mac) | whatever model you load |
| `custom` | `AI_API_KEY` (optional) | set `ai.model` and `ai.base_url` |

- **The model must be able to read images** (a "vision" model), because it's sent a screenshot.
- **Model names change often.** If you get a "model not found" error, set `ai.model` to a
  current model from your provider's model list.
- **`custom`** works with any service that offers an OpenAI-compatible
  `/chat/completions` endpoint. Set `ai.base_url` to the address ending in `/v1`.
- To use a different key variable name, set `ai.api_key_env`.

Keys in your real environment variables take priority over `.env`. `.env` is created so
only your user account can read it.

## Outputs

| `output.device` | What blinks | Notes |
|---|---|---|
| `capslock` | Caps Lock LED | Works on any Mac keyboard, including external Apple keyboards. Caps Lock is really on while the LED is lit, so don't type during playback. Your original Caps Lock state is restored afterwards. |
| `backlight` | Built-in keyboard backlight | MacBooks only. Uses Apple's private CoreBrightness framework, so it may break in a future macOS. Auto-brightness is paused during playback and restored afterwards. |
| `console` | A dot in the terminal | For testing. |

Set `"invert": true` to make the LED stay on and turn off for each symbol instead.

## Custom codes

Codes are JSON files in `codes/`. Point `code.file` at the one you want and set the speed with
`code.wpm` (words per minute).

- `codes/morse.json`: standard International Morse
- `codes/simple_yes_no.json`: example custom code with short/long/hold blinks and whole-word
  signals (YES = one long blink, NO = two short blinks, ...)

To make your own, copy one of these files and edit it:

```json
{
  "symbols":    { "s": 1, "l": 4 },        // symbol → how many units the LED stays ON
  "symbol_gap": 1, "letter_gap": 4, "word_gap": 10,   // OFF units
  "table":      { "A": "sl", "B": "ls" },  // character → symbols
  "words":      { "YES": "l" },            // optional whole-word shortcuts
  "prefix": "", "suffix": "",
  "ai_instructions": "Answer only YES or NO."   // optional, added to the AI's instructions
}
```

The AI is told which characters and words your code supports, and anything it can't
represent is removed before blinking. One time unit is `1.2 / wpm` seconds.

## Trigger it without hotkeys

`python -m morse_eye --once "What's on screen?"` runs a single capture and exits. You can
connect it to the **Shortcuts** app ("Run Shell Script" action) and give it a shortcut
there, or bind it to a Stream Deck or Raycast instead of running the listener.

## Settings reference

| Key | Meaning |
|---|---|
| `ai.provider` | Which AI to use (see [AI providers](#ai-providers)) |
| `ai.model` | Model name; leave empty for the provider's default |
| `ai.base_url` | Only for `custom`, or to point a preset at a different server |
| `ai.api_key_env` | Use a different environment variable for the key |
| `ai.effort` | Claude only: `low` (fast and cheap) up to `high` (more careful) |
| `ai.max_chars` | Maximum answer length the AI is asked for. Keep it short, because Morse is slow. |
| `screenshot.display` | 1 = main display, 2 = second display, ... |
| `screenshot.max_edge` | Downscale the screenshot to this many pixels on its longest side (saves tokens) |
| `notify` | Show a macOS notification when a capture happens |
| `print_reply` | Print the answer and its Morse in the terminal |

## Tests

```bash
pip install pytest
python -m pytest
```
