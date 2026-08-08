#!/usr/bin/env python3
"""Verify a corner-radius change was a rename and not a restyle.

Sibling of typescale-check.py, which does the same job for fonts. The spec
(specs/type-scale.md) forbids changing how anything looks under a rename, so
this is the check that enforces it.

Method: for every file the diff touches, resolve EVERY corner radius in the old
revision and in the new working tree down to a number — literals as themselves,
`Radius.foo` through that revision's own Theme.swift — and compare the two
multisets. If a file rendered radii {8,8,12} before and {8,8,12} after, nothing
moved, regardless of which line each came from.

This replaced a line-pairing approach that zipped the diff's removed and added
lines positionally. That works on a single-file diff and quietly pairs lines
from *different files* on a wide one, reporting mismatches that are artefacts of
the pairing rather than real changes. A check that cries wolf on a correct
change is as useless as one that passes a broken one.

Usage: scripts/checks/radius-check.py [git-ref]   (default: HEAD)
"""
import os
import re
import subprocess
import sys
from collections import Counter

# Derived from this file's location, not hardcoded: the tool lives in the repo
# it checks, so it should keep working after a clone or a move.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
THEME = "OllamaSearch/Shared/Views/Theme.swift"
TOKEN_DECL = re.compile(r"static let (\w+): CGFloat = (\d+)")
RADIUS = re.compile(r"cornerRadius\(?:? ?(?:Radius\.(\w+)|(\d+))")

ref = sys.argv[1] if len(sys.argv) > 1 else "HEAD"


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args],
                          capture_output=True, text=True).stdout


def token_table(source):
    return {n: int(v) for n, v in TOKEN_DECL.findall(source)}


def radii(source, table, where):
    """Every corner radius in `source`, resolved to a number."""
    out, unresolved = [], []
    for tok, lit in RADIUS.findall(source):
        if lit:
            out.append(int(lit))
        elif tok in table:
            out.append(table[tok])
        else:
            unresolved.append(f"Radius.{tok} ({where}) is not declared in that revision's Theme.swift")
    return Counter(out), unresolved


# Resolve both revisions' token tables. New side reads the WORKING TREE, not the
# index: the point is to validate an edit before it is staged, and `git show
# :path` would resolve tokens from the pre-edit file and compare the change
# against itself.
new_tokens = token_table(open(os.path.join(REPO, THEME)).read())
old_tokens = token_table(git("show", f"{ref}:{THEME}"))
if not new_tokens:
    sys.exit("FAIL: no Radius tokens found in the working tree's Theme.swift")

print("old tokens: " + (", ".join(f"{k}={v}" for k, v in sorted(old_tokens.items())) or "(none)"))
print("new tokens: " + ", ".join(f"{k}={v}" for k, v in sorted(new_tokens.items())))

changed = [f for f in git("diff", "--name-only", ref, "--", "OllamaSearch").splitlines()
           if f.endswith(".swift")]
if not changed:
    print(f"\nNo Swift files changed against {ref} — nothing to verify.")
    sys.exit(0)

problems, checked_files, total = [], 0, 0
for f in changed:
    before, _ = radii(git("show", f"{ref}:{f}"), old_tokens, f"{ref}:{f}")
    path = os.path.join(REPO, f)
    after, unresolved = radii(open(path).read() if os.path.exists(path) else "",
                              new_tokens, f"working tree {f}")
    problems.extend(unresolved)
    if not before and not after:
        continue
    checked_files += 1
    total += sum(after.values())
    if before != after:
        gained = after - before
        lost = before - after
        problems.append(
            f"{f} renders different radii\n"
            f"      before: {dict(sorted(before.items()))}\n"
            f"      after : {dict(sorted(after.items()))}\n"
            f"      added: {dict(sorted(gained.items())) or '{}'}  "
            f"removed: {dict(sorted(lost.items())) or '{}'}")

print(f"\n{checked_files} file(s) with radii checked, {total} radius use(s) resolved.")
if problems:
    print(f"\nFAIL — {len(problems)} problem(s):")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1)
print("PASS — every file renders exactly the radii it did before.")
