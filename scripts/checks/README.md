# Checks

Verification tools for mira-apps. There is no CI in this repo, so a local build
is the only automated check there is — and a build only proves the code
compiles, not that it still looks or decodes the way it did. These fill that gap
for the changes where "it compiles" is a particularly weak signal.

They lived in `mira-core/notes/` until 2026-08-08, which was wrong twice over:
mira-apps tooling in another repo, and in a gitignored folder, so a fresh clone
of mira-core would have silently dropped all of them. mira-apps hosts all things
mira-apps.

| tool | answers |
|---|---|
| `radius-check.py` | did a corner-radius change alter what anything renders? |
| `typescale-check.py` | did a font-role substitution alter (size, weight, design)? |
| `decode-check.sh` | do the app's model/backend/memory types still decode the live server? |
| `connection-check.sh` | does a failed request still say what actually went wrong? |
| `approval-protocol.md` | notes on the destructive-action approval contract |

All are read-only and safe to run at any time.

```bash
scripts/checks/radius-check.py [git-ref]     # default HEAD
scripts/checks/typescale-check.py [base-ref] # default HEAD
scripts/checks/decode-check.sh [server-url]  # default http://localhost:8000
scripts/checks/connection-check.sh           # no server, no token
```

## What they are for

`radius-check.py` and `typescale-check.py` both exist because
`specs/type-scale.md` forbids changing how anything looks under a rename. A
rename that quietly moves a value compiles perfectly and is invisible in review;
these are what make it fail loudly instead.

`radius-check.py` compares, per file, the **multiset of resolved radii** before
and after — literals as themselves, `Radius.foo` resolved through that
revision's own `Theme.swift`. It deliberately does *not* pair diff lines: the
earlier version zipped removed and added lines positionally, which works on a
one-file diff and pairs lines from different files on a wide one, reporting
mismatches that were artefacts of the pairing. `typescale-check.py` still uses
line pairing and has the same weakness — treat a mismatch it reports on a large
diff as a prompt to look, not as proof.

`decode-check.sh` covers `/models`, `/backends` and `/hardware`. The third is
there because it is the only one whose failure is silent: a renamed key in
`/models` empties a picker and someone notices, while a renamed key inside
`system_memory` decodes to `.unknown`, renders as nothing, and is
indistinguishable from a healthy machine — the banner would simply never appear
again and nothing would report it. So it asserts more than "decoding threw
nothing": every advisory the server can emit maps to a known case, the states
that must stay silent stay silent, and absence in all its shapes still passes,
since an older server, a non-mira-mlx backend and a backend still starting all
legitimately send nothing.

`connection-check.sh` covers the other half of the same problem: not whether a
success decodes, but whether a *failure* explains itself. It needs no server —
every input is a constructed status code — because the types it compiles were
split out of `APIClient.swift` into `ConnectionErrors.swift` for exactly that
reason. `APIClient` reaches `ThinkingMode` in `ChatViewModel.swift`, which pulls
in SwiftUI, so nothing in that file could be checked without building the app.

It asserts that 401 points at the token, 403 points at `allowed_hosts`, 503 says
"starting", an unreachable server names the connection, and that no two of those
four read the same — collapsing any pair sends the user to the wrong fix. It
also asserts no message reads as "couldn't be read", which is the wording the
original bug produced for a 401.

Its last assertion is a grep, not Swift: the number of direct `session.data`
calls in `APIClient.swift`. `send()` is what inspects the status before anything
is decoded, and a new call site that skips it reintroduces the bug one endpoint
at a time. Six are expected and each is listed in the script. A seventh is not
automatically wrong — it needs a reason, and the count needs updating with it.

It reports failures rather than trapping. Compiled at `-O`, a failed
`precondition` aborts *without printing its message*, so a real failure arrived
as `Trace/BPT trap: 5` with the reason gone. All assertions now go through a
`check()` that prints and counts, and the exit code comes from the total.

## Credentials

`decode-check.sh` needs the server's auth token. It reads `MIRA_TOKEN`, falling
back to `auth_token` in `$MIRA_YAML` (default `~/Projects/mira-core/mira.yaml`),
and never echoes it. An earlier version had the token hardcoded on line 3 —
in a repo that is public. Do not put a credential back into these files.
