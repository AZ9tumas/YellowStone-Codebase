# Glossary

The vocabulary this codebase uses. Several of these words mean something
narrower here than they do in general Roblox development.

### Gait
One of the five locomotion stages, slowest to fastest:
`Idle → Walk → Trot → Run → Sprint`. The ladder is defined **once**, in
`MovementStates.GaitOrder`; `Stats.MovementStages` and the gait-banding math
both read it from there.

### Visual gait
The gait **derived from the creature's measured speed**. Drives the animation
only. Never leaves the client. Computed each frame by
`Stats.ResolveGaitFromVelocity`. Stored on the `StateMachine`'s gait slot.

### Intent gait
The gait **the player is asking for** — from the keyboard, before physics.
`Idle` with no input, otherwise the active slow or fast style. This is the
**only** locomotion value that crosses the network, and only when it changes.

> Visual vs intent is the distinction to keep straight. Intent is what you
> *want*; visual is what the creature is *doing*. They differ constantly —
> the whole point of momentum-based movement is that the body lags the input.

### Style
Which gait a key currently means. `Z` toggles the **walk style** (`Walk` ⇄
`Trot`) and `X` toggles the **run style** (`Run` ⇄ `Sprint`). Holding Shift
selects the run style; releasing it selects the walk style.

### Facing
The creature's own forward direction — a unit `Vector3` on the XZ plane, owned
by the client. Movement is always **along the facing**, never along the input
(tank controls). Input steers the facing; it doesn't strafe the body.

### Angle gap
The angle between the current facing and the heading the player is demanding.
Drives both the rotation this frame and the turn brake. Shown as `Angle` on the
debug HUD.

### Turn brake
A multiplier in `[0, 1]` applied to the creature's speed, read off its
`TurnBrakeCurve` as a function of the angle gap. Sharp turn ⇒ low brake ⇒ speed
bleeds. It is **eased**, so the creature visibly decelerates into a turn and
accelerates out. Client-side only; the server never learns about it. Shown as
`Break` on the debug HUD (spelled that way in the UI).

> A brake of exactly `0` stops the creature dead and lets it pivot on the spot.
> No shipped curve bottoms out at 0, and none should.

### Turn rate
The maximum angular velocity (rad/s) for the current gait, from
`CreatureStats`: `info[gait .. "TurnRate"]`, falling back to `BaseTurnRate`.
Faster gaits configure *lower* turn rates, which is what produces wide arcs at
speed. Turning is never throttled by speed itself — only capped by this rate.

### Hysteresis
The dead zone around each gait boundary. A creature cruising at exactly its
`WalkSpeed` sits precisely on the Walk/Trot edge, so without a margin, physics
jitter would flap the animation every frame. You must *exceed* a boundary by
12% to shift up, and fall *below* it by 12% to shift back down. See
[Gait Resolution](Gait-Resolution.md).

### Morph
Turning a player into a creature: clone the model from
`ServerStorage.Models.<Gender>.<Name>`, set `player.Character`, attach the body
movers, build the animation folder. `SpawnService:Morph`.

### Body movers
The two constraints on the HumanoidRootPart that actually move the creature:
a **`LinearVelocity`** in `Plane` mode (X/Z only — gravity keeps Y) and an
**`AlignOrientation`** (force-based, not rigid) for facing.

### The object / per-life object
The single table holding all mutable per-character state in
`MovementController`, rebuilt on every spawn and owned by a `Trove`. When the
character dies the Trove destroys everything, so nothing leaks between lives.

### Action
A discrete, guarded activity that occupies the single action slot:
`Eat`, `Drink`, `Fight`, `Rest1`, `Rest2`. Actions are *requested* and may be
**rejected** — for example, you cannot start eating while sprinting.

### Freezing action
An action that suppresses locomotion (`Eat`, `Drink`, `Rest*`). While one runs,
intent and visual gait are both forced to `Idle` and no velocity is driven.

### Rest depth
`0` standing, `1` = Rest1, `2` = Rest2. **Derived** from the action name rather
than stored separately, so there's no second value to desync. `R` deepens it;
movement input pops one level.

### Loud failure
This codebase's house rule: configuration lookups `assert` instead of falling
back to a default. A missing speed or a malformed curve is a bug you want to see
immediately, not one masked by a silent `0`. See [Conventions](Conventions.md).

### Framerate independence
All easing uses $\alpha = 1 - e^{-k\,\Delta t}$ rather than
$\min(k \cdot \Delta t, 1)$, and all penalties are driven by *angles* rather
than per-frame rates. The system behaves identically at 30 and 240 FPS.

### Knit
The client/server framework in use. **Services** live on the server, **controllers**
on the client, and Knit generates the remotes between them. See
[Code Tour](Code-Tour.md).

### Trove
A cleanup helper. You `trove:Add(thing)` or `trove:Connect(signal, fn)`, and a
single `trove:Destroy()` tears all of it down.
