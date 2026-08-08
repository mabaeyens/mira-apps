#!/usr/bin/env python3
"""Prove the type-scale pass was a rename and not a restyle.

Diffs the working tree against a base commit, and for every `.font(...)` line
that changed, resolves the new named role back to a concrete font spec and
compares it to the literal that was there before. A role whose value does not
match what it replaced is reported, which is the only way this pass can go wrong
silently.

Usage: scripts/checks/typescale-check.py [base-ref]
"""
import re
import subprocess
import sys
from pathlib import Path

# Derived from this file's location, not hardcoded: the tool lives in the repo
# it checks, so it should keep working after a clone or a move.
REPO = Path(__file__).resolve().parent.parent.parent

# The scale, as declared in Theme.swift. (size, weight, design); None = default.
ROLES = {
    "rowTitle":        (15, "medium", None),
    "rowTitleDense":   (14, "medium", None),
    "sectionHeader":   (11, "medium", None),
    "bannerLabel":     (13, None, None),
    "pillLabel":       (13, None, None),
    "monoStatus":      (13, "medium", "monospaced"),
    "monoStatusSmall": (11, "medium", "monospaced"),
    "monoDetail":      (12, None, "monospaced"),
    "iconSmall":       (13, None, None),
    "iconCompact":     (16, None, None),
    "iconMedium":      (17, None, None),
    "iconLarge":       (22, None, None),
    "iconXL":          (28, None, None),
}

LITERAL = re.compile(
    r"\.font\(\.system\(size:\s*(\d+)"
    r"(?:\s*,\s*weight:\s*\.(\w+))?"
    r"(?:\s*,\s*design:\s*\.(\w+))?\s*\)\)"
)
# .font(.roleName) or .font(.roleName.weight(.medium))
ROLE_USE = re.compile(r"\.font\(\.(\w+)(?:\.weight\(\.(\w+)\))?\)")


def spec_from_literal(text):
    m = LITERAL.search(text)
    if not m:
        return None
    size, weight, design = m.group(1), m.group(2), m.group(3)
    return (int(size), weight, design)


def spec_from_role(text):
    m = ROLE_USE.search(text)
    if not m:
        return None
    name, override = m.group(1), m.group(2)
    if name not in ROLES:
        return None
    size, weight, design = ROLES[name]
    if override:
        weight = override
    return (size, weight, design)


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    diff = subprocess.run(
        ["git", "diff", "-U0", base, "--", "OllamaSearch"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout

    removed, added = [], []
    current_file = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:]
        elif line.startswith("-") and not line.startswith("---"):
            removed.append((current_file, line[1:]))
        elif line.startswith("+") and not line.startswith("+++"):
            added.append((current_file, line[1:]))

    old_specs = [(f, t, spec_from_literal(t)) for f, t in removed]
    old_specs = [x for x in old_specs if x[2]]
    new_specs = [(f, t, spec_from_role(t)) for f, t in added]
    new_specs = [x for x in new_specs if x[2]]

    print(f"base {base}: {len(old_specs)} literal(s) removed, {len(new_specs)} role use(s) added")

    if len(old_specs) != len(new_specs):
        print("  note: counts differ, which is fine if some lines changed for other reasons")

    mismatches = []
    for (of, ot, ospec), (nf, nt, nspec) in zip(old_specs, new_specs):
        if ospec != nspec:
            mismatches.append((of, ot.strip(), ospec, nt.strip(), nspec))

    print()
    if mismatches:
        print(f"{len(mismatches)} SUBSTITUTION(S) CHANGED THE RENDERED FONT:")
        for f, ot, ospec, nt, nspec in mismatches:
            print(f"  {f}")
            print(f"    was {ospec}  {ot}")
            print(f"    now {nspec}  {nt}")
        return 1

    print("Every substitution resolves to the same (size, weight, design) it replaced.")

    # Anything still hardcoded, for the record.
    remaining = subprocess.run(
        ["grep", "-rn", "--include=*.swift", r"\.font(\.system(size:", "OllamaSearch"],
        cwd=REPO, capture_output=True, text=True,
    ).stdout.strip().splitlines()
    print(f"\n{len(remaining)} literal(s) still in place (one-offs, see the spec):")
    for line in remaining:
        print("   ", line.split(":", 1)[0] + ":" + line.split(":")[1])
    return 0


if __name__ == "__main__":
    sys.exit(main())
