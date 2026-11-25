# Changelog

## 0.3.0

Proofreading stays strict. Everything else is now one click away.

- **Rewrite on demand:** every card has **✨ Improve**, **Formal** and **Casual** buttons. The result shows as a diff
  and only lands when you press Apply. <kbd>⌃⌥E</kbd> brings the buttons to any field.
- **Translate your drafts:** a **→ English** (or your language) button on the card. When a draft is in another
  language than the one you translate to, Babelpen offers the translation by itself (dismiss once per field, or turn
  it off per app with `offerTranslationIgnoredApps`).
- **Translate what you read:** select a message in another language and a **🌐 Translate** button appears, with the
  translation and a short note on what the author means (tone, implied requests, idioms, slang). Or press <kbd>⌃⌥T</kbd>.
- Rewrites and translations run on a second engine process with their own prompt, started on first use.
  Optional `assistModel` to use a bigger model for them.
- Language detection for these features runs on your Mac (Apple's NaturalLanguage).
- <kbd>⌃⌥B</kbd> opens the Babelpen menu at the mouse pointer. On a MacBook with a notch, macOS hides menu bar icons
  that don't fit, and the ✎ can end up behind it.

## 0.2.0

Revisor is now **Babelpen**: proofreading for every language, in every app.

- **Writing languages:** pick the languages you write in from the menu (defaults to your system languages). Text is always fixed in its own language, never translated.
- **Your vocabulary:** words Babelpen must never touch (names, jargon, slang). Select a word and press ⌃⌥V, or edit `vocabulary.txt`.
- **Interface in 6 languages:** English, Português, Español, Français, Deutsch, Italiano, switchable from the menu.
- **One-line install** and prebuilt universal releases (Apple Silicon + Intel) as `.dmg` and `.zip`, Developer ID signed and notarized by Apple.
- Apply only pastes into the app the suggestion came from.
- Keeps working while the menu is open.

## 0.1.0

First public release.

- Real-time proofreading in any macOS text field through the Accessibility API
- Engines: Claude Code (warm streaming process), Codex CLI, custom command
- Suggestion card with word-level diff, apply with ⌃⌥G, review now with ⌃⌥R
- JSON config, English and Portuguese UI, launch at login
