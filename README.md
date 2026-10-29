# Grammar Check

A macOS app that sends your text to Claude through the Claude Code CLI (`claude -p`), using your Claude Pro login. It needs no API key and adds no billing.

- **Main window:** paste text on the left and press ⌘↩. The suggestion appears on the right, with deletions in red strikethrough and insertions in green. Switch off "Show changes" to get an editable plain result, then use "Copy result" (⇧⌘C) or "Use as input".
- **Selection mode:** select text in any app and press ⌃⌥G. A review panel opens; ↩ replaces the selection in place and Esc closes the panel.
- **Mode and preset:** dropdowns on the main screen and in the selection panel. Changing either one in the panel re-checks the text.
  - Mode: "Grammar only" or "Grammar + style".
  - Preset: extra instructions for a context, such as "Slack — colleague" or "Slack — UK client". Manage presets under Settings (⌘,) → Presets. Preset rules override the defaults (tone, formality, US/UK spelling) but never the output format.
- **Model:** Sonnet, Haiku or Opus, under Settings → General.

## Requirements

1. macOS 15 or later, plus Xcode or the Command Line Tools: `xcode-select -p` should print a path.
2. Claude Code is installed and logged in with your Pro account:
   ```bash
   curl -fsSL https://claude.ai/install.sh | bash   # or: brew install --cask claude-code
   claude            # then run /login and choose your Claude subscription
   claude -p "say ok"  # must answer without asking for an API key
   ```

## Build and run

```bash
cd ~/LocalSites/grammar-check
chmod +x build.sh
./build.sh
open build/GrammarCheck.app
```

To open the package in Xcode, run `open Package.swift`. Xcode runs the raw executable, not the `.app` bundle, which is fine for working on the UI.

## Accessibility permission (selection mode only)

Selection mode presses ⌘C and ⌘V on your behalf, which macOS only allows with Accessibility permission. The first ⌃⌥G triggers the system prompt. Enable Grammar Check under System Settings → Privacy & Security → Accessibility.

An ad-hoc signature (the default) changes with every rebuild, and macOS then treats the app as new, so the permission silently stops working. Either remove the app from the list and add it again after each rebuild, or sign with a stable self-signed certificate once:

1. Open Keychain Access and choose Certificate Assistant → Create a Certificate…
2. Set Name to `GrammarCheck Dev`, Identity Type to Self Signed Root and Certificate Type to Code Signing.
3. Build with `SIGN_ID="GrammarCheck Dev" ./build.sh`.

## Versioning

The version is set in `Resources/Info.plist` and goes up by one patch number with every update (1.0.3 → 1.0.4). Changes are listed in `CHANGELOG.md`, and the running version is shown under Settings → General → About.

## App icon

`Resources/AppIcon.icns` is generated from `Resources/AppIcon.png` (1024×1024). To change it, replace the PNG and rebuild the `.icns`:

```bash
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns && rm -r AppIcon.iconset
```

## How it works

| File | Role |
|---|---|
| `ClaudeCLI.swift` | Finds `claude` and runs `claude -p --output-format json` with no tools, no MCP and no session files. The text goes in through stdin. The CLI runs in a temporary folder so no project `CLAUDE.md` gets loaded. `ANTHROPIC_API_KEY` is removed from the environment so the Pro plan is used, not API billing. |
| `Prompt.swift` | System prompts for the two modes, plus the selected preset's instructions. The model returns `<corrected>…</corrected>`. |
| `Presets.swift` | Preset model and storage (JSON in UserDefaults), plus the shared mode and preset dropdowns. |
| `GrammarService.swift` | Keeps the text's original leading and trailing whitespace, and keeps a cache of the last 40 results (identical re-checks are instant and use no quota). |
| `TextDiff.swift` | Word-level diff using Swift's `CollectionDifference`, rendered as an `AttributedString`. |
| `SelectionController.swift` | Registers the global hotkey ⌃⌥G (Carbon), copies the selection, shows the review panel, then pastes the result and restores your clipboard. |

## Known limits

- Each check takes about 3–10 s because a CLI process starts every time.
- Each call carries roughly 14K tokens of Claude Code's own context. It is cached for an hour, so repeated checks cost less, but it still counts toward your Pro usage limits. Haiku is the lightest option.
- Selection mode depends on the target app supporting ⌘C/⌘V, and the selection must still be active when you press Replace.
- The Dock icon doesn't reopen a closed window; use the menu bar icon and choose "Open Grammar Check".
