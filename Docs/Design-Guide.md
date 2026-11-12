# Context — Design Guide

Context should feel like a calm, native Mac utility where **text is the interface**. It belongs to the Constellation family. The visual and structural rules below follow Cue (`~/Projects/cue/Docs/Design-Guide.md` §16) and Crew (`~/Projects/Crew/Docs/Design-System.md`). When this guide is silent, follow those guides.

## Character

- Restrained, typographic, and quiet. Not an AI dashboard.
- Fast and keyboard-first. Every action is reachable without the mouse and has a menu item with a key equivalent.
- Dense where it helps and empty everywhere else.

## Structural rules

- **Text only by default.** Chrome appears on hover or on command, and recedes while you type.
- **System first.** Use system typography (SF Pro, and SF Mono for code), system window materials, SF Symbols, native menus, and context menus for object actions. Do not invent custom chrome when a system control exists.
- **Appearance follows the system.** Light and dark come from system appearance, and Context respects the user's accent color.
- **Brand color is a signal, not a theme.** It covers a few percent of the surface at most, the same rule as Cue.
- **No AI sparkle.** AI lives behind one command entry point and shows up as inline proposals. Do not add a sparkle icon to every button.
- **Progressive disclosure.** Model, vault, and harness configuration stay out of the writing surface (Crew rule).
- **Accessibility identifiers.** Every actionable control gets a stable identifier for UI tests and agent verification (Crew rule).
- **Avoid web-app patterns.** No oversized cards, floating pill navigation, or dashboard side rails.

## Zen canvas

The canvas starts with text and nothing else. These rules turn "less is more" into layout:

- **No visible window chrome.** No title bar, separator, toolbar, or status bar. The traffic lights always show; hiding them makes the window look broken.
- **Three layers of disclosure.**
  1. **Hidden (the default).** Text, the caret, and generous margins. Nothing else is drawn.
  2. **Hover bands.** When the pointer is near the top edge, the header fades in: the pad name, new note, search, and ⋯. When the pointer is near the bottom edge, the note-position dots fade in. The dots also flash briefly after a note switch. Typing hides both until the pointer moves again.
  3. **Native menus.** Every note action is built once (`noteMenuItems`) and appears in the menu bar's Note menu, the canvas's right-click menu, and the header's ⋯ button. Deeper configuration stays in Settings.
- **Settings inspector.** A panel that slides in from the right edge (⌥⌘I, or ⋯ › Show Inspector) with the current pad's project documents, delivery targets, AI model, and look (theme, text size). The window grows to make room so the text stays put, and Esc closes it. Full configuration stays in Settings.
- **Transient work floats.** AI proposals and the legacy mode readouts are floating material cards at the bottom of the canvas. They are not full-width bars, and they disappear when they are done.
- **No hint text.** Shortcuts live in menus, not in the canvas.

### Typography and paper

- **The first line is the title.** In a prose note, the first line is set in the system serif (New York) at 1.85× the body size, with space under it. Clipboard entries and mode notes (`math`, `list`, …) get no title; mode notes keep uniform lines so their gutters align.
- **Body rhythm.** System sans at the user's text size, with line spacing 0.3× and space after each line 0.45× (prose notes only).
- **Display only.** Typography is attributes on the text view. The string, and so the Markdown file, never changes. The rules live in `CanvasTypography` (ContextDomain).
- **Paper is the default theme.** Background `#F4F2EC` light and `#1F1D1A` dark, ink `#2B2925` and `#E9E4D8`, accent `#B57614`. Mocha and Forest keep the system label color for text.

## Surfaces

- **Quick overlay.** One pad at a time, with full-bleed text. Switch pads by swipe or ⌘[ / ⌘]. The pad indicator stays minimal. The overlay opens ready to type.
- **Library.** Bear-style sources, note list, and editor, but zen: it opens as the note alone. The pointer at the left edge (or ⌃⌘S) slides in the sources and the list. Opening a note hides the sources at once; the list stays until the pointer moves into the text. Read/Edit (⌘E) and the note's actions sit in a header that fades in at the top edge. Logic: `LibraryReveal`.
- **Canvas editor.** Markdown is styled inline as you type, Bear-style, not shown in a split preview. Embedded objects render inline at reading size. The file on disk stays plain Markdown.
- **AI proposals.** Proposals appear on the page as an inline diff or ghost text, with accept and reject. Accepting is one undoable edit.

## Existing themes

The Paper (default), Mocha, and Forest themes, adjustable text size, and the translucent window option already exist. Consolidating them against the family rules is open work. Do not add new themes before that pass.

## References

These references are for feel and interaction only. Do not copy proprietary assets or code.

| Reference | Take from it |
| --- | --- |
| Antinote | Instant overlay, pads, and swipe navigation |
| Bear | Library layout and typographic Markdown editing |
| Granola | AI working directly on the canvas (not its meeting features) |
| Cue and Crew | Constellation family visuals and native chrome |
