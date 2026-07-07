# Gait Resolution

The **visual gait** (which locomotion animation plays) is derived every frame
from the creature's *measured* velocity — not from input, and not from the
server's `WalkSpeed`. This is what makes the animation "super dynamic": it
climbs the ladder while accelerating, descends it while decelerating, and
reflects purely client-side speed loss (turn braking, collisions) that the
server never knows about.

Raw per-frame velocity is far too noisy to drive animation directly — it was
the cause of the instantaneous `Idle → Walk` / `Walk → Trot` flicker when
climbing terrain. Three defences are applied in series, all in
`MovementController.resolveVisualGait` and
`MovementMath.ResolveGaitFromVelocity`.

## Stage 1 — Horizontal, authority-clamped measurement

$$
s_{\text{raw}} =
\begin{cases}
0 & \text{if a freezing action is active} \\[4pt]
\min\big(\lVert \mathbf{v}_{xz} \rVert,\ W\big) & \text{otherwise}
\end{cases}
$$

where $\mathbf{v}_{xz}$ is `AssemblyLinearVelocity` with $y$ zeroed and $W$
is `Humanoid.WalkSpeed`.

* **Horizontal only** — climbing a slope adds vertical velocity; the 3-D
  magnitude of a creature walking at $7$ studs/s up a $45°$ incline reads
  $\approx 9.9$, which is inside the Trot band. Locomotion speed is defined on
  the ground plane.
* **Clamped by $W$** — locomotion can never legitimately exceed the server's
  authority. Anything above it is a physics artifact (measured spikes of
  $\sim\!2W$ occur while the `AlignOrientation` whips the body toward a new
  heading and flings the assembly's centre of mass). Every *real* dynamic
  (turn braking, obstacles, deceleration) lives **below** $W$ and passes
  through untouched. This clamp was validated in-game: without it, every
  walk-start briefly showed the Trot animation.

## Stage 2 — Exponential smoothing (framerate-independent)

$$
s \leftarrow s + \big(s_{\text{raw}} - s\big)\,\big(1 - e^{-k\,\Delta t}\big),
\qquad k = 8\ \text{s}^{-1}
$$

An exponential moving average with rate constant $k$. Unlike the common
`min(dt * k, 1)` form, the exponential form composes exactly: two half-steps
equal one full step, so the filter behaves identically at any framerate.
$k = 8$ tracks genuine acceleration (63% of a step change in
$1/k = 125\,\text{ms}$) while swallowing single-frame physics jitter.

## Stage 3 — Hysteresis banding

A naive banding (`speed ≤ walkSpeed → Walk`, etc.) puts a cruising creature
**exactly on a band edge**: walking speed *is* the Walk/Trot boundary, so
$\pm 0.1$ studs/s of jitter flaps the animation every frame. Instead, the
band only changes when the speed *clearly* crosses a boundary:

$$
\text{up}_i = T_i\,(1 + h), \qquad
\text{down}_i = T_i\,(1 - h), \qquad h = 0.12
$$

where $T_1 \ldots T_3$ are `WalkSpeed`, `TrotSpeed`, `RunSpeed` (the upper
bounds of the Walk / Trot / Run bands). To move **up** from tier $i$, the
smoothed speed must exceed $\text{up}_i$; to move back **down**, it must fall
below $\text{down}_i$. Between the two thresholds the current gait is held —
a dead zone of width $2hT_i$ around every boundary.

The Idle boundary is absolute (a fraction of zero is zero):

$$
\text{leave Idle: } s > 1.2 \text{ studs/s}, \qquad
\text{enter Idle: } s < 0.6 \text{ studs/s}
$$

The resolution loop allows multi-band jumps in a single frame (a hard stop
from Sprint goes straight to Idle):

```lua
while tier < 5 and speed > upBound[tier]       do tier += 1 end
while tier > 1 and speed < downBound[tier - 1] do tier -= 1 end
```

`ResolveGaitFromVelocity` **asserts** that the passed `currentGait` is one of
the five locomotion gaits — the controller keeps the last locomotion gait in
`object.VisualGait` separately from the gait slot (which may hold a turn
state), so the hysteresis always has a valid previous band.

## Worked example (Wolf: Walk 7, Trot 16, Run 42)

| Situation | Smoothed speed | Result |
|---|---|---|
| Cruising at walk speed | $7.0$ | Walk (needs $> 7.84$ to become Trot) |
| Slope jitter while walking | $7.5$ | Walk — inside the dead zone |
| Genuine acceleration | $8.2$ | Trot |
| Trot dips in a bend | $15 \to 12$ | Trot — needs $< 6.16$ to drop to Walk |
| Hard turn at Sprint | $73 \to 16$ | Descends Sprint → Run → Trot as speed bleeds |
| Released input | $\to 0.4$ | Idle below $0.6$ |

## Interaction with the rest of the system

* The smoothed speed $s$ also drives the **animation playback rate**
  (see [Animation System](Animation-System.md)), so the same filtered signal
  paces the legs and picks the gait.
* While a **turn-in-place** state owns the gait slot, gait resolution still
  runs every frame in the background (speed near zero ⇒ `Idle`), so the
  moment the turn ends the correct band is already known.
* A **freezing action** (Eat/Drink/Rest) forces the visual gait to `Idle`
  and feeds $s_{\text{raw}} = 0$ into the filter.
