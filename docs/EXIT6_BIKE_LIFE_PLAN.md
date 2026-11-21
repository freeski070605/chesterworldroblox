# Exit 6 — Bike Life (Phase 1)

Status: planned; road/highway reconstruction paused. This feature branch starts from main. Do not modify roads, terrain, bridges, or existing car behavior as part of Bike Life.

## Core goal
Add rideable dirt bikes and sport quads with server-authoritative ownership/spawning, physics-driven controls, and Xbox/keyboard/mobile input. Existing vehicles/phone/profile/economy must remain functional.

## Initial vehicle roster (fictional names; no third-party trademarks in shipped assets)
- 110 Trail (small dirt bike)
- 250 MX (medium dirt bike)
- 450 MX (high-power dirt bike)
- 450 Sport Quad (sport ATV)
- 700 Sport Quad (high-torque ATV)

## Ride controller
- Use Roblox constraints and assemblies, not CFrame teleporting for motion.
- Server validates driver seat ownership, spawn permissions, purchase/reputation checks and speed sanity. Client predicts responsive controls and camera.
- Bike pitch/balance requires tuning; use lean controller with correction limits and speed-sensitive stabilization. At rest, use kickstand/foot down logic or controlled low-speed assist.
- Quad has four-wheel suspension, separately-tunable steering/braking, traction/slip model and rollover detection.
- Do not claim final physics quality until tested in Roblox Studio and Xbox.

## Controls (first-pass proposals; rebind to avoid conflicts)
- Xbox: RT throttle, LT brake/reverse, left stick steer, A wheelie/lean-back modifier, B dismount when stopped, X stunt interaction, right stick camera.
- Keyboard: W throttle, S brake/reverse, A/D steer, Space wheelie/lean, F dismount, R reset if stuck.
- Mobile: dedicated throttle/brake, steering and wheelie button.
- Important: check existing Exit 6 phone, jump and vehicle input bindings before wiring final controls.

## Rideout gameplay
- Start/join rideout via phone (existing phone must stay functional).
- Group waypoints/meetups, participant count, optional leaderboard for longest controlled wheelie.
- Respect reputation gates; Roblox purchase of Chester Cash must never bypass them.
- Cosmetic monetization only initially; no cash betting or pay-to-win boost.

## Integration stages
1. Audit active vehicle/phone/garage modules and input bindings.
2. Prototype one 250 MX bike and one 450 Sport Quad in a safe test area; verify seat, mount/dismount and physics.
3. Xbox and keyboard tests: wheelie, turning, curbs, slopes, collisions, StreamingEnabled and performance.
4. Implement garage/catalog, spawn/despawn lifecycle, customization.
5. Expand lineup, rideouts and tricks/score system.
6. Mobile support and network hardening.

## Test acceptance
- Existing cars still work; phone opens/closes; no code from road feature branches is merged unintentionally.
- Bikes and quads spawn without falling through terrain, have controllable turning/braking and recover from crashes.
- A second player sees motion correctly; occupied bikes cannot be hijacked through spoofed requests.
- Xbox controls and camera verified on device.
- No change to 102-tile world startup dependencies as part of Phase 1.
