# Online features

Local-network co-op is implemented: two to four players on the same network, each on their own device. See [co-op](COOP.md). There is no internet play, matchmaking, authentication, remote storage or score submission. The daily seed and lifetime counters are local. The Android preset requests network permissions for local co-op only.

## What co-op is built on

- `Session` (`scripts/session.gd`) is the transport: ENet on the local network, one host and up to three guests. Its handshake checks the protocol version and the content revision. `LanDiscovery` finds parties by broadcast query and announcement.
- Each device runs its own player and keeps its own run state (`Run`): health, wallet, relics, spellbook, pickups and rewards. Discrete actions still travel as commands through `Session.submit` to one validated handler (`scripts/interactions/game_actions.gd`), which runs on the player's own device.
- The host runs the shared world: foes, spells in flight, residue, hazards, bombs, props, doors and lanterns (`scripts/coop/party.gd`). Guests draw it and send back what their player did to it. Foes are credited once per stable source id (`<room>:e<n>`), on the host. Every player then receives their own drops for each credited kill.
- Floors are built by the host from the seed and sent to the guests, so the party walks the same rooms even if generation ever differed between devices.
- Co-op climbs are not saved. A solo save is never overwritten or deleted by a co-op climb.

## What remains

1. Rejoining a climb in progress after a dropped connection, and handing the host's world to a guest if the host leaves.
2. An authenticated relay or supported hosting service for play beyond the local network. Test latency, packet loss, reconnects and mobile app suspension over real internet links.
3. Saving a co-op climb. That needs the party roster, the shared world and every player's own state, which the solo save format does not hold.

## Leaderboards and cloud saves

Use a backend rather than trusting client-written score documents. Issue daily challenge IDs and seeds server-side; attach game/content versions and validate submissions. Unverified local runs should not enter ranked boards.

Cloud saves need accounts, schema migration and an explicit conflict policy. Sync profile progress separately from active run checkpoints. For concurrent devices, preserve the losing branch or present a choice rather than silently overwriting an active run.

No backend vendor or account system has been chosen.
