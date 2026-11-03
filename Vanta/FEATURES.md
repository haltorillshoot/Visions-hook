# Vanta feature checklist against Visions-hook

This is an honest status list, not a claim of completeness. Vanta does **not** yet reproduce every Visions-hook feature.

How it was built: the 28 top-level features of the current menu (`rows.<name> = <Section>:AddLabel(...)` in `Visions-hook.lua`, lines 16958 to 17350) and their option panels were read and listed with a script. Line numbers below are in `Visions-hook.lua` at the time of writing.

Legend: **Done** = implemented and in the Vanta menu. **Partial** = a working core, some options missing. **No** = not implemented. "Tested" says what was run on a live client; in every test there was no other player in the server, so nothing was tested against a real opponent.

## Summary

| Status | Count | Features |
|---|---|---|
| Done | 10 | Auto Stomp, 3D Target Circle, View Target, Show FOV, Tracer, Auto Ammo, Auto Mask, A/D, Hitboxes, Anti Bounty |
| Partial | 16 | Automatic Fire, Auto Equip, Resolver, Prediction, Lead Fast Targets, Target Selection, Follow Target, Void, Safe Purchasing, Auto Loadout, Auto Armor, Auto Heal, Quick Draw, Full Auto, Auto Bounty, Anti Stomp |
| No | 2 | Maximum Fire Rate, Anti Report (both deliberately not reproduced, reasons below) |

## Feature by feature

| Original (line) | What it does | Vanta | Missing options / notes | Tested |
|---|---|---|---|---|
| Automatic Fire (16958) | Fires the guns at the target | Partial | Has: per-gun ammo, cooldown and range, slow guns first, shotgun void guard, equip, reload, hitbox. Gun Gap is in (minimum time between different guns). Missing: At Target Vehicle, Dont Render, Show Fake Bullets, Pre Fire, Pre Fire Time, Bullet Manipulation, Double Tap, Distance Check | No (no loaded gun and no opponent) |
| Auto Equip (16965) | Equips guns for you | Partial | Auto Fire equips the gun it fires. Missing: Unequip When, Guns, Prioritize DB | No |
| Quick Draw (16975) | Takes out the gun that reaches the target when holding a knife or nothing, and puts it back after | Partial | Guns list and a one second hold before putting the knife back. Not run (no gun in the test inventory, no opponent) | No |
| A/D (16983) | Taps A and D in turn while there is a target | Done | Interval slider; lets go when the toggle goes off, the character is knocked or a text box has focus | Yes: A and D alternated, released on disable |
| Resolver (16990) | Finds the target's real position | Partial | Has cluster and adaptive modes with radius, window, hold and lead. Missing: the weighted and hybrid types, Out Of Void Bonus, Normal Position Trust, Forget Rate, Void Trust, Accuracy, Distance Based Penalty, Lerp | Yes, synthetic positions: cluster, normal mover, void |
| Hitboxes (16997) | Head, Body, Arms, Legs | Done | Same rule as the original: head wins when ticked, otherwise the torso | Config round trip of the multi dropdown: yes. Shots: no |
| Prediction (17012) | Leads the aim | Partial | Lead is in the Resolver. Missing: Resolver Rate, Velocity Source, Strength as separate options | Yes, with the resolver |
| Lead Fast Targets (17027) | Leads targets that move fast | Partial | Same lead as above, capped at 30 studs | Yes |
| Target Selection (17121) | Chooses the target | Partial | Has: automatic with Cooldown, priority (mouse, character, health, random), FOV, distance, Ignore If (in void, protected, knocked), Untarget When (dead, knocked, flung), notifications, target key (press selects, press clears). Missing: Target When Shot At, Force, Wait For Spawn Protection, Void While Waiting (Void Spam has its own), Target Statuses | Config round trip of the multi dropdowns: yes. Selection and the key: no (needs players) |
| 3D Target Circle (17165) | Ring round the target | Done | Colour; the gradient colour is not there | Yes (24 line segments drawn and removed) |
| View Target (17172) | Camera on the target | Done | | Yes |
| Show FOV (17185) | FOV circle | Done | Colour and active colour; Outline and Follow Target options missing | Yes |
| Tracer (17192) | Line to the target | Done | Thickness, colour, origin; Outline and End Point missing | Yes |
| Full Auto (17231) | Hold the left mouse button to keep shooting the gun in hand | Partial | Speed is a share of the gun's own fire rate and never goes past its cooldown. The original's AUG round-by-round mode is not there | No (no gun in the test inventory) |
| Maximum Fire Rate (17239) | Patches the client gun scripts to remove their limits | No | Deliberately not reproduced: it works around the client-side fire limiter | |
| Auto Stomp (17248) | Stomps knocked targets | Done | Stop When Target Dead; Target Statuses, Wait For All and Prioritize Over Reloading missing | No (needs a knocked player) |
| Anti Bounty (17255) | Leaves the server when a bounty is put on you | Done | Reads the 21 bounty posters twice a second | Poster reading yes (own name found, unknown name ignored); the kick itself was not run |
| Auto Bounty (17263) | Hunts whoever has the bounty | Partial | Switches on ragebot, follow, auto fire, auto stomp and reload for the bounty holder, and puts them back off when nobody has it | Poster reading yes; an unknown name switches nothing on; the hunt itself needs a second player |
| Safe Purchasing (17271) | Holds a purchase while players stand near the shop | Partial | Avoid target or anyone within a set distance. Missing: the friendly, neutral and enemy status choices (Vanta has no player statuses) | No (needs another player) |
| Auto Loadout (17278) | Buys a loadout | Partial | Buys the chosen guns you do not own and tops up their reserve ammo (packs slider). Missing: Disable When | No (spends real in-game cash on guns; not run) |
| Follow Target (17285) | Moves the body round the target | Partial | Has orbit, random, above, strafe above, teleport, zigzag, distance, height, speed, reposition, follow into void, Stop If, Lead and Lead Time, Orbit Shape (circle, square, triangle, pentagon, hexagon, decagon, heart), Teleport Min/Max, Zig Zag Height and Speed, Visualize. Missing: Adjust | Yes on a self target: all seven shapes at the right radius, teleport range 5.4 to 24.7 for 5 to 25, zig zag flips at the set speed, Stop If stops the body, visualize drawn and removed, clean disable |
| Auto Ammo (17292) | Buys ammo | Done | Minimum Clips, packs per purchase; Disable When missing | Yes: two Rifle ammo packs bought, reserve 35 to 45, cash dropped by 562 |
| Auto Armor (17299) | Buys armor | Partial | Buy If Below and the keep-cash reserve; Try Cooldown missing | The purchase path is tested with other items; armor itself was not bought |
| Anti Stomp (17306) | Keeps a knocked character out of reach | Partial | Stands in the void while knocked. The original also kills the character on purpose and flings it; that is not reproduced (it forces health and physics ownership) | Yes with a locally faked knock: body went out and came back |
| Anti Report (17313) | Shuts everything off and kicks you when someone reports | No | Deliberately not reproduced: its purpose is to avoid reports to the game's moderators | |
| Auto Mask (17321) | Buys and wears a mask | Done | Buys a ninja mask and puts it on; does nothing while one is worn. Disable options missing | Yes: mask bought and worn; nothing bought while worn |
| Auto Heal (17328) | Heals | Partial | Buys popcorn and eats it below a health percentage, with the eat interval. Missing: Stop Following While Healing | No (needs damage; not run) |
| Void (17350) | Void hide, spam and bait | Partial | Has the spam cycle with void and window times and the ready-gun gate, hide while waiting, Type (random, deep, bait), Deep Distance, Offset, and Bait (distance, cooldown, time, freeze, spot random or where you stood, skipped when another gun covers the spot or health is low). Missing: Disable When, Force When, Stop If Forced, Out With Target, Hide While Target Hides | Yes on a self target: deep spot stable at 1.1e8 studs, 16 bait visits in 3 s, bait at the standing spot, cycle ran, body restored, clean disable |

## The older menu

`ORIGINAL_INVENTORY.md` lists all 517 controls of the older menu in `Visions-hook.lua`, section by section, each with a status: 98 Yes, 19 Partial, 393 No, 7 Declined. The systems with no entry in the top-level list above are in it: the legit bot (aim assist done; silent aim, triggerbot and recoil/spread options not), player ESP (box, name, distance, tool, health, armor done; chams, highlight, image, icons and the per-status colours not), movement (speed, flight, noclip, jump power, anti sit done), the lighting and weather settings, the hit and bullet feedback (tracers, markers, sounds, chams), the local character visuals, skins, the animation tools and trash talk, none of which are in Vanta yet. Not yet read in detail: the Des Hood part, the inventory sorter and the intro animation.

## What the final audit shows

The audit you asked for cannot be signed off: 393 of the 517 older-menu controls are not implemented, 7 are declined, and nothing here was tested against a real opponent. The table in `ORIGINAL_INVENTORY.md` is the full account.

## Shop (added)

The shop module buys through the shop parts in `Workspace.Ignored.Shop`: 105 distinct items were found in the live game, the cheapest copy of each is used. A purchase holds the character beside the part for its whole duration and puts it back afterwards. A click from 8.8 studs below the part was refused in testing; one from 3 studs beside it was sold. Tested live with real in-game cash: cranberry, hamburger, lemonade-style cheap items, two Rifle ammo packs, a ninja mask; an unaffordable item fails and backs off.

## Added in the last round

| Area | What exists | Tested |
|---|---|---|
| Player ESP | Box, name (display name option), distance (studs or metres), tool text, health bar and text, armor bar, colour and target colour, only-target | On yourself: every element drawn and cleared. Other players: no |
| Aim assist | Hold key, camera or mouse method, head/chest/root, FOV circle, max distance, horizontal and vertical smoothing, visibility check, ignore knocked and protected | No (needs players) |
| Movement | Speed, flight, noclip, jump power (a game-side reset is overridden through a `__newindex` hook), anti sit | Jump power holds 120 across frames and restores to 50; noclip leaves 0 colliding parts; flight hovers; speed needs walking input |
| Utility | Anti AFK, rejoin, watermark switch | Watermark switch yes; rejoin and anti AFK not run |

## Hit and shot feedback (added)

Ten of the older "game" visuals now exist as the Feedback module: 2D and 3D hit markers, damage numbers, hit sound (15 sounds from this repository's `assets`, fetched once into `Vanta/sounds` and played through `getcustomasset`), hit overlay, hit chams, hit particles, hit skeleton, local bullet tracers, local bullet impacts; shot notifications are partial (hit, or no hit). A shot is learned from the game's own `ShootGun` call (a read-only hook that passes the call straight on); a health drop on another player within 0.6 s and 30 studs of where the shot was sent counts as the hit.

Tested live: every effect created from a synthetic shot and hit (nine effects alive, then none after their lifetimes, no leftover parts), the overlay and chams objects, the sound download, load and playback (0.86 s clip, names with a space work). Not tested: the real shot hook and the real hit match (no second player). Not reproduced: player bullet tracers and volume, mute gun sounds, local bullet sound, RPG warning, override armor pop.

## Legit bot (added)

The legit bot is now three features that share one player finder (`Legit.best`): aim assist (camera or mouse method, separate horizontal and vertical smoothing, target swap cooldown), silent aim (hitbox, FOV, max distance, max curve in degrees, dont curve vertically, redirect chance rolled once per press; it answers the game's own gun script through the mouse and never touches the shot data) and the triggerbot (hitboxes, max distance, refresh rate, hover time, cooldown, delay; it activates the gun in hand).

Tested live with a second account in the server: the finders pick the right player and part; aim assist turned the camera onto the player (20.0 degrees off to 0.02 in half a second); the target key selects, clears and selects again; ESP drew every element on the other player; Follow held the body exactly 15.0 studs from them with the real position restored each frame. Not tested: silent aim and the triggerbot (they need a held mouse button or a gun and a shot; nothing was fired at the other account).

Not reproduced: bullet manipulation, force hit, range enhancer and double tap (they change what is claimed to the server), reduce shotgun spread (changes the shot data), remove recoil (the original drops the game's recoil packet through its event forwarder; not rebuilt).

## World, crosshair and character visuals (added)

All of these are local to your screen and put back what they replaced.

- **World:** time of day, ambient colours, lighting technology (written through the reflection library), atmosphere (the game's own is changed when it has one), colour correction (saturation, contrast, tint), blur, five skyboxes, rain or snow that follows the camera, hide chat, hide the cursor icon, switch 3D rendering off. The game rewrites some of these on its own, so the ones that are on are written every frame. The original spoofs the values the game reads back to hide the change; that is not done here.
- **Crosshair:** four lines with gap, size, thickness, outline and rotation, optionally on the target, a different colour while there is a target, and a state panel (shopping, void spam phase, following, targeting, idle).
- **Character:** highlight, material, china hat, particle aura, rainbow highlight on the tool in hand.
- **ESP:** chams (fill) and highlight (outline), through walls or not.

Tested live: every world setting switched on and off (time, sky id, atmosphere density, colour correction 1.5 and blur 9 created as separate effects and then removed, weather patch created and destroyed, cursor hidden and restored, lighting technology set); crosshair nine objects drawn and cleared; character highlight, hat, aura and 24 ForceField parts applied and fully reverted; ESP chams on the second account on and off.

The main chunk had reached the limit of 200 local variables while this was added (the script failed to run until the menu was moved into a function); the menu now builds inside `buildMenu()`.

## Remaining misc (added)

Movement: lock walk speed, remove slowdowns and remove jump cooldown (they drop or correct the writes the game makes to your humanoid's WalkSpeed and JumpPower, through the shared hook), anti trip, spinbot, and the pushback guard (when one frame carries the body backwards by more than 24 studs and more than 8 frames of travel, speed and flight fall to a quarter for 10 seconds, again for each repeat). Misc: hide other players' nametags, animation player (nine emotes and a custom asset id), unlock camera distance.

Tested live: the walk speed held at 60 while locked and went back to 16 when unlocked; the spinbot turned the character and gave AutoRotate back; anti trip turned FallingDown off and on; the camera zoom limit lifted and restored; the animation played, switched and stopped; the pushback guard fell to 1/64 on a simulated push back and returned to 1 after ten seconds. Not tested: remove slowdowns and remove jump cooldown (they need the game to write a lower value), hide nametags on the second account (it had left the server by then).

Not reproduced: animation breaker (changes what other players see of your animations) and trash talk (automated chat messages).

**A reload bug fixed.** Each load installed three more metamethod hooks (they cannot be removed) and the layers stacked, so a client that had been reloaded many times slowed on every instance index, call and write; one test client dropped out of the connection while I was reloading it. There is now one hook per kind for the whole session (`Hooks.set`); a load or an unload only changes the handler behind it. Six reloads in a row left three hooks and the same timing.

## Remaining combat (added)

- **Statuses:** every player can be marked friendly, neutral or enemy (a "players" tab with a list, a set-status button and a set-as-target button), kept in `Vanta/statuses.json` by user id. Optional rules mark friends and crew mates friendly and the friends of an enemy enemy. The statuses are used by target selection, Auto Stomp (which now also stomps other knocked players of the allowed statuses within a range), Safe Purchasing, the legit features and ESP (friendly and enemy colours, and which statuses are drawn).
- **Resolver:** weighted and hybrid modes with the original's controls (out of void bonus, normal position trust, void trust, forget rate, accuracy, distance penalty, lerp when close). A target that moves like a player is now aimed at where it shows in every mode: a resolved spot only lags behind it.
- **Visuals:** FOV circle on the target, FOV and tracer outlines, tracer end point, view target stops when knocked, an information panel (name and status, health, armor, distance, tool, resolver source and confidence), face target.
- **Void spam:** force when (reloading, tabbed out, not full health), stop if forced, out with target, hide while target hides.
- **Auto equip:** equip order, prioritize the Double-Barrel, unequip when; Shop: armor try cooldown, pause when, stop following while healing; Anti stomp: teleport back.

Tested live with a second account in the server: statuses (default, set, persisted file, skipped by the default target statuses, allowed when listed, cleared); the three resolver modes on a synthetic faker (all within half a stud of the true spot) and on a walker (aimed directly); void spam conditions (target hiding gets no window, target coming out gets the body onto it, force when tabbed out hides even with the spam off); FOV and tracer outlines, end point, information panel; face target (0.0 degrees off, auto rotate restored); shop pause logic. Not tested: auto equip (no gun in the inventory), anti stomp teleport back, auto set statuses by friends or crew (no friend or crew in the server).

Not reproduced: target when shot at, force, wait for spawn protection, wait for all targets knocked, prioritize over reloading, fire cooldown, shot delay, pre fire and the other auto fire extras (at target vehicle, always fire, dont render, show fake bullets, fast retry), resolver rate and velocity source, follow adjust.

## Skins and inventory (added)

**Skin changer.** The module reads `ReplicatedStorage.SkinModules` (per gun, every skin with the mesh or texture to use and where the mesh sits), and for a chosen skin either swaps the gun mesh's texture or hides the mesh and welds the skin's mesh in its place, then takes the skin's shoot sound and particles from `SkinAssets` when it has them. It covers 20 guns and the bat. Choices are saved per weapon in `Vanta/skins.json` and applied again when a tool is added or the character respawns. Everything is local: other players see the gun as it is.

Tested live: the weapon list (21), a texture skin (texture changed and restored), a mesh skin (one welded clone, original hidden), switching skins (still one clone), the changer off and on, a tool removed and added back, default, and two other guns (the Double-Barrel and the Flintlock).

Not reproduced: knife skins (they need the hand weld and the knife's animation and sounds), custom skins from files (meshes, beams, particles, sounds, animations) and the refresh-custom-skins button.

**Inventory sorter.** The game saves a hotbar layout as the setting `HotbarLayout` and arranges its hotbar by it. The module works the layout out from nine slot choices and sends that same setting (`UpdateSingleSetting`), only when it differs from the saved one and at most every 1.5 s; Sort Now and an auto switch (after the backpack changes and after a respawn). Tested live end to end: the default layout, "already saved" when the slots match, a real send (the server's attribute changed to the new layout) and a second send that restored the account's original layout exactly. Not reproduced: ordering the tools that have no slot, which the original does by moving them out of the hotbar through the hotbar script's internals.
