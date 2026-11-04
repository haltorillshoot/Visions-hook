#!/usr/bin/env bash
# Runs every automated check that can run outside Roblox. Usage: bash tools/test.sh
# Raknet/tests/desync_menu.spec.luau is not run: it targets a menu block that was removed on purpose (see docs/rewrite/BASELINE.md).
set -u
cd "$(dirname "$0")/.."
status=0

run() {
	echo "== $*"
	"$@" || status=1
}

run python -I tools/build/bundle.py --check
run lune run tests/compile.spec
run lune run tests/lead/golden.spec
run lune run tests/lead/model.spec
run lune run tests/follow/golden.spec
run python -I tools/audit/check_keys.py
run lune run Raknet/tests/raknet_research.spec
run lune run Raknet/tests/desync_research.spec

[ "$status" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $status
