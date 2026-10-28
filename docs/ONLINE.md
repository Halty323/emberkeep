# Planned online features

The current game is **single-player and offline**. There is no networking transport, matchmaking, authentication, remote storage or score submission. The daily seed and lifetime counters are local. The Android preset does not request internet access.

## Foundations already present

- Floor graphs use a seeded generator separated from cosmetic randomness. Save data preserves the gameplay RNG state as a string to avoid JSON integer precision loss.
- Entities have runtime IDs; the player also has an owner peer ID.
- `Run.snapshot()` produces versioned run data for local saves.
- `Session` exposes command and snapshot signals and an authority check. The main scene publishes a small player/room snapshot at 10 Hz while playing. These signals are local only.
- Discrete player actions — use item, place bomb, interact, inspect painting, collect pickup and enter a doorway — already travel as commands through `Session.submit` to one validated handler (`scripts/interactions/game_actions.gd`). Each command carries an event id and the issuing peer; the handler checks ownership, range and resources, applies once, persists the result with its debit, and ignores duplicate event ids. A future host can run the same handlers for remote players. Movement and firing are still read locally.
- Rewards are credited once per stable source id (`<room>:e<n>`, splitter children derived from their parent), stored with the room, so restarting an encounter never pays twice. Client-side collection counts are not proof for any future leaderboard.

These are extension points, not an implementation of authoritative multiplayer or deterministic lockstep. Simulation uses physics and frame timing, so sharing a seed alone cannot synchronize two clients.

## Suggested co-op implementation order

1. Define two-player rules: shared or individual loot, health/revival, room transitions, camera framing and pause behavior.
2. Route player input through validated per-peer commands. Run all spawning, damage, loot and room progression on a single host authority.
3. Add an ENet transport and explicit replicated entity schemas, reliable spawn/despawn events and sequenced state snapshots. Add client interpolation and local-player prediction/reconciliation.
4. Build LAN join/host and disconnect/rejoin behavior before internet matchmaking. Include content and protocol versions in the handshake.
5. Add an authenticated relay or supported hosting service if internet connectivity requires it. Test latency, packet loss, reconnects and mobile app suspension.

## Leaderboards and cloud saves

Use a backend rather than trusting client-written score documents. Issue daily challenge IDs and seeds server-side; attach game/content versions and validate submissions. Unverified local runs should not enter ranked boards.

Cloud saves need accounts, schema migration and an explicit conflict policy. Sync profile progress separately from active run checkpoints. For concurrent devices, preserve the losing branch or present a choice rather than silently overwriting an active run. A co-op session checkpoint will need the party roster and shared state, which the present solo save format does not contain.

No backend vendor or account system has been chosen. Enable Android internet permission only when the online implementation is introduced.
