# Constellation Context

Open source Mac-native scratchpad. Antinote-style instant notes with IDE-friendly plain text.

## MVP shipped (Antinote parity slice)

- Global hotkey `⌥A` floating scratchpad, menu bar extra, pin on top
- Plain-text notes, paste strips formatting, bullets, and indentation
- First-line triggers: `math`, `sum`, `avg`, `count`, `list`, `code`, `timer`, `paste`
- Inline math with variables, descriptive text, length/weight/temperature conversion
- Checklists with tick-off rows, word/line/char counting
- Stopwatch, countdown (`timer 25m`, `timer 10:00`), and pomodoro parsing
- AutoPaste collection while a `paste` note is armed
- Image drop OCR via Apple Vision, on-device only
- Export to txt, Markdown, PDF, clipboard; recoverable Void trash with 30-day expiry
- Catppuccin Mocha theme, local JSON store, Swift 6 macOS 15 native

## Run

```bash
swift test
CONTEXT_REBUILD=1 ./Scripts/run-app.sh
```
