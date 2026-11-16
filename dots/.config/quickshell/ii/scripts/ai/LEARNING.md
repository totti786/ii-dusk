# Continual learning in the desktop companion

Codex, Claude Code and OpenCode share the same local knowledge store. Their CLI
sign-ins still own authentication; no API key or embedding service is needed.

## The learning loop

1. The user completes a meaningful task through the companion.
2. The bridge records the user's request, the answer and bounded actual tool
   outcomes. Screenshots are not copied into the learning audit. Casual thanks
   and knowledge-only lookups do not trigger another review.
3. A durable local job is queued. A short-lived background worker asks the same
   signed-in engine to review the outcome with **knowledge tools only**. It cannot
   run shell commands, browse, change settings, or control the desktop. Reviews
   use that engine's account allowance, separately from the user-facing answer.
4. The reviewer searches existing knowledge before writing. Durable facts use
   stable keys so corrections update the previous value. Automatic facts need
   an exact quote from the user's own explicit preference/fact, not an inference
   from assistant prose or a live system reading.
5. Useful procedures are saved or revised with triggers, verification steps,
   evidence references and versions. Failed/unverified attempts can be retained
   as **drafts**; the proxy prevents an unverified review from promoting them to
   working skills. Drafts are excluded from ordinary skill retrieval. A later
   verified task can update/promote an existing draft.
6. Future requests retrieve relevant facts, verified skills and historical
   conversation excerpts. The loop therefore changes future behavior rather
   than only producing an unused review log.

There is one worker lock. Jobs survive restart; interrupted jobs are retried,
and errors are visible in Settings. Failed reviews have a bounded retry policy
and do not spin indefinitely. Reviews cannot recursively enqueue more reviews.
The newest 100 completed/skipped jobs are retained as an audit trail.

## Controls and review

Open **AI Assistant → Context & Memory**:

- Reopen the last conversation on startup.
- Enable memory and choose the fact limit (40 by default).
- Enable retrieval from earlier conversations.
- Choose an approximate input-context budget (12,000 tokens by default).
- Enable saved skills and automatic post-task learning independently.
- Inspect learning status, its last result, saved skills and verification
  evidence. Forget a skill from this page; facts remain editable in the
  sidebar's Memory view.

The `remember_fact`, `memory_search`, `memory_forget`, `skill_search`,
`skill_save` and `conversation_search` tools are shared by all three engines.
Search results include fact/skill IDs or session/message references. Explicit
skill searches can include drafts for review. Project-specific entries are
isolated from other projects; global preferences remain shared. Automatic
learning preserves the knowledge-tool permissions offered on the original task.

## Storage

- Facts: `~/.local/state/quickshell/user/ai/memory.json`.
- Skills: `~/.local/share/quickshell-ii/skills/<name>/SKILL.md`, with metadata,
  versions, evidence and optional project scope beside each file.
- Rebuildable local FTS5 index: `knowledge.sqlite3` in the AI state directory.
- Learning jobs/status: `learning-jobs/` and `learning-status.json` there.
- Recovery copies: `knowledge-history/` and the skill library's `.trash/`.

These paths respect `XDG_STATE_HOME` and `XDG_DATA_HOME`. Data files are private
to the user. Forgetting removes an entry from active recall and suppresses exact
forgotten fact text from historical retrieval/replay; recovery copies and the
original saved conversation are retained. It is not a secure-erasure operation.

## Context management

Every turn gets the live desktop architecture, recent complete conversational
turns and a bounded selection of relevant personal knowledge. Local BM25/FTS5
ranks references without an extra model request. Broad pinned preferences stay
available across topics. Historical records carry source references and are
treated as reference data, not instructions or proof of current system state.

Long replay is bounded independently of whether a provider advertises its
context window. Existing optional conversation summarization remains available.
Older relevant excerpts can be recalled, and the full saved transcript remains
searchable. Large text attachments are explicitly marked as selected excerpts;
the agent can read their files in chunks when more detail is needed. Current
messages that exceed the budget are rejected with an explanation rather than
silently cut. Token counts are estimates, and the native agents also manage
their own in-turn tool context.

## Validation

The full AI test run passed 801 of 803 checks. The remaining two pre-existing
failures are older media/null-player and alarm-date source contracts; the new
memory, retrieval and learning tests pass. The full log is at
`/tmp/qs-ai-final-learning-validation.log`.

Tests exercise fact replacement, scoped retrieval, Arabic text, forgetting,
skill versions/drafts, source evidence, disabled learning, bounded replay,
attachment excerpts, durable review jobs and recovery after interruption.

Live verification included:

- A real shell process restart restored the same conversation, fact and skill.
- Codex saved a preference and Claude retrieved that same fact and revised the
  shared wallpaper skill to version 2.
- Completing a live battery/network/CPU/memory task automatically queued a
  review and generated `quickshell-live-system-report` without a skill-save
  request. It retained the reusable procedure and unavailable-reading caveats,
  without saving transient measurements as facts.
