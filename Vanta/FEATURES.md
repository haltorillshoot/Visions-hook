# Vanta feature checklist against Visions-hook

This is an honest status list, not a claim of completeness. Vanta does **not** yet reproduce every Visions-hook feature.

How it was built: the 28 top-level features of the current menu (`rows.<name> = <Section>:AddLabel(...)` in `Visions-hook.lua`, lines 16958 to 17350) and their option panels were read and listed with a script. Line numbers below are in `Visions-hook.lua` at the time of writing.

Legend: **Done** = implemented and in the Vanta menu. **Partial** = a working core, some options missing. **No** = not implemented. "Tested" says what was run on a live client; in every test there was no other player in the server, so nothing was tested against a real opponent.

## Summary

| Status | Count | Features |
|---|---|---|
| Done | 7 | Auto Stomp, 3D Target Circle, View Target, Show FOV, Tracer, Auto Ammo, Auto Mask |
| Partial | 12 | Automatic Fire, Auto Equip, Resolver, Prediction, Lead Fast Targets, Target Selection, Follow Target, Void, Safe Purchasing, Auto Loadout, Auto Armor, Auto Heal |
| No | 9 | Quick Draw, A/D, Hitboxes, Full Auto, Maximum Fire Rate, Anti Bounty, Auto Bounty, Anti Stomp, Anti Report |

## Feature by feature

| Original (line) | What it does | Vanta | Missing options / notes | Tested |
|---|---|---|---|---|
| Automatic Fire (16958) | Fires the guns at the target | Partial | Has: per-gun ammo, cooldown and range, slow guns first, shotgun void guard, equip, reload, hitbox. Gun Gap is in (minimum time between different guns). Missing: At Target Vehicle, Dont Render, Show Fake Bullets, Pre Fire, Pre Fire Time, Bullet Manipulation, Double Tap, Distance Check | No (no loaded gun and no opponent) |
| Auto Equip (16965) | Equips guns for you | Partial | Auto Fire equips the gun it fires. Missing: Unequip When, Guns, Prioritize DB | No |
| Quick Draw (16975) | Draws the chosen guns quickly | No | not started | |
| A/D (16983) | A/D strafe | No | not started | |
| Resolver (16990) | Finds the target's real position | Partial | Has cluster and adaptive modes with radius, window, hold and lead. Missing: the weighted and hybrid types, Out Of Void Bonus, Normal Position Trust, Forget Rate, Void Trust, Accuracy, Distance Based Penalty, Lerp | Yes, synthetic positions: cluster, normal mover, void |
| Hitboxes (16997) | Hitbox options | No | not started | |
| Prediction (17012) | Leads the aim | Partial | Lead is in the Resolver. Missing: Resolver Rate, Velocity Source, Strength as separate options | Yes, with the resolver |
| Lead Fast Targets (17027) | Leads targets that move fast | Partial | Same lead as above, capped at 30 studs | Yes |
| Target Selection (17121) | Chooses the target | Partial | Has: automatic with Cooldown, priority (mouse, character, health, random), FOV, distance, Ignore If (in void, protected, knocked), Untarget When (dead, knocked, flung), notifications, target key (press selects, press clears). Missing: Target When Shot At, Force, Wait For Spawn Protection, Void While Waiting (Void Spam has its own), Target Statuses | Config round trip of the multi dropdowns: yes. Selection and the key: no (needs players) |
| 3D Target Circle (17165) | Ring round the target | Done | Colour; the gradient colour is not there | Yes (24 line segments drawn and removed) |
| View Target (17172) | Camera on the target | Done | | Yes |
| Show FOV (17185) | FOV circle | Done | Colour and active colour; Outline and Follow Target options missing | Yes |
| Tracer (17192) | Line to the target | Done | Thickness, colour, origin; Outline and End Point missing | Yes |
| Full Auto (17231) | Hold-fire | No | not started | |
| Maximum Fire Rate (17239) | Patches the client gun scripts to remove their limits | No | Deliberately not reproduced: it works around the client-side fire limiter | |
| Auto Stomp (17248) | Stomps knocked targets | Done | Stop When Target Dead; Target Statuses, Wait For All and Prioritize Over Reloading missing | No (needs a knocked player) |
| Anti Bounty (17255) | Bounty handling | No | not started | |
| Auto Bounty (17263) | Bounty handling | No | not started | |
| Safe Purchasing (17271) | Holds a purchase while players stand near the shop | Partial | Avoid target or anyone within a set distance. Missing: the friendly, neutral and enemy status choices (Vanta has no player statuses) | No (needs another player) |
| Auto Loadout (17278) | Buys a loadout | Partial | Buys the chosen guns you do not own and tops up their reserve ammo (packs slider). Missing: Disable When | No (spends real in-game cash on guns; not run) |
| Follow Target (17285) | Moves the body round the target | Partial | Has orbit, random, above, strafe above, teleport, zigzag, distance, height, speed, reposition, follow into void, Stop If, Lead and Lead Time, Orbit Shape (circle, square, triangle, pentagon, hexagon, decagon, heart), Teleport Min/Max, Zig Zag Height and Speed, Visualize. Missing: Adjust | Yes on a self target: all seven shapes at the right radius, teleport range 5.4 to 24.7 for 5 to 25, zig zag flips at the set speed, Stop If stops the body, visualize drawn and removed, clean disable |
| Auto Ammo (17292) | Buys ammo | Done | Minimum Clips, packs per purchase; Disable When missing | Yes: two Rifle ammo packs bought, reserve 35 to 45, cash dropped by 562 |
| Auto Armor (17299) | Buys armor | Partial | Buy If Below and the keep-cash reserve; Try Cooldown missing | The purchase path is tested with other items; armor itself was not bought |
| Anti Stomp (17306) | Protects against stomps | No | not started | |
| Anti Report (17313) | Report handling | No | not started | |
| Auto Mask (17321) | Buys and wears a mask | Done | Buys a ninja mask and puts it on; does nothing while one is worn. Disable options missing | Yes: mask bought and worn; nothing bought while worn |
| Auto Heal (17328) | Heals | Partial | Buys popcorn and eats it below a health percentage, with the eat interval. Missing: Stop Following While Healing | No (needs damage; not run) |
| Void (17350) | Void hide, spam and bait | Partial | Has the spam cycle with void and window times and the ready-gun gate, hide while waiting, Type (random, deep, bait), Deep Distance, Offset, and Bait (distance, cooldown, time, freeze, spot random or where you stood, skipped when another gun covers the spot or health is low). Missing: Disable When, Force When, Stop If Forced, Out With Target, Hide While Target Hides | Yes on a self target: deep spot stable at 1.1e8 studs, 16 bait visits in 3 s, bait at the standing spot, cycle ran, body restored, clean disable |

## Not yet inventoried

`Visions-hook.lua` also contains an older menu with 517 elements (204 toggles, 118 sliders, 108 colour pickers, 80 dropdowns) and systems that have no entry above: the legit bot, aim assist, triggerbot and silent aim, player and NPC ESP, skins and the shop, weather, and the Des Hood part. I counted them but did not list or audit them one by one, and none of them is in Vanta yet.

## What the final audit shows

The audit you asked for cannot be signed off. 15 of the 28 top-level features are missing, 8 are partial, and the older menu's 517 elements and the other systems above are not accounted for individually. Nothing here was tested against a real opponent.

## Shop (added)

The shop module buys through the shop parts in `Workspace.Ignored.Shop`: 105 distinct items were found in the live game, the cheapest copy of each is used. A purchase holds the character beside the part for its whole duration and puts it back afterwards. A click from 8.8 studs below the part was refused in testing; one from 3 studs beside it was sold. Tested live with real in-game cash: cranberry, hamburger, lemonade-style cheap items, two Rifle ammo packs, a ninja mask; an unaffordable item fails and backs off.
