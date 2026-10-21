# Bone Writing (the shared writer)

Three layers now write bones on the same creature every frame —
[Body Articulation](Body-Articulation.md), [Leg IK](Leg-IK.md) and
[Head Look](Head-Look.md). `BoneWriter` is the single piece of bookkeeping
they share, and it exists for two reasons that are easy to get wrong
independently.

| Module | Path |
|---|---|
| `BoneWriter` | `src/ReplicatedStorage/Modules/Movement/BoneWriter.luau` |

---

## 1. Why offsets cannot be composed blindly

`Bone.Transform` is written in `RunService.PreSimulation` — after the
`Animator` has written this frame's animation pose — and is **composed on top
of it**. The trap is that the Animator only rewrites `Transform` on bones the
playing clip actually keyframes, and skips distant rigs entirely when it
throttles. On the wolf, Idle keyframes `Back.002` but **not** `Back.001`.

So `bone.Transform *= offset` compounds forever on exactly those bones.

The writer instead remembers, per bone, both the value it last wrote and the
animation pose it built that value on. On the first touch of a frame:

* if the bone still holds our remembered value, the Animator did not touch it,
  and the remembered base is reused **verbatim**;
* otherwise what is there now *is* the new animation pose.

There is no per-frame inverse, so there is nothing to accumulate error. This
is also why nothing needs to special-case `Animator.EvaluationThrottled`.

Verified: `Release()` restores every bone to a `0.000e+00` residual.

## 2. Why one writer per character, not per layer

More than one layer legitimately wants the same bone. The neck both **leads
into a turn** (Body Articulation) and **aims at something** (Head Look). With
a writer each, the second layer would read the first one's write as the
animation pose and strip it.

With one writer the offsets simply compose in call order onto a single
remembered base. That is what makes the layers additive rather than
competing, and it is why `HeadLook` can share `Neck.002` with the tuned
`Neck` chain instead of having to carve bones away from it.

Within a single layer, sharing is still a bug — two chains on one bone would
fight — so `BoneWriter.Claimer` enforces one owner *per layer* and fails loud
on a bone that is missing, ambiguous, or claimed twice.

## 3. The frame

```lua
writer:BeginFrame()
articulation:Update(signals, dt)   -- spine, neck, tail, bank
legIK:Update(signals, dt)          -- then the legs correct the pose it made
headLook:Update(signals, dt)       -- then the head aims
writer:EndFrame()
```

* `Prepare(bone)` tracks the bone for this frame and returns its animation
  base. First touch strips it back to that base; a later touch by another
  layer leaves the offsets already added, so that layer reads — and composes
  onto — the pose so far.
* `Add(bone, offset)` composes an offset and writes it out **immediately**,
  not at `EndFrame`. This matters: layers convert a world axis into a bone's
  local frame via `TransformedWorldCFrame`, so a child must see its parent's
  new pose, and `LegIK` re-reads a joint between its own two rotations.
* `EndFrame()` hands back every bone no layer touched this frame. A layer that
  eases out therefore needs no release bookkeeping of its own — it just stops
  writing.
* `Release()` (also `Destroy`) takes everything off. The **driver** owns the
  writer's lifetime; the layers do not have teardown.

## 4. Ordering

Order is not arbitrary:

1. **Body Articulation** first. It bends `Back.001` → `Lowe Back`, which are
   the hind legs' ancestors, so the legs must see the bent pose.
2. **Leg IK** second, correcting the pose that produced.
3. **Head Look** last, aiming on top of the neck's turn lead.

Both drivers ([`MovementController`](Code-Tour.md) for the local creature,
`ArticulationController` for everyone else's) run exactly this order.

## 5. Rig lookup lives here too

`BoneWriter.Index`, `BoneWriter.Missing` and `BoneWriter.Claimer` are the one
implementation of "find configured bones on a rig", used by all three layers
and by both drivers to wait out a rig that is still replicating. See
[Known Issues](Known-Issues.md) for why that wait exists (atomic model
streaming can deliver the rig after the spawn signal).
