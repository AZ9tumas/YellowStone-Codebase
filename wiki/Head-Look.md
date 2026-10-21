# Head Look (attention)

The creature turns its head toward whatever is worth looking at — the nearest
other creature — while the gait animation keeps playing underneath, and
relaxes back onto the animated pose when there is nothing around.

This is inverse kinematics in the same sense [Leg IK](Leg-IK.md) is: a
world-space point goes in, the joint angles that aim at it come out.

| Module | Path |
|---|---|
| `HeadLook` | `src/ReplicatedStorage/Modules/Movement/HeadLook.luau` |
| `CreatureStats[..].HeadLook` | Per-creature config. Absent = feature off |

---

## 1. It composes with the neck, it does not replace it

[Body Articulation](Body-Articulation.md)'s `Neck` chain leads into a **turn**
— where the creature is steering. `HeadLook` aims at a **thing**. They are
different behaviours and both are bounded, so they simply add: both write the
neck through the shared [BoneWriter](Bone-Writing.md), and the tuned `Neck`
chain keeps `Neck.001` and `Neck.002` exactly as it had them.

## 2. Sign safety

The only rotation this layer performs is *"swing direction A onto direction B
about A × B"* — the same primitive Leg IK's hip uses, and the one behaviour
measured directly on the rig. Nothing here assumes which local axis of a bone
points forward, so there are no per-rig axis constants.

* The **aim direction** is read from the pivot bone to an `Aim` bone further
  down the skull (the wolf uses `Nose`). Whatever the rig's bone axes are, the
  line between two joints is unambiguous.
* The **target direction** is clamped inside the yaw/pitch cone by
  *rebuilding* it from the body basis (`forward`, `right`, `up`), not by
  rotating — so the clamp cannot flip a sign either.

Splitting the swing across several bones by weight is **exact for the
direction**: rotations about a common axis add, so 0.4 on the neck plus 0.6 on
the head aims exactly where 1.0 on the head would, spread over a nicer curve.
It does move the head's origin slightly, so a very close target is aimed at a
little loosely — irrelevant at the ranges this runs at.

## 3. Target selection needs no replication

`Bone.Transform` does not replicate, so every client runs this for every
creature it can see. Target selection is therefore derived only from state all
clients already share — who is standing where — so **everyone sees the same
creature look at the same thing**, with zero network traffic and no
client-authority question.

`HeadLook.FindTarget` picks the nearest other player's creature inside
`Radius` and inside the `Cone` half-angle, refreshed 4×/second; the aim itself
slews every frame. A caller may pass `Signals.Target` to override this with an
explicit world point (prey, a scripted beat) — the self-acquire only runs when
that is absent.

Losing a target does not snap: `strength` eases to 0 and the head relaxes back
onto whatever the animation is doing.

## 4. Configuration

```lua
["HeadLook"] = {
    ["Bones"] = { "Neck.002", "Head" },
    ["Weights"] = { 0.4, 0.6 },   -- head carries more than the neck
    ["Aim"] = "Nose",             -- marks "forward" without assuming a bone axis
    ["MaxYaw"] = 55,              -- deg off the body's facing
    ["MaxPitch"] = 35,
    ["Response"] = 6,             -- 1/s, aim slew rate
    ["Radius"] = 60,              -- studs
    ["Cone"] = 120,               -- deg half-angle
},
```

`Bones` is the chain that shares the swing, neck → head. `Aim` is only ever
**read**, never written, so it may well be a bone another layer owns.

## 5. Measured behaviour

Driven with explicit targets on an isolated rig:

| Asked | Result |
|---|---|
| yaw +40°, pitch +20° | yaw +40.0°, pitch +20.0° |
| yaw −40°, pitch −15° | yaw −40.2°, pitch −14.8° |
| yaw +100°, pitch +60° (outside the cone) | clamped to exactly +55° / +35° |
| suppressed | returns to the rest aim to 0.01°, bit-for-bit |

## 6. Traps

| Trap | Guard |
|---|---|
| Assuming a bone's local axis is "forward" | Aim is a line between two joints; only swing-onto rotations are used |
| Double-counting the neck's turn lead | Different behaviours, both clamped; they are meant to add |
| Head snapping when a target appears or leaves | `strength` eases in/out; the aim direction is seeded on first sighting |
| Per-client disagreement about what a creature is looking at | Target derived only from shared positions, never from local input |
