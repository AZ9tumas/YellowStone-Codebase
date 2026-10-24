# Per-animal Movement Tuning README

> Short version of [Creature Configuration](Creature-Configuration.md): only
> the keys that change how a creature **moves**, what each one really does at
> runtime, and where it is read. All live in
> `src/ReplicatedStorage/Modules/Stats/CreatureStats.luau` under
> `CreatureStats[Species][Gender]`.

Checked against the code on 22 October 2026. The current rows are `Horsie.Male`,
`MuleDeer.Male`, and `Wolf.Male`. This document describes existing behavior;
it does not change any settings.

## What the sharp-turn sliding is about

Two separate things combine: the brake curve keeps some forward speed, and
the wolf's sharp-turn animation shows footwork authored for turning on the
spot. At full sprint authority, the strongest wolf brake commands
`73 × 0.2 = 14.6` studs/s. The body therefore continues travelling while the
paws appear planted. A Trot gait label around that speed is appropriate, but
the turn overlay takes visual priority over the trot animation underneath.

Lower brake multipliers mean less travel during a turn; a higher turn-animation
entry angle means fewer turns use that footwork. These are separate controls.
Neither is a direct foot-sliding correction, and changing either affects feel.
`TurnInPlace.Brake` is: it caps speed only while a turn clip plays (wolf 0.05).

## How the pieces fit (one frame)

```
server:  WalkSpeed  ──ramps toward──▶  stamina-adjusted gait target × health scale
                                        (Acceleration / Deceleration)
client:  velocity  =  Facing × CommandedSpeed   (≤ WalkSpeed)
         Facing    turns toward input at  <VisualGait>TurnRate  (rad/s)
                   or follows a turn clip's pace, with that cap × SpeedMultiplier
         CommandedSpeed → WalkSpeed × TurnBrakeCurve(angle between facing and input)
                   while input is held: dropping fast, recovering at Acceleration
         on release: CommandedSpeed → 0 at Deceleration, still ≤ WalkSpeed
         VisualGait = band of the measured speed (Walk/Trot/RunSpeed thresholds)
```

**The turn brake is a fraction of the current server-controlled WalkSpeed.**
With Sprint selected and movement + Shift held, the server targets
`SprintSpeed`, subject to acceleration, stamina and health. For the current
descending curves, their last `Brake` is their minimum multiplier. The nominal
full-sprint minimum is therefore `SprintSpeed × minimum Brake`. This is a
commanded-speed minimum from braking alone; collisions, slopes, actions or
lower speed authority can produce lower actual speeds. The brake also takes
time to approach the curve value.

## Speeds (studs/s)

| Key | What it really does |
|---|---|
| `WalkSpeed` / `TrotSpeed` / `RunSpeed` / `SprintSpeed` | Server target speed for that **input** gait, and reference for the gait animation's playback rate (smoothed measured speed ÷ configured speed, clamped 0.5–1.2). Walk/Trot/Run also define the visual gait boundaries: upshift above the lower gait's speed × 1.12, downshift below it × 1.06. `SprintSpeed` is not another band boundary. Changing a speed can therefore change both travel and animation selection. |
| `IdleSpeed` | Server target when input is released or an action freezes movement; currently 0 for every animal. |
| `Acceleration` | How fast the server raises WalkSpeed (studs/s²), getting up to speed from rest. Also caps how fast speed comes back after a turn while movement input remains held (client side). |
| `Deceleration` | How fast the server lowers WalkSpeed on release / gait drop (studs/s²). On release, the client also reduces its current commanded speed toward zero at this rate, without recovering turn-braked speed. The server ceiling is still respected; the two reductions do not add together. **Does not affect turn braking while input is held** — speed is shed into a turn at a fixed rate (`TURN_BRAKE_RESPONSE = 10` in MovementController, ~0.1 s time constant). |

## Turning

| Key | What it really does |
|---|---|
| `<Gait>TurnRate` (`IdleTurnRate`, `WalkTurnRate`, `TrotTurnRate`, `RunTurnRate`, `SprintTurnRate`) | Max rotation speed in **rad/s** (4 ≈ 229°/s, 6 ≈ 344°/s, 10 ≈ 573°/s), chosen by the **visual** gait. Braking from Sprint into Trot changes the cap to `TrotTurnRate`, even while Sprint remains the input intent. An active turn overlay multiplies this cap by its `SpeedMultiplier`. Higher caps permit tighter turns; a slower turn clip may still limit rotation. Approximate radius at steady speed/rate is `speed ÷ angular rate`. |
| `BaseTurnRate` | Fallback for any gait without its own `<Gait>TurnRate`. Required. |
| `SwimIdleTurnRate` / `SwimTurnRate` / `SwimFastTurnRate` | Turn caps while swimming (see [Swimming](Swimming.md)). The deer's old `SwimmingTurnRate` is unread. |
| `TurnBrakeCurve[].Angle` | Heading gap in degrees between controller facing and requested direction. Points must be ordered by increasing angle; values between points are linearly interpolated. Moving a point changes where braking begins or strengthens. This is not degrees turned per second. |
| `TurnBrakeCurve[].Brake` | Fraction of speed retained at that point: 1 keeps full speed, 0.2 keeps 20%, 0 commands zero after easing. Lower means stronger braking. The minimum configured value determines the strongest brake; in the shipped curves it is the last point. These values affect ordinary steering and turn overlays alike. |

## Sharp turns (`TurnInPlace`, optional)

| Key | What it really does |
|---|---|
| `MinAngle` | Minimum heading gap (deg) to start or repeat a turn cycle. Raising it reduces how often clips start. An active cycle can continue below this angle until alignment, release, reversal, interruption or its end. |
| `Brake` | Optional. Most speed kept while a turn clip plays (fraction of WalkSpeed); the brake target becomes the lower of this and the curve, eased the same way. The clips plant the paws, so this is what stops the body sliding through them. Lower = more planted pivot; higher = more sweeping, more slide. Omitted = curve only. |
| `Turns[].Angle` | Authored turn size in degrees, used to select the closest clip by angle ratio. The 90/180 choice changes at about 127.3°. Actual rotation follows the requested gap, not a forced exact 90/180. |
| `Turns[].Left` / `Right` | Names from `Animations` for each direction. Rotation follows a smoothstep over the clip's playback duration, capped by the current gait rate × `SpeedMultiplier`. The wolf's 180 clips are about 1 second long at authored speed. Same-side repeats keep the clip looping. |
| `Turns[].SpeedMultiplier` | Optional positive, finite number; omitted or `1` = current pace. Shared by left/right in this row. Scales animation playback, rotation timing, and the turn's rate cap together: `1.3` = 30% faster, `0.8` = 20% slower. Playback duration is clip length ÷ multiplier. Also divides a procedural `Duration`; it does not change procedural paw-step settings. Does not directly change travel speed, braking, entry angle, or ordinary steering rates. |
| `Turns[].Duration` | Base seconds per procedural turn cycle, used instead of `Left`/`Right`; effective duration is this value ÷ `SpeedMultiplier`. Enables procedural paw stepping. Retained for experiments, currently not selected for Wolf. |

Turn overlays never zero velocity or force Idle. Movement continues at
`WalkSpeed × TurnBrake`, with the brake capped at `Brake` while a clip plays;
release/alignment cancels the overlay,
direction reversal switches sides, and actions or losing ground interrupt it.

For example, keep quarter-turns at their current pace and speed up about-faces:

```lua
Turns = {
    { Angle = 90, Left = "Turn90Left", Right = "Turn90Right", SpeedMultiplier = 1 },
    { Angle = 180, Left = "Turn180Left", Right = "Turn180Right", SpeedMultiplier = 1.3 },
}
```

A one-second clip takes about 0.77 seconds at `1.3`. The rotation cap scales
with it, but a restrictive gait cap can still prevent full alignment in one
cycle. Faster alignment can shorten the time spent braking; this setting does
not change the brake's speed floor. Wolf uses `1` for 90° and `1.3` for 180°. Set the value
back to `1`, or remove it, to restore the previous pace.

## Swimming (optional, currently Wolf)

| Key | What it really does |
|---|---|
| `Swimming.FloatDepth` | How low the body floats, as a fraction of its standing root height; also how deep water must be before it swims. |
| `Swimming.Buoyancy` | How fast the body settles to that float height (1/s). |
| `SwimIdleSpeed` / `SwimSpeed` / `SwimFastSpeed` | Server speeds in water: Idle, Walk/Trot and Run/Sprint input respectively. |
| `SwimStaminaDrain` / `SwimFastStaminaDrain` / `SwimIdleStaminaGain` | Stamina in water. An exhausted fast swim slows to `SwimSpeed`, never below. |

## Banking / lean

| Key | What it really does |
|---|---|
| `MaxTiltAngle` | Max whole-body roll into a turn (deg). Ignored when `BodyArticulation.Bank` exists (wolf). |
| `TiltSensitivity` | Whole-body roll in radians per rad/s of controller turning, capped by `MaxTiltAngle`. This bank is also bypassed when `BodyArticulation.Bank` exists. |
| `TiltSpeed` | How fast whole-body roll approaches its target (per s). Higher responds faster. It does not change steering or braking. |

## Terrain

| Key | What it really does |
|---|---|
| `TerrainAlignmentEnabled` | Enable ground probes and tilt the body to match the ground. Those probes also supply the slope used by `MaxClimbAngle`; this switch is therefore relevant to climb blocking too. |
| `TerrainAlignmentSpeed` | How fast it re-aligns (per s). |
| `MaxTerrainAngle` | Cap on the ground-normal tilt target (deg), before banking/rest lean is added. Does not set climb permission. |
| `MaxClimbAngle` | Forward slope (deg) past which velocity is zeroed — the "can't climb" wall. |
| `TerrainRaycastDistance` | Ground-probe reach in studs, with additional reach based on root size. Larger can find ground farther below the creature. |
| `MaxTerrainPitch` / `MaxTerrainRoll` | Present in config but not read by the current controller. |

## Stamina / health → speed

| Key | What it really does |
|---|---|
| `MaxStamina` | Stamina capacity in points. With the same point drain/gain, a larger capacity takes longer to empty or refill. |
| `RunStaminaDrain` / `SprintStaminaDrain` | Stamina points per second while that gait is the **input** gait. |
| `IdleStaminaGain` / `WalkStaminaGain` / `TrotStaminaGain` | Points per second regained. |
| `StaminaPenaltyThreshold` | Fraction of remaining stamina below which the speed calculation changes. Run blends toward `TrotSpeed`; the current Sprint formula adds a bonus based on the Sprint/Run speed ratio while stamina remains above zero. It is not a simple percentage multiplier. |
| `HealthPenaltyThreshold` | Health fraction below which the speed penalty begins; 0.5 means below 50% health. |
| `MaxHealthSpeedPenalty` | Largest fractional speed reduction at zero health; 0.15 means up to 15%. The penalty increases linearly below the health threshold. |

Stamina uses input intent: sprinting through a turn still drains sprint stamina
even when the measured speed and animation gait fall to Trot.

## Visual body movement (optional, currently configured for Wolf)

These settings change bone poses, not root speed or steering limits.

| Key | What it really does |
|---|---|
| `BodyArticulation.SpeedRef` | Name of a speed stat, currently `TrotSpeed`; the body-language effect reaches full strength at that speed. |
| `BodyArticulation.IdleScale` | Fraction of body-language strength remaining at zero speed. |
| `Chains[].Name` / `Bones` | Chain identifier and ordered rig bones to bend. `Follows` refers to `Name`. |
| `Chains[].Weights` | Share of bending on each bone; omitted means equal shares. Values must sum to 1. |
| `Chains[].MaxYaw` | Maximum sideways bend of that chain in degrees. |
| `Chains[].Frequency` | Spring response frequency in Hz. Higher responds faster and generally trails less. |
| `Chains[].Damping` | Spring damping ratio: below 1 permits overshoot, 1 settles without oscillation, above 1 settles more sluggishly. |
| `Chains[].TracksTarget` | Follow the requested heading to anticipate a turn, used by the neck. |
| `Chains[].Follows` | Follow another earlier chain's filtered heading, used by the tail. Mutually exclusive with `TracksTarget`. |
| `Bank.Bone` / `MaxRoll` | Bone to bank and maximum roll in degrees. Target lean depends on speed and physical yaw rate. |
| `Bank.Frequency` / `Damping` | Spring response and settling for the bank, with the same meanings as chain settings. |
| `LegIK.Legs[].Name` / `Upper` / `Mid` / `Foot` | Leg label and hip/shoulder, knee/elbow, and paw bone mappings. Define which joints the ground-contact solver moves. |
| `LegIK.BodyBone` | Whole-body bone the solver can lower to help the paws reach the ground. |
| `HeadLook.Bones` / `Weights` / `Aim` | Neck/head bones, shares of rotation, and the bone marking where the nose points. |
| `HeadLook.CameraTracking` | `true` follows the owner's camera direction and shares it with other players. `false` or omitted restores automatic nearby-creature attention. Enabled for Wolf. |
| `HeadLook.MaxYaw` / `MaxPitch` | Limits on sideways and vertical head aim, in degrees. These are active settings, unlike `MaxTerrainPitch/Roll`. |
| `HeadLook.Response` | How quickly head aim follows its target, per second. |
| `HeadLook.Radius` | Maximum target-search distance, in studs, for automatic attention. Unused in camera tracking mode. |
| `HeadLook.Cone` | Search cone's half-angle from body facing, in degrees, for automatic attention. Unused in camera tracking mode; `MaxYaw`/`MaxPitch` still limit head rotation. |

Optional LegIK overrides, currently omitted from the animal rows:
`AlignFeet` enables paw tilt; `MaxFootTilt` caps it in degrees; `Response`
sets ground-correction smoothing. `MaxLift`, `MaxDrop`, `RayUp`, and `RayDown`
set correction/probe distances as fractions of each leg's length.
`MaxBodyDrop` and procedural `Crouch` use average leg length.
`Step` exposes the retained PawStepper's procedural stepping settings; see
[PawStepper](../src/ReplicatedStorage/Modules/Movement/PawStepper.luau).

`Animations` maps gait/action/turn names to asset IDs. Gait playback scales
with measured speed; turn clips use their row's `SpeedMultiplier` (default `1`).
`AttackDamage`, `StaminaAttackCost`, and `HealthAttackCost` affect combat damage,
not locomotion speed or braking.

## Current values per animal

| | Horsie | MuleDeer | Wolf |
|---|---|---|---|
| Walk / Trot / Run / Sprint | 15 / 28 / 42 / 55 | 7 / 16 / 42 / 73 | 7 / 16 / 42 / 73 |
| Accel / Decel | 25 / 10 | 60 / 60 | 60 / 60 |
| Turn rate Idle·Walk·Trot·Run·Sprint (rad/s) | 4.5 everywhere (Base only) | 10 · 6 · 6 · 4 · 4 | 5 · 2 · 5 · 4 · 4 |
| Brake curve (deg→×) | 5→1, 40→.45, 75→.25, 180→.25 | 5→1, 45→.42, 75→.28, 180→.28 | 10→1, 45→.6, 90→.25, 180→.2 |
| **Nominal full-sprint minimum from turn braking** | 55 × .25 ≈ **13.8** | 73 × .28 ≈ **20.4** | 73 × .20 ≈ **14.6** (≈3.7 while a turn clip plays) |
| TurnInPlace | — | — | MinAngle 90; Brake 0.05 (≈3.7 at sprint); SpeedMultiplier 1 for 90° and 1.3 for 180° |
| Body lean | whole-body tilt 20° | whole-body tilt 30° | chest bank 18° (BodyArticulation) |

## Quick knobs for common feel problems

| Want | Turn |
|---|---|
| Lower speed floor in hard reversals | last 1–2 `Brake` values in `TurnBrakeCurve` |
| Brake later / only on really sharp turns | move the middle curve points to higher `Angle` |
| Tighter turning circle at speed | raise the relevant visual gait's turn rate; matters only when that cap is limiting rotation |
| Turn clip only on true reversals | raise `TurnInPlace.MinAngle` |
| Faster / slower turn animation and rotation together | `TurnInPlace.Turns[].SpeedMultiplier` on the desired 90° or 180° row |
| Less sliding during turn clips | lower `TurnInPlace.Brake` |
| Snappier / softer braking into a turn | `TURN_BRAKE_RESPONSE` (code constant, not per animal) |
| Faster / slower recovery after a turn | `Acceleration` (also changes acceleration from rest) |

These are tuning relationships, not tested replacement values. Lowering
`SprintSpeed` also changes straight-line running. Changing `Deceleration`
changes stopping and gait downshifts, but does not change how the turn brake
eases. Those broader changes can alter feel without addressing the animation
mismatch directly.
