"""Feature preservation check: every config key in docs/rewrite/config-keys.txt has to be reachable in a script.

A key counts as present when its name is a quoted string in the source, when it is an "e_" key whose engine flag is (the menu shim
prefixes engine flags with "e_" at run time, and a leading "!" marks an engine override), when it is a "bind:" key whose flag is
present by one of those rules, or when it is built from a quoted prefix at run time ("auto_sorter_slot_" .. slot, or the prefix
handed to a helper that appends "_glow", "_length" and so on). The prefix rule is the weakest one: it cannot see a single member of
such a family disappear, only the whole family.

Usage: python tools/audit/check_keys.py [script.lua ...]    (default: Visions-hook.lua)
Exit code 1 when any key is missing.
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
targets = [Path(arg) for arg in sys.argv[1:]] or [root / "Visions-hook.lua"]
keys = [line.strip() for line in (root / "docs/rewrite/config-keys.txt").read_text(encoding="utf-8").splitlines() if line.strip() and not line.startswith("#")]
source = "\n".join(path.read_text(encoding="utf-8", errors="ignore") for path in targets)
quoted = set(re.findall(r'"([A-Za-z0-9_:.! /-]+)"', source))


prefixes = {text for text in quoted if len(text) >= 8}


def present(key):
    if key in quoted:
        return True

    for prefix in prefixes:
        if key.startswith(prefix + "_") or (prefix.endswith("_") and key.startswith(prefix)):
            return True

    if key.startswith("bind:"):
        return present(key[5:])

    if key.startswith("e_"):
        return key[2:] in quoted or key[2:].lstrip("!") in quoted

    return False


missing = [key for key in keys if not present(key)]
print("keys: %d | present: %d | missing: %d" % (len(keys), len(keys) - len(missing), len(missing)))

for key in missing:
    print("  missing:", key)

sys.exit(1 if missing else 0)
