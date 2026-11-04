# Stage 1: Lead

Branch `rewrite/lead-model`, started from `rewrite/audit-and-baseline`. Nothing is pushed. The original is on `backup/pre-rewrite-2026-11-04`.

## What changed

- `src/Lead/LeadModel.lua` (new): the lead maths as pure functions (`isTrusted`, `factor`, `leadTime`, `vector`, `clampToFloor`, `compute`, `isSteady`, `followAhead`, `closingSpeed`, `preFire`). All constants are named and documented in one place, with the measured findings that used to sit in comments next to the inline code.
- `tools/build/bundle.py`: injects the module into `Visions-hook.lua` between `-- @bundle-begin` / `-- @bundle-end` markers, so the shipped script is still one file for the loader. `--check` fails when the generated region is out of date. Edit `src/`, run the bundler, never edit the generated lines.
- `Visions-hook.lua` (5 call sites, recorded in `tools/build/wire_lead.py`): the velocity steadiness check, the whole prediction lead block, Follow Target's lead, Auto Fire's Pre Fire lead, plus the generated module region. The floor raycast stays in the engine as a small probe function handed to the module, because it needs engine state.

## What is proven unchanged

The prediction lead is bit-for-bit identical to the original code. The test slices the original block out of the backup branch (not a retyped copy) and runs it next to the module and next to the shipped call site on 40,000 random inputs each: velocity speeds from 0 to 5,000 studs/s including NaN, replicated velocity present, absent, agreeing and not, resolver on and off, every Prediction setting, ping 15 to 400 ms, Lead Fast on, off and unset, Prediction Strength unset and 50 to 200, with and without a floor. Zero mismatches. The steadiness check, closing speed and Pre Fire lead are identical on 20,000 cases each. Follow Target's lead is identical from 40 studs/s upward whenever the aim carries no lead of its own.

## What changed on purpose

Both changes are in `Lead.followAhead` (Follow Target's Lead option) and need no new setting:

1. **Fade-in instead of a switch.** The original had no follow lead below 40 studs/s and the whole lead from 40.001. It now fades in from 30 studs/s (where the prediction starts trusting a fast movement) and is identical from 40 up. Simulation, speed measured at 40 studs/s plus random noise, 110 ms Lead Time, largest frame-to-frame change of the body offset:

   | speed noise | before | after |
   |---|---|---|
   | +-1 studs/s | 4.51 studs | 0.64 studs |
   | +-2 studs/s | 4.62 studs | 1.27 studs |
   | +-4 studs/s | 4.84 studs | 2.42 studs |
   | +-8 studs/s | 5.28 studs | 4.53 studs |

   The benefit shrinks as the noise grows; at +-8 studs/s it is small. How noisy the measured speed really is in a game has not been measured.
2. **One cap for both leads.** The body offset (up to 60 studs) was added on top of the aim's own lead (up to 150 studs when trusted) with no combined limit, so the body could be sent up to 210 studs ahead. Now the two together stay inside the trusted cap of 150. Nothing changes while they already fit; in practice it only matters for targets faster than about 450 studs/s with a long Lead Time.

## Not changed

- The shot hook's lead spread (`hide_manager.lead_scales`, lines around 18775) and the origin lag scales: they are tied to the namecall hook and tuned against the server's tolerance. Moving them needs the in-game rig.
- The velocity measurement itself (position delta, jump detection, Velocity Source): it keeps state across frames and stays inline for now.
- `Des-Hood/Des-Hood.lua` still has the old inline code.

## Tests

`bash tools/test.sh` runs everything below; all pass.

| check | result |
|---|---|
| bundle region up to date | pass |
| all shipped scripts compile | pass |
| `tests/lead/golden.spec.luau` | 18 passed: block anchors, 40,000 cases module vs original, 40,000 cases shipped call site vs original, 8 module mutations and 5 call site mutations all detected |
| `tests/lead/model.spec.luau` | 21 passed: steadiness, closing speed and Pre Fire vs original, follow lead vs original, fade-in monotonic and continuous at 40, combined cap never exceeded and inactive while the leads fit, jitter simulation |
| `tools/audit/check_keys.py` | 716 of 716 config keys present |
| `Raknet/tests/raknet_research.spec.luau`, `desync_research.spec.luau` | 31 and 71 passed |

Compile size: bytecode 1271.6 KB to 1274.5 KB, compile time within noise.

## Not verified

Nothing here has run in Roblox. The maths is proven equal to the original offline, but the engine around it (the floor probe, argument order at the call sites beyond what the mutation tests cover, the load order of the bundled region) has only been exercised through the shipped-block test and a compile check. In-game verification plan: load the rewritten script on the test client, repeat the baseline run (original: 30/30 and 29/30 hits, pooled 98.3%), and compare follow tracking against the original with an opponent that moves at 30 to 60 studs/s. The second part needs the opponent rig, which is blocked until Based Hub's void mode is off on the second client.
