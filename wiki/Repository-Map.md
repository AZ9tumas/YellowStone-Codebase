# Repository Map

Where everything lives, and where your new code should go.

## Rojo mapping

`default.project.json` maps folders on disk onto Roblox services. Only these
four branches are synced; everything else in the game lives in the `.rbxl`.

| Disk | Roblox |
|---|---|
| `src/ReplicatedStorage/` | `ReplicatedStorage` |
| `src/ServerScriptService/` | `ServerScriptService` |
| `src/ServerStorage/` | `ServerStorage` |
| `src/StarterGui/` | `StarterGui` |
| `src/StarterPlayer/StarterPlayerScripts/` | `StarterPlayer.StarterPlayerScripts` |
| `src/StarterPlayer/StarterCharacterScripts/` | `StarterPlayer.StarterCharacterScripts` |

File-name suffixes decide the script class:

| Suffix | Becomes |
|---|---|
| `Foo.luau` | `ModuleScript` |
| `Foo.server.luau` | `Script` (server) |
| `Foo.client.luau` | `LocalScript` |
| `init.luau` in a folder | The folder itself becomes that ModuleScript |

## Shared — `src/ReplicatedStorage/Modules/`

Code both sides need. Nothing here may touch a `Player`'s input or a remote.

| Path | Role |
|---|---|
| `Movement/MovementStates.luau` | **Pure data.** Every movement state (gaits, actions) and its rules. The gait ladder is defined here, once. |
| `Movement/StateMachine.luau` | Per-character state: one gait slot, one action slot, two signals. |
| `Stats/CreatureStats.luau` | **All tuning data**, per species and gender. Speeds, turn rates, brake curves, terrain settings, animation ids. |
| `Stats/MovementMath.luau` | Pure math: brake curve evaluation, gait banding, acceleration, spring-damper. Numbers in, numbers out. |
| `Movement/BodyArticulation.luau` | Procedural spine/neck/tail bend and chest bank on top of the animation; runs on every client (see [Body Articulation](Body-Articulation.md)) |
| `Movement/LegIK.luau` | Terrain foot planting — two-bone IK onto a probed contact point (see [Leg IK](Leg-IK.md)) |
| `Movement/HeadLook.luau` | Neck/head follow the camera or attend to nearby creatures (see [Head Look](Head-Look.md)) |
| `Movement/BoneWriter.luau` | Shared `Bone.Transform` bookkeeping + rig lookup for all three layers (see [Bone Writing](Bone-Writing.md)) |
| `Stats/StaminaMath.luau` | Pure math: stamina drain/gain, health-based speed penalties. |
| `Stats/init.luau` | Aggregator — flattens the three above so callers write `Stats.Accelerate(...)`. |
| `AnimationController.luau` | Loads and plays animation tracks on two layers (gait, action). |
| `Common.luau` | `Player` → creature-config lookup. Fails loud when a player isn't set up. |
| `CommonFunctions.luau` | Small generic helpers. |

## Server — `src/ServerScriptService/`

| Path | Role |
|---|---|
| `KnitServerInit.server.luau` | Boots Knit; registers everything in `Services/`. |
| `Services/SpawnService.luau` | Morphs a player into a creature: clones the model, attaches body movers, builds the animation folder, places them on the spawn. Also enforces the physics contract (collidable, massive root; massless, non-collidable cosmetics) and runs the out-of-world fall guard — see [Known Issues](Known-Issues.md) |
| `Services/MovementService.luau` | **The speed authority.** Ramps `Humanoid.WalkSpeed` toward the client's reported intent; applies stamina and health penalties. |
| `Services/HeadLookService.luau` | Validates and shares the owner's camera look direction for other clients' head/neck aiming. |
| `Services/CombatService.luau` | Attack damage resolution. |
| `Services/LoadingService.luau` | Gates spawning until the client reports it's loaded. |
| `DayNightHandler.server.luau`, `FoodSourceControl/`, `FootstepSFXServer/`, `HealthModifier.server.luau`, `WaterPart *.server.luau` | Older standalone systems, not yet ported to Knit services. |

## Client — `src/StarterPlayer/StarterPlayerScripts/`

| Path | Role |
|---|---|
| `KnitClientInit.client.luau` | Boots Knit; registers everything in `Controllers/`. |
| `Controllers/MovementController.luau` | **The main event.** The per-frame locomotion loop: input → gait → turning → velocity → orientation → animation. |
| `Controllers/ArticulationController.luau` | Runs all three procedural layers for every *other* player's creature from replicated physics |
| `Controllers/LoadingController.luau` | Client-side loading gate. |
| `ui.client.luau` | Creature-select menu and the debug HUD. |
| `mechanics/` | HUD, food/water cycle, footstep SFX. Older scripts, not Knit controllers. |
| `RbxCharacterSounds.client.luau` | Stock Roblox character sounds. |

## Not synced — lives in the `.rbxl`

* **The map and terrain** (`Workspace`).
* **Creature models**, under `ServerStorage.Models.<Gender>.<CreatureName>`.
  `SpawnService` clones these.
* **GUIs** under `StarterGui`.
* `ReplicatedStorage.Movers` — the `AlignOrientation` template `SpawnService`
  clones onto each character.
* `ReplicatedStorage.Packages` — Knit, Promise, Signal, Trove, etc.

## Where do I put new code?

| I'm adding… | Put it in |
|---|---|
| A tuning number | `Stats/CreatureStats.luau` — never hardcode it in a controller |
| A formula with no side effects | `Stats/MovementMath.luau` or `StaminaMath.luau` |
| A new movement state | `Movement/MovementStates.luau` (one row) |
| Client-side per-frame behaviour | A method or pipeline step in `MovementController` |
| A new client system with its own lifecycle | A new ModuleScript in `Controllers/` — Knit picks it up automatically |
| Something the server must own or validate | A new ModuleScript in `Services/` — Knit picks it up automatically |
| Anything both sides need | `ReplicatedStorage/Modules/` |
