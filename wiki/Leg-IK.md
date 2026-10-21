# Leg IK (terrain foot planting)

The gait animation decides **when** and **where** a paw swings. `LegIK` only
corrects the height and tilt it **lands at**, so paws meet a slope, a rock or
a step instead of floating above it or sinking through it.

This is the genuine inverse-kinematics half of the movement stack:
[Body Articulation](Body-Articulation.md) bends the spine by *forward*
kinematics (angles in, pose out), while here a world-space contact point
comes in and the joint angles that reach it come out.

| Module | Path |
|---|---|
| `LegIK` | `src/ReplicatedStorage/Modules/Movement/LegIK.luau` |
| `CreatureStats[..].LegIK` | Per-creature config. Absent = feature off |

---

## 1. The frame

1. **Strip** last frame's solve, so the probe sees the pose the animation and
   Body Articulation just produced rather than our own output.
2. **Probe.** Raycast down from each paw. The correction is how far the ground
   sits from where the animation put the paw, plus that paw's rest clearance,
   clamped and smoothed so an edge or a gap cannot pop it.
3. **Drop the body** by the deepest correction, so an over-reaching leg can
   touch down instead of stretching straight. This runs before the legs — the
   body bone is their common ancestor.
4. **Solve** each leg onto its contact point.
5. **Tilt** the paw onto the ground normal.

A foot with nothing under it relaxes to the animated pose, so a creature in
the air needs no separate "airborne" signal — it falls out for free.

## 2. The solve

Two rotations per leg, no iteration:

* **Knee** — change *only* the interior angle at the knee, about the limb's
  own plane normal (`(hip−knee) × (paw−knee)`). Law of cosines gives the angle
  that makes the hip→paw span match the distance to the target.
* **Hip** — the limb now spans exactly the right distance, so one rotation
  about `(paw−hip) × (target−hip)` lands the paw exactly on the target.

Two properties fall out of this that are worth stating plainly.

**There is no pole vector.** Bending about the limb's *existing* plane means
the plane the animation put the leg in acts as the pole. There is nothing to
configure, nothing to get wrong, and the knee can never flip to the other side
mid-stride. This is the main reason not to route this through `IKControl`,
whose `Pole` is unreliable on multi-segment chains.

**The end effector is the paw, not the ankle.** Only the hip and knee are ever
rotated, so everything below the knee — the ankle joint included — is rigid
within the frame, and the law of cosines on hip→knee→paw lands the paw
exactly. Aiming the *ankle* instead and shifting the target by the ankle-to-paw
gap treats a rotation as a translation and misses by (paw lever) × (swing
angle). Measured on the wolf: **0.002 studs** on the short front pastern but
**0.2** on the long hock. Re-solving to chase that error *diverges* the moment
the limb has to straighten, because the leftover delta never shrinks and each
pass swings the straight limb further past the ground — over a stud of error.
Solving for the paw has neither problem and needs no iteration.

Out of reach simply saturates: the limb straightens and points at the target,
which is the right visual degradation for a step too tall.

## 3. Nothing to tune

Every distance is authored as a **fraction of that leg's own rest length**,
measured at construction, and each paw's ground clearance is read off the rest
rig (the drop from the paw bone to the deepest bone under it — the toes).
A creature of any size therefore needs no numeric tuning at all. The wolf's
whole config is four bone triples and one body bone:

```lua
["LegIK"] = {
    ["Legs"] = {
        { ["Name"] = "FrontLeft",  ["Upper"] = "Shoulder.L", ["Mid"] = "Forearm.L", ["Foot"] = "Front Paw.L" },
        { ["Name"] = "FrontRight", ["Upper"] = "Shoulder.R", ["Mid"] = "Forearm.R", ["Foot"] = "Front Paw.R" },
        { ["Name"] = "BackLeft",   ["Upper"] = "Thigh.L",    ["Mid"] = "Leg.L",     ["Foot"] = "Back Paw.L" },
        { ["Name"] = "BackRight",  ["Upper"] = "Thigh.R",    ["Mid"] = "Leg.R",     ["Foot"] = "Back Paw.R" },
    },
    ["BodyBone"] = "Body IK CTRL",
},
```

`Upper` swings the limb, `Mid` is the joint whose angle changes, `Foot` is the
end effector, the contact reference and what gets tilted. `BodyBone` must be
an ancestor of all the legs; omit it to disable the body drop.

Optional overrides, all fractions of leg length unless noted:

| Key | Default | Meaning |
|---|---|---|
| `MaxLift` / `MaxDrop` | `0.45` | Cap on a foot's correction |
| `RayUp` / `RayDown` | `0.6` / `1.2` | Probe extent above/below the paw |
| `MaxBodyDrop` | `0.25` | Cap on the body drop (of mean leg length) |
| `Response` | `14` (1/s) | Smoothing of each foot's correction |
| `AlignFeet` | `true` | Roll the paw onto the ground normal |
| `MaxFootTilt` | `35` (deg) | Cap on that roll |

## 4. Measured behaviour

Residual = studs the paw is still off its contact point after the solve
(0 = planted). Body held level, ground tilted underneath — the hard case,
since in game [terrain alignment](Terrain-Alignment.md) also tilts the body
and the legs then absorb roughly half as much.

| Ground | Height spread under the four paws | Worst residual |
|---|---|---|
| Flat | 0.00 studs | **0.016** |
| Pitch 18° | 1.07 studs | **0.016** |
| Pitch 30° | 1.81 studs | 0.309 |
| Compound 25° / 18° | 1.66 studs | 0.198 |

Exact to ~0.016 studs while the correction is inside `MaxLift`/`MaxDrop`;
beyond that it degrades gracefully at exactly the configured clamps rather
than tearing the leg.

## 5. Traps

| Trap | Guard |
|---|---|
| Probing our own output instead of the animation pose | Every owned bone is `Prepare`d before the probe pass |
| Body drop double-counting the leg correction | The contact point is recorded as an **absolute world point** before the drop; the solve re-reads the paw after it, so the drop cancels itself |
| Rig stored on its side measuring clearance along the wrong axis | Rest-up comes from `HumanoidRootPart`, then `PrimaryPart`, then the model pivot — never world up |
| Raycast hitting the creature itself | `RaycastParams` excludes the character's descendants |
| Limb dead straight, so the bend plane is undefined | Falls back to the sagittal axis `(knee−hip) × up` |

See also [Bone Writing](Bone-Writing.md) for why this layer must run *after*
Body Articulation and how it shares bones safely.
