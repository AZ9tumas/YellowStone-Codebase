# Creature Configuration

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
| `TurnInPlace` | **Optional.** Enables turn-in-place; requires the four turn animations |

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

* **Full planting stop** (predator, Isle-style): bring the curve to `Brake = 0`
  at the angle where the creature should refuse to slide (Wolf: 120°). Pair
  with a `TurnInPlace` block so the stop resolves into a turn animation.
* **Momentum keeper** (heavy or fleet species): bottom the curve out above
  zero (Horse: 0.25) — the creature always carries some speed through a turn.

#### `TurnInPlace`

```lua
["TurnInPlace"] = {
    ["MaxSpeed"]  = 2.5, -- studs/s: at/below this the turn happens in place
    ["MinAngle"]  = 55,  -- deg gap that triggers a turn
    ["Angle180"]  = 120, -- deg gap at/above which the 180 animation is used
    ["ExitAngle"] = 12,  -- deg gap that ends the turn
},
```

Omit the whole block for creatures without turn animations — the feature is
then disabled for that species (this is a feature flag, not a data fallback).

### Tilt (banking)

| Key | Meaning |
|---|---|
| `MaxTiltAngle` | Roll clamp (deg) |
| `TiltSensitivity` | Roll per yaw-rate gain |
| `TiltSpeed` | Easing rate (s⁻¹) |

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
state name from there. The five gaits are required; `Turn90Left/Right` and
`Turn180Left/Right` are required iff `TurnInPlace` is configured; action/rest
tracks are optional until those features are given animations.

> Animation assets must be **shared with the experience** (or owned by it) or
> they will fail to load at runtime with a permission error. The movement
> system degrades gracefully (see
> [Turn In Place — Hardening](Turn-In-Place.md#hardening-against-brokenslow-assets)),
> but the animations simply won't show until permissions are granted.

## Checklist: adding a new creature

1. Add the model under `ServerStorage/Models/<Gender>/<CharacterName>`.
2. Add the `CreatureStats[CharacterName][Gender]` row — every key above
   except the optional ones. Missing required keys fail loudly at first use,
   by design.
3. Author the five gait animations on the creature's rig; add turn one-shots
   if it should turn in place, plus a `TurnInPlace` block.
4. Shape `TurnBrakeCurve` for the species' mass/agility.
5. Verify in Studio: watch the debug HUD (`Break`, `Angle`, `State`,
   `TurnRate`) while driving the creature over slopes and through reversals.

## Tuning cheat-sheet

| Symptom | Knob |
|---|---|
| Animation flickers between two gaits while cruising | The two adjacent speed configs are too close together; or raise the hysteresis fraction in `MovementMath` |
| Creature feels like it ice-skates through turns | Deepen the mid-range of `TurnBrakeCurve` |
| Speed bleeds while running straight | Widen the curve's free zone (first points at `Brake = 1`) |
| Turn-in-place triggers while jogging | Lower `TurnInPlace.MaxSpeed` |
| 180 animation used for gentle corners | Raise `TurnInPlace.Angle180` |
| Body lags terrain changes | Raise `TerrainAlignmentSpeed` |
| Body jitters on rough terrain | Lower `TerrainAlignmentSpeed` or raise `TerrainRaycastDistance` |
| Sluggish launch / harsh stops | `Acceleration` / `Deceleration` |
