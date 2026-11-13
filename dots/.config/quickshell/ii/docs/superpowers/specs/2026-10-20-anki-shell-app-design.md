# Anki Review — built-in shell app

**Date:** 2026-10-20
**Status:** Implemented; verified in isolated Quickshell runs (full-shell restart pending)
**Scope:** A native Quickshell reviewer for the local Anki collection

## 1. Summary

Build a first-class Quickshell app that reviews the user's Anki collection without
opening Anki desktop. The app uses Anki's installed Python backend for scheduling,
undo, deck counts, card rendering and typed-answer comparison. It presents a QML
reviewer in the same visual family as Packages, Downloads, Mixer and Monitor.

Anki desktop and the shell app cannot write to one collection at the same time. The
shell app owns the collection only while its window is open and releases it when the
window closes. If Anki is already running, the app explains the conflict instead of
opening the database.

AnkiWeb sync is deliberately out of scope for this version. It will be a separate
follow-up spec built on the same bridge.

## 2. Goals

- Browse the deck tree and see new, learning and review counts.
- Review cards: question, reveal answer, grade Again/Hard/Good/Easy.
- Use Anki's real scheduler, not a reimplementation.
- Undo the last answer.
- Render text, common HTML/CSS, images and pronunciation audio.
- Support typed answers with Anki's own comparison rules.
- Keep the collection safe: no direct SQL writes, clean close, clear lock handling.
- Fit the existing app-window pattern (`docs/design/app-windows.md`).

## 3. Non-goals for this version

- Adding, editing or deleting notes and cards.
- Card browser, filtered-deck creation, custom study.
- Statistics, heatmaps or add-on UIs.
- AnkiWeb sync, login, full upload/download or media sync (separate v2).
- Running Anki add-ons inside the reviewer. Cards that depend on add-on-injected
  JavaScript will render a readable fallback and offer "Open in Anki".
- Replacing Anki desktop. The app releases the collection on close so Anki remains
  the owner whenever it is open.

## 4. User workflow

1. Open the app from launcher search, the `Super+Ctrl+Q` shortcut, or the `anki` IPC
   target.
2. The bridge opens the collection and returns the deck tree, current deck and counts.
3. The user picks a deck or continues with Anki's current deck.
4. The question appears. If the card asks for a typed answer, an input appears.
5. Space/Enter reveals the answer. Question audio plays automatically if enabled.
6. The user grades with 1–4 or clicks a grade button. The next card appears.
7. `U` undoes the last answer and reloads that card.
8. Closing the window releases the collection and stops the helper.

If Anki desktop is running, step 2 fails with a clear screen: "Anki is open. Close it
to review here, or open Anki instead." No database is touched.

## 5. Architecture

```
AnkiApp.qml                    lifecycle, shortcut, IPC
  └─ AnkiWindow.qml            FloatingWindow, title "ii Anki"
       └─ AnkiContent.qml      top bar, deck sidebar, review pane, settings sheet
            └─ AnkiService.qml Process, JSON-line protocol, state and timeouts
                 │
                 │  stdin/stdout, one JSON object per line
                 ▼
scripts/anki/anki_bridge.py    stateful Anki backend
                 │
                 │  official anki Python API
                 ▼
collection.anki2 + collection.media
```

### 5.1 Why a long-lived helper

Anki's backend must hold an open `Collection` to keep the queued card, scheduler
states and card timer consistent between question, reveal and answer. Opening the
collection for every click would be slower, would lose the timer, and would create
unnecessary lock churn. A single helper per app window is the smallest correct unit.

The helper writes no protocol data anywhere except the collection, and the collection
is only opened read-write while the app window is open.

### 5.2 Alternatives considered

| Alternative | Why not |
|---|---|
| Short-lived helper per action | Slow; loses queued-card state and timer; repeated open/close can race with Anki. |
| AnkiConnect add-on | Requires Anki running and an add-on; conflicts with the chosen shell-owned model. |
| Direct SQLite reads/writes | Reimplements scheduling and is unsafe against Anki's schema. |
| QtWebEngine card renderer | Quickshell 0.3.2 constructs `QGuiApplication` with `argc = 0`, which crashes QtWebEngine. Patching Quickshell is out of scope. |

### 5.3 Components

| Component | Responsibility |
|---|---|
| `modules/ii/anki/AnkiApp.qml` | `Scope`: open/close/toggle, `GlobalShortcut` `ankiToggle`, `IpcHandler` target `anki`. |
| `modules/ii/anki/AnkiWindow.qml` | `FloatingWindow`, title `ii Anki`, size clamping, close signal. |
| `modules/ii/anki/AnkiContent.qml` | `FocusScope`: layout, deck sidebar, review pane, settings, keyboard handling, error/empty states. |
| `services/AnkiService.qml` | Singleton bridge: starts/stops the helper, sends requests, correlates responses, exposes state, timeouts and errors. |
| `modules/ii/anki/DeckSidebar.qml` | Searchable, collapsible deck tree with counts and current-deck selection. |
| `modules/ii/anki/ReviewPane.qml` | Card surface, question/answer HTML, typing input, media, grade buttons, undo. |
| `modules/ii/anki/AnkiMedia.qml` | Sequential audio playback and replay controls. |
| `modules/ii/anki/AnkiCardHtml.qml` | Shared rich-text renderer, link handling and missing-media affordances. |
| `scripts/anki/anki_bridge.py` | Backend protocol, Anki API calls, HTML sanitisation, deck serialisation, typed answers, lifecycle. |
| `scripts/tests/test_anki_bridge.py` | Backend unit/integration tests against fixture collections. |
| `scripts/tests/test_anki_app_contract.py` | QML/registration/keybind contract checks. |

The module gets a `qmldir` exporting the app, window, content and reusable pieces, and
both panel families import `qs.modules.ii.anki`.

## 6. Backend protocol

One JSON object per line, UTF-8. Requests carry a unique string `id`; responses echo
it. The helper never writes human-readable text to stdout; logs go to stderr.

```json
{"id":"1","cmd":"open","args":{"profile":"User 1"}}
{"id":"1","ok":true,"data":{"version":"26.09.3","profile":"User 1","mediaPath":"...","decks":{...},"currentDeckId":123,"counts":{"new":70,"learn":5,"review":700}}}
{"id":"2","cmd":"card"}
{"id":"2","ok":true,"data":{"done":false,"card":{...},"counts":{...}}}
{"id":"3","cmd":"reveal","args":{"typed":"tragen"}}
{"id":"3","ok":true,"data":{"answerHtml":"...","buttons":[{"rating":0,"label":"Again","interval":"10m"}, ...],"audio":[...]}}
{"id":"4","cmd":"answer","args":{"rating":2}}
{"id":"4","ok":true,"data":{"done":false,"card":{...},"counts":{...}}}
{"id":"5","cmd":"undo"}
{"id":"5","ok":true,"data":{"card":{...},"counts":{...}}}
{"id":"6","cmd":"close"}
{"id":"6","ok":true,"data":{"closed":true}}
```

Errors:

```json
{"id":"2","ok":false,"error":{"code":"collection_locked","message":"Anki is already open."}}
```

### 6.1 Commands

| Command | Args | Result |
|---|---|---|
| `open` | `profile?`, `collectionPath?` | Version, profile, paths, deck tree, current deck, counts. |
| `profiles` | — | Profile names and the last-used profile. |
| `decks` | — | Refreshed deck tree and counts. |
| `selectDeck` | `deckId` | Current deck, counts, and the first card or a done state. |
| `card` | — | Current question payload, or `done` with counts. |
| `reveal` | `typed?` | Answer payload, grade buttons and typed-answer diff. |
| `answer` | `rating` (0–3) | Next question payload, or `done`. |
| `undo` | — | Reloaded question payload after Anki undo. |
| `close` | — | Closes the collection and exits the helper. |
| `ping` | — | Version and collection-open state. |

`open` accepts a `collectionPath` for tests and development. Production uses Anki's
base directory and profile. `ANKI_SHELL_COLLECTION` is also accepted as a development
override.

### 6.2 Collection and profile discovery

- Base directory: `$XDG_DATA_HOME/Anki2`, falling back to `~/.local/share/Anki2`.
- Collection: `<base>/<profile>/collection.anki2`.
- Media: `<base>/<profile>/collection.media`.
- Profile selection: explicit `Config.options.anki.profile`; otherwise Anki's last
  loaded profile from `prefs21.db`; otherwise the first non-`_global` profile.
- If no collection exists, return `collection_missing` with the path and the available
  profiles.
- If the `anki` Python package or `Collection` API is unavailable, return
  `anki_missing` or `unsupported_version` and do not attempt to touch the collection.

### 6.3 State machine

```
closed ──open──> idle ──card/selectDeck──> question
question ──reveal──> answerShown
answerShown ──answer──> question | done
question | answerShown ──undo──> question
any ──close──> closed
```

- `answer` is rejected unless the state is `answerShown`.
- `reveal` is idempotent while in `answerShown`.
- `card` returns the current question if one is already loaded; it does not restart the
  timer.
- The helper stores the current `QueuedCard` and calls `card.start_timer()` once when
  the question is first shown. This is required by `Scheduler.build_answer()`.
- After `answer`, the helper drops the queued card and fetches the next one.
- After `undo`, the helper calls `Collection.undo()` and fetches the queue again; the
  undone card is normally at the front.
- `done` means `get_queued_cards()` returned no cards. Counts are returned with it.

### 6.4 Deck payload

```json
{
  "id": 1655436163205,
  "name": "A1  Wortliste Goethe Institute",
  "level": 1,
  "collapsed": false,
  "new": 0,
  "learn": 0,
  "review": 700,
  "newUncapped": 1841,
  "reviewUncapped": 1841,
  "total": 1852,
  "children": []
}
```

The tree comes from `Scheduler.deck_due_tree()`; all counts are the capped values Anki
uses for the day, with uncapped values included for the empty-state explanation. The
current deck path is expanded by default; other nodes follow the tree's `collapsed`
flag and then the user's local expand/collapse choices.

### 6.5 Card payload

```json
{
  "cardId": 1584886455911,
  "noteId": 1584886454775,
  "deckId": 1655436163205,
  "deckName": "A1  Wortliste Goethe Institute",
  "kind": "review",
  "questionHtml": "...",
  "audio": [
    {"side":"question","index":0,"filename":"word.mp3","url":"file:///.../word.mp3","missing":false}
  ],
  "images": [
    {"src":"01.jpg","url":"file:///.../01.jpg","missing":false}
  ],
  "typeAnswer": {
    "field": "Term",
    "clozeOrdinal": null,
    "combining": true
  },
  "scripted": false,
  "hasMissingMedia": false,
  "counts": {"new": 70, "learn": 5, "review": 699}
}
```

- `kind` is derived from `card.ctype`: new, learning, review or relearning.
- `questionHtml` and `answerHtml` are sanitised and media-rewritten by the bridge.
- `audio` comes from `card.question_av_tags()` and `card.answer_av_tags()`. `index`
  corresponds to the `[anki:play:q:N]`/`[anki:play:a:N]` markers removed from the HTML.
- `typeAnswer` is present only when the rendered question contains a type-answer
  marker. The expected answer is **not** sent to QML before reveal.
- `scripted` is true when the rendered card contained `<script>`. The UI shows a
  small notice and an "Open in Anki" action.
- `images` is the fallback list for the renderer; the HTML also contains absolute
  `file://` image URLs where possible.
- `hasMissingMedia` is true if any referenced image or audio file is absent.

### 6.6 Answer payload

```json
{
  "answerHtml": "...",
  "buttons": [
    {"rating": 0, "label": "Again", "interval": "10m"},
    {"rating": 1, "label": "Hard", "interval": "2d"},
    {"rating": 2, "label": "Good", "interval": "3.3y"},
    {"rating": 3, "label": "Easy", "interval": "8.5y"}
  ],
  "audio": [...],
  "typedResult": {
    "provided": "tragen",
    "html": "<span style='color:green'>tragen</span>",
    "correct": true
  },
  "counts": {"new": 70, "learn": 5, "review": 699}
}
```

- Buttons are built from `Scheduler.answerButtons(card)` and
  `Scheduler.describe_next_states(states)`. Ratings map to `CardAnswer` values 0–3.
- Intervals are the labels Anki itself would show.
- `typedResult` is present only for type-answer cards. The comparison uses
  `Collection.compare_answer(expected, provided, combining)`; for cloze cards the
  expected value is extracted with `Collection.extract_cloze_for_typing()`.
- The typed diff HTML is sanitised with the same rules as card HTML.

## 7. Rendering

QtWebEngine is not available inside Quickshell, so the app uses Qt rich text with a
purpose-built sanitizer.

### 7.1 Sanitisation

- Remove `<script>` and its contents; set `scripted`.
- Remove event-handler attributes (`on*`), `<iframe>`, `<object>`, `<embed>` and
  `<video>`.
- Allow links only for `http`, `https` and `mailto`; QML opens them externally.
- Keep `<style>` for the Qt rich-text CSS subset. Unsupported rules degrade to the
  app's base card typography.
- Replace `[anki:play:q:N]` and `[anki:play:a:N]` markers with nothing; the audio list
  carries the filenames and indices.
- Replace `[[type:...]]` markers with nothing; the QML type field is shown separately.
- Rewrite relative `<img src="...">` values to URL-encoded absolute `file://` paths
  under the media directory. Reject paths that escape the media directory.
- If an image or audio file is missing, mark it and render a muted placeholder rather
  than a broken element.
- Cap image widths to the card width so tall screenshots do not overflow.

### 7.2 Rich text and images

`AnkiCardHtml` renders the sanitised HTML with `Text.RichText`, wrapping in a
`Flickable` for long cards. Inline `<img>` is used when the Qt 6.12 `Text` element
loads local file URLs; otherwise the bridge's `images` list is rendered as a media
strip immediately below the text. The backend contract is identical either way.

### 7.3 Audio

`AnkiMedia` owns a `MediaPlayer` and `AudioOutput`. Question audio plays
automatically when a card appears; answer audio plays when the answer is revealed;
both respect `Config.options.anki.autoPlayAudio`. Multiple clips play sequentially.
A replay button remains available. Missing files show a muted icon with the filename
in the tooltip.

### 7.4 Typed answers

`ReviewPane` shows a `TextField` when `typeAnswer` is present. On reveal it sends the
typed text to `AnkiService.reveal(typed)`. The answer view displays the bridge's
`typedResult.html` diff and the correct answer. The input becomes read-only after
reveal. Empty input is allowed and is compared as an empty answer.

## 8. UI

### 8.1 Frame

Follow `docs/design/app-windows.md`:

- `FloatingWindow` titled `ii Anki`, centered by a new Hyprland window rule.
- `ClockTopBar` with app title and deck subtitle; actions: undo, open in Anki,
  settings, close.
- `ClockStyle` colors, spacing, type and controls throughout.
- Window size roughly 1100×760, clamped to the screen; minimum about 900×600.
- At narrow widths the deck sidebar becomes a sheet opened by a "Decks" button.

### 8.2 Deck sidebar

A `ClockPane`-style surface with:

- Search field filtering deck names.
- Collapsible tree with indentation and a chevron per parent.
- New/learning/review badges, using the existing badge colors where possible.
- Current deck highlighted with `colActiveCard`.
- "Due only" toggle to hide zero-due decks.
- Current deck path expanded after open or deck change.
- Virtualized `ListView` for the 200+ deck case; no nested `Column` of all decks.

### 8.3 Review pane

- Card header: deck name, card kind chip, due counts.
- Card surface: question HTML, media, type field.
- Primary button: Show Answer (Space/Enter).
- After reveal: answer HTML, typed diff, four grade buttons with intervals.
- Grade colors: Again red, Hard amber, Good green, Easy blue (using existing palette
  tokens).
- Undo action and "Open in Anki" in the top bar; "Open in Anki" releases the
  collection first.
- Scripted-card notice: "This card uses scripts. Open it in Anki for the intended
  view." The readable text still renders.

### 8.4 Empty and error states

- **No cards due:** congratulatory state, counts, "Choose another deck", "Open Anki".
- **Collection locked:** lock icon, explanation that Anki is open, "Retry" and
  "Open Anki". No region-selection or silent fallback.
- **Collection missing:** path and profile picker.
- **Unsupported Anki version:** version found and a request to update Anki.
- **Helper crashed:** error summary with a Details expander and Retry.
- **Zoom/long cards:** scrollable card area; grade bar stays pinned.

### 8.5 Keyboard

| Key | Action |
|---|---|
| Space / Enter | Reveal answer (or submit typed answer) |
| 1–4 | Again/Hard/Good/Easy after reveal |
| U | Undo last answer |
| Esc | Close the app (or close settings sheet first) |
| Ctrl+W / Ctrl+Q | Close |
| R | Replay audio |

Typing in the answer field must not trigger grading shortcuts. The grade bar is
disabled before reveal and while a request is in flight.

## 9. Lifecycle and data safety

- The helper opens the collection only when the app window opens.
- Closing the window sends `close`; the helper closes the collection and exits. A
  short watchdog terminates the process if it does not exit.
- The helper also exits and closes the collection on stdin EOF, SIGTERM and SIGINT.
- If Anki is already running, opening fails with `collection_locked`; the app does not
  retry in a loop.
- The app never issues custom SQL writes. All scheduling, undo and typed-answer
  comparisons go through Anki's API.
- Anki's own backups and schema version checks remain in effect.
- Tests use temporary copies of collections; the real collection is never used in
  automated tests.
- The app is offline in v1: no network calls, no sync credentials, no ports.

## 10. Integration

### 10.1 QML and shell registration

- `GlobalStates.qml`: `ankiOpen`, `ankiPendingDeck`, `openAnkiApp(deckId)`.
- `modules/common/ShellActionRegistry.qml`: add an `anki` app action, keywords
  (`anki`, flashcards, review, study, cards, spaced repetition, SRS), add `anki` to
  `appIds`, and trigger `GlobalStates.openAnkiApp("")`.
- `panelFamilies/IllogicalImpulseFamily.qml` and `LiteFamily.qml`: import
  `qs.modules.ii.anki` and add `PanelUrlLoader`.
- `~/.config/hypr/hyprland/keybinds.lua`: bind `SUPER + CTRL + Q` to
  `quickshell:ankiToggle`, description "Anki: Review flashcards".
- `~/.config/hypr/hyprland/rules.lua`: float and center `ii Anki`.

### 10.2 Config

```qml
property JsonObject anki: JsonObject {
    property string profile: ""          // empty = Anki's last-used profile
    property bool autoPlayAudio: true
    property string collectionPath: ""   // empty = Anki's default; tests/advanced
}
```

No migration is needed: missing keys use defaults. The in-app settings sheet edits
`profile` and `autoPlayAudio`; `collectionPath` stays an advanced/testing value.

### 10.3 Dependencies

Add an optional `anki` feature to `defaults/dependencies.json`:

- Package `anki` on Arch, `anki` on Fedora; check `bin: anki` or `python: anki`.
- Description: "Built-in Anki review app (uses the installed Anki Python backend)."
- The app itself shows a helpful error if the backend is absent; the dependency
  is optional so the rest of the shell does not fail.

## 11. Error handling

| Code | UI behaviour |
|---|---|
| `anki_missing` | Explain that Anki must be installed; offer the package command. |
| `unsupported_version` | Show the installed version and ask the user to update Anki. |
| `collection_locked` | Explain Anki is open; Retry / Open Anki. |
| `collection_missing` | Show the expected path and profile choices. |
| `collection_corrupt` | Link to Anki's backup folder; do not attempt repair. |
| `no_profiles` | Explain that Anki has not been started yet. |
| `not_open` | Internal state error; Retry restarts the helper. |
| `no_card` | Treat as done and refresh counts. |
| `answer_not_ready` | Reveal the card first. |
| `nothing_to_undo` | Disable/no-op the undo action. |
| `bad_request` | Log details; show a generic helper error. |
| `internal` | Generic error with stderr details. |

The bridge catches expected Anki exceptions and maps them to these codes. Unexpected
exceptions include a traceback only in the Details expander, not in the main message.

## 12. Testing

### 12.1 Backend

`scripts/tests/test_anki_bridge.py` builds a fixture collection in a temporary
directory using Anki's own API:

- Open, deck tree, current deck and counts.
- Question payload: text, script stripping, audio tags, images, type-answer metadata.
- Reveal: answer HTML, grade labels, typed answer diff.
- Answer with each rating; next card; daily counts change.
- Undo restores the card.
- Deck selection changes the queue.
- Locked collection returns `collection_locked`.
- Missing collection/profile returns the right error.
- Missing media is marked, not fatal.
- EOF and SIGTERM close the collection.

### 12.2 QML contracts

`scripts/tests/test_anki_app_contract.py` checks:

- `GlobalStates` has the open flag and function.
- `ShellActionRegistry` includes `anki` in actions and `appIds`.
- Both panel families load the app.
- `AnkiApp` has the shortcut and IPC target.
- The keybind and window rule exist.
- The bridge command names used by QML exist in the Python dispatcher.

### 12.3 Manual

- Run against a copy of the real collection with the media directory symlinked
  read-only. Verify deck navigation, text/image/audio cards, typing, reveal, all four
  grades, undo, empty state, locked state and the scripted fallback.
- Only after the copy passes, run one full manual session on the real collection.
- Do not sync during testing.

## 13. Performance

- One helper per open window; no polling.
- Deck tree serialized once on open and refreshed on deck change, session completion
  or explicit refresh. Per-answer responses update the current deck counts.
- Card HTML is sanitized once per side and cached for the current card.
- Media is local; images are width-capped; audio is played sequentially.
- Deck list uses `ListView` virtualization; 200+ decks remain responsive.
- Request timeout: 20 seconds for `open`, 10 seconds for card/answer operations.
  Timeouts surface as errors, not silent hangs.

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Anki Python API changes | Version check; clear error; keep the bridge API small; tests pin behaviour against the installed version. |
| Collection lock conflict | Detect `collection_locked`; never retry in a loop; release on close. |
| Rich-text fidelity | Sanitize to a safe subset; provide image fallback; "Open in Anki" for scripted cards. |
| Missing media | Mark and render placeholders; never crash on a missing file. |
| Full-sync data loss | Not in v1. Sync is a separate spec with explicit full-sync warnings. |
| Add-on rendering differences | Document that add-ons are not executed; fallback to Anki. |
| Large deck tree | Flattened/virtualized list; collapsed by default; search. |

## 15. Follow-up: sync v2

The bridge API leaves room for `syncStatus`, `sync`, `syncLogin` and `fullSync`
commands. V2 must add:

- Reading Anki's stored sync key (or a login flow) without exposing it to QML.
- Incremental sync and media progress events.
- Full upload/download confirmation screens with explicit destructive warnings.
- Conflict and error recovery.

V2 gets its own design and implementation plan. Nothing in the reviewer's card
protocol needs to change.

## 16. Definition of done

- The app opens from launcher, shortcut and IPC.
- The deck tree, counts, question, reveal and four grades work against a copy and
  then the real collection.
- Typed answers use Anki's comparison and show the diff.
- Images and audio work; missing media is non-fatal.
- Undo works.
- Closing the app releases the collection; Anki can open immediately afterward.
- If Anki is open, the app shows the lock state and does not touch the database.
- Backend and QML contract tests pass.
- No automated test writes to the real collection.
