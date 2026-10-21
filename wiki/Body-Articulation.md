# Body Articulation (procedural turning)

The wolf does not rotate like a statue on a turntable. When it corners, the
**head leads** into the turn, the **spine bends** through it, the
**hindquarters lag** and swing through with a little overshoot, the **tail
whips** as a counterbalance, and the **chest banks** into the curve. None of
that is animated. `BodyArticulation` produces it every frame from the same
signals the movement controller already computes, on every client, with zero
network traffic.

Files:

| Module | Path | Role |
|---|---|---|
| `BodyArticulation` | `src/ReplicatedStorage/Modules/Movement/BodyArticulation.luau` | The layer: per-chain springs, bone writes |
| `BoneWriter` | `src/ReplicatedStorage/Modules/Movement/BoneWriter.luau` | Shared bone bookkeeping — see [Bone Writing](Bone-Writing.md) |
| `MovementMath.SpringDamperExact` | `src/ReplicatedStorage/Modules/Stats/MovementMath.luau` | Exact-integration spring used by every chain |
| `MovementController` | `Controllers/MovementController.luau` | Drives the **local** creature (richer signals) |
| `ArticulationController` | `Controllers/ArticulationController.luau` | Drives every **remote** creature from replicated physics |
| `CreatureStats[..].BodyArticulation` | `src/ReplicatedStorage/Modules/Stats/CreatureStats.luau` | Per-creature config. Absent = feature off |

---

## 1. This layer is FK — the IK is elsewhere

Body articulation is **forward kinematics**: set bone rotations, let the
hierarchy propagate. Inverse kinematics solves the opposite problem — given a
world-space end-effector target, find joint angles — and applies to
paw-on-ground and head-at-prey, not to bending a spine.

Both now exist, as separate additive layers running after this one:
[Leg IK](Leg-IK.md) plants the paws on the terrain, and
[Head Look](Head-Look.md) aims the head at the nearest creature. All three
share one writer ([Bone Writing](Bone-Writing.md)).

This matters because routing it through `IKControl` would import four open
engine problems the research surfaced (bone-twist accumulation without a
playing animation, unreliable `Pole` on multi-segment chains, no joint
constraints on Bone chains, and an open animation-vs-IK jitter bug on shared
chains). FK bone offsets carry none of them and are the officially documented
procedural-animation path (the `Animator` doc's own sample is
`bone.Transform = procedural * bone.Transform`).

Those IK layers deliberately do **not** use `IKControl` either; see
[Leg IK](Leg-IK.md) §2 for why bending about the limb's existing plane beats
a configured `Pole`.

## 2. The rig makes this cheap

The wolf is a single skinned `MeshPart` deformed by a 102-bone armature whose
hierarchy is **chest-rooted**:

```
Base → Body IK CTRL → Chest.IK → Chest
    ├── Back.001 → Back.002 → Lowe Back          ← 3-segment spine, runs FRONT → REAR
    │       ├── Pelvis.L/R → Thigh → Leg → Ankle → Back Paw
    │       └── Tail.001 … Tail.007
    ├── Scapula.L/R → Shoulder → Forearm → Wrist → Front Paw
    └── Neck.001 → Neck.002 → Head
```

The hindquarters are *descendants* of the chest. Yaw a spine bone and
everything behind it swings — the pelvis, the hind legs, the tail. "Front
leads, rear follows" is already encoded in the parenting; the layer only adds
per-segment **lag** to a propagation the rig performs for free. Every bone's
local `+Y` points down-chain (Blender convention, preserved through export).

**Chest is never yawed.** It parents both the rear chain *and* the neck, so
yawing it would move everything and double-count. Chest only banks.

## 3. The model

Each articulated chain owns a **spring-damper tracking a yaw signal**. The
chain's visible bend is the *difference* between its filtered yaw and the yaw
it is measured against:

| Chain | Tracks (goal) | Measured against (ref) | Result |
|---|---|---|---|
| `Spine` | body yaw | body yaw | lags → rear falls behind |
| `Neck` | **demanded heading** | body yaw | leads → head anticipates |
| `Tail` | the spine's filtered yaw | the spine's filtered yaw | lags the lag → whip |

$$\theta_{\text{chain}} = \operatorname{clamp}\big((\psi_{\text{filtered}} - \psi_{\text{ref}})\cdot g,\ \pm\texttt{MaxYaw}\big)$$

where $g$ is the speed gain (§3.3). When the turn ends every filter converges
on its reference, every $\theta \to 0$, and the rig relaxes onto the animated
pose. **The layer is self-zeroing by construction and cannot drift.**

### 3.1 Why a second-order filter

First-order smoothing ($1 - e^{-k\,\Delta t}$, the codebase's usual idiom)
gives pure lag: the rear trails and asymptotically catches up. It reads as
rubber-band. A spring-damper with damping ratio $\zeta < 1$ gives lag **plus
overshoot plus settle** — the hindquarters swing past the new heading and come
back. That overshoot is follow-through, and it is the entire perceptual
difference between "smoothed" and "alive".

`MovementMath.SpringDamperExact` is the closed-form solution of
$x'' = s\,(g - x) - d\,x'$, so it is unconditionally stable at any `dt` and
produces the **identical trajectory at any frame rate** — verified: one 0.6 s
step, 36 steps at 1/60 and 144 steps at 1/240 agree to 5 decimal places, and
all match a 20 kHz brute-force integration to $2.5\times10^{-5}$. Tuning is in
animator terms: `Frequency` (Hz) and `Damping` (ratio), converted by
`MovementMath.SpringParams`.

### 3.2 Anticipation uses the future, not a filter trick

A lagging filter can only trail its input. The head leads because its goal is
the **demanded heading** (`ctx.targetDir` — where the player is steering),
which is ahead of the body by construction. This only reads as a lead if the
neck's `Frequency` beats the body's turn rate; at the wolf's aggressive
`IdleTurnRate` (10 rad/s) a 4 Hz neck could not keep up, so it ships at 6 Hz.
The demand is measured from the **physical** heading, but the controller
chose its turn direction against the **desired** one, which the body trails
by up to a few tens of degrees. A near-reversal can therefore land on the
other side of 180° from the way the body is actually going. Whenever the
caller supplies `TurnSign`, any demand in the reversal half-plane is taken
round that side (`off ∓ 2π`); the bend is clamped, so a 200° goal is
harmless, and the head never flips sides mid-turn. The remote path has no
sign; there only an exact tie is broken, by the measured yaw rate. On a side
slope the local driver also projects the demand onto the root's plane, the
same projection the physical look already carries, so a straight demand
gives a zero offset instead of a permanent uphill head cock.

### 3.3 Speed gain

$$g = \texttt{IdleScale} + (1 - \texttt{IdleScale})\cdot\operatorname{clamp}\!\left(\frac{v}{v_{\text{ref}}},\,0,\,1\right)$$

eased with $1 - e^{-8\,\Delta t}$, and forced to $0$ while resting / frozen
(the ease means suppression never pops). `IdleScale = 0.35` keeps a little
articulation when pivoting on the spot.

### 3.4 Distribution down a chain

The chain's total bend is split across its bones by `Weights` (sum to 1,
omitted = even). Because children inherit their parents' rotation, bone $i$
receives only its own share and the cumulative rotation at the last bone is
the full $\theta$. The wolf's spine is rear-loaded (`0.25 / 0.35 / 0.40`): the
lumbar region is the flexible part of a quadruped.

Each share is applied about **the body's own up axis — the root's
`UpVector`, i.e. the axis the body actually turns about on a slope — expressed
in the bone's local frame**:

```lua
local axis = bone.TransformedWorldCFrame:VectorToObjectSpace(signals.Up)
offset = CFrame.fromAxisAngle(axis, share)
```

World-up would be wrong on terrain: on a 30° climb half of a spine bend would
leak into roll, and on a side-hill into pitch (lifting or burying the hind
paws). The root's up excludes the chest bank, so banking never tilts the yaw
axis. Computing the axis per bone per frame also means no per-rig constants
(it varies from $-0.77$ to $-1.00$ along local $Z$ across the rig).

### 3.5 Bank

$$\phi = -\arctan\!\left(\frac{v\,\omega}{g_{\text{world}}}\right)$$

clamped to `MaxRoll`, through its own damper, applied on `Chest` about the
body's forward axis — so the whole body inherits the lean. `MovementController`
zeroes its whole-body `Tilt` while a creature banks through the bone layer, so
the lean is never applied twice.

### 3.6 Sign conventions — measured, not derived

| Fact | Consequence |
|---|---|
| $\psi = \operatorname{atan2}(F_x, F_z)$ **increases** on a left turn | filters live in this space |
| $+\theta$ about the body's up (root `UpVector`; equal to world-up on the flat, where this was measured) swings a chain's far end to the body's **right** | lag applies $\theta = \psi_{\text{filtered}} - \psi_{\text{body}}$ directly; no per-chain sign |
| $+\phi$ about body-forward on Chest lifts the **left** shoulder | banking into a left turn ($\omega > 0$) is $\phi = -\arctan(v\omega/g)$ |

All three were measured on the rig in Studio and re-confirmed live.

## 4. Engine contract

| Fact | What the code does about it |
|---|---|
| The Animator writes bone `Transform`s, **then** `RunService.PreSimulation` fires. Writes anywhere else get stomped next frame. | Both drivers connect `PreSimulation` and compose on top. The `RenderStepped` sim loop never touches bones. |
| `Bone.Transform` does **not** replicate. | Every client runs the layer locally, from replicated state. `ArticulationController` covers remote creatures. |
| The Animator only rewrites bones the **playing clip keyframes**. On the wolf, Idle keyframes `Back.002`/`Lowe Back`/neck/tail but **not `Back.001`**. | Blind multiplication would compound forever on static bones. [`BoneWriter`](Bone-Writing.md) remembers the exact value it wrote and the pose it built it on; if the bone still holds that value the Animator did not touch it and the remembered base is reused verbatim (no per-frame inverse to drift). Verified: `Release()` restores the pose to a `0.000e+00` delta. |
| `Animator.EvaluationThrottled` marks frames where a distant rig's evaluation was skipped. | Nothing special: the write-detection above already treats an un-rewritten bone correctly, and skipping frames would drop `dt` from the springs. |
| The physical body trails `object.Facing` (force-based `AlignOrientation`). | **`Signals.Facing` must be the physical root orientation**, never a desired heading. Feeding `object.Facing` made the spine converge faster than the body and visibly *lead*. The demanded heading goes only to `TargetDir`. Pass the raw `LookVector`: yaw uses X/Z, and its pitch on slopes is the bank axis. |
| `RunService.PreSimulation` passes one argument, the physics step's `dt` (measured: `nargs=1`, 1/120 s). | Both drivers connect `function(dt)`. The yaw-rate estimate divides by the *real* `dt`; only the spring integration step is clamped to 0.1 s, so a hitch neither inflates `omega` nor overshoots. |
| A creature far away or frozen still exists. | The gain eases to 0; once it has died the layer releases its bones (`_release`) and skips writes. Springs keep integrating so nothing swings when the gain returns. |

## 5. Integration

**Local creature** — `MovementController._buildObject` constructs the layer
when `info.BodyArticulation` exists, owns it through the per-life `Trove`, and
feeds it on a dedicated `PreSimulation` connection:

```lua
local articulation = BodyArticulation.fromInfo(char, info)   -- nil = feature off
...
articulation:Update({
    Facing     = rootCF.LookVector,          -- PHYSICAL orientation
    Up         = rootCF.UpVector,            -- the axis the body turns about
    TargetDir  = demand,                     -- object.TargetDir projected onto the root's plane
    TurnSign   = object.TurnSign,            -- which way the controller is turning; nil while not steering
    Speed      = min(|v_xz|, WalkSpeed),     -- raw; BodyArticulation smooths it
    Suppressed = sm:FreezesMovement(),
}, dt)
```

Speed is smoothed **inside** `BodyArticulation` (one owner), so the local and
remote drivers cannot drift apart on a copied constant.

`BodyArticulation.fromInfo(character, info)` is the single place the config
block and its `SpeedRef` are resolved, whoever the caller is.

`SpawnService.Spawned` carries the new character model. It streams
atomically and can arrive *after* the remote, in which case the client
receives `nil` and `_buildObject` waits for `CharacterAdded` — it never falls
back to `player.Character`, which at that instant can still resolve to the
previous, rig-less character.

**Remote creatures** — `ArticulationController` attaches to every other
player's character and drives it from replicated physics. Which creature a
character *is* comes from the `CharacterName`/`Gender` attributes
`SpawnService` stamps on the character **model** before parenting it —
attributes replicate with the instance, so they are present the moment
`CharacterAdded` fires on other clients. (The `Player` attributes are set
afterwards and can still name the previous species during a re-morph; do not
read those here.) Signals: `Facing`/`Up` from the root's `LookVector`/`UpVector`; `Speed`
from horizontal `AssemblyLinearVelocity` **capped at the replicated
`WalkSpeed`** (smoothed by the module, exactly as for the local creature);
`TargetDir` extrapolated from `AssemblyAngularVelocity.Y` over `LEAD_TIME`
(0.13 s — sized so a typical turn rate lands near the neck's cap rather than
pinning it, see below) and clamped to `MAX_LEAD` (90°) so a spinning root can never
extrapolate past the body's rear and flip the lead. Beyond `MAX_DISTANCE`
the creature is suppressed (gain → 0, bones released).

Attach is synchronous and silent about "not yet": it constructs only once the
root, the Humanoid, the species attributes and **every configured bone** are
present, and otherwise just returns. A once-a-second sweep over the players
is the only retry — it also brings back a creature that streamed out and in
without a `CharacterAdded`. `SpawnService` sets the character's
`ModelStreamingMode` to `Atomic`, so root and bones arrive and leave
together and a half-replicated rig is never seen. A genuine config bug fails
loud once and is not retried. The local driver waits for the same bone list
before constructing, using the shared `BodyArticulation.MissingBones`.

`LEAD_TIME` is 0.13 s: the visible remote lead is yaw rate × `LEAD_TIME`
minus the neck spring's own ramp-tracking lag ($2\zeta/\omega$ = 0.053 s at
6 Hz), so 6 rad/s shows ~27°, near the neck's cap without pinning it.

## 6. Configuration

```lua
["BodyArticulation"] = {
    ["SpeedRef"]  = "TrotSpeed", -- fully on at this speed
    ["IdleScale"] = 0.35,        -- gain when stationary
    ["Chains"] = {               -- processed in order; Follows must name an earlier chain
        { Name = "Spine", Bones = { "Back.001", "Back.002", "Lowe Back" },
          Weights = { 0.25, 0.35, 0.40 }, MaxYaw = 22, Frequency = 2.5, Damping = 0.7 },
        { Name = "Neck",  Bones = { "Neck.001", "Neck.002" }, Weights = { 0.45, 0.55 },
          MaxYaw = 30, Frequency = 6.0, Damping = 1.0, TracksTarget = true },
        { Name = "Tail",  Bones = { "Tail.001", … "Tail.007" },
          MaxYaw = 45, Frequency = 1.8, Damping = 0.45, Follows = "Spine" },
    },
    ["Bank"] = { Bone = "Chest", MaxRoll = 18, Frequency = 2.5, Damping = 0.9 },
}
```

| Key | Meaning |
|---|---|
| `SpeedRef` | Name of the creature speed stat at which the gain reaches 1 |
| `IdleScale` | Gain at zero speed, 0–1 |
| `Chains[].Bones` | Bone names, parent → child. Must exist and be unambiguous — asserted at spawn |
| `Chains[].Weights` | Per-bone share of the bend. Sum to 1 (asserted). Omit for an even split |
| `Chains[].MaxYaw` | Hard clamp on the chain's total bend, degrees |
| `Chains[].Frequency` / `Damping` | Spring response (Hz) and damping ratio (< 1 overshoots) |
| `Chains[].TracksTarget` | Chase the demanded heading instead of body yaw (a lead) |
| `Chains[].Follows` | Chase another chain's filtered yaw (must be declared earlier) |
| `Bank` | Optional. Roll bone, clamp, spring. Presence disables `TiltSensitivity` for this creature |

Absent block = feature off for that creature (the same feature-flag convention
the rest of the config uses). `Chains` may be omitted for a bank-only creature,
but a block that declares neither `Chains` nor `Bank` is rejected.
Misconfiguration fails loud at spawn, naming the chain: unknown or ambiguous
bone names, a bone claimed by two chains (or a chain and `Bank`), empty
`Bones`, a `Weights` list whose length differs from `Bones`, a negative
weight, weights that don't sum to 1, negative `MaxYaw`/`MaxRoll`, missing or
non-positive `Frequency`/`Damping`, a duplicate chain name, a chain that both
`Follows` and `TracksTarget`, a `Follows` target declared later, `IdleScale`
outside 0–1, or a `SpeedRef` that is not a positive speed stat.

### Tuning guide

| Symptom | Knob |
|---|---|
| Rear feels glued to the front | Lower `Spine.Frequency`, raise `Spine.MaxYaw` |
| Rear wobbles after a turn | Raise `Spine.Damping` toward 1 |
| Head does not visibly lead | Raise `Neck.Frequency` (it must beat the body's turn rate) |
| Head snaps | Lower `Neck.Frequency` or `Neck.MaxYaw` |
| Tail too stiff / too floppy | `Tail.Frequency` / `Tail.Damping` |
| Nothing happens when pivoting on the spot | Raise `IdleScale` |
| Leans too hard | Lower `Bank.MaxRoll` |
| Bend saturates (hard edge) on snap turns | The body's `<Gait>TurnRate` is very high; raise `MaxYaw` or lower the turn rate |

## 7. Verifying it

The HUD shows every configured chain's bend by name (degrees), plus
`Bank` (degrees), `Gain` (0–1) and `Omega` (the physical yaw rate, rad/s).
At rest everything reads `0.0` and `Gain` equals `IdleScale`. Rename or add
a chain and the HUD follows the config.

Objective check used during development, driving the wolf at trot into
sustained turns (`Debugging and Testing` has the sampler pattern):

```
right turns → tail +10.6°  head −17.1°  chest roll −7.9° (leans right)
left turns  → tail −7.0°   head +3.7°   chest roll +4.9° (leans left)
turn ends   → head ≈ 0 within 5 frames, tail within 15, roll within 30
```
(walk/trot speeds; at a sustained trot spin the tail reaches ±11–17° and the
head's measured chord — Neck.001→Head, which under-reads the two-bone bend —
sits around 22°. The bend itself is clamped at `Neck.MaxYaw`, 30°.)

An isolated unit run (static clone, synthetic signals, no animator) is the
cleanest sign test: a 90° left snap gives `Spine −22, Tail −31.8, Bank −13.1`,
the tail then overshoots to `+4.2` and settles, and `Destroy()` returns the
rig to a 0.0000 delta.

## 8. Traps

| Trap | Guard |
|---|---|
| Yaw wrap at ±π — a spring sees a 2π step and explodes | Every yaw signal is unwrapped (`unwrap` / `wrapPi`) |
| Transform compounding on non-keyframed bones | Write-detection in [`BoneWriter`](Bone-Writing.md) |
| Writing bones on `RenderStepped` | Own `PreSimulation` connection |
| Hardcoding the yaw axis | Computed per bone per frame from the root's `UpVector` (`Signals.Up`); the axis varies 0.77→1.00 across the rig |
| Yawing `Chest` | Chest banks only |
| Double-counted lean | Whole-body tilt zeroed when `Bank` exists |
| Feeding a desired heading as `Facing` | Physical root yaw only; see §4 |
| Stationary/resting creature articulating | Gain eases to `IdleScale` / 0 |
| `dt` spike after a hitch | Exact integration; `omega` from the real `dt`, integration step clamped; `omega` clamp for teleports |
| Steady-state lag depending on frame rate | The exact spring holds its goal over a step; each chain integrates toward the midpoint of the previous and current goal (trapezoidal), removing the first-order dependence |
| Stale `TurnSign` (+1 when not steering) steering the reversal rule | The controller publishes a sign only while it is actually turning |
| A half-replicated rig (root present, bones not) | `Atomic` model streaming; both drivers wait on `MissingBones` |
| Skipping frames while the Animator throttles | Don't — the write-detection already handles it, and skipping drops `dt` |
| Near-reversal demand while the body trails the desired facing — head flips sides | `TurnSign` decides the side for any demand past 90° (remote: sign of `omega` on an exact tie) |
| Bend about world-up on a slope leaks into roll/pitch | Bend about the root's `UpVector` |
| Side slope — permanent head cock | Demand projected onto the root's plane, like the physical look |
| Remote lead extrapolating past 180° / pinned at `MaxYaw` | `LEAD_TIME` 0.13 s, clamped to `MAX_LEAD` |
| Remote creature streams out and back — never re-attaches | The once-a-second sweep re-attaches; attach is synchronous and silent until the rig is complete |
| Remote attach reading stale `Player` attributes on re-morph | Species read from attributes stamped on the character model |
