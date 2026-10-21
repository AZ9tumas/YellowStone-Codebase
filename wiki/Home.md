# YellowStone

A Roblox survival game where you play as an animal. Most of this codebase is the
creature locomotion system: momentum-based movement, per-species turning
behaviour, terrain-aware orientation, and animation state derived from the
creature's **measured velocity** rather than its input. The movement model is
inspired by *The Isle*.

This wiki is written against the current source under `src/`, and every formula
here is the exact formula implemented in code.

---

## New here? Read in this order

| # | Page | Time |
|---|---|---|
| 1 | **[Getting Started](Getting-Started.md)** — install, run, spawn a creature | 15 min |
| 2 | **[Repository Map](Repository-Map.md)** — what lives where | 5 min |
| 3 | **[Code Tour](Code-Tour.md)** — one keypress followed all the way to the screen | 20 min |
| 4 | **[Glossary](Glossary.md)** — the vocabulary, several words mean something specific here | 10 min |
| 5 | **[Conventions](Conventions.md)** — the house rules, before you write code | 10 min |

After that you can make a real change. **[Common Tasks](Common-Tasks.md)** has a
recipe for most of them.

## Working on it

| Page | Contents |
|---|---|
| [Common Tasks](Common-Tasks.md) | Recipes: add a creature, add an animation, add a state, add a service, tune feel |
| [Debugging and Testing](Debugging-and-Testing.md) | The debug HUD, what healthy looks like, how to verify a change |
| [Known Issues](Known-Issues.md) | Traps and gotchas — **skim this early**, it will save you an afternoon |

## Deep dives

Reference documentation for the movement system. Read [Code Tour](Code-Tour.md)
first; these assume you know the vocabulary.

| Page | Contents |
|---|---|
| [Architecture and Authority](Architecture-and-Authority.md) | Client/server split, per-frame pipeline, networking model |
| [Gait Resolution](Gait-Resolution.md) | Velocity-derived visual gait: clamping, smoothing, hysteresis |
| [Turning and the Turn Brake](Turning-and-the-Turn-Brake.md) | Per-gait turn rates, per-creature brake curves, velocity application |
| [Body Articulation](Body-Articulation.md) | Procedural spine bend, neck lead, tail whip and chest bank — how a turn looks alive |
| [Leg IK](Leg-IK.md) | Terrain foot planting: paws meet the slope instead of floating over it |
| [Head Look](Head-Look.md) | The head aims at the nearest creature while the gait keeps playing |
| [Bone Writing](Bone-Writing.md) | How three layers write the same bones without fighting |
| [Terrain Alignment](Terrain-Alignment.md) | Ground probe, plane fitting, normal smoothing, orientation composition |
| [Animation System](Animation-System.md) | Track layers, phase-synced crossfades, playback-rate scaling |
| [Server Speed Authority](Server-Speed-Authority.md) | `MovementService`: speed ramping, stamina, health penalties |
| [Creature Configuration](Creature-Configuration.md) | Full `CreatureStats` reference and tuning guide |

---

## Source map

| Module | Path | Role |
|---|---|---|
| `MovementController` | `src/StarterPlayer/StarterPlayerScripts/Controllers/MovementController.luau` | Client: the per-frame movement loop (input, turning, velocity, orientation) |
| `MovementService` | `src/ServerScriptService/Services/MovementService.luau` | Server: `WalkSpeed` authority, stamina/health integration |
| `SpawnService` | `src/ServerScriptService/Services/SpawnService.luau` | Server: morphing, body movers, animation folder setup |
| `StateMachine` | `src/ReplicatedStorage/Modules/Movement/StateMachine.luau` | Shared: gait slot + action slot, signals |
| `MovementStates` | `src/ReplicatedStorage/Modules/Movement/MovementStates.luau` | Shared: declarative state definitions and the gait ladder |
| `MovementMath` | `src/ReplicatedStorage/Modules/Stats/MovementMath.luau` | Shared: pure math (brake curve, gait bands, acceleration) |
| `StaminaMath` | `src/ReplicatedStorage/Modules/Stats/StaminaMath.luau` | Shared: pure math (stamina, health penalties) |
| `CreatureStats` | `src/ReplicatedStorage/Modules/Stats/CreatureStats.luau` | Shared: per-species/gender configuration data |
| `AnimationController` | `src/ReplicatedStorage/Modules/AnimationController.luau` | Client: track loading, layered playback, crossfading |
| `BodyArticulation` | `src/ReplicatedStorage/Modules/Movement/BodyArticulation.luau` | Client: procedural spine/neck/tail/bank on top of the animation |
| `ArticulationController` | `src/StarterPlayer/StarterPlayerScripts/Controllers/ArticulationController.luau` | Client: runs `BodyArticulation` for every *other* player's creature |
| `Common` | `src/ReplicatedStorage/Modules/Common.luau` | Shared: player → creature-config lookup (fails loud) |

## Design principles

1. **The server owns speed magnitude; the client owns direction.** The client
   can never move faster than the server-driven `Humanoid.WalkSpeed` allows, but
   all steering, braking and orientation are simulated client-side for
   zero-latency feel.
2. **Animation state is derived, never commanded.** The visual gait is a pure
   function of the measured velocity, so it can never desync from what the
   creature is physically doing.
3. **No silent fallbacks on data fetches.** Configuration lookups assert on
   missing data. A `nil` speed or malformed curve is a bug to surface, not to
   paper over with a default.
4. **Framerate independence everywhere.** All easing uses
   $\alpha = 1 - e^{-k\,\Delta t}$ and all penalties are driven by *angles*, not
   per-frame rates, so behaviour is identical at 30 FPS and 240 FPS.
5. **Simple beats clever.** A fixed-order pipeline of plain functions over one
   state table is preferred to an object graph that does the same job. Add
   indirection when a second caller needs it, not before.

> The repo's root `README.md` describes an **older movement model that no longer
> exists**. Ignore it; see [Known Issues](Known-Issues.md).
