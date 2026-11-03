# Vanta final audit

This is the audit against Visions-hook. It says what exists, what is wired to a menu control, and what was actually run. Anything not listed as tested was **not** tested. Vanta does not reproduce every Visions-hook feature; the missing ones and the reasons are listed at the end and, control by control, in `ORIGINAL_INVENTORY.md`.

The checks and how to repeat them:

| Check | How | Result |
|---|---|---|
| Syntax, names, types | `luaucheck.py Vanta/Vanta.lua` | 0 warnings, 0 parse errors, 82 API names checked, 0 problems |
| Every control is read by code | static script over `Vanta.lua` | 353 declared controls, all read; 7 flags are read through a prefix (`aimassist_`, `silent_` + `hitbox`, `distance`, `visible`, `fov`) and `utility_watermark` through its callback |
| No duplicate flags, no conflicting fallbacks, toggle defaults match | same script | none found |
| Live harness | `Vanta/tests/audit.lua` (copy it next to `Vanta.lua` in the executor workspace, `loadstring(readfile("VantaAudit.lua"))()`) | below |

## Live harness results (one client, alone in its server)

- 366 flags created. Config save, change of 108 numbers, load of the saved config: identical.
- 124 toggles switched on together (the ones that spend cash, fire at players, kick, or switch off the screen are skipped: shop, auto fire, full auto, triggerbot, silent aim, auto stomp, anti bounty, auto bounty, no render, hide chat, sorter, skin changer): **0 errors logged**. Frame time 4.2 ms with Vanta idle, 5.3 to 6.3 ms with all of it on.
- Everything switched off again: Lighting back to its original child count, workspace, camera, sound and character unchanged. The CoreGui and hidden-UI counts drop by 6 each; that is the library's own notification toasts expiring.
- Unload: footprint identical to the one taken before Vanta was loaded, and the `Vanta` global is gone.
- Five load/unload cycles: memory 59.6 MB after the first, 51.8 MB after the fifth (no growth; the executor only allows `collectgarbage("count")`, so this is not a forced collection). Three metamethod hook layers exist for the whole session, however often it is reloaded.

Found and fixed by the audit: the atmosphere and skybox Vanta creates were not removed (and the game's own were not put back) when their switches went off, which left one extra object in Lighting. Both are now removed and restored.

## The 28 top-level features of Visions-hook

UI connected means the control exists in the Priv9 menu and the code reads it (static check above). Tested is live testing on the days this was built; "synthetic" means a made-up position or a locally faked state, nothing was fired at a real player.

| Original feature | New module | Implemented | UI connected | Tested |
|---|---|---|---|---|
| Automatic Fire | AutoFire | Partial: per-gun ammo, cooldown, range, gun gap, fire cooldown, shot delay, equip, reload, hitbox. Not: always fire, bullet manipulation, double tap, pre fire, fast retry, at target vehicle, dont render, show fake bullets | Yes | Timing with a fake client-side gun (cooldown, delay, drop on target clear). Real shots and server acceptance: no |
| Auto Equip | AutoFire | Yes (order, prioritize Double-Barrel, unequip when) | Yes | No (no gun in the test inventory) |
| Quick Draw | QuickDraw | Partial (guns list, hold time) | Yes | No |
| A/D | AdStrafe | Yes | Yes | Yes |
| Resolver (cluster, adaptive, weighted, hybrid) | Resolver | Yes, with the original's controls | Yes | Yes on synthetic faker and walker; second account for the walker |
| Hitboxes | AutoFire / Aim | Yes | Yes | Config only; shots no |
| Prediction, Lead Fast Targets | Resolver | Yes (strength, resolver rate, velocity source) | Yes | Yes |
| Target Selection | Target | Yes incl. target when shot at, force, wait for spawn protection, statuses | Yes | Selection and key with the second account; target when shot at and wait for spawn protection: code paths only |
| 3D Target Circle, View Target, Show FOV, Tracer | Visuals | Yes (outlines, end point, gradient not) | Yes | Yes |
| Full Auto | FullAuto | Partial (no AUG round mode) | Yes | No |
| Maximum Fire Rate | none | Declined: patches client gun limits | n/a | n/a |
| Auto Stomp | AutoStomp | Yes (statuses, wait for all targets) | Yes | No (no knocked player) |
| Anti Bounty, Auto Bounty | Bounty | Yes | Yes | Poster reading yes; the kick and the hunt no |
| Safe Purchasing | Shop | Yes | Yes | No (needs another player) |
| Auto Loadout | Shop | Partial (no Disable When) | Yes | No (spends cash) |
| Follow Target | Follow | Yes: 7 styles, 7 shapes, lead, teleport range, zig zag, visualize, Stop If, follow into void. Not: Adjust | Yes | Yes on self and on the second account (held 15.0 studs) |
| Auto Ammo, Auto Mask | Shop | Yes | Yes | Yes with real in-game cash |
| Auto Armor, Auto Heal | Shop | Yes | Yes | Purchase path only; armor and heal themselves not run |
| Anti Stomp | Body provider | Partial: leaves reach while knocked, teleports back; does not kill or fling the character | Yes | Yes with a locally faked knock; teleport back no |
| Anti Report | none | Declined: its purpose is to avoid reports to moderators | n/a | n/a |
| Void (hide, spam, bait) | VoidSpam | Yes incl. force when, stop if forced, out with target, hide while target hides | Yes | Yes on self; conditions with the second account |

## Other systems

| Original | New module | Implemented | UI connected | Tested |
|---|---|---|---|---|
| Player ESP (box, name, distance, tool, health, armor, bars, fonts, chams, highlight, statuses) | Esp | Yes except the ESP image, per-status colour variants of some bars | Yes | Yes on self and on the second account |
| Legit: aim assist, silent aim, triggerbot | Legit | Yes except bullet manipulation, force hit, range enhancer, double tap, recoil and spread edits | Yes | Aim assist and finders with the second account; silent aim and triggerbot no |
| Movement (speed, flight, noclip, jump power, anti sit, anti trip, spinbot, locks, pushback guard) | Movement | Yes | Yes | Yes except remove slowdowns and remove jump cooldown |
| Hit and shot feedback (markers, numbers, sounds, overlay, chams, particles, skeleton, tracers, impacts) | Feedback | Yes except player bullet tracers and volume, RPG warning, armor pop | Yes | Effects from synthetic shots; the real shot hook and hit match no |
| World (time, ambient, technology, atmosphere, colour, blur, skies, weather, chat, cursor, no render) | World | Yes | Yes | Yes (no render and hide chat not run) |
| Crosshair and HUD, statistics window, aspect ratio | Crosshair / Misc | Yes | Yes | Yes |
| Local character (highlight, material, hat, aura, rainbow tool) | LocalChar | Yes except custom character, skinny, material tools | Yes | Yes |
| Skin changer, hotbar sorter | Skins, Inventory | Guns and bat; knives and custom file skins not | Yes | Yes (sorter sent and restored the real setting) |
| Statuses (friendly, neutral, enemy), players tab | Status | Yes | Yes | Yes |
| Misc (nametags, animation player, camera distance, anti AFK, rejoin, watermark) | Misc / Utility | Yes | Yes | Rejoin, anti AFK and nametags on others not run |
| Config save and load, notifications, cleanup | Priv9 + Vanta | Yes | Yes | Yes (round trip, unload footprint, reload) |
| Panel menu items: purchase item, ammo amount, purchase ammo | none | No (Vanta buys through the Shop switches, there is no manual purchase button) | n/a | n/a |
| Des Hood part, intro animation | none | No (not read in detail, not reproduced) | n/a | n/a |

The per-control account of all 517 controls of the older menu is `ORIGINAL_INVENTORY.md` (Yes 306, Partial 40, No 145, Declined 26).

## Deliberately not reproduced

Features that fake or change what the server sees or that avoid moderation are not in Vanta: position and velocity desync, fake position, sender rate, anti report, trash talk, animation breaker, bullet manipulation, double tap, force hit, range enhancer, reduce shotgun spread, rapid fire, remove anti gun macro, always fire, maximum fire rate, kill and fling for anti stomp. Vanta does not touch server permissions or validation and has no anti-cheat evasion.

## Improvements over the reference

One target record and one body driver (providers for anti stomp, auto stomp, void spam, follow, applied each frame and restored before rendering); one shared metamethod hook per kind instead of a new layer per load; flags read live so settings cannot get out of step; a grid pass for the resolver clustering; every module restores what it changed on disable and unload; config saved and loaded by the library.

## Bugs found while building and auditing

Hook layers stacking on reload (one client dropped; fixed with `Hooks.set`); the 200-local limit of the main chunk (menu moved into `buildMenu()`); shop purchases refused when standing under the part (stand beside it and hold the body); a duplicate mask purchase (1.5 s block); jump power reset by the game every frame (overridden through `__newindex`); the weighted resolver lagging behind normal walkers (aim directly when the target moves like a player); atmosphere and sky left in Lighting (this audit).

## Limitations

- Almost nothing that needs a real opponent was tested: real shots, hit matching, silent aim, the triggerbot, Auto Stomp, Auto Fire, Auto Equip, Quick Draw and Full Auto have not been run against another player. They are implemented and wired, not verified.
- No anti-cheat handling: Da Hood's client checks may react to the movement.
- The hooks cannot be removed; after unload they pass straight through.
- The Priv9 library is loaded from `i77lhm/Libraries`; if that file changes, the menu can change with it.
- The harness cannot force a garbage collection (the executor only allows `collectgarbage("count")`).

## Load and configure

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/haltorillshoot/Visions-hook/main/Vanta/Vanta.lua"))()
```

Settings are saved and loaded from the Priv9 config tab; statuses are kept in `Vanta/statuses.json` and skin choices in `Vanta/skins.json` in the executor workspace. `getgenv().Vanta.unload()` removes everything.
