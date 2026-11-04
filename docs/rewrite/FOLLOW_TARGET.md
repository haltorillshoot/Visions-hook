# Stage 2: Follow Target placement

Branch `rewrite/follow-target`, started from `rewrite/lead-model`. Nothing is pushed. The original is on `backup/pre-rewrite-2026-11-04`. Stage 1 (Lead) is described in `LEAD.md`; Follow Target's lead already goes through the Lead model.

## What changed

- `src/FollowTarget/Placement.lua` (new): the placement maths that depends on nothing but numbers, as pure functions: `orbitOffset` (circle, triangle, square, pentagon, hexagon, decagon, heart), `zigzagEvery`, `reach` (how far each style can put the body from the target, one function per style instead of an if-chain), `adjustSearch` (Adjust's search for a place with a clear line).
- `Visions-hook.lua` (recorded in `tools/build/wire_follow.py`): four call sites now use the module (orbit shapes, Zig Zag timing, reach, the Adjust search). The generated module region is injected by `tools/build/bundle.py` as in Stage 1. The 14-direction table that only Adjust used moved into the module.
- Two small costs removed: `orbitOffset` built a lookup table on every call (it is a constant now), and Adjust's search built 112 candidate tables, then sorted them, on every search (the candidates are built once and reused, and each search only fills in distances and sorts).

## What is proven unchanged

The original code is sliced out of the backup branch (not retyped) and run next to the module and next to the shipped call sites on random inputs:

- `orbitOffset`: 30,000 cases, every shape plus unknown shapes, shares from -3 to 3, bit for bit.
- `zigzagEvery`: 30,000 cases including an unset Zig Zag Speed.
- `reach`: 30,000 cases across all styles and flag combinations, including unset flags and a value that is not a number.
- `adjustSearch`: 4,000 cases with different ranges (including NaN) and different shares of blocked places. It returns the same place and makes the same wall checks in the same order, so the cost of the raycasts and the behaviour are identical.

Each comparison has to be able to fail: 9 mutations of the module and 5 of the call sites were all detected (one call site mutation was first missed because the test never left Zig Zag Speed unset; the test was fixed, not the mutation dropped).

Geometry checks: no orbit point lies outside its radius, every shape comes back to the same place after a full turn, a square corner sits on the radius, and the orbit stays flat.

## Speed

Under lune with a table-based `Vector3` stand-in (so it shows that work was removed, not how much a Roblox client saves), four runs gave 56 to 72% of the original time for `orbitOffset` (200,000 calls) and 69 to 76% for `adjustSearch` (3,000 searches). Garbage could not be measured under lune (only `collectgarbage("count")` works), so no claim is made about it. In-game frame time has not been measured.

## What was checked and is not a problem

Target retention. The Follow Target audit asked for fewer unnecessary target switches. In automatic mode the picker only runs when there is no current target and the cooldown only limits how often an empty target is retried, so a target is kept until it becomes invalid; there is nothing to fix there. (Switching by `Target when shot at` and the target key was not changed.)

## Not changed

- `follow_cframe` and the rest of the follow step: they hold state, random numbers and the clock, and interleave Visualize, Shot Lock and the void recovery. They stay inline for now; moving them needs injected clocks and a CFrame model, and the risk is higher than the gain.
- The wall check (`walls_clear`) and Follow Into Void logic.
- `Des-Hood/Des-Hood.lua` still has the old inline code.

## Tests

`bash tools/test.sh` now also runs `tests/follow/golden.spec.luau` (41 checks). All checks pass: bundle regions up to date, all scripts compile, Lead specs (18 + 21), the 716 config keys, the Raknet specs (31 + 71), and the placement spec.

## In-game smoke test (2026-11-04, commit `03b651a`)

Loaded on two clients in one Da Hood server (a shooter and an opponent test account) with the saved `hvh` config. On a clean session both came up fully: session alive, 598 engine flags, both modules in memory, `hide_manager.orbit_offset` is the module's function. With Roblox's own `Vector3` the module returned the expected values: a square corner at exactly 40.000000 studs, a hexagon midpoint at 30.0000, the heart's start at z = 5.000, `zigzagEvery(89, 100)` = 0.11540 and `zigzagEvery(0, 250)` = 0.03, `reach("strafe", 89, 71)` = 113.8508, nil for Random Spam and for an adjusted body. The live hooks gave `follow_reach()` = 117.034 and `follow_hold_time()` = 0.1154, which is exactly what the config implies (Zig Zag, Distance 89, Height 74, Zig Zag Speed 100).

With both accounts running the script they fought each other. Over 20 s on each client the follow step ran every sample (`hide_manager.follow_last` was set 10 of 10 times, `follow_aim` changed as the target moved) with no errors in the console, and one sample showed the two bodies exactly 89 studs apart, the configured Distance. That exercised `zigzagEvery` through Zig Zag. Adjust never needed to move the body (no offset was set in any sample), so `adjustSearch` has not run in-game beyond a manual call with a stand-in wall check (3 checks, result 14, 0, 0).

**Open problem, not yet explained:** the first time I reloaded the script over a running session on the shooter client (Stage 1 build replaced by this one), no session was left afterwards (no session object, no engine flags, no menu) and nothing was logged. A second load onto that clean state worked. It is unknown whether re-running the original script over a running original session does the same, so this may or may not be caused by the rewrite; it needs a control run (original over original) before it can be called either way.

Control run, second attempt (2026-11-04, the shooter account rejoined as a fresh client): every reload variant worked, each checked 40 seconds after the load with the client still in the server and the session alive with 598 engine flags and the menu references present:

| step | result |
|---|---|
| original loaded onto a clean client | session alive, 598 flags |
| original loaded over the running original | session alive, 598 flags |
| rewrite loaded over the running original | session alive, 598 flags |
| rewrite loaded over the running rewrite | session alive, 598 flags |

So reloading over a running session is not broken in general, for the original or for the rewrite, and the first anomaly (Stage 2 over Stage 1 on the shooter client, no session left) did not reproduce. A fifth reload, rewrite over rewrite on the second account (the opponent), ended with that client disconnecting from the server before it could be checked, so that one has no result. Both anomalies happened on clients that had been running for a while (one of them in a fight between the two accounts); the cause is not known and nothing here ties either of them to the rewrite.

Earlier control attempt (not completed): on the shooter client I unloaded the session (clean: no session, no flags, nothing in the log), loaded the original from the backup branch onto that clean state, and the client disconnected from the server within about a minute (the other account was then alone in the server). No Visions error was logged. Two earlier clients also disappeared right after a script was loaded onto them, so a client dropping after a (re)load has now happened several times; the cause (the game, the executor, or a manual close) is not known. The control has to be repeated on fresh clients, one step per fresh client: original loaded clean, original loaded over a running original, rewrite loaded over a running rewrite.

## Not verified

Beyond the smoke test above, nothing in this stage has run in Roblox. The module uses only `Vector3.new`, `.Unit`, `.Magnitude` and arithmetic, which behave the same in Roblox, but the load order, the engine variables the call sites read (`distance`, `height`, `follow_target_style`, `adjust_state`, `lift`, `clear`) and the visual behaviour have only been exercised through the shipped-block tests and a compile check. In-game plan: reload the script on the test client, confirm the module is live and its functions return the expected values with Roblox's `Vector3`, then let Follow Target run against a target and check that the body keeps its distance and style.
