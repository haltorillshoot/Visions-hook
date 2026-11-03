# Vanta

A new, modular HvH script for Da Hood on the Priv9 UI. It is written from scratch with Visions-hook as a reference; no code was copied from it.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/haltorillshoot/Visions-hook/main/Vanta/Vanta.lua"))()
```

Running it again unloads the previous copy first. The `misc` tab has an unload button.

## Layout

| Module | Job |
|---|---|
| Util | `Maid` (connection bag), void test, ping |
| Players | Da Hood state from `BodyEffects` (dead, knocked, loading, spawn protection) |
| Target | The one selected target every module reads; picking, the target key, respawn and leave handling |
| Resolver | Where the target really is: grid clustering of recent map sightings, direct position plus lead for normal movers |
| Aim | Silent aim for the game's own gun scripts (`Mouse.Hit` / `Mouse.Target`), only while a shot is being made |
| Body | The only code that moves the character; asks Void Spam, then Follow, applies on Heartbeat, restores before the frame is drawn |
| Follow | Styles: orbit, random, above, strafe above, teleport, zigzag |
| VoidSpam | Void and window cycle; a window only opens when a gun can shoot in it |
| AutoFire | Per-gun ammo, cooldown and range; equips, aims and activates the tool; reloads empty guns while hidden |
| Ragebot | One Heartbeat step and one PreRender step, in a fixed order |

Every module reads its settings from the UI flags each frame, so a loaded config takes effect with no extra wiring, and each module resets itself when its toggle goes off.

## Techniques taken from Visions-hook

- `BodyEffects` for dead, knocked and loading states, and the ForceField check for spawn protection.
- Void positions are those 900,000 or more studs out.
- Shots wait until the server has had the body at its spot for a round trip.
- Slow guns go first; a gun repeats on its own cooldown.
- Shotguns are never fired from or at the void (SecurityTolerance).
- A Void Spam window only opens when a gun is ready, with an idle fallback.
- Reloads happen while the body is hidden.

## Improvements over the reference

- One target record and one body driver instead of state spread over a 46,000 line file.
- The clustering is a grid pass (linear in the history), redone 20 times a second at most.
- Settings are read live from the Priv9 flags; there are no per-setting callbacks to get out of step.
- Disabling any module or unloading restores the character, clears the silent aim and disconnects every connection.

## Limitations and untested parts

- **Not tested against another player.** The only test client was alone in its server. Tested live: loading, unloading, config save and load, all 37 flags created, the resolver (cluster, normal mover, void), Follow styles and Void Spam moving the body with the real position restored every frame, and clean disable.
- **Not tested:** target selection and the target key against real players, Auto Fire (no loaded gun was available), silent aim, reload requests, and whether the server accepts the shots.
- **No anti-cheat handling.** Da Hood's client anti-cheat may react to the movement; Visions-hook has its own handling for that, which this script does not include.
- The silent aim hook sits on `__index` of every instance and cannot be removed; it passes straight through when nothing is aimed. Unloading and reloading adds another pass-through layer.
- The Priv9 library is loaded from `i77lhm/Libraries`; if that file changes, the menu can change with it.
- There is no visuals tab because there are no visual features yet.
