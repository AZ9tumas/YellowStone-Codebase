# Code Tour

Follow one keypress from your keyboard to the animation on screen. If you read
one page before touching the code, read this one.

## Part 1 — Boot

The game uses [Knit](https://sleitnick.github.io/Knit/), a framework that
splits code into **Services** (server) and **Controllers** (client) and
generates the networking between them.

```
SERVER                                   CLIENT
KnitServerInit.server.luau               KnitClientInit.client.luau
  Knit.AddServices(Services/)              Knit.AddControllers(Controllers/)
  Knit.Start()                             Knit.Start()
    ├─ every module gets :KnitInit()         ├─ every module gets :KnitInit()
    └─ then every module gets :KnitStart()   └─ then every module gets :KnitStart()
```

Drop a ModuleScript into `Services/` or `Controllers/` and it is registered
automatically — there is no list to update.

Inside a service, `self.Client` is the public surface. A function on it becomes
a `RemoteFunction`; a `Knit.CreateSignal()` becomes a `RemoteEvent`. The client
reaches it with `Knit.GetService("SpawnService")`.

## Part 2 — Spawning

```
ui.client.luau            player clicks "Wolf"
  └─ SpawnService:Spawn("Wolf", "Male")          [client → server]

SpawnService:Morph(player, "Wolf", "Male")       [server]
  ├─ look up CreatureStats.Wolf.Male             ← rejects unknown names
  ├─ clone ServerStorage.Models.Male.Wolf → Workspace, set player.Character
  ├─ initChar          Humanoid.WalkSpeed = config WalkSpeed
  ├─ addBodyMovers     attach LinearVelocity + AlignOrientation to the HRP
  ├─ setupAnimations   build player.Animations from the config's animation ids
  ├─ attachFootstepSounds
  ├─ placeOnBase       pivot onto Workspace.Base
  └─ Client.Spawned:Fire(player)                 [server → client]

MovementController                                [client]
  └─ :_buildObject()   builds the per-life state and starts the frame loop
```

### The two body movers, and why

`SpawnService.addBodyMovers` attaches exactly two constraints to the
HumanoidRootPart. The split is deliberate:

* **`LinearVelocity`** in `Plane` mode drives **X/Z only**. It physically cannot
  push on Y, so gravity and the Humanoid keep the vertical axis to themselves.
* **`AlignOrientation`** (force-based, `RigidityEnabled = false`) drives
  **facing**. Rigid orientation would force-rotate the root through geometry and
  eject the character upward.

### The per-life object

All mutable state lives in one table (`object`) rebuilt on every spawn, owned by
a `Trove`. When the character dies, `trove:Destroy()` disconnects every
connection and destroys the `StateMachine` and `AnimationController` with it.
Nothing leaks between lives.

## Part 3 — One frame

`MovementController.update()` runs on `RenderStepped` and is five steps in a
fixed order. The order matters: each step reads what the previous ones wrote.

```lua
local ctx = buildContext(self, object)
updateState(self, object, ctx, dt)
updateMovement(self, object, ctx, dt)
updateOrientation(self, object, dt)
updateAnimationSpeed(object)
```

### 1. `buildContext` — read the world

Samples the move vector from Roblox's `ControlModule`, the shift key, and the
creature's measured horizontal speed. Converts the input into a **desired
heading** relative to the camera, then computes the **angle gap** between where
the creature is facing and where you're asking it to go, plus which way to turn.

Everything downstream reads this one snapshot, so all five steps see a
consistent view of the frame.

### 2. `updateState` — decide what the creature *is*

Two different gaits are resolved here, and confusing them is the single most
common mistake in this codebase:

* **Visual gait** — derived from the creature's *measured speed*
  (`Stats.ResolveGaitFromVelocity`). Drives the animation. Never sent anywhere.
* **Intent gait** — derived from your *input* (`Walk`/`Trot` or `Run`/`Sprint`,
  or `Idle`). This is the **only** locomotion value that crosses the network,
  and only when it changes.

Because the visual gait follows physics rather than input, the animation climbs
the ladder as the creature accelerates and descends it as it coasts to a stop —
for free, with no extra network traffic, and it can never desync from what the
body is doing.

### 3. `updateMovement` — turn and move

```
maxTurnRate = the gait's TurnRate (from CreatureStats)
Facing      = rotate toward the demand, capped at maxTurnRate · dt
targetBrake = EvaluateTurnBrakeCurve(angleGap, creature's curve)
TurnBrake   = ease toward targetBrake
LinearVelocity.PlaneVelocity = Facing · (Humanoid.WalkSpeed · TurnBrake)
```

That last line is the whole authority model in one expression. **The server owns
the magnitude** (`WalkSpeed`), **the client owns the direction** (`Facing`) and
may only ever *reduce* the magnitude (`TurnBrake` ∈ [0, 1]). A client cannot
make itself faster.

Turning itself is free — it is never throttled by speed. You pay for a sharp
turn in *speed*, through the brake curve, not in *turn rate*.

### 4. `updateOrientation` — stand on the ground

Fires four downward rays around the root, fits a plane to the hits, and eases
the creature's up-vector toward that surface normal. Composes the final CFrame
from facing + terrain normal + banking tilt and hands it to the
`AlignOrientation`. Also publishes `Grounded` and `ForwardSlope`, which
`updateMovement` uses next frame to block impossible climbs.

### 5. `updateAnimationSpeed` — sync feet to ground

Scales the playing gait cycle by `smoothedSpeed / gaitNominalSpeed` (clamped
0.5–1.2) so the legs don't skate when the creature is between bands.

## Part 4 — The server side

`MovementService` runs its own loop per player:

```
client reports intent ──> Humanoid.WalkSpeed ramps toward the config
                          speed for that gait, using Acceleration /
                          Deceleration, modified by stamina and health
```

Release the keys and the client reports `Idle`; the server ramps `WalkSpeed`
down to 0; the magnitude in step 3 shrinks with it — so the creature
**decelerates** instead of stopping dead. Acceleration from rest is the same
mechanism in reverse.

The server also rejects any reported state that isn't a locomotion gait.

## Part 5 — Animation

Nothing calls `PlayAnimation` directly. Animations follow state changes:

```
StateMachine.GaitChanged   → AnimationController:PlayGait(name)
StateMachine.ActionChanged → AnimationController:PlayAction / StopAction
```

The `AnimationController` resolves a track by **state name** from the player's
`Animations` folder — which `SpawnService` built from the creature's
`Animations` config. So adding an animation is a config edit, not a code edit.

## Where to read next

| You want to understand | Page |
|---|---|
| Why the gait doesn't flicker on hills | [Gait Resolution](Gait-Resolution.md) |
| Turn rates and the brake curve | [Turning and the Turn Brake](Turning-and-the-Turn-Brake.md) |
| The ground probe and plane fitting | [Terrain Alignment](Terrain-Alignment.md) |
| Crossfades and the layer model | [Animation System](Animation-System.md) |
| Speed ramping, stamina, penalties | [Server Speed Authority](Server-Speed-Authority.md) |
| The full client/server contract | [Architecture and Authority](Architecture-and-Authority.md) |
