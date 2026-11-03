# Raknet

`RaknetResearch.lua` is a passive recorder for outgoing RakNet packets. It never calls `packet:SetData`, so it changes nothing that is sent.

## What it records

Per packet: index, id, seconds since start, gap to the previous packet and to the previous packet of the same id, size, a hex preview of the first 16 bytes, and whether the buffer is long enough for the offsets other code reads (`u32@1`). It also keeps per-id counts and an event log (hook on/off, errors, saves, simulations).

## Use in Visions hook

`utility` section, `raknet recorder` toggle, with a settings panel: packet logging, error notifications, packet ids (hex, empty = all), status, review (console), debug info (console), save recording, clear recording. The module is read from the executor workspace (`RaknetResearch.lua`) first, then from this repo. Unloading the menu removes the hook.

## Recordings

Saved with the luau-toolkit serializer (`luaukit/Ser.lua`) to `dumps/raknet/visions_<time>.json`. Without the toolkit in the workspace the recording stays in memory and save reports that.

## Tests

```
lune run Raknet/tests/raknet_research.spec.luau
```

Uses a mock `raknet` table and simulated packets only (hook add/remove, ids, sizes, validation, timing, ordering, filtering, ring cap, error isolation, before/after simulation, save, overhead).

## Not verified

- What packet `0x1B` means or its layout. Nothing offline documents it; the module records its size and timing and makes no claim.
- The real `raknet` packet object on a live executor (only `PacketId`, `AsBuffer`, `SetData` are known, from `Visions-hook.lua`).
- The UI in a running game (the file compiles; the menu was not opened).
- Real-traffic overhead.
