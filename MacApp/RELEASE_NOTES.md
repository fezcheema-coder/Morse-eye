## Install

1. Download **MorseEye-….dmg** below and open it.
2. Drag **Morse Eye** onto **Applications**.
3. Open **Terminal** and paste this once (the app isn't registered with Apple, so macOS
   otherwise says it's damaged):

   ```
   xattr -dr com.apple.quarantine "/Applications/Morse Eye.app"
   ```

4. Open **Morse Eye** from Applications. Its icon appears in the menu bar (top right), and
   Settings opens:
   - **General** → **Allow…** screen recording, then quit and reopen Morse Eye.
   - **AI & Keys** → pick your AI (e.g. Groq), paste your key, **Save**, **Test connection**.
5. Press **⌥⇧⌘M** anywhere. The answer blinks on Caps Lock.

Works on Apple Silicon and Intel Macs with macOS 14 (Sonoma) or newer.
