# Swimming

> Surface swimming in Terrain water. Code: `Movement/Swimming.luau` (shared
> rules), `MovementService` (speed + stamina), `MovementController` (float +
> animation), `SpawnService` (the `SwimLift` constraint). Currently enabled
> for the wolf only.

## How it works

1. **Probe.** A ray from above the root finds the Terrain water surface, a
   second ray (ignoring water) finds the bed. The probe sees only Terrain, so
   trees, bridges and other creatures can't hide the water.
2. **Decide.** With `h` = standing root height (`HipHeight + root.Size.Y / 2`,
   read off the rig), the creature swims once the water is at least
   `h × (1 + FloatDepth)` deep and its root is no more than `h / 2` above the
   surface. It wades out again below 85% of that depth, so shorelines don't flicker.
3. **Server.** `MovementService` runs the same probe and maps the reported land
   intent onto the swim ladder: Idle → `SwimIdle`, Walk/Trot → `Swim`,
   Run/Sprint → `SwimFast`. Speed, drain and gain then come from the usual
   `<Gait>Speed` / `<Gait>StaminaDrain` / `<Gait>StaminaGain` rows. Clients
   can never report a swim gait themselves. The verdict is published as the
   character's `Swimming` attribute.
4. **Client.** `MovementController` runs its own probe so it reacts on the
   same frame. It enables `SwimLift` (a Y-only `LinearVelocity`), which eases
   the root to `FloatDepth × h` below the surface, picks the visual gait from
   the swim ladder, and turns off LegIK paw planting and the turn clips. The
   Humanoid's built-in Swimming state is disabled so it can't fight the lift.
   Other clients read the `Swimming` attribute to release that creature's paws.
5. **Restrictions.** Eat and Drink are blocked from the swim gaits, and Rest
   can't be entered while swimming.

## Config (per creature)

| Key | Meaning |
|---|---|
| `Swimming.FloatDepth` | Fraction of standing root height the root sits under the surface while floating. Also sets how deep water must be before swimming starts. |
| `Swimming.Buoyancy` | How fast (1/s) the body settles to that height. Higher feels stiffer. |
| `SwimIdleSpeed` / `SwimSpeed` / `SwimFastSpeed` | Server target speeds. `SwimSpeed` also sets the visual Swim/SwimFast band (same ±12% / 6% margins as land gaits). |
| `SwimIdleTurnRate` / `SwimTurnRate` / `SwimFastTurnRate` | Turn caps (rad/s) per swim gait. |
| `SwimStaminaDrain` / `SwimFastStaminaDrain` | Points/s drained. Below `StaminaPenaltyThreshold` a fast swim slows toward `SwimSpeed`; the slow swim is never penalised, so nobody drowns. |
| `SwimIdleStaminaGain` | Points/s regained while treading water. |
| `Animations.SwimIdle` / `Swim` / `SwimFast` | Clips. The wolf currently reuses its Idle / Walk / Trot clips as placeholders. |

A creature without a `Swimming` block never swims; land movement is unchanged.

## Adding swimming to another creature

Copy the wolf's `Swimming` block and its `Swim*` speed, turn-rate, stamina
and animation rows. `tests/movement-regressions.luau` fails if any of them is
missing.
