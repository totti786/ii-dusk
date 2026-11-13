# Anki Review Shell App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native Quickshell Anki reviewer backed by the installed Anki Python API.

**Architecture:** A long-lived Python bridge owns the collection while the app window is open and speaks JSON lines over stdin/stdout. QML owns the window, deck tree, card rendering, typing, audio and lifecycle.

**Tech Stack:** Quickshell/QtQuick 6, Python 3.14, Anki 26.09 Python backend, QtMultimedia.

---

### Task 1: Backend protocol and collection lifecycle

**Files:**
- Create: `scripts/anki/anki_bridge.py`
- Test: `scripts/tests/test_anki_bridge.py`

- [ ] Implement JSON-line dispatch with `open`, `profiles`, `decks`, `selectDeck`, `card`, `reveal`, `answer`, `undo`, `close`, `ping`.
- [ ] Resolve `XDG_DATA_HOME/Anki2`, profile, collection and media paths.
- [ ] Open `anki.collection.Collection`, map lock/missing/version errors to protocol errors.
- [ ] Close the collection on `close`, stdin EOF, SIGINT and SIGTERM.
- [ ] Test with a temporary fixture collection created through Anki's API.

### Task 2: Card payload, sanitisation and media

**Files:**
- Modify: `scripts/anki/anki_bridge.py`
- Test: `scripts/tests/test_anki_bridge.py`

- [ ] Return deck tree and counts from `deck_due_tree()`.
- [ ] Return question/answer HTML, card kind, deck name, audio tags, image list.
- [ ] Strip scripts, unsafe tags/attributes and unsafe links.
- [ ] Rewrite image paths to absolute URL-encoded media paths; mark missing files.
- [ ] Remove `[anki:play:...]` and `[[type:...]]` markers.
- [ ] Test text, scripted, image, audio and missing-media cards.

### Task 3: Typed answers, grading and undo

**Files:**
- Modify: `scripts/anki/anki_bridge.py`
- Test: `scripts/tests/test_anki_bridge.py`

- [ ] Call `card.start_timer()` when a question is first shown.
- [ ] Use `answerButtons()` and `describe_next_states()` for four buttons.
- [ ] Build answers with `build_answer()` and submit with `answer_card()`.
- [ ] Compare typed answers with `compare_answer()` and cloze extraction.
- [ ] Implement undo via `Collection.undo()`.
- [ ] Test each rating, typed diff, undo and done state.

### Task 4: QML service

**Files:**
- Create: `services/AnkiService.qml`
- Modify: `modules/ii/anki/qmldir`

- [ ] Start `python3 -I scripts/anki/anki_bridge.py` with stdin enabled.
- [ ] Parse stdout JSON lines and correlate by request id.
- [ ] Expose `open`, `selectDeck`, `card`, `reveal`, `answer`, `undo`, `close`.
- [ ] Track loading, error, decks, current card, answer buttons and counts.
- [ ] Close on shutdown; handle process exit, timeout and restart.

### Task 5: App shell and registration

**Files:**
- Create: `modules/ii/anki/AnkiApp.qml`, `AnkiWindow.qml`, `AnkiContent.qml`, `qmldir`
- Modify: `GlobalStates.qml`, `modules/common/ShellActionRegistry.qml`, `panelFamilies/IllogicalImpulseFamily.qml`, `panelFamilies/LiteFamily.qml`, `modules/common/Config.qml`, `~/.config/hypr/hyprland/keybinds.lua`, `~/.config/hypr/hyprland/rules.lua`, `defaults/dependencies.json`

- [ ] Add `ankiOpen`, `openAnkiApp()` and the app action/trigger.
- [ ] Add the module import and `PanelUrlLoader` entries.
- [ ] Add `anki.profile`, `anki.autoPlayAudio`, `anki.collectionPath` config.
- [ ] Add `Super+Ctrl+Q`, float/center rule and optional dependency entry.
- [ ] Verify the launcher, IPC and shortcut paths.

### Task 6: Deck sidebar and review pane

**Files:**
- Create: `modules/ii/anki/DeckSidebar.qml`, `ReviewPane.qml`, `AnkiCardHtml.qml`, `AnkiMedia.qml`
- Modify: `modules/ii/anki/AnkiContent.qml`

- [ ] Render a searchable, collapsible deck tree with counts.
- [ ] Render question/answer HTML with images and links.
- [ ] Add type-answer field and diff.
- [ ] Add sequential audio playback and replay.
- [ ] Add Show Answer, four grade buttons, undo, empty/locked/error states.
- [ ] Add keyboard shortcuts and compact layout.

### Task 7: Settings and polish

**Files:**
- Create: `modules/ii/anki/AnkiSettingsSheet.qml`
- Modify: `modules/ii/anki/AnkiContent.qml`

- [ ] Add profile selection and audio autoplay setting.
- [ ] Add "Open in Anki" that releases the collection first.
- [ ] Add scripted-card and missing-media notices.
- [ ] Check narrow layout and theme consistency.

### Task 8: Contract tests and verification

**Files:**
- Create: `scripts/tests/test_anki_app_contract.py`
- Modify: `docs/superpowers/specs/2026-10-20-anki-shell-app-design.md` only if implementation reveals a correction.

- [ ] Assert GlobalStates, ShellActionRegistry, panel loaders, shortcut, IPC, keybind and window rule.
- [ ] Run Python backend tests.
- [ ] Validate QML syntax and run the app in a throwaway Quickshell instance.
- [ ] Manually test against a copy of the real collection, then the real collection.
- [ ] Confirm closing the app releases the collection.
