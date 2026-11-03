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

# Desync test module

`DesyncResearch.lua` is a controlled desync test, separate from the recorder above. It does not log packets; it keeps running totals.

## What it does

**Write (the desync).** While on, it overwrites one u32 of the outgoing packet with id `0x1B` (offset 1, value `0xFFFFFFFF`, the same write `fake position` makes) and hands the packet on with `SetData`. It is gated and fails closed:

- it only turns on in a private/reserved server, or on a place this account created, and only while every other player in the server is in the trusted account list; a public server of someone else's place is refused (`state = blocked`);
- it turns itself off when an untrusted player joins, after the time limit (default 20 s), and after repeated errors;
- a packet shorter than offset + 4 is skipped and counted, `Verify Writes` reads the field back after `SetData`.

**Diagnostics (read only, any server).** Test mode samples the local character at a fixed rate and shares its last 20 samples with the other test client through `visions_desync/<userId>.json` in the executor workspace. The observer compares what it sees of the peer with what the peer reports: position gap now, delay of the replicated position (while the peer moves), update interval, jumps, stale reads, and the peer's reported state. Totals are kept per phase label, which the primary publishes. A field probe reports min / max / distinct values of the u32 at the offset and whether byte 0 equals the packet id, so the field's behaviour is checked instead of assumed.

**Suite (primary).** `baseline-before` (write off) -> `desync` (write on) -> `baseline-after` (write off). If the gate refuses the write phase it is recorded as skipped and the run is marked incomplete.

## Use in Visions hook

`utility` section: `Raknet Desync Test` toggle (the write), a status row, a clients row, and a settings panel: test mode, role (primary / observer), trusted account IDs, time limit, sample rate, jump threshold, suite phase length, auto walk, verify writes, notifications, run / cancel suite, status, compare clients, diagnostics (console), save results, clear results. The module is read from the executor workspace (`DesyncResearch.lua`) first, then from this repo. Unloading the menu removes the hook, stops test mode and deletes this client's exchange file.

Two-account test: put both accounts in the same private server, enter both user IDs in `Trusted Account IDs` on both clients, turn `Test Mode` on, set one client to `Observer`, run the suite on the primary, then `Diagnostics (Console)` on the observer and `Save Results` on both (`visions_desync/results_<time>_<role>.json`).

## Tests

```
lune run Raknet/tests/desync_research.spec.luau
lune run Raknet/tests/desync_menu.spec.luau
```

`desync_research.spec.luau` runs the module against a mock `raknet` (gate, write, short packets, error isolation, time limit, joiner shut-off, comparison between two simulated clients, suite, cleanup, hook cost). `desync_menu.spec.luau` runs the real menu block from `Visions-hook.lua` against a fake menu library and mock game.

## Not verified

- What the field at offset 1 of `0x1B` means. Nothing offline documents it.
- That `0x1B` is sent at all on the test clients: on 2026-11-04 the send and receive hooks received no packets of any id on either client (see the report below), so the id, size and byte layout are unconfirmed on a live executor.
- The write phase on a live executor: both test accounts were in a public server, where the gate refuses it.
- Update delay between clients: the primary character did not move, so the delay is not measurable from that run.
- The menu rows in a running game (the block is exercised against a fake library only).

## Test report, 2026-11-04 (two Potassium accounts)

Setup: two accounts attached to Potassium, same server of place 2788229376 (a public server, `PrivateServerId` empty, two players, both test accounts). Module loaded from the executor workspace on both clients; account 1 primary, account 2 observer. Nothing was written to any packet.

| Check | Result |
| --- | --- |
| Gate on a real public server: `enable()` on the primary | refused, `state = blocked`, reason `public server of a place you do not own`, `written = 0` |
| Suite on the primary (5 s phases) | `baseline-before` and `baseline-after` ran, `desync` skipped by the gate, `complete = false` |
| Exchange between the clients | both `visions_desync/<userId>.json` files appeared, the observer read the peer's state and phase |
| Observer, write off (`baseline-before` 49 samples, `baseline-after` 48 samples) | 0 stale reads, position gap max 0.001 studs, 0 jumps. The characters were stationary, so update delay and interval were not measurable |
| `add_send_hook` / `add_receive_hook` / `remove_*` | all succeeded without errors and removal was clean (no further callbacks) |
| Packets seen by the send and receive hooks | none, on either client, in three windows (7 s, 6 s, 10 s); `isrbxactive()` was false on both and the primary did not move (0.00 studs after `Humanoid:Move` for 4 s). A second run after rejoining another public server (primary moved 1.56 studs, 9 s) also saw none. Likely cause: Potassium's `settings.json` has `enable_raknet: false`; not yet confirmed by turning it on |
| Unload | hook removed, sampler threads 0, connections 0, own exchange file deleted, 0 errors |

Not run: the write phase (gate), anything that needs `0x1B` packets, delay measurement under movement. To complete them, turn RakNet on in Potassium's settings (`enable_raknet`, restart the clients if needed), put both accounts in a private server (or a place you own), and run the suite again. Both rejoin attempts so far landed in public Da Hood servers, so the gate would have refused the write again.

Saved on the test machine: `visions_desync/results_1793746247_primary.json` and `results_1793746247_observer.json` in the Potassium workspace.
