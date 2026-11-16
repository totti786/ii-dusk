# Signed-in AI agents

Open the Intelligence sidebar and click the model chip beside the microphone.
Choose **Codex**, **Claude Code**, or **OpenCode**. Click an engine header to
expand its individual model choices, or search by model name. Codex and Claude
choices come from their native CLI catalogs, cached for ten minutes without
generating a response. Default rows show the model the CLI currently recommends.
Claude aliases such as `opus` track the version offered by Claude Code. OpenCode
shows models already connected to its service. The floating voice orb uses the
same selected engine, conversation and tools as the sidebar.

All three engines are installed and signed in on this machine. QuickShell
does not require API keys. If a login expires, run the appropriate command:

```sh
codex login
claude auth login
opencode auth login
```

Then open **Settings → AI Assistant → Agents & Sign-in** and refresh connection
status. Codex uses its ChatGPT login; Claude Code uses its Claude subscription
login; OpenCode uses its connected providers. Their account limits still apply.
An OpenCode provider needs its own supported authentication; the shell does not
turn an unconnected provider into a free service.

## Architecture

`agent_models.py` discovers the native choices via Codex `model/list` and Claude
streaming control initialization, retaining only public model metadata.
`ModelCatalog.qml` exposes only those three agent backends. One
`OpencodeStrategy.qml` consumes the shared event stream from `agent_bridge.py`.
The latter runs the native Codex/Claude CLIs or delegates to the existing
OpenCode service bridge. QuickShell remains the source of conversation history;
Codex/Claude turns are ephemeral and receive the current transcript.

`agent_tools_mcp.py` exposes only the tools offered for the current turn. Native
Codex/Claude tools and unrelated user MCP configurations are disabled for these
turns. Browser control, screenshots, desktop input, files, shell commands and
settings go through the existing shell tools and approval rules. Auto mode
continues to allow ordinary actions; privileged commands retain approval.
Cancellation terminates the CLI process group and its MCP child processes.
MCP configuration explicitly passes a small allowlist of desktop connection
variables (including WAYLAND_DISPLAY and XDG_RUNTIME_DIR). Codex otherwise
filters these out, making QuickShell IPC misidentify a running shell as absent.
OpenCode reconnects its tool server when that desktop connection changes.

Codex/Claude inherit their normal CLI login storage. API-key environment
variables are removed from their subprocess environment. QuickShell neither
copies subscription tokens nor adds a separate credential store. A local CLI
or loopback server can use cloud models, so all three are blocked by Local-only
AI policy. Kokoro speech and local speech recognition remain independent.

The active UI no longer loads API-key testing, OpenRouter import catalogs or
Ollama model catalogs. Legacy strategy/catalog source files remain available
for rollback; they are not instantiated by the active agent path. Ollama
startup model probing was removed; optional RAG embedding support is separate.

## Desktop context and native actions

Every turn through the shared strategy includes a small live description of
QuickShell ii, Hyprland, the shell source location, wallpaper configuration and
native control routes. This also applies to callers with their own system
prompt, including compact search. It is shared by Codex, Claude and OpenCode.
`desktop_context` refreshes that snapshot during a turn. Hardware, installed
packages, services and unfamiliar config are inspected on demand rather than
copied into every prompt.

`wallpaper_search` walks the configured library recursively (up to eight
subfolder levels), returns real files rather than folders, and excludes paths
and symlinks outside that library. `wallpaper_set` validates the selected file
and calls the existing `Wallpapers.apply` renderer/theme pipeline through IPC.
It follows the normal Auto/approval setting and journals the previous image
for `undo_change`. The result distinguishes configuration verification from
asynchronous visible rendering; `desktop_capture` can verify the screen.
Generic tools such as feh or waypaper are not used for this shell's wallpapers.

Validated in the running sidebar: native context, recursive search, reapplication
of the existing wallpaper and a subsequent context check all succeeded. The
active image was retained. Tests cover nested folders, external symlinks,
invalid files, native apply routing and undo journaling.

## Continual learning

Facts, verified skills, historical retrieval and the post-task learning worker
are shared across the three engines. See [Learning and context](LEARNING.md)
for the loop, controls, storage and validation.

## Verification and rollback

```sh
qs -c ii ipc call ai agents
python3 -m unittest discover -s scripts/ai/tests -p test_agent_bridge.py
```

Live checks passed for signed-in text generation and `companion_status` tool
execution through all three engines, plus image attachments through Codex and
Claude. The account panel and model picker were inspected in the running shell.
Explicit selection was verified by choosing GPT-6 Luna in the UI, observing
`--model gpt-6-luna` on the native process, and receiving READY in the chat.
The previous Claude Default selection was then restored.

Pre-change main files are backed up under
`~/.local/state/quickshell/user/ai/agent-stack-backup/`. No existing credentials
were deleted. The full regression suite currently has two unrelated failures
in older media/null-player and alarm-date source contracts; see the final test
log at `/tmp/qs-ai-desktop-context-final-tests.log`.
