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
Speech input uses local Voxtype exclusively, with the multilingual base model.

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

Agent Auto mode is enabled in this environment: browser actions, screenshots,
input, ordinary commands and speech run without individual approval cards.
The setting can be changed in AI Tools & Permissions. Root-level
commands retain their separate approval. Auto mode is broad user-level access,
not a security sandbox; confirmation of irreversible actions in auto mode is a
model instruction, not a technical transaction barrier. Tool permissions can
disable individual capabilities. Screen/page content is marked untrusted.

Pointer input, shortcuts and fallback typing use `ii-companion-input.service`, a user ydotoold with a
0600 socket at `$XDG_RUNTIME_DIR/ii-companion-input.sock`. It uses this machine's
existing /dev/uinput ACL, with no sudo or new root service. Stop it with:

    systemctl --user disable --now ii-companion-input.service

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
  session. Eight seconds without speech also ends it. There is no wake word.
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

`ii-companion-voice.service` keeps the model warm behind a private 0600 Unix
socket. Text is split into short sentences/clauses, with a bounded synthesis
queue. Playback starts with the first chunk, and subsequent synthesis overlaps
playback. Disconnecting the client stops audio immediately and cancels remaining
chunks. The service uses roughly 470–580 MiB resident memory here, with a 900 MiB cap.

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
