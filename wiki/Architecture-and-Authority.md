# Architecture and Authority

> **Reference for the client/server contract and the per-frame pipeline.**
> New to the codebase? Start with [Getting Started](Getting-Started.md) and the
> [Code Tour](Code-Tour.md); this page assumes the vocabulary in the
> [Glossary](Glossary.md).

## Authority model

The movement system splits authority so that exploits on speed are impossible
while steering still feels instant:

| Quantity | Owner | Mechanism |
|---|---|---|
| Speed magnitude | **Server** | `Humanoid.WalkSpeed`, written only by `MovementService` |
| Facing / direction | **Client** | `AlignOrientation.CFrame`, simulated in `MovementController` |
| Turn braking | **Client** | Multiplier on the applied velocity (can only *reduce* speed) |
| Locomotion intent | **Client → Server** | `SetState` remote, validated against known gaits |
| Visual gait / animation | **Client** | Derived from measured velocity, never networked |

Every frame the client applies

$$
\mathbf{v} = \hat{\mathbf{f}} \cdot \big(W \cdot b\big)
$$

where $\hat{\mathbf{f}}$ is the client-simulated facing (unit vector on the
XZ plane), $W$ is the replicated server-driven `Humanoid.WalkSpeed`, and
$b \in [0, 1]$ is the client-side turn brake. Because $b \le 1$, the client can
only ever move **slower** than the server allows, never faster. The vector is
applied through a plane-locked `LinearVelocity`
(`VelocityConstraintMode = Plane`, XZ tangents), so the constraint physically
cannot push on the Y axis — gravity and the Humanoid own vertical motion.

## The per-frame client pipeline

`MovementController` runs on `RunService.RenderStepped`. Each frame executes
four phases in order (`update`):

```
buildContext ─► updateState ─► updateMovement ─► updateOrientation ─► updateAnimationSpeed
```

### 1. `buildContext`

Gathers everything the rest of the frame needs, computed **once**:

* `moveVector` from the `ControlModule` (camera-relative input).
* `hasMoveInput` — whether any input is held.
* **Desired heading** $\hat{\mathbf{t}}$: the move vector transformed into
  world space by the camera and flattened to the XZ plane. With no input,
  $\hat{\mathbf{t}} = \hat{\mathbf{f}}$ (the current facing), which makes the
  angle gap zero and lets the brake recover.
* **Angle gap** — the demanded heading change:

$$
\theta_{\text{gap}} = \arccos\big(\operatorname{clamp}(\hat{\mathbf{f}} \cdot \hat{\mathbf{t}},\ -1,\ 1)\big)
$$

* **Turn sign** — which way to rotate ($+1$ = left / counter-clockwise from
  above):

$$
\sigma = \operatorname{sign}\big((\hat{\mathbf{f}} \times \hat{\mathbf{t}})_y\big), \qquad \sigma = 1 \text{ if the cross is zero}
$$

* `currentSpeed` — the **horizontal** measured speed
  $\lVert \mathbf{v}_{xz} \rVert$ from `AssemblyLinearVelocity`. The Y
  component is deliberately excluded: climbing a slope adds vertical velocity
  that is not locomotion (see [Gait Resolution](Gait-Resolution.md)).

### 2. `updateState`

* Steps the resting posture on the rising edge of movement input, or aborts
  `abortOnMove` actions.
* Resolves the **visual gait** from the measured velocity
  ([Gait Resolution](Gait-Resolution.md)).
* Sends the **intent** to the server — only when it changes:

```
intent = "Idle"                     if freezing action or no input
       = runStyle  (Run/Sprint)     if Shift held
       = walkStyle (Walk/Trot)      otherwise
```

### 3. `updateMovement`

Turning, braking and the velocity write
([Turning and the Turn Brake](Turning-and-the-Turn-Brake.md)).

### 4. `updateOrientation`

Terrain alignment, banking tilt and the resting lean, composed into the
`AlignOrientation` goal ([Terrain Alignment](Terrain-Alignment.md)).

### 5. `updateAnimationSpeed`

Scales the playing gait cycle to the measured speed
([Animation System](Animation-System.md)).

## State model

State is split into two orthogonal slots held by `StateMachine`
(one instance per character life):

* **Gait slot** — exactly one of `Idle | Walk | Trot | Run | Sprint`
  (category `Gait`). Drives the single locomotion animation track. There is
  deliberately **no transition graph**: the gait is a function of the current
  speed, so it can never desync from physics.
* **Action slot** — zero or one of `Eat | Drink | Fight | Rest1 | Rest2`
  (category `Action`). Actions are *requested* and may be rejected
  declaratively (`blockedGaits`, `guard`). Freezing actions
  (`freezesMovement = true`) force the intent and visual gait to `Idle` and
  zero the driven velocity. Resting is a two-level posture stack reusing the
  action slot (`Rest1 → Rest2`), deepened with <kbd>R</kbd> and popped by
  movement input.

`StateMachine` fires `GaitChanged` / `ActionChanged` signals; the
`AnimationController` is driven exclusively from those signals, so animation
always follows state through a single path.

## Networking

Exactly **one** locomotion value crosses the network: the intent gait, fired
through `MovementService.SetState` (a fire-and-forget `RemoteSignal`) and only
on change. The server validates it against `MovementStates.Definitions`
(category must be `Gait` — turn states and garbage are rejected) before
storing it in the player's `State` attribute. Everything else the client needs
(`WalkSpeed`) replicates natively through the `Humanoid`.

## Spawn wiring (`SpawnService`)

On morph the server:

1. Clones the species model and sets `CharacterName` / `Gender` / `State`
   attributes.
2. Applies the **physics contract** before parenting: the `HumanoidRootPart`
   collides and carries the mass, every other part is massless and
   non-collidable. The rigs ship with no collidable part at all, so without
   this a creature walks straight through walls — see
   [Known Issues](Known-Issues.md).
3. Creates the body movers on the `HumanoidRootPart`:
   * `LinearVelocity` — plane-locked (XZ), unlimited XZ force, zero Y force.
   * `AlignOrientation` — one-attachment, **force-based**
     (`RigidityEnabled = false`; rigid alignment would force-rotate the root
     through geometry and eject the character upward).
4. Builds the per-player `Animations` folder from the creature's
   `Animations` config table — the client `AnimationController` loads every
   entry in it at spawn.
5. Starts the **fall guard**, which remembers the last pose the creature was
   genuinely standing in and restores it if the root ever drops near
   `FallenPartsDestroyHeight`. Collision cannot recover a body that is already
   inside terrain; this is what stops a fall-through ending in a destroyed
   character.
6. Fires `Spawned` to the client, which rebuilds its `MovementObject`
   (all per-life state, cleaned up via a `Trove` on `CharacterRemoving`).
