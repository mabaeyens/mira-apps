# Spec: Fast Fallback When a Referenced Local File Is Unreachable

## Status: NOT IMPLEMENTED

## Problem

Asking Mira about a local file that it cannot reach — e.g. `fix the crash in parser.py` in a
conversation with **no active project** — causes a long agentic loop (minutes) before any answer.
The user can see step after step and usually cancels. The expected behaviour is a quick:
"I don't have access to `parser.py` — attach it or open a project, and I'll take a look."

This is worse when thinking is on (more latency per step), but the loop is the root issue.

## What's actually happening

- **No filesystem tools in general chat.** `_active_tools` (`mira-core/core/orchestrator.py:191–194`)
  returns the full `TOOLS` list only when `workspace_root` is set (an active project with a
  `local_path`). Otherwise it strips `_LOCAL_TOOLS` (`mira-core/core/tools.py`) — `read_file`,
  `write_file`, `edit_file`, `list_files`, `search_files`, `move_file`, `delete_file`, `run_shell`.
  So in general chat the model has only `web_search`, `fetch_url`, the `github_*` tools and
  `task_done`.
- **The system prompt pushes persistence.** RULE 7 (`mira-core/core/prompts.py:98–100`) says
  "keep working until the goal is fully achieved — do not stop mid-way." With no local-file tool
  available, the model improvises: it tries `fetch_url` on a fabricated path, searches GitHub,
  retries with varied queries.
- **Loop guards don't catch it.** `AGENT_DIVERGENCE_LIMIT = 1` (`config.py`) only trips on
  *identical* tool+args repeats; the model varies arguments each step so divergence never fires.
  `SAME_TOOL_REPEAT_LIMIT = 15` and `MAX_AGENT_STEPS = 15` are far too loose to bail early on a
  hopeless local-file hunt.
- The system prompt already states tools are unavailable in general chat
  (`prompts.py:28–30`), but nothing tells the model what to *do* about a local-file request in
  that mode — so it doesn't conclude "I can't reach this; ask the user."

## Fix

Primarily a prompting change, optionally backed by tighter loop guards.

### Prompt (`mira-core/core/prompts.py`)
Add a rule (general-chat mode especially): when the user references a local file or path that is
not reachable with the currently available tools, **stop and say so immediately** — ask the user
to attach the file or open a project. Never fabricate a `file://` / workspace path, and never use
`web_search`/`fetch_url`/`github_*` to try to reach a local file. (This pairs with RULE 7: "fully
achieved" includes correctly concluding that the goal is not achievable with the current tools.)

### Optional loop hardening (`mira-core/core/config.py` + orchestrator loop)
- Lower `SAME_TOOL_REPEAT_LIMIT` for unproductive read-only tools (e.g. repeated failed
  `fetch_url`/`github_search_code`) so a hopeless hunt bails in 2–3 tries, not 15.
- Consider a "no progress" heuristic: N consecutive tool calls that all error or return empty →
  inject a redirect telling the model to summarise what it could not do and respond.

## Caveats
- Once a per-session temporary workspace exists (see `spec-temp-workspace.md`), an *attached*
  file becomes reachable via local tools, so this fallback should fire only when the file is
  genuinely absent — not when it was attached.
- Tightening loop guards risks bailing too early on legitimate multi-step web/GitHub tasks; tune
  per-tool rather than globally, and keep the higher caps for productive tools.

## Scope
- `mira-core/core/prompts.py` (new rule, ~5 lines)
- Optional: `mira-core/core/config.py` + the agentic loop in `mira-core/core/orchestrator.py`

## Verification
1. General chat (no project): `fix the crash in parser.py` → within ~1 step Mira replies it can't
   access the file and asks the user to attach it or open a project. No multi-minute loop.
2. Same request with the file **attached** → Mira uses the attachment, does not bail (depends on
   `spec-attachment-read-tool.md` / `spec-temp-workspace.md`).
3. A legitimate multi-step web task still runs to completion (no premature bail).
