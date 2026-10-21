# Known Issues and Gotchas

Things that will confuse you, with the explanation up front so they don't cost
you an afternoon.

---

## The root `README.md` is obsolete

It documents a movement model **that no longer exists**: speed-dependent turn
rates $\omega_{max} = \omega_{base}/(1 + v \cdot k_{decay})$, a
`TurnBrakeSensitivity` scalar, server-side inverse speed validation, and tilt
applied through a Motor6D.

None of that is in the code. Turning is now capped per gait and unaffected by
speed, braking uses a per-creature `TurnBrakeCurve`, the server ramps
`WalkSpeed` toward reported intent (it does not derive a speed limit from
observed angular velocity), and tilt goes through the `AlignOrientation`.

**This wiki is the source of truth.** The README should be replaced with a short
pointer here.

---

## Creature collision (fixed)

**Was:** the rigs ship from Blender with **zero collidable parts** — every part,
*including the `HumanoidRootPart`*, `CanCollide = false` — and with the mass on
the cosmetic meshes while the root is `Massless = true`. The creature therefore
had no collision geometry at all.

Standing still looked fine, because the Humanoid's own floor probe holds the
creature at `HipHeight` above the ground. But that probe is a *sensor*, not a
*support*, and it does nothing horizontally. Measured:

```
60 studs/s at a solid 4-stud wall, CanCollide = false -> passed straight through
60 studs/s at a solid 4-stud wall, CanCollide = true  -> stopped at the wall
```

**Fix:** `SpawnService.applyPhysicsContract`, applied to every creature before
the model is parented, so it holds for every species and gender and cannot be
lost when a rig is re-exported:

* `HumanoidRootPart` — `CanCollide = true`, `Massless = false`. It is the
  physics body.
* everything else — `CanCollide = false`, `Massless = true`. Decoration.

Only the root collides, on purpose. The visible wolf is ~7 studs long; giving
the meshes collision would snag it on every slope and doorway. The root is
**not** resized either: the Humanoid holds the root's *bottom* at `HipHeight`
above the floor, so changing size or `HipHeight` would move the whole body and
silently re-tune [Leg IK](Leg-IK.md). Verified unchanged: stance sits at 3.180
studs above the surface with collision on or off, and paw planting stays within
0.0035 studs.

The consequence to know about is that the collider is the root only, so the
head and tail can still overlap thin geometry visually.

---

## A creature below the surface cannot climb back out

This is **not** fixed by collision, and it is worth understanding before
reaching for one.

Roblox does not eject a body that is already *inside* terrain. Verified with a
plain collidable 1x1x2 part, which behaves exactly like a creature:

```
plain collidable part placed 1 stud inside terrain -> sank to Y = -446
```

So once the root is under the surface the Humanoid probe finds nothing beneath
it, collision does not push it out, and it accelerates to
`FallenPartsDestroyHeight` (-500) and the character is destroyed. That state is
reachable in normal play — a fast descent, or (with `StreamingEnabled`) a
creature outrunning the terrain streaming in beneath it.

> An earlier revision of this page claimed `HRP CanCollide = true` recovered
> from being placed one stud under. That does not reproduce; the part test
> above shows why it cannot.

**Mitigation:** `SpawnService.startFallGuard` remembers the last pose where the
creature was genuinely standing — ground within 6 studs *and* vertical speed
under 5 studs/s — and restores it if the root ever drops within 50 studs of
`FallenPartsDestroyHeight`. Both conditions matter: sampling on the ground
probe alone lets a creature record a "safe" spot mid-fall and be rescued
straight back into the ground it was falling through, which is what the first
version did.

The trigger sits far below any reachable ground, so a legitimate fall down a
cliff is never interrupted. Measured: 3/3 recoveries from being sunk 2 and 6
studs under the terrain, each returning to the exact standing pose.

Still worth fixing at the source:

* **`Workspace.StreamingEnabled = true`.** A fast creature can outrun terrain
  streaming; an unstreamed chunk means no probe hit *and* no collision. The
  guard catches the fall, but the creature still takes the trip.
* **`Workspace.Base`** (the spawn marker) is a 4x1x2 `CanCollide = false` part
  at `y = -1.5`, sitting a full stud proud of the terrain at `y = -2`. Every
  creature therefore spawns straddling a 1-stud lip: the front paws plant on
  the marker and the hind paws on the terrain below it, which is more than
  Leg IK's per-foot clamp can span. Sinking it flush with the terrain, or
  making it non-queryable, would fix the spawn stance.

---

## Rojo overwrites your Studio edits

`rojo serve` syncs **one way: files → Studio.** Anything you type into a script
inside Studio is discarded the next time Rojo pushes that file. Edit the `.luau`
files.

## Deleting a file doesn't delete the script

Every branch in `default.project.json` sets `$ignoreUnknownInstances`. That
keeps Rojo from nuking instances it doesn't manage — but it also means removing
a `.luau` file leaves the corresponding script alive in the `.rbxl`, still
running. **Delete it by hand in Studio and re-save the place.**

If you removed a module and its old behaviour persists, this is why.

---

## `Bighorn` exists as a model but cannot be spawned

`ServerStorage.Models.Female.Bighorn` has no row in `CreatureStats`, so
`SpawnService:Morph` rejects it with `"No such character"`. There is also no menu
button for it. Either finish it (stats row + animations + button) or remove the
model — right now it's a trap for anyone reading the models folder and assuming
it works.

---

## Animation assets need experience permissions

An animation id that isn't shared with the experience fails to load at runtime
with `The experience doesn't have access permission to use asset id …`. The
track then silently never plays, which reads as "my animation code is broken"
when it isn't.

Fix in Creations → the asset → Permissions, or publish the asset under the
experience owner.

---

## Legacy scripts outside the Knit structure

Not everything has been ported. These still run as standalone scripts and don't
follow the service/controller pattern:

* `ServerScriptService/DayNightHandler.server.luau`
* `ServerScriptService/FoodSourceControl/`, `FootstepSFXServer/`
* `ServerScriptService/HealthModifier.server.luau`
* `ServerScriptService/WaterPart *.server.luau`
* `StarterPlayerScripts/mechanics/`

They produce most of the harmless console noise listed in
[Debugging and Testing](Debugging-and-Testing.md#reading-the-console). Treat
them as legacy; new work belongs in `Services/` or `Controllers/`.

---

## Turn overlays are interruptible

Wolf uses its authored 90 and 180 turn clips again. `TurnInPlace` follows live
input and never locks velocity or forces Idle; it only caps speed to
`TurnInPlace.Brake` while a clip plays, so the planted paws don't slide. Releasing input cancels the
turn; sustained sharp steering loops it. See
[Turning and the Turn Brake](Turning-and-the-Turn-Brake.md).

The procedural `PawStepper` implementation is retained but is not selected
for the wolf's 180 turns. It can be selected with a `Duration` turn config.
