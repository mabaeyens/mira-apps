# mira-apps changes needed after the 2026-07-20 confirmation-gate fix

LOCAL ONLY (`notes/` is gitignored). Companion to `security-audit-2026-07.md`.
When this eventually becomes a mira-apps issue or CHANGELOG entry, describe it as
a **UX/protocol change** ("destructive actions now require an explicit tap to
approve"), not as a vulnerability fix.

## What changed server-side

Approval for a destructive action used to be a `force` / `confirm` boolean in the
tool's own JSON schema — i.e. **the model filled it in**. It is now an
out-of-band token that only the user can supply.

Affected tools: `run_shell`, `delete_file`, `github_merge_pr`,
`github_delete_file`, `github_delete_branch`.

## The new flow

1. Model calls e.g. `run_shell {"command": "rm -rf build/"}`.
2. Server matches its destructive-pattern list and **refuses**, returning:

   ```json
   {
     "requires_confirmation": true,
     "action": "run_shell",
     "command": "rm -rf build/",
     "matched": "rm -rf",
     "approval_token": "ee13a2dd54f41fddf9ab74306d3abd38",
     "message": "..."
   }
   ```

3. Client shows a confirm dialog with `command` / `path` and the `matched` label.
4. If the user approves, the client sends the **next** `/chat` request with the
   token echoed back:

   ```
   POST /chat  (multipart/form-data)
     message=<usually the same instruction, or "yes, go ahead">
     conversation_id=<same>
     approved_tokens=ee13a2dd54f41fddf9ab74306d3abd38     # repeatable field
   ```

5. Server honours the action only if the model asks for **exactly** the same
   command again. A token for `rm -rf build/` does not approve `rm -rf ~/`.

## API contract

- `POST /chat` gains an optional repeatable form field **`approved_tokens`**.
  Absent → no approvals → destructive actions refused. Fully backwards
  compatible: an app that never sends it keeps working, it simply cannot run
  destructive actions.
- Approvals are **scoped to a single request**. They are not remembered across
  turns; the client must re-send a token for each request that should carry it.
  (Deliberate: a stale approval silently authorising a later command is the
  failure mode being removed.)
- The token is a content hash, not a secret. It carries no authority by itself —
  its only property is that the model cannot mint one for an action the user was
  never shown.

## Until the app is updated

Destructive commands are **refused, every time**. Non-destructive commands are
unaffected, so normal use is unchanged. This is a deliberate fail-closed choice:
the previous behaviour was that the model could approve itself.

If that is too disruptive before an app release, the interim options are:
- add a `mira.yaml` escape hatch to auto-approve (re-opens the hole — not
  recommended), or
- ship the app change first, then this server change together in one release.

## Client work items

- [ ] Parse `approval_token` from any tool result carrying `requires_confirmation`
- [ ] Confirm dialog: show `command` (or `path`), `matched`, and `message`
- [ ] Hold pending tokens per conversation; send as `approved_tokens` on the next
      `/chat`
- [ ] Clear a pending token once used or once the user declines
- [ ] Handle several pending approvals in one turn (field is repeatable)
- [ ] The model may still *narrate* that it needs approval — make sure the UI
      does not double-prompt

## Note on the prompt

`core/prompts.py` still instructs the model to "ask the user to confirm". That
text is now describing the UI's job rather than a mechanism the model controls.
Worth rewording when the app lands, so the model relays the refusal instead of
retrying — the tool description in `core/tools.py` already says not to retry.
