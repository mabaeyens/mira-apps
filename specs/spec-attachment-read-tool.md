# Spec: Attachment-Read Tool + Clear Attachment Framing

## Status: NOT IMPLEMENTED

## Problem

Attaching a file and asking Mira to act on it fails in confusing ways. Example: attach a 2-line
`small.pdf` and send "review this". Mira spends ~2 minutes "thinking", says it can't open the
file, and reaches for GitHub tools — even though the PDF's full text ("This is a small PDF for
testing RAG. That's it.") is present in the RAG context and shown in the document-chunk section.

The model has the content but doesn't realise it, because the content is framed like retrieved
search context rather than "the file the user just attached and asked you to review."

## What's actually happening

- **Non-text files become RAG, not inline content.** `file_handler.load_file_bytes` returns a PDF
  as `{"type": "rag", ...}` (`mira-core/core/file_handler.py:147`). In `stream_chat`, only
  `type == "text"` attachments are inlined as `[File: <name>]\n<content>`
  (`mira-core/core/orchestrator.py:401–409`). A `rag` attachment is indexed
  (`orchestrator.py:369–376`) and surfaces **only** through retrieval as
  `[Relevant document sections]\n[Source: <name> | Score: …]\n<text>` (`orchestrator.py:411–416`).
- **The framing reads like web/search context.** "Relevant document sections / Source / Score"
  looks like retrieved background, not "here is the attachment to act on." The model doesn't
  connect "review this" → that block, so it tries to *open* the file with a tool.
- **No tool can open it.** In a no-project chat, `_active_tools` excludes all local file tools
  (`orchestrator.py:191–194`; see `spec-agentic-local-file-fallback.md`). The only file-ish tools
  are `fetch_url` and `github_*`, so the model fabricates `fetch_url("file://…")` (→ see
  `spec-temp-workspace.md`) and wanders into GitHub.

## Fix

Chosen approach: **give the model a real attachment-read tool**, plus reframe presentation so the
model knows what was attached.

### 1. Track attachments per conversation
Persist a per-conversation registry of attachments handled this session: name, type, size, and a
handle to the content/bytes (in memory and/or on disk via `spec-temp-workspace.md`). This lets a
tool resolve "the attachment named X" across turns, not just the turn it was uploaded.

### 2. New tools (available even without a project)
- `list_attachments()` → names + types + sizes of files attached to this conversation.
- `read_attachment(name, [offset/limit])` → returns the (text-extracted) content of an attachment
  by name; for large files supports ranged reads. Backed by the registry above. These are added to
  `TOOLS` (`mira-core/core/tools.py`) and are **not** in `_LOCAL_TOOLS`, so they remain available
  in general chat.

### 3. Reframe the presentation (`mira-core/core/orchestrator.py:401–416`)
When files were attached this turn, prepend an explicit, unambiguous note, e.g.:
"The user attached these files: `small.pdf`. Their content is provided below / readable with
`read_attachment`. Use it directly — do NOT use web or GitHub tools to open them." Keep RAG
retrieval for large docs, but label the block as the attachment(s), not generic "document
sections."

## Caveats
- Overlaps with `spec-temp-workspace.md`: if attachments are written to a temp workspace, the
  existing `read_file`/`search_files` tools may cover most of this — `read_attachment` can then be
  a thin convenience wrapper that resolves by attachment name rather than path. Decide whether to
  ship the dedicated tool, the temp-workspace path, or both.
- Image attachments (`type == "image"`) already flow as vision input (`orchestrator.py:407`) and
  are out of scope here.
- Keep RAG for genuinely large attachments; inlining everything would blow the context window
  (see `spec-temp-workspace.md` for the small-file inline option, which the user did not choose
  here).

## Scope
- `mira-core/core/tools.py` (tool schemas: `read_attachment`, `list_attachments`)
- `mira-core/core/orchestrator.py` (attachment registry, tool dispatch, reframed presentation)
- Possibly `mira-core/core/file_handler.py` (expose extracted text for `read_attachment`)

## Verification
1. Attach `small.pdf`, send "review this" → Mira reads the attachment content directly (via the
   tool or inline), answers quickly, never invokes GitHub tools.
2. Attach a file, then in a later turn ask about it → `read_attachment`/`list_attachments`
   resolves it from the registry.
3. A large attachment still indexes into RAG and is retrievable, without inlining the whole file.
