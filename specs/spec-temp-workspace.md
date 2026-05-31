# Spec: Per-Session Temporary Workspace + fetch_url Protocol Guard

## Status: NOT IMPLEMENTED

## Problem

Two related failures in no-project chats:

1. **Attachments have nowhere to live on disk.** Without an active project there is no workspace
   root, so attached files can't be written to disk for the filesystem tools or path-based RAG to
   use. The model, lacking a way to reach the file, fabricates a path like
   `file://workspace/small.pdf`.
2. **`fetch_url` leaks a raw error.** When the model calls `fetch_url("file://workspace/small.pdf")`,
   the UI shows `file://workspace/small.pdf - Error: requestURL is missing an http: or https:
   protocol` — the raw httpx error, surfaced verbatim.

## What's actually happening

- **Workspace is project-bound.** `workspace_root` is `self.project["local_path"]`
  (`mira-core/core/orchestrator.py:187–188`); `WORKSPACE_ROOT` defaults to `~/workspace`
  (`mira-core/core/config.py:65`) but is only used by the fs tools when a project supplies a path.
  No project ⇒ no workspace ⇒ fs tools stripped (`orchestrator.py:191–194`) and nowhere to drop an
  attachment.
- **`fetch_url` doesn't validate scheme.** `fetch_url` calls `httpx.get(url, …)`
  (`mira-core/core/url_fetcher.py:26`) and catches only `httpx.TimeoutException` and
  `httpx.HTTPStatusError`. A `file://` URL raises httpx's "Request URL is missing an 'http://' or
  'https://' protocol", which isn't caught and propagates as the tool result string shown to the
  user.

## Fix

### 1. Per-session temporary workspace (the user's idea)
Create a temporary workspace directory on the device for conversations without a project (e.g.
under the OS temp dir or app-support, keyed by conversation id). On attachment upload, write the
file there; point the workspace-scoped fs tools (`read_file`, `search_files`, `list_files`) **and**
RAG-by-path at this directory so the model can read/search attachments even in general chat. Clean
up the directory when the conversation ends / session closes.

Open design questions to resolve during implementation:
- Whether the temp workspace also enables `write_file`/`run_shell` (sandboxed) or stays read-only
  for safety in general chat.
- Lifecycle: per-conversation vs per-app-session; eviction policy and size cap.
- How this composes with `spec-attachment-read-tool.md` — the temp workspace is the storage
  layer; `read_attachment`/`list_attachments` can be a name-based convenience over it, or the
  plain `read_file` may suffice once a workspace exists.

### 2. fetch_url protocol guard (`mira-core/core/url_fetcher.py`)
Before calling httpx, reject non-`http(s)` URLs with a clear, model-readable message rather than
leaking the stack-trace string, e.g.:
"I can only fetch http(s) URLs. To use a local file, attach it to the conversation." Also broaden
the `except` to catch malformed-URL/protocol errors defensively. This stops the ugly UI error and
nudges the model toward the right action (use the attachment, not a fabricated path).

## Caveats
- Security: a writable temp workspace + `run_shell` in general chat widens the sandbox surface;
  default to read-only or a tightly scoped temp dir, and never resolve paths outside it (reuse the
  existing `_safe_path`/`workspace.safe_path` guards).
- Device storage: cap total temp-workspace size and clean up reliably (app may be backgrounded /
  killed on iOS) to avoid leaking files.
- The protocol guard is independent and low-risk; it can ship before the temp-workspace work.

## Scope
- `mira-core/core/url_fetcher.py` (scheme validation + broader error handling) — small, standalone
- `mira-core/core/orchestrator.py` + `mira-core/core/config.py` (temp-workspace creation, wiring fs
  tools + RAG to it, lifecycle/cleanup) — larger
- Coordinate with `spec-attachment-read-tool.md` (storage vs. tool layer) and
  `spec-agentic-local-file-fallback.md` (attached files become reachable, so the "can't reach it"
  fallback should only fire for genuinely absent files).

## Verification
1. No-project chat: attach a file → it is written to the temp workspace and is readable/searchable
   via the local tools; the model answers about it without fabricating paths.
2. `fetch_url("file://…")` → returns the friendly "I can only fetch http(s) URLs…" message; no raw
   httpx error reaches the UI.
3. Conversation end / session close → temp workspace is cleaned up (no leftover files).
