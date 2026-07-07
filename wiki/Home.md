# YellowStone — Creature Movement System

This wiki documents the complete creature locomotion stack: physics, state
resolution, turning, terrain alignment, animation blending, and the
server-side speed authority. It is written against the current source under
`src/` and every formula here is the exact formula implemented in code.

The system is modelled on *The Isle*'s creature movement: momentum-based
locomotion, per-species turning behaviour, angle-driven speed braking,
turn-in-place animations while stationary, and animation state derived from
the creature's **measured velocity** rather than its input.

## Pages

| Page | Contents |
|---|---|
| [Architecture and Authority](Architecture-and-Authority.md) | Client/server split, per-frame pipeline, networking model |
| [Gait Resolution](Gait-Resolution.md) | Velocity-derived visual gait: clamping, smoothing, hysteresis |
| [Turning and the Turn Brake](Turning-and-the-Turn-Brake.md) | Per-gait turn rates, per-creature brake curves, velocity application |
| [Turn In Place](Turn-In-Place.md) | Isle-style standing turns: states, triggers, animation-paced rotation |
| [Terrain Alignment](Terrain-Alignment.md) | Ground probe, plane fitting, normal smoothing, orientation composition |
| [Animation System](Animation-System.md) | Track layers, phase-synced crossfades, playback-rate scaling |
| [Server Speed Authority](Server-Speed-Authority.md) | MovementService: speed ramping, stamina, health penalties |
| [Creature Configuration](Creature-Configuration.md) | Full `CreatureStats` reference and tuning guide |

## Source map

| Module | Path | Role |
|---|---|---|
| `MovementController` | `src/StarterPlayer/StarterPlayerScripts/Controllers/MovementController.luau` | Client: the per-frame movement loop (input, turning, velocity, orientation) |
| `MovementService` | `src/ServerScriptService/Services/MovementService.luau` | Server: WalkSpeed authority, stamina/health integration |
| `SpawnService` | `src/ServerScriptService/Services/SpawnService.luau` | Server: morphing, body movers, animation folder setup |
| `StateMachine` | `src/ReplicatedStorage/Modules/Movement/StateMachine.luau` | Shared: gait slot + action slot, signals |
| `MovementStates` | `src/ReplicatedStorage/Modules/Movement/MovementStates.luau` | Shared: declarative state definitions (gaits, turns, actions) |
| `MovementMath` | `src/ReplicatedStorage/Modules/Stats/MovementMath.luau` | Shared: pure math (brake curve, gait bands, acceleration) |
| `StaminaMath` | `src/ReplicatedStorage/Modules/Stats/StaminaMath.luau` | Shared: pure math (stamina, health penalties) |
| `CreatureStats` | `src/ReplicatedStorage/Modules/Stats/CreatureStats.luau` | Shared: per-species/gender configuration data |
| `AnimationController` | `src/ReplicatedStorage/Modules/AnimationController.luau` | Client: track loading, layered playback, crossfading |
| `Common` | `src/ReplicatedStorage/Modules/Common.luau` | Shared: player → creature-config lookup (fails loud) |

## Design principles

1. **The server owns speed magnitude; the client owns direction.** The client
   can never move faster than the server-driven `Humanoid.WalkSpeed` allows,
   but all steering, braking and orientation are simulated client-side for
   zero-latency feel.
2. **Animation state is derived, never commanded.** The visual gait is a pure
   function of the measured velocity, so it can never desync from what the
   creature is physically doing.
3. **No silent fallbacks on data fetches.** Configuration lookups
   (`Common.GetPlayerInfo`, curve evaluation, gait resolution) `assert` on
   missing data. A `nil` speed or malformed curve is a bug to surface, not to
   paper over with a default. Fallbacks are only used where a genuine
   alternative source exists (e.g. `info[gait .. "TurnRate"] or info.BaseTurnRate`,
   where `BaseTurnRate` is the documented guaranteed value).
4. **Framerate independence everywhere.** All easing uses the exponential form
   $\alpha = 1 - e^{-k\,\Delta t}$ and all penalties are driven by *angles*,
   not per-frame rates, so behaviour is identical at 30 FPS and 240 FPS.
