# Visions-hook audit (phase 0 of the rewrite)

Status: audit, feature inventory and baseline are done. **No code has been rewritten yet.** Nothing here was pushed. The original is preserved on `backup/pre-rewrite-2026-11-04`; this branch is `rewrite/audit-and-baseline`. Numbers and test results are in `BASELINE.md`; the generated feature map is `FEATURE_MAP.md`; the preservation list is `config-keys.txt`.

Everything below that says "from reading" comes from reading the code and has not been measured in a game. Line numbers are for `Visions-hook.lua` at `ebcba03`.

## 1. Repository map

| path | lines | what it is |
|---|---|---|
| `Visions-hook.lua` | 46,590 | the Da Hood script: bypasses, libraries, UI shim and UI library, cheat engine (single file) |
| `Des-Hood/Des-Hood.lua` | 43,777 | the same engine for Des Hood (header: "what used to be Visions-hook.lua lives here now") |
| `Vanta/Vanta.lua` (+ docs, `tests/audit.lua`) | 6,327 | a separate, smaller script with its own audit harness |
| `Raknet/*.lua`, `Raknet/tests/*` | 1,577 plus tests | packet recorder and desync research modules, with Lune specs |
| `Visions-hook-menu.lua` | 1,289 (1.1 MB) | UI-only mock ("Nothing here does anything"); referenced by no other file |
| `assets/` | 53 files | sounds, images, rbxm models fetched by raw URL |

Entry point: users load `Visions-hook.lua` from `main` with one `loadstring`. In Des Hood it hands over to `Des-Hood/Des-Hood.lua` (lines 5-29). The executor workspace copy of `Des-Hood.lua` is used first when present.

Remote branches besides `main`: `da-hood-bounty`, `fix/void-spam-auto-fire`, `shotgun-void-guard` (all fully behind `main`) and `move-da-hood-into-des-hood` (8 commits ahead, 46 behind). I did not look inside them.

## 2. Architecture of `Visions-hook.lua`

| lines | layer |
|---|---|
| 1-880 | game wait, Des Hood hand-over, anti-cheat and actor bypasses, anti AFK, global helpers, unload |
| 884-1231 | assets, signal library, tween library, connection list |
| 1232-17782 | menu shim and the UI library (about 16,500 lines), wrapped in one function to stay under Lua's 200-local limit (comment at line 1600), plus the native menu rows |
| 17787-46534 | the cheat engine: ragebot / HVH (33979-44750), legitbot, visuals, movement, misc, player data, addons |
| 46253-46590 | finish loading, engine tabs, update data |

`FEATURE_MAP.md` lists all 50 top-level sections with their line ranges and sub-features.

## 3. Findings

1. **One 46,590-line file.** The UI library (about a third of it) and the engine share locals and load order. Nothing can be unit-tested in isolation today.
2. **Two near-identical forks.** `Des-Hood.lua` shares 14,535 distinct long lines with `Visions-hook.lua`: 92% of one and 98% of the other. Every fix has to be made twice, and the two have already drifted.
3. **Shared mutable state.** `hide_manager[...]` is touched 655 times and acts as a global bag; sections also communicate through engine locals (`ragebot_target`, `ragebot_aim_position`, `local_following`, `in_void`, ...). Behaviour depends on the order of per-frame updates. Follow Target, for example, reads `hide_manager["aim_velocity"]` and `["aim_trusted"]`, which the prediction block writes.
4. **String-keyed config on hot paths.** 578 `flags["..."]` lookups, several inside per-frame functions (Follow Target reads `follow_target_reposition`, `follow_target_lead`, `follow_target_lead_time` and `follow_target_visualize` every frame). Caching on change is the obvious fix; its effect is not measured yet.
5. **Two menu layers joined by a name map.** 527 options are visible to static extraction as engine options, 148 native menu helper calls exist, and `NL_TO_NEVERLOSE_FLAG` maps 152 flags between them. Many flags are built at run time (`e_` prefix, `auto_sorter_slot_` plus a number, the tracer look helper). A static feature inventory therefore under-counts, which is why the preservation list is the saved config key set (716 keys) and not a parsed list.
6. **Saved config and live state differ.** On the running client, `void_hide_exploit` was false and `target_selection_automatic` true, while the saved `hvh` file says the opposite. Config loading or saving does not reflect what the script is actually running; the cause is not found yet.
7. **Error handling.** 434 `pcall` and 1 `xpcall`. I have not counted how many discard the error.
8. **Knowledge loss.** Line 38722: `-- theres a reason for not using else ifs i think? i forget but im not risking it`. Behaviour the code depends on is not documented.
9. **Obfuscator coupling.** 97 `LPH_JIT_MAX` and 273 `LPH_NO_VIRTUALIZE` markers (Luraph). A rewrite has to keep them, with the same fallbacks the script defines at the top, or protected builds break.
10. **Stale test.** `Raknet/tests/desync_menu.spec.luau` fails because it targets a block removed in `633279e`. No tests cover the engine, the UI library or the menu.
11. **Unreferenced file.** `Visions-hook-menu.lua` (1.1 MB, 19 embedded base64 blobs) is referenced nowhere.

## 4. Follow Target (lines 38208-38905), from reading

What it does: `follow_target(dt, hrp, bypass)` runs a guard chain (ragebot target present and alive, target phase, void spam active, spam cycle, Follow Into Void limits under the kill height, stop-if reasons: reloading, target knocked, no gun, auto heal) and then moves the body to a spot chosen by style. Styles: strafe, zig zag, random, random spam, randomize, above, strafe above. Orbit shapes: circle, triangle, square, pentagon, hexagon, decagon, heart. Options present in the saved config: adjust, distance, height, lead, lead_time, orbit_shape, reposition, sky_min, sky_max, speed, stop_if, style, teleport_min, teleport_max, visualize, zigzag_height, zigzag_speed.

Candidate weaknesses (none measured):

- Style dispatch is three separate string if-chains (`follow_hold_time`, `follow_reach`, `follow_cframe`) that have to be edited together.
- `follow_adjust` raycasts for walls and re-searches when the aim moved more than 4 studs or after the reposition interval (0.02-0.25 s). For fast targets that probably means a search nearly every frame; the cost scales with target speed.
- The lead (section 5) switches on at 40 studs/s as a step, not a ramp.
- The target is taken from the ragebot (`ragebot_target`). Target switching and retention live in the target selection code, audited in Stage 2: automatic picking (`do_ragebot`, `pick_ragebot_target`) only runs when there is no current target (`not target`), and `Target Selection Cooldown` only limits how often an empty target is retried. A target is therefore kept until it becomes invalid, so there is no flapping between two targets to fix in automatic mode.
- Void recovery is a separate Heartbeat connection (38625-38670) that has to agree with the main follow state through `local_following`.

## 5. Lead, from reading

There are five separate lead computations with different units and caps:

| where | what | unit | cap |
|---|---|---|---|
| 37102-37250 | ragebot prediction: velocity x (factor x strength/100), ping floor `clamp(ping/1000 + 0.16, 0.12, 0.45)`, gravity term, floor raycast | seconds, strength % | 60 studs, 150 for a trusted fast target |
| 37135 | Lead Fast Targets (`ragebot_lead_fast`): automatic lead with Prediction off, speed over 60 and steady | automatic | same cap |
| 38747 | Follow Target lead: speed x lead time, added on top of the aim position | milliseconds | 60 studs, speed over 40 only |
| 18775-18814 | shot hook "lead spread": cycles shares of the lead per shot | scale list | none of its own |
| 45207 | auto fire pre-fire lead: closing speed x pre-fire time | milliseconds | 40 studs |

Interaction problems:

- The follow lead is added to `ragebot_aim_position`, which already contains the prediction lead. The two caps are independent, so the body can be sent up to about 210 studs ahead of the target (150 + 60) with no combined limit.
- Only the prediction lead has the gravity term and the floor raycast; the follow lead and pre-fire lead ignore both.
- The same velocity is trusted differently in each place (`aim_trusted` in two of them, a plain speed threshold in the others).

## 6. How preservation will be verified

1. `tools/audit/check_keys.py`: every one of the 716 saved config keys must still be reachable. Baseline: 716 of 716. It fails on a renamed key (checked).
2. Golden-master tests for the pure maths (lead, orbit offsets, style placement): extract the functions, record the original's output for sampled inputs, and require the rewrite to match or to differ only where a fix is documented.
3. In-game comparison on the two-client rig (shots, hit rate, kills per minute, follow tracking error), original against rewrite, same opponent behaviour. A per-feature checklist for everything that cannot be automated, filled in with what was actually observed.
4. `FEATURE_MAP.md` and a feature-by-feature table are regenerated at the end and diffed.

## 7. Feasibility and recommended order

A full rewrite of about 90,000 lines across two forks, with every feature verified, cannot be done safely in one step. There is no in-game regression harness, the shared state makes untested moves risky, and the repository loads as a single file. I recommend staged rewrites, each one gated by the checks in section 6:

1. **Tooling first** (started): preservation check, metrics, baseline. Still to add: a bundler (modules to the single `Visions-hook.lua` the loader needs), golden-master harness, rig metrics for follow and lead.
2. **Lead**: one lead model (velocity, ping, gravity, floor, one trust rule, one combined cap), with the five consumers keeping their own settings and meaning.
3. **Follow Target**: extracted module, table-driven styles, cached config, target retention, the new lead as input.
4. **Config layer**: cached flag values updated on change; find the saved/live drift from finding 6.
5. **UI library separated** from the engine; one shared engine for Da Hood and Des Hood with game adapters.
6. **Remaining engine sections**, one module at a time.

## 8. Test rig status

Two Potassium clients are in one Da Hood server: a shooter test account (running Visions) and an opponent test account (running Based Hub). The passive shot and hit logger works. A scripted void-spam opponent cannot work while Based Hub holds the opponent client in the void; its void mode has to be switched off first. Without that opponent, measurements only show regressions in hit rate on an in-range target (the baseline was 98.3%, so there is no room to show an improvement).

## 9. Decisions needed

- Staged rewrite (recommended) or a single large rewrite?
- Scope: `Visions-hook.lua` only, or both forks (92% shared)?
- `Visions-hook-menu.lua`: keep, or archive?
- `desync_menu.spec.luau`: retire it, or retarget it?
- Switch off Based Hub's void mode on the opponent client so the opponent rig works.
