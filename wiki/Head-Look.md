# Head Look (camera tracking and attention)

With `CameraTracking = true`, the creature's neck and head follow its owner's
camera direction, including left/right yaw and up/down pitch. Wolf enables
this mode. Camera zoom does not affect the aim: the input is the camera's
look direction, not its position or distance from the creature.

With `CameraTracking = false` or omitted, the previous automatic attention
mode remains available: look at the nearest other creature and relax back
onto the animated pose when none is nearby.

This is inverse kinematics in the same sense [Leg IK](Leg-IK.md) is: a
world-space direction or point goes in, the joint angles that aim at it come out.

| Module | Path |
|---|---|
| `HeadLook` | `src/ReplicatedStorage/Modules/Movement/HeadLook.luau` |
| `HeadLookService` | `src/ServerScriptService/Services/HeadLookService.luau` — validates and shares camera look direction |
| `CreatureStats[..].HeadLook` | Per-creature config. Absent = feature off |

---

## 1. It composes with the neck, it does not replace it

[Body Articulation](Body-Articulation.md)'s `Neck` chain leads into a **turn**
— where the creature is steering. `HeadLook` then corrects that pose toward
the camera direction or attention target. Both write through the shared
[BoneWriter](Bone-Writing.md); the body, gait, movement direction and turn
timing remain controlled by their existing systems.

Camera aiming works while stationary and moving. It respects `MaxYaw` and
`MaxPitch`, slews at `Response`, and fades out during movement-freezing
actions, death, or when no camera direction is available. The smoothed aim
is re-clamped against the current body orientation so a sharp body turn
cannot leave the head pointing beyond its limits.

The camera owns the final skull orientation, including roll. The neck still
leads into movement, but its turn pose cannot tilt the final camera aim.
As the body catches up to the camera heading, the head's angle relative to
the body naturally decreases; that is expected, not tracking switching off.

## 2. Neutral-pose calibration

Camera mode derives a look frame from the head's **unanimated bind pose**
relative to `HumanoidRootPart`. A level camera facing forward therefore
preserves the rig's natural skull angle, without assuming a local bone axis
points forward. `WorldCFrame` excludes bone animation transforms, so starting
the solver during an animation does not bake that animation into calibration.

The wolf's head-to-nose line slopes down about **31°** in its bind pose.
Treating that line as its gaze direction used to lift the muzzle even with
a level camera. Camera mode now uses the calibrated frame, correcting both
forward and up after the turn layer. This also prevents sideways roll that
a direction-only correction leaves unconstrained.

Automatic attention retains its original behavior: swing the line from the
head joint to `Aim` toward the target. Both modes clamp the desired direction
against the body basis and share the resulting world-axis rotation across
the configured neck/head bones.

Splitting the correction by weight is **exact for the orientation**:
rotations about a common axis add, so 0.4 on the neck plus 0.6 on
the head aims exactly where 1.0 on the head would, spread over a nicer curve.
It does move the head's origin slightly, so a very close target is aimed at a
little loosely — irrelevant at the ranges this runs at.

## 3. Camera direction and multiplayer

`Bone.Transform` does not replicate, so every client runs this for every
creature it can see. The owner aims immediately from `CurrentCamera` and
publishes changes at most 10 times per second through
`HeadLookService.SetDirection`. Changes under 0.5° are skipped, with a
0.5-second refresh to recover the final pose if an update was rate-limited.

The server accepts only the sender's current character, checks the feature
is enabled, rejects invalid vectors, normalises valid directions and limits
update frequency. It writes `HeadLookDirection` on that character. Observers
read this replicated attribute and smooth the head locally, applying the same
joint limits. Late joiners and streamed-in creatures receive the latest pose.
An absent direction fades out; observers never substitute their own cameras.

`Signals.Direction` takes priority over an explicit `Signals.Target` point.
Camera tracking does not auto-acquire creatures when a direction is missing.

## 4. Automatic attention

`HeadLook.FindTarget` picks the nearest other player's creature inside
`Radius` and inside the `Cone` half-angle, refreshed 4×/second; the aim itself
slews every frame. A caller may pass `Signals.Target` to override this with an
explicit world point (prey, a scripted beat). Self-acquisition only runs when
`CameraTracking` is off and no explicit point or direction is supplied.
This mode uses positions all clients already share and needs no camera updates.

Losing a target does not snap: `strength` eases to 0 and the head relaxes back
onto whatever the animation is doing.

## 5. Configuration

```lua
["HeadLook"] = {
    ["CameraTracking"] = true,    -- false restores nearby-creature attention
    ["Bones"] = { "Neck.002", "Head" },
    ["Weights"] = { 0.4, 0.6 },   -- head carries more than the neck
    ["Aim"] = "Nose",             -- aim marker for automatic attention
    ["MaxYaw"] = 55,              -- deg off the body's facing
    ["MaxPitch"] = 35,
    ["Response"] = 6,             -- 1/s, aim slew rate
    ["Radius"] = 60,              -- studs; automatic attention only
    ["Cone"] = 120,               -- deg half-angle; automatic attention only
},
```

`Bones` is the chain that shares the swing, neck → head. `Aim` is only ever
**read**, never written, so it may well be a bone another layer owns. Camera
mode uses the last bone's calibrated orientation instead of the `Aim` line.
Its yaw/pitch limits describe gaze relative to the body's facing and the
neutral skull pose; they do not force the head-to-nose line to be horizontal.

## 6. Validation

Run `lune run tests/headtracking-regressions.luau` for local regression checks
of camera yaw/pitch, both bones sharing the aim, body-relative limits, smooth
reversals, suppression, automatic attention and the server's input handling.
These use hierarchical mock rigs, including captured wolf bind geometry in
`tests/fixtures/wolf-head-rest.luau`, and fake network signals. The wolf cases
check its neutral skull angle, roll, animated neck turn lead, body turns on
slopes, intermittent animation writes, suppression and reacquisition at
30/60/144 FPS. Visual verification still requires a Studio play session.

Earlier automatic-attention measurements with explicit targets on an isolated rig:

| Asked | Result |
|---|---|
| yaw +40°, pitch +20° | yaw +40.0°, pitch +20.0° |
| yaw −40°, pitch −15° | yaw −40.2°, pitch −14.8° |
| yaw +100°, pitch +60° (outside the cone) | clamped to exactly +55° / +35° |
| suppressed | returns to the rest aim to 0.01°, bit-for-bit |

## 7. Traps

| Trap | Guard |
|---|---|
| Assuming a bone's local axis is "forward" | Camera uses the bind-pose calibration; automatic attention uses the pivot-to-Aim line |
| Muzzle lifted at a level camera angle | Preserve the natural skull angle instead of flattening the sloped head-to-nose line |
| Head points correctly but tilts sideways during turns | Correct the full calibrated camera frame, including up, after articulation |
| Double-counting the neck's turn lead | HeadLook reads the already-articulated pose and corrects it toward the bounded aim |
| Head snapping when a target appears or leaves | `strength` eases in/out; the aim direction is seeded on first sighting |
| Remote creatures following the viewer's camera | Only the owner publishes a direction; observers read the character attribute |
| Body turning past the smoothed head direction | Clamp the smoothed direction against the current body basis each frame |
