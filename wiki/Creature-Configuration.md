# Creature Configuration

> **Reference for every key in `CreatureStats`, plus a tuning guide.**
> New to the codebase? Start with [Getting Started](Getting-Started.md) and the
> [Code Tour](Code-Tour.md); this page assumes the vocabulary in the
> [Glossary](Glossary.md).

All per-species tuning lives in one table:
`src/ReplicatedStorage/Modules/Stats/CreatureStats.luau`, keyed as
`CreatureStats[CharacterName][Gender]`. `Common.GetPlayerInfo(player)` is the
canonical accessor — it **asserts** on any missing attribute or row (the
project's loud-failure rule: a player without stats is a bug to surface, not
to default around). Gate pre-spawn code with `Common.IsSpawned(player)`.

## Reference

### Speeds (studs/s)

| Key | Meaning |
|---|---|
| `IdleSpeed` | Always 0; target while idle |
| `WalkSpeed` | Walk target **and** the Walk/Trot visual band boundary |
| `TrotSpeed` | Trot target and the Trot/Run boundary |
| `RunSpeed` | Run target and the Run/Sprint boundary |
| `SprintSpeed` | Sprint target |

The same numbers serve as server ramp targets and as the gait-band thresholds
(with the $\pm 12\%$ hysteresis described in
[Gait Resolution](Gait-Resolution.md)), so animation bands always match the
speeds the server actually drives.

### Acceleration

| Key | Meaning |
|---|---|
| `Acceleration` | WalkSpeed ramp-up rate (studs/s²) |
| `Deceleration` | WalkSpeed ramp-down rate (studs/s²) |

### Turning

| Key | Meaning |
|---|---|
| `BaseTurnRate` | Guaranteed max turn rate (rad/s); fallback for gaits without their own |
| `IdleTurnRate` … `SprintTurnRate`, `SwimmingTurnRate` | Optional per-gait overrides — looked up as `info[gait .. "TurnRate"]` |
| `TurnBrakeCurve` | **Required.** Demanded-angle → speed-multiplier control points |

#### `TurnBrakeCurve`

An ordered array of `{ Angle = deg, Brake = 0..1 }`, linearly interpolated
(see [Turning and the Turn Brake](Turning-and-the-Turn-Brake.md) for the
formula and the shipped curves). Rules, enforced by assertion:

* at least two control points;
* angles strictly increasing;
* start the curve with points at `Brake = 1` up to ~5–10° — that is the free
  zone that keeps camera micro-corrections from bleeding speed;
* end the curve at `Angle = 180` so the tail is explicit.

Shaping guide:

* **Planter** (agile predator): deepen the mid and tail of the curve so sharp
  turns cost most of the speed (Wolf: 0.25 at 90°, 0.20 at 180°).
* **Momentum keeper** (heavy or fleet species): keep the tail higher (Horse:
  0.25) — the creature always carries more speed through a turn.

Never bottom a curve out at exactly `0`: that stops the creature dead and lets
it pivot on the spot with no forward motion.

### Tilt (banking)

| Key | Meaning |
|---|---|
| `MaxTiltAngle` | Roll clamp (deg) |
| `TiltSensitivity` | Roll per yaw-rate gain |
| `TiltSpeed` | Easing rate (s⁻¹) |

Ignored for a creature whose `BodyArticulation` block has a `Bank` entry — the
lean is then applied on the chest bone instead (see below).

### Body articulation

| Key | Meaning |
|---|---|
| `BodyArticulation` | **Optional.** Procedural spine bend / neck lead / tail whip / chest bank during turns. Absent = off |
| `LegIK` | **Optional.** Terrain foot planting. Absent = off. Four bone triples and a body bone; every distance is a fraction of leg length, so there are no stud values to retune per creature (see [Leg IK](Leg-IK.md)) |
| `HeadLook` | **Optional.** Head aims at the nearest creature. Absent = off (see [Head Look](Head-Look.md)) |

The block is documented key-by-key, with a tuning table, in
[Body Articulation](Body-Articulation.md). Bone names and weights are asserted
at spawn, so a typo fails loud rather than silently disabling a chain.

### Terrain alignment

| Key | Meaning |
|---|---|
| `TerrainAlignmentEnabled` | Master switch |
| `TerrainAlignmentSpeed` | Normal easing rate (s⁻¹) |
| `MaxTerrainAngle` | Cap on body tilt from terrain (deg) |
| `MaxClimbAngle` | Forward slope that blocks movement (deg) |
| `TerrainRaycastDistance` | Ground-probe depth (studs) |
| `MaxTerrainPitch`, `MaxTerrainRoll` | Reserved (not currently read by the pipeline) |

### Stamina and health

| Key | Meaning |
|---|---|
| `MaxStamina` | Stamina points (stamina is stored normalized 0–1) |
| `RunStaminaDrain`, `SprintStaminaDrain` | Points/s drained by those gaits |
| `IdleStaminaGain`, `WalkStaminaGain`, `TrotStaminaGain` | Points/s recovered |
| `StaminaPenaltyThreshold` | Normalized stamina below which speed degrades toward Trot |
| `HealthPenaltyThreshold` | Health fraction below which speed degrades |
| `MaxHealthSpeedPenalty` | Max fractional speed loss at zero health |

Every gait must have **either** a `<Gait>StaminaDrain` **or** a
`<Gait>StaminaGain` — the server asserts if both are missing.

### Combat

| Key | Meaning |
|---|---|
| `AttackDamage` | Base damage |
| `StaminaAttackCost`, `HealthAttackCost` | Fractional damage penalties when low (see `StaminaMath.GetAttackDamage`) |

### Animations

`Animations` maps **state name → asset id**. `SpawnService` turns it into the
player's `Animations` folder; the `AnimationController` resolves tracks by
state name from there. The five gaits are required; action/rest tracks are
optional until those features are given animations. Extra entries are
harmless — they are preloaded and simply never played (the Wolf's
`Turn90Left/Right` and `Turn180Left/Right` ids are parked there for future
use).

> Animation assets must be **shared with the experience** (or owned by it) or
> they will fail to load at runtime with a permission error. Tracks that fail
> to load simply never play; the movement system itself keeps working.

## Checklist: adding a new creature

1. Add the model under `ServerStorage/Models/<Gender>/<CharacterName>`.
2. Add the `CreatureStats[CharacterName][Gender]` row — every key above
   except the optional ones. Missing required keys fail loudly at first use,
   by design.
3. Author the five gait animations on the creature's rig.
4. Shape `TurnBrakeCurve` for the species' mass/agility.
5. Verify in Studio: watch the debug HUD (`Break`, `Angle`, `State`,
   `TurnRate`) while driving the creature over slopes and through reversals.

## Tuning cheat-sheet

| Symptom | Knob |
|---|---|
| Animation flickers between two gaits while cruising | The two adjacent speed configs are too close together; or raise the hysteresis fraction in `MovementMath` |
| Creature feels like it ice-skates through turns | Deepen the mid-range of `TurnBrakeCurve` |
| Speed bleeds while running straight | Widen the curve's free zone (first points at `Brake = 1`) |
| Body lags terrain changes | Raise `TerrainAlignmentSpeed` |
| Body jitters on rough terrain | Lower `TerrainAlignmentSpeed` or raise `TerrainRaycastDistance` |
| Sluggish launch / harsh stops | `Acceleration` / `Deceleration` |
