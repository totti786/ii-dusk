# QuickShell desktop companion — first implementation

Use the AI chat with **Codex**, **Claude Code** or **OpenCode** and **Tools** mode.
The engines reuse their CLI sign-ins; see [Agent stack](AGENT_STACK.md).
File attachments, conversation memory, system inspection, settings edits with
undo, and command approval already existed; this extends that assistant.

New tools appear under the **companion** domain in AI tool permissions:

| Tool | Purpose |
| --- | --- |
| desktop_context | Actual shell architecture, wallpaper and native control routes |
| wallpaper_search / wallpaper_set | Recursive configured library search and native wallpaper/theme apply |
| companion_status | Live monitors, app window addresses, browser connection and dependencies |
| browser_tools | Discover the installed browse MCP schemas |
| browser_call | Call that MCP, retaining text and image results |
| desktop_capture | Capture the focused or named monitor on demand |
| desktop_input | Focus apps, move, click, drag, scroll, type Unicode text, or send a shortcut |
| speak_text | Read aloud using local Kokoro, with multilingual Edge fallback |

The speaker button below an answer reads it aloud and becomes Stop while playing.
Code blocks and old inline reasoning are omitted. Speech is capped at 4000
characters. The default English voice is now local Kokoro `af_heart`, with streaming playback.
Edge TTS remains installed for unsupported scripts and explicit Edge voices.
That fallback sends text to Microsoft; local English speech stays on the machine.
Speech input stays on-device and uses Hex or Whisper, depending on the speech settings.

Try: “Check your companion capabilities”, “What is on my screen?”, or
“Use my browser to research this”. Screen understanding requires a model with
vision. Captures are returned directly to the selected model, without saving
screenshots to disk. All monitors use global logical coordinates; the returned
origin must be added to image positions. Input is one action per call.

The browser uses the existing `browse mcp`, with a persistent connection per
tool server. The managed relay starts on demand. Open the already paired
browser profile and enable its browse extension if status says paired-offline.
The bridge has been checked against browse 0.0.17 and the paired Chromium extension. It does not copy browser
credentials or configure a new browser profile.

Auto mode applies to Codex, Claude Code and OpenCode. Browser actions, desktop capture,
desktop input, speech and privileged commands require approval across those engines.
AI Tools & Permissions controls which tools the assistant can request.

Pointer input, shortcuts and fallback typing use a private user ydotoold (started by the shell via `scripts/ai/ensure_daemons.sh`, no systemd unit) with a
0600 socket at `$XDG_RUNTIME_DIR/ii-companion-input.sock`. It uses this machine's
existing /dev/uinput ACL, with no sudo or new root service. Stop it with `pkill -f ii-companion-input.sock`; the shell starts it again within a minute.

Text entry prefers `wtype` through the compositor's virtual keyboard protocol,
verified with mixed Arabic and English text in a native GTK app. `ydotool` handles
mouse input and shortcuts, and provides ASCII typing fallback if wtype is absent
or the compositor explicitly reports an unsupported virtual keyboard protocol.
An ambiguous typing failure is never retried automatically to avoid duplicates.

Only companion tools resolve stale Hyprland environment variables automatically;
this does not change the environment of unrelated terminals or services.

Pre-change files are saved at:
`~/.local/state/quickshell/user/ai/companion-backup/`.

Validation:

    python3 -m unittest discover -s scripts/ai/tests -p 'test_companion_tools.py'
    python3 -m unittest discover -s scripts/ai/tests -p 'test_shell_tools_mcp.py'
    python3 -m unittest discover -s scripts/ai/tests -p 'test_opencode_bridge_rules.py'

The desktop control update passed 89 targeted companion, signed-in bridge,
permission-rule and MCP tests, plus QML parsing. Live checks verified 1920×1080
capture, focus, click, keyboard shortcuts, text entry, dragging and both scroll
directions against a temporary native GTK app. Dragging releases the mouse button
even if motion fails. Browse MCP filled a test field, clicked its button and read
back the result in the existing Chromium profile. Chromium must be running for
the paired extension to connect; the companion's instructions cover reopening it.
Browser tool discovery excludes output schemas to keep conversation context small.

Speech dependency installation (already completed in this environment):

    python3 -m venv ~/.local/share/quickshell-ii/edge-tts-venv
    ~/.local/share/quickshell-ii/edge-tts-venv/bin/python -m pip install -r scripts/ai/companion-requirements.txt

## Voice orb

The companion docks as a themed Dynamic Island bubble by default. All chat text, attachments, model
selection and approval cards stay in the sidebar.

- Click the orb or press **Super+Alt+Q** to start speaking.
- Pause for about 0.75–1 second to send the utterance, or click again to finish it.
- The orb shows listening, understanding, thinking, preparing voice, speaking,
  approval-needed and error states. Its shape reacts to microphone levels and
  the synthesized reply's audio envelope.
- Replies play through local Kokoro for English. After playback, it listens for the next turn.
- Click while speaking to interrupt and talk again. Click Stop to end the voice
  session. Eight seconds without speech also ends it. An optional wake word ("hey jarvis", Settings > AI Assistant > Trigger word, off by default; `wake_word.py`, openWakeWord ONNX in the voice venv, ~6% of one core) starts a session; it holds the mic only while the orb is idle.
- Right-click or use the chat icon to open the sidebar transcript and approvals.
- Hover the island bubble for voice controls. Drag the bubble or its expanded header out to float it.
- Grab the floating orb to move it. Hover reveals four separate controls around it: conversation, return, voice and hide. The orb and all four controls share one hover area; holding a control keeps it open. It follows the pointer directly while held and snaps near a screen edge on release.
- A companion bubble previews the docking position in the Dynamic Island while dragging. The island’s bottom edge shows a smooth outward traveling scallop wave during dragging, driven at display frame rate, with stronger depth when docking is available; the preview bubble also brightens. Release to dock, or click Return to island. Reduced motion uses a static outward scallop. Docking fades into that native bubble without a separate outline or flight animation. Floating position and docked state survive a shell restart.
- Close hides it; the shortcut brings it back. Motion follows the shell theme and reduced-motion setting.
- Locking the screen stops the microphone and this voice session. Shell reloads
  do not restore listening automatically.

PipeWire records mono 16 kHz audio, with a 60-second utterance limit and adaptive
energy/pause detection. Local **Voxtype**, forced to its **Whisper multilingual
base** engine using the already installed `ggml-base.bin`, transcribes the WAV.
Its configuration is isolated from normal dictation hooks. Audio and temporary
transcripts are removed after use. Only recognized text is sent to the selected
AI model. English replies use local Kokoro; multilingual Edge fallback sends reply
text to Microsoft's speech service.

This is turn-based speech: playback and capture alternate. Interruption is by
click/shortcut; simultaneous listening and acoustic echo cancellation are not
implemented. Silence detection is an energy heuristic, so background voices can
count as speech.

IPC: `qs -c ii ipc call companion open`, `talk`, `stop`, `hide`, `toggle`,
`transcript`, or `status`. `open` only reveals the orb; `talk` activates the mic.
The user shortcut remains in `~/.config/hypr/hyprland/keybinds.lua`.

## Faster local voice

English now uses **Kokoro Heart (`af_heart`)** through ONNX Runtime on CPU.
The full precision 326 MB model and 28 MB voice bundle are checked against the
upstream release SHA-256 digests. No Torch or GPU service is required.

The warm voice daemon (`local_voice.py`, started by the shell via `scripts/ai/ensure_daemons.sh`, no systemd unit) keeps the model warm behind a private 0600 Unix
socket. Text is split into short sentences/clauses, with a bounded synthesis
queue. Playback starts with the first chunk, and subsequent synthesis overlaps
playback. Disconnecting the client stops audio immediately and cancels remaining
chunks. It costs roughly 440 MiB of resident and swapped memory, so the daemon
only lives while it can be heard: the shell starts it as soon as the orb is
visible and runs `ensure_daemons.sh stop-voice` 90 s after it is hidden (never
mid-sentence). An explicit speech request while it is stopped — sidebar
"Read aloud", the settings test, IPC — starts it on demand and waits ~2.5 s for
the model, so a hidden orb does not pay for it all day.

Configuration: `~/.config/illogical-impulse/companion-voice.json`:

    {"backend":"kokoro","voice":"af_heart","speed":1.05,"edgeVoice":"en-US-EmmaMultilingualNeural"}

Choose `backend: "edge"` to restore the previous voice. Arabic, CJK, Cyrillic and
other scripts unsupported by this English voice use Edge automatically. Local
worker failures do not silently send English text to a network service.

Installed runtime: `~/.local/share/quickshell-ii/voice-venv/` (Python 3.12),
with dependencies recorded in `scripts/ai/local-voice-requirements.txt`.
Models: `~/.local/share/quickshell-ii/kokoro/`.

Measured on this i5-1235U laptop: the old Edge path needed 10.50 seconds to obtain
the complete audio for the fixed short test phrase. Local warm first-chunk
synthesis measured 629, 804 and 810 ms for three short prompts; the actual
playback request began feeding audio after 857 ms. These measurements exclude
speech recognition and AI response time, which still contribute to total turn
latency. Process cancellation completed in 16 ms, with no player left running.

Upstream: https://github.com/thewh1teagle/kokoro-onnx

Presentation controls over IPC:

    qs -c ii ipc call companion dock
    qs -c ii ipc call companion undock
    qs -c ii ipc call companion status

Pointer regression checks (offscreen; do not move the desktop cursor):

    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input scripts/tests/companion_pointer
    node scripts/tests/test_companion_placement.cjs

## Files and responsive voice

Drop local files onto the floating orb, the docked bubble, or its expanded card.
The orb highlights with an attachment icon while hovering and shows an attachment
count afterward. Dropping opens the existing sidebar attachment tray; nothing is
sent automatically. Files go through the same type, size, model-capability and
extraction checks as sidebar attachments. Ask by voice after dropping; a voice
request waits for outstanding file preparation. Remove files in the sidebar.
Remote URLs and directory inputs are not treated as local document contents.

Hovering or conversing shows a compact phase hint; clicking while listening sends
the utterance, and clicking during playback interrupts into listening. Thinking
and transcription have animated dots. Voxtype is the only STT path in both the
composer and the orb. The orb uses a one-second silence window for short phrases
and 0.75 seconds after longer speech, and resumes listening after 120 ms rather
than 450 ms. This removes 0.6–0.9 seconds of deliberate waiting per turn without
changing the selected model. Local Kokoro remains the TTS engine, with the existing
language fallback. Playback still starts after the model completes its answer;
model generation and Voxtype inference are separate remaining latency costs.

`companion status` includes `timings` for transcription, generation and time to
speech playback. `companion attach PATH` queues one local file through the same
drop pipeline; `companion detach PATH` removes that attachment from the draft.

Checks for this update: live Voxtype inference on a generated 16 kHz WAV (1.64 s),
real Wayland drag-and-drop from a separate Qt window onto the orb, attachment
processing and cleanup without sending, file URL parsing (including escaped and
Arabic names), pause detection, voice/config contracts and pointer/menu tests.

File-manager drop cleanup: both grid and list views disarm the press target,
clear the drag proxy and mime data, and reset selection-drag flags when the
platform drag finishes. The orb advertises Copy during hover and accepts Copy
before queuing attachment processing on the next event-loop turn, so opening the
sidebar cannot interrupt same-process native drag completion. Verified against
the actual QuickShell file manager, with the source kept open and pointer movement
after release: the drag finished as Copy, the fixture attached without moving its
original, and no new drag started without a press.

## Context, instant actions and moods (2026-11-18)

**Fast path config.** `ai.voice.fastPath` (true), `fastModel` ("haiku"), `actions` (true) and
`screen` (true) are declared in `Config.qml`. They were missing before, so the warm session
was silently off and every turn went to Codex.

**Context.** `AiCompanionActions.snapshot()` puts a short `<desktop-context>` block in front
of each spoken turn: time, focused window, now playing, volume, battery, unread notifications,
next alarm, soon reminder, running timers, open tasks. Questions about these need no tool
call. The block is declared untrusted data in the system prompt (window titles and track
names can contain instructions). The clipboard is deliberately not included.

**Actions.** The model starts a reply with `[[DO verb args]]` lines, then one short
confirmation. `voice_agent.py` parses them (`parse_head`) and emits `action` events;
`AiCompanionActions.run()` runs them from a closed table with validated, clamped arguments:
`media`, `volume`, `brightness`, `theme`, `open` (desktop entries only), `timer`, `alarm`,
`remind`, `task`, `workspace`. Locking, closing windows, typing, files and shell commands
are not in the table. A refused or failed action sends the turn to the full agent; if
something already ran, the orb says so instead of repeating it. What was done is recorded
in the chat as `(Set volume to 26%)` so later Codex turns know.

**Attach screen region.** Choose a window or drag a rectangle from the orb's screen button.
The image appears in the chat draft, where you can review it and the selected model before
sending. The screenshot is scoped to that turn. The quick model receives battery or volume
information when relevant. Settings → AI Assistant → Voice orb shows the latest turn receipt
and can clear local, prompt-free timing history.

**Allow automatic screen capture** (`ai.voice.autoScreen`, off by default, protected from the
assistant). When on, a question about the screen makes the quick model reply `[[LOOK]]`; the
agent captures the focused monitor once (grim, JPEG, scaled) and sends it to Claude with no
preview. The chat records "(Looked at your screen)". It needs quick answers with Claude, so
never in Local only or Off, and nothing is captured while the screen is locked. The image stays
in the warm session until that ends; switching the setting off ends it. When off, the quick
model has no screenshot access.

**Enable the orb** (`ai.voice.orbEnabled`, on by default; `qs -c ii ipc call companion orb
on|off`). Off removes the orb, kitten, satellites and island bubble, ignores the shortcuts,
IPC talk/ask, desktop double-click and wake word, ends the warm voice agent, stops coding
session alerts and typed routing, and lets the local voice model be unloaded. Hiding the orb
is separate and is remembered across the switch.

**Moods.** `AiCompanionUi.mood` picks one word for the creature: forced (IPC), the voice
session's (`delighted` after an action, `curious` while looking), `startled` on a new
notification (not while Do Not Disturb), `worried` at 15% battery or less and not charging,
`night` from midnight to 5. The creature (`AiCreature.qml`, `personality: true` only on the
orb) changes eye shape, tilt and timing; a turn that runs over 6 s squints. Check each face:

    qs -c ii ipc call companion mood startled   # delighted curious worried night, "" clears

Tests: `python3 -m unittest tests.test_voice_agent_markers` in this folder.
Pre-change copies: `~/.local/state/quickshell/user/ai/orb-personality-backup/`.

**Rules first (Tier 1).** `voice_rules.py` matches the commonest whole-utterance commands
before any model is asked: media (pause, play, next, previous), volume (set, up/down, mute),
brightness, light/dark theme, timers, alarms, "remind me to ...", "add X to my tasks",
`workspace N` and "open <app>". It handles filler ("can you please..."), number words
("thirty", "half an hour") and am/pm, and refuses anything chatty or ambiguous ("play some
jazz", "remind me tomorrow...", "open the sidebar", "set a timer") so those reach the model
unchanged. A hit emits the same `action` events, so `AiCompanionActions` still validates
everything. Measured: 1-40 ms to decide, 75 ms generation and 0.6 s to speech through the orb.
`ai.voice.rules` turns it off. Tests: `python3 -m unittest tests.test_voice_rules`.

**Transcription tuning (2026-11-18).** `stt_daemon.py` now hints Whisper with the commands the
orb understands (`PROMPT`; English/auto only) and builds its common model at start. Measured
on synthetic speech: "alarm at seven thirty am" went from nonsense to `alarm at 7:30 am`.
Warm transcription is 0.7-1.4 s for a 1.5 s clip on this CPU; smaller `audio_ctx` windows and
greedy/no-fallback decoding were not faster in a way worth the hallucination risk (a
no-fallback run looped "next song" 60 times). The rules now also accept `brightness set N`,
`volume set N` and `workspace3`. `voice-timings.jsonl` records each spoken turn's stages.

**Latency work (2026-11-18).**
- *Chime.* A rule-matched command that ran ends with a 0.14 s chime (`pw-play`, freedesktop `bell`)
  instead of a spoken sentence, then listening resumes after 420 ms so the mic does not hear it. Falls back to
  speech when shell sounds are off. `ai.voice.chime`.
- *Speculative transcription.* While the pause detector waits, `orb_audio.py` transcribes the audio so far
  in a thread (after 0.4 s of quiet). If no speech follows, that transcript IS the final one, so `captured`
  carries `text` and the second transcription is skipped (`early: reuse`); a complete rule command after
  0.55 s of quiet ends the turn at once (`early: rule`; alarms never). The audio file is deleted by
  `orb_audio`. Speech that resumes invalidates the snapshot. Disable with `II_ORB_SPECULATE=0`.
  Checked with synthetic speech fed through a fake microphone in real time.
- *Escalation model.* `Ai.submit` accepts `context.modelId` for one turn. `ai.voice.escalationModel`
  ("haiku" or "sonnet", empty = the sidebar's model) sends orb turns that need the desktop through
  Claude Code. Same tool turn (list windows): Codex 21.6 s, Claude Haiku 3.7 s, Sonnet 4.9 s. Off by default.
- *Not done, on purpose:* a persistent `codex app-server`. Even `codex exec` for "reply ok" takes 6-9 s, with
  or without `--no-daemon`, and the bridge's per-turn MCP env, tool list and instructions are fixed when
  that process starts.

**Choosing models (2026-11-18).** Settings > AI Assistant > Models & execution > *Voice orb models* sets what
handles each stage of a spoken request: instant commands (rules, no model), quick answers (a warm Claude
Code session when `ai.voice.fastModel` is a Claude alias, otherwise a short-answer turn on that catalog model; there is no separate fallback setting) and desktop tasks (`ai.voice.escalationModel`: empty =
the sidebar's model, otherwise any tool-capable catalog id such as `claude:haiku`,
`opencode-server:opencode-go/glm-5.3-flash` or a Codex model). It changes spoken requests only. Check the
current choice with `qs -c ii ipc call companion models`; `voice-timings.jsonl` records the serving model per
turn. Verified live: GLM 5.3 Flash as the tasks model, 5.5 s generation for a "list my windows" turn
(about 0.8 s of that is Haiku deciding to hand over).

**Instant-command settings (2026-11-18).** The voice orb settings page lists what the rules handle in nine
groups (media, volume, brightness, light/dark, timers, alarms, reminders & tasks, workspaces, apps) with a switch
each (`ai.voice.rulesOff`), lets you add your own phrases (`ai.voice.customRules`: `{phrase, do, say}`, where
`do` is a `;`-separated list of actions from the same closed table and `{n}` stands for a spoken number;
custom phrases are tried before the built-ins) and has a "try a sentence" box that runs
`python3 voice_rules.py PHRASE [OFF_CSV [CUSTOM_JSON]]`. The shell sends the settings to `voice_agent.py` as a
`config` op at start and on every change. Switching a group off sends that kind of request on to the quick-answers
stage (Haiku can still run the action, about a second slower); it does not block the action.

**Small orbs (2026-11-18).** `services/ai/AiCompanionSatellites.qml` lists the live things (running or just-finished
timers, an alarm or reminder due within the hour, the playing track; at most five) and `CompanionSatellite.qml` draws
each as a small orb with a progress ring. They sit on the arc of `CompanionPlacement.satelliteOffsets`, opposite the
hover control fan and kept on screen, bud out of the orb when they appear, and the state label lifts above them. Click:
pause/resume a timer, dismiss a finished one, play/pause the track; right-click removes a timer. Only while the orb is
floating (not docked). Each of the five slots has its own input region in `orbMask`. Config: `ai.voice.satellites`,
`satelliteMedia`. Not built: orbs for background agent tasks (no clean per-task signal in `Ai`).

**Small orbs, later the same day.** They are drawn as blobs like the main orb (timer progress = a liquid level) and each
wears the main orb's `AiCreature` face with a mood for what it watches: a timer is calm, worried in its last 30 s, sleepy
when paused and delighted (fidgeting for attention) when finished; the music orb sways and looks pleased; an alarm or
reminder is curious. An orb is also shown for the running AI request (`Ai.runCoordinator`, eyes dart while it works,
"curious" when it waits on you) and, when a request finishes while the sidebar is closed and the orb is not speaking, a
lingering done/failed orb that opens the chat when clicked. Config: `ai.voice.satelliteTasks`.

**Typed messages take the spoken route (2026-11-18).** `Ai.sendUserMessage` (sidebar composer, overview search, IPC `ai ask`)
asks `AiCompanionVoiceService.canRouteTyped()` first; if yes, `typedAsk()` sends it to the same agent (instant rules, then
warm Haiku) and the answer is added to the chat in text, never spoken, with no microphone or orb listening. A hand-over
(needs the desktop / error) goes to `Ai.submit(..., "chat")` on the desktop-tasks model. Not routed: slash/! commands,
messages with attachments, while a run is active, and when `ai.voice.typedRouting` or `fastPath` is off. The reply is a
spoken-style Haiku answer, shorter and plainer than the chat model's. The answer appears when finished, not streamed.

**No Claude Code (2026-11-18).** `AiCompanionVoiceService.claudeFound` (`command -v claude` at start, "Check again" on the
settings page, and cleared if the agent reports it missing) gates `quickReady`. Without it the quick-answer stage is
skipped everywhere: spoken turns go rules then the desktop-tasks model, typed messages take the ordinary chat route, the
sidebar pill shows the real model instead of "Auto", `companion models` reports "unavailable", and the settings page shows a
warning. Instant commands never depend on it.

**Claude installed but signed out.** `claudeState` (`checking`/`ready`/`missing`/`signedOut`) comes from
`claude auth status` run with the same environment the agent uses (it parses `loggedIn`). `signedOut` is handled like
`missing`: the quick stage is skipped everywhere and the settings page says to sign in, with a "Check again" button. A
login/auth error from the agent at run time also flips it. An unreadable answer (timeout, old CLI) does not block the stage.

**Remote AI switch (2026-11-18).** The existing global AI policy (`policies.ai`: 1 On, 2 Local only, 0 Off; Settings >
Sidebars, now also the top of the Voice orb models page and `qs -c ii ipc call companion remote on|local|off`) is honoured by
everything the orb added. `Ai.onlineAllowed` false means: no warm Claude session (it is killed when the policy flips), no
screenshot to Claude, no quick-answer stage, a pinned remote desktop-tasks model is ignored in Local only (the chat model,
which must be local, takes over), Edge TTS (sends text to Microsoft) is refused via `II_LOCAL_ONLY=1`, and the plan-usage
quota calls stop. The instant rules, local speech and local models keep working; the agent is still asked first with
`quick:false` so the rules run, and anything else is handed straight back. Trap: `policies.ai` is also kept in
`~/.config/illogical-impulse/local-preferences.json` and the shell rewrites config.json from memory, so do not toggle it by
editing files (replacing config.json atomically also breaks its file watcher): use the IPC or the settings page.

## More instant commands (2026-11-20)

`voice_rules.py` now also understands, with no model call:

- **toggles** (`toggle <wifi|bluetooth|nightlight|dnd|awake|gamemode|mic> <on|off|toggle>`), **power** profile, **capture** (screenshot, area, record, region, stop, color picker), **panels** (settings, sidebar, cheat sheet, app drawer, power menu, clipboard, mixer), **windows** (fullscreen, float, pin, move to workspace N, focus an app by name; resolved against the real window list).
- **info** questions (time, date, battery, playing, volume, next alarm, notifications, focused window) answered by `answer_info()` from the `<desktop-context>` lines; if the data is missing the model gets the turn.
- **confirmed verbs**: lock, suspend, reboot, shutdown, close window. The rule only asks "say yes to confirm". `voice_agent.ask_rules` keeps one pending command for 12 s; only a plain yes emits the action with `confirmed: true`, and `AiCompanionActions.run()` refuses these verbs otherwise (model `[[DO]]` markers and custom phrases can never reach them).

Settings groups: toggles, power, capture, panels, windows, info, system. Tests: `tests/test_voice_rules.py`, `tests/test_voice_confirm.py`.
Verified live: night light, DND, power profile, panels, screenshot, float, focus, fullscreen, close-with-yes, lock-then-no. NOT verified: wifi/bluetooth/mic toggles, lock/suspend/reboot/shutdown actually firing, screen recording (record.sh did not start a recording even when run directly, a separate problem).


## What the assistant can see running

`running_now` (MCP tool + `qs ipc call aitools running`) reports what is running right now, names and counts only:
the shell's media, timers, soundscapes, recording, downloads, VPN, game mode, sleep inhibit, notifications, the AI and the
orb (`services/ai/integrations/AiRunningIntegration.qml`), the cached weather and prayer times, water/bedtime/screen-time
state, Bluetooth/Tailscale/Docker, which sensors are in use and pending updates, plus (in `shell_tools_mcp.py`) the machine's
running user services, apps playing or recording sound, the biggest process names by memory and the orb's helper programs.
The orb's quick-answer context also carries the weather and next prayer (`glance()`) and a one-line "running:" summary (`brief()`).
Settings are found and changed by the full assistant through `settings_search` / `settings_get` / `settings_set`
(the index covers every config key; protected keys stay user-only); the quick path hands settings requests over on purpose.

**Command table and recent actions (2026-11-24).** The `[[DO ...]]` list in the model prompt is generated from
`voice_rules.ACTION_HELP` (`action_prompt()`), and `tests/test_voice_rules.py` checks it against `GROUPS` and the
shell's table in `AiCompanionActions.qml`, so a verb cannot be added in one place only. The context block gains a
`recent actions:` line (the last three actions that ran, within ten minutes), so a follow-up like "turn it back up"
works after an instant command that no model saw. Natural phrasings ("it's too loud", "the third workspace",
"wake me up at seven thirty", "don't let anything disturb me") are matched whole-sentence only; `NaturalPhrasing` in
the rules tests keeps a list of casual sentences that must stay unmatched.
