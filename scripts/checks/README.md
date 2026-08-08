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
| `decode-check.sh` | do the app's model/backend types still decode the live server? |
| `approval-protocol.md` | notes on the destructive-action approval contract |

All are read-only and safe to run at any time.

```bash
scripts/checks/radius-check.py [git-ref]     # default HEAD
scripts/checks/typescale-check.py [base-ref] # default HEAD
scripts/checks/decode-check.sh [server-url]  # default http://localhost:8000
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

## Credentials

`decode-check.sh` needs the server's auth token. It reads `MIRA_TOKEN`, falling
back to `auth_token` in `$MIRA_YAML` (default `~/Projects/mira-core/mira.yaml`),
and never echoes it. An earlier version had the token hardcoded on line 3 —
in a repo that is public. Do not put a credential back into these files.
