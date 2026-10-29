# Morse Eye

A Mac menu bar app. Press a shortcut and Morse Eye takes a screenshot, asks an AI about
it, then blinks the answer in Morse code (or your own code) on your **Caps Lock light** or
**keyboard backlight**.

- Lives only in the menu bar: no Dock icon.
- Works with Claude, OpenAI, Gemini, **Groq**, Grok, Mistral, OpenRouter, Together, or any
  OpenAI-compatible service.
- Can download free open-source AI models that run entirely on your Mac.
- API keys are stored in the macOS Keychain.

Needs macOS 14 (Sonoma) or newer.

## Install

**Easiest:** download the latest **MorseEye-….dmg** from this repo's
[Releases](../../releases) page, open it, and drag Morse Eye into Applications. Then open
Terminal and paste this once (the app isn't registered with Apple, so macOS otherwise says
it's damaged):

```bash
xattr -dr com.apple.quarantine "/Applications/Morse Eye.app"
```

Open Morse Eye from Applications and continue with the first-launch steps below.

**Or build it yourself:**

1. **Right-click `Install Morse Eye.command` → Open → Open.**
   macOS asks for the right-click the first time because the file was downloaded.
2. If a window asks to install **developer tools**, click **Install**. It's free from Apple
   and takes a few minutes. Then run step 1 again.
3. The app builds itself (a minute or two), copies itself to **Applications**, and opens.
   Look for the **((·))** icon at the top right of your screen.

The settings window opens on first launch:

1. **General** → **Allow…** next to *Allow screen recording*, switch Morse Eye on in the
   window that appears, then quit and reopen Morse Eye from the menu bar.
2. **AI & Keys** → set *Provider* to **Groq**, paste your key from
   [console.groq.com/keys](https://console.groq.com/keys) next to Groq, click **Save**,
   then **Test connection**.
3. Press **⌥⇧⌘M** anywhere. Caps Lock blinks the answer.

## Using it

| Shortcut | What it does |
|---|---|
| ⌥⇧⌘M | "Briefly, what is on this screen?" |
| ⌥⇧⌘E | "Is there an error or warning visible?" |
| ⌥⇧⌘T | "What time or date is shown on screen?" |
| ⌥⇧⌘R | Replay the last answer |
| ⌥⇧⌘X | Stop blinking |

Change them, or add your own shortcuts with your own questions, in **Settings → Shortcuts**.
The menu bar popover also shows the last answer as text, with its Morse.

Each Morse answer starts with `-.-.-` and ends with `.-.-.`, so you can tell where it begins
and ends.

## Settings

- **AI & Keys**: pick the AI and model, save keys for every provider, and test the connection.
  The model has to understand images ("vision"). Model names change often; if you see
  "model not found", choose a current vision model from your provider's list.
- **Local Models**: free AI that runs on your Mac. Click **Install Ollama** (the free engine
  that runs the models), then **Download** a model and click **Use**. Gemma 3 4B is a good
  start on 8 GB Macs; Qwen 2.5 VL reads screens well if you have 16 GB.
- **Shortcuts**: each shortcut takes a screenshot and asks its own question.
- **Signals**: choose Caps Lock, keyboard backlight or menu bar icon; the code; and the speed.
  Codes are JSON files you can edit or duplicate to invent your own signals. See
  `Simple Signals` for an example: one long blink = YES, two short = NO.

## Good to know

- **Caps Lock is really on while it's lit**, so don't type during playback. Your previous
  Caps Lock state is restored afterwards.
- **Keyboard backlight** works only on built-in MacBook keyboards. It uses a private macOS
  feature that a future update could change.
- **After rebuilding the app**, macOS may ask again for screen recording permission, and
  ask whether Morse Eye may use its saved keys (click **Always Allow**). This happens
  because each build is signed for this Mac only.

## For developers

```
MacApp/
  Package.swift            Swift package (SwiftUI, macOS 14+)
  build-app.sh             builds "Morse Eye.app" and installs it to /Applications
  Info.plist               LSUIElement = menu-bar-only app
  Sources/MorseEye/
    MorseEyeApp.swift      menu bar + settings window scenes
    SettingsView.swift     settings tabs
    AppState.swift         settings, capture → AI → blink flow
    AI.swift               providers, Keychain, Claude + OpenAI-compatible clients
    Ollama.swift           local model installer/downloader
    Screenshot.swift       ScreenCaptureKit capture
    LEDs.swift             Caps Lock (IOKit), backlight (CoreBrightness), menu bar icon
    HotKeys.swift          global shortcuts (Carbon, no Accessibility permission needed)
    SignalCode.swift       Morse/custom code engine + built-in codes
python-cli/                the earlier command-line version
```

Every push to `main` builds the app and a DMG on a GitHub Mac runner
(`.github/workflows/build-mac-app.yml`). To publish a release, push a version tag:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

The workflow stamps that version into the app and attaches `MorseEye-v1.0.1.dmg` to a new
GitHub Release. Run `MacApp/make-dmg.sh` after `build-app.sh --no-install` to make a DMG locally.
