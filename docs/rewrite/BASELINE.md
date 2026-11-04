# Baseline (2026-11-04)

Everything here was measured on `rewrite/audit-and-baseline`, branched from `main` at `ebcba03`. The untouched original is preserved on `backup/pre-rewrite-2026-11-04`. Nothing in this branch has been pushed.

## Environment

- Lune (Luau runtime) for compiling and for the offline specs. Roblox itself is not available here, so nothing below says anything about in-game behaviour.
- In-game checks use the two Potassium clients described in `AUDIT.md` (section 8).

## Automated tests that exist in the repository

| suite | result | notes |
|---|---|---|
| `Raknet/tests/raknet_research.spec.luau` | 31 passed, 0 failed | mock `raknet` library |
| `Raknet/tests/desync_research.spec.luau` | 71 passed, 0 failed | mock `raknet` library |
| `Raknet/tests/desync_menu.spec.luau` | **fails on load** | crashes at line 28 (`string.sub` with a nil index) |
| `Vanta/tests/audit.lua` | not run | it is an in-executor harness (needs Roblox services), cannot run under Lune |

Why `desync_menu.spec.luau` fails: it cuts the "Raknet desync test" block out of `Visions-hook.lua` by a comment marker, and commit `633279e` ("drop raknet rows") removed that block on purpose. The spec has to be retired or retargeted; it does not indicate a runtime bug.

## Tests added in this branch

| check | what it proves | baseline |
|---|---|---|
| `tools/audit/check_keys.py` | every config key in `config-keys.txt` (716: 586 settings, 130 binds) is still reachable in the script | 716 of 716 present in the original |

Negative controls for the check, run to make sure it can fail: pointing it at `Vanta/Vanta.lua` reports 649 missing, and renaming `ragebot_lead_fast` in a copy of the original reports that key and its bind as missing.

Limit: keys built from a prefix at run time (`auto_sorter_slot_` plus a number, the tracer look helper) are matched by prefix, so the check cannot see one member of such a family disappear, only the whole family.

## Compile metrics (Lune, best of 3)

| file | source | bytecode | compile | loads |
|---|---|---|---|---|
| `Visions-hook.lua` | 2025.7 KB | 1271.6 KB | 137 ms | yes |
| `Des-Hood/Des-Hood.lua` | 2971.8 KB | 2265.2 KB | 136 ms | yes |
| `Vanta/Vanta.lua` | 219.5 KB | 180.7 KB | 18 ms | yes |
| `Visions-hook-menu.lua` | 1122.1 KB | 1113.9 KB | 13 ms | yes |
| `Raknet/DesyncResearch.lua` | 34.3 KB | 23.9 KB | 1 ms | yes |
| `Raknet/RaknetResearch.lua` | 10.6 KB | 7.2 KB | 1 ms | yes |

Reproduce with `lune run tools/audit/metrics.luau` (edit the base path at the top).

## Static code metrics for `Visions-hook.lua`

| metric | value |
|---|---|
| lines | 46,590 |
| `create_connection(` calls | 640 |
| `flags["..."]` lookups | 578 |
| `hide_manager[...]` accesses | 655 |
| `pcall(` / `xpcall(` | 434 / 1 |
| `LPH_JIT_MAX` / `LPH_NO_VIRTUALIZE` markers | 97 / 273 |
| frame-bound connections found (Heartbeat / RenderStepped / Stepped) | 8 / 3 / 2 |
| TODO / FIXME | 0 |

The frame-bound count only covers connections written as `run_service["Heartbeat"]` and similar; helper wrappers can hide more.

## Not measured yet

Runtime numbers (frame time, memory, hit rate, follow tracking error) have no baseline. The two-client Potassium rig is the only way to get them; the plan in `AUDIT.md` builds the measurements first so that every later change has something to be compared against.
