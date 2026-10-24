# Turning and the Turn Brake

> **Reference for turn rates and the speed cost of turning.**
> New to the codebase? Start with [Getting Started](Getting-Started.md) and the
> [Code Tour](Code-Tour.md); this page assumes the vocabulary in the
> [Glossary](Glossary.md).

Turning follows The Isle's model: **rotation is free but rate-capped per
gait**, and the *cost* of turning is paid in **speed**, through a per-creature
brake curve driven by how sharp a turn the player is demanding.

All quantities below are computed in `MovementController.updateMovement` from
the shared per-frame context (see
[Architecture and Authority](Architecture-and-Authority.md)).

## 1. Rotation — rate-capped per gait

Each gait can define its own maximum turn rate; `BaseTurnRate` is the
guaranteed fallback for gaits that don't:

```lua
maxTurnRate = info[gait .. "TurnRate"] or info.BaseTurnRate   -- rad/s
```

The facing advances toward the desired heading by at most that rate:

$$
\Delta\psi = \min\big(\theta_{\text{gap}},\ r_{\text{gait}}\,\Delta t\big),
\qquad
\hat{\mathbf{f}} \leftarrow R_y(\sigma\,\Delta\psi)\,\hat{\mathbf{f}}
$$

where $\theta_{\text{gap}}$ is the angle between facing and desired heading,
$r_{\text{gait}}$ is the gait's max turn rate, and $\sigma = \pm 1$ is the
turn direction from the cross-product sign. Lower turn rates produce wider
arcs at the same speed. These are the ordinary steering limits; a turn overlay
scales its limit by the selected turn row's `SpeedMultiplier` (default `1`).

While **resting**, rotation is disabled entirely.

## 2. The brake — a per-creature curve over the demanded angle

The speed penalty is a function of the **demanded turn angle**
$\theta_{\text{gap}}$, *not* of the per-frame turn rate. A per-frame rate is
$\theta / \Delta t$, which explodes at high FPS for the same tiny heading gap
(a constant $0.72°$ gap reads $0.18$ rad/s at 60 FPS but $0.43$ rad/s at
138 FPS) — that made the old brake framerate-dependent and bite while
sprinting straight. The raw angle is framerate-invariant.

Each creature defines its own relation between turn sharpness and speed as an
ordered list of control points, linearly interpolated
(`MovementMath.EvaluateTurnBrakeCurve`):

$$
B(\theta) =
\begin{cases}
B_1 & \theta \le \theta_1 \\[4pt]
B_{i-1} + \big(B_i - B_{i-1}\big)\dfrac{\theta - \theta_{i-1}}{\theta_i - \theta_{i-1}} & \theta_{i-1} < \theta \le \theta_i \\[8pt]
B_n & \theta > \theta_n
\end{cases}
$$

with $\theta$ in degrees and $B \in [0,1]$ the speed multiplier. The curve
replaces the old single `TurnBrakeSensitivity` scalar; the "free zone" for
micro-corrections (camera noise while holding a straight line) is expressed
directly by the first control points sitting at $B = 1$.

Evaluation **asserts** the curve exists, has at least two points, and that
angles are strictly increasing — a malformed curve is a data bug and fails
loud, per the project's no-fallback rule.

### Shipped curves

| $\theta$ (deg) | Wolf | Horsie | MuleDeer |
|---:|---:|---:|---:|
| 0 | 1.00 | 1.00 | 1.00 |
| 5–10 (free zone) | 1.00 | 1.00 | 1.00 |
| 40–45 | 0.60 | 0.45 | 0.42 |
| 75–90 | 0.25 | 0.25 | 0.28 |
| 180 | 0.20 | 0.25 | 0.28 |

The wolf **plants** hardest — it sheds the most speed on a sharp turn — while
the heavier horse and the deer keep more momentum through one. Every curve
bottoms out **above zero**: a brake of exactly $0$ stops the creature dead and
lets it pivot on the spot, which is not a behaviour this system has any more.
This is the intended axis of species differentiation: give each creature
whatever curve shape fits its body mass and agility.

## 3. Easing — brake fast in, accelerate out at `Acceleration`

The instantaneous curve value is a *target speed*, $W \cdot B(\theta_{\text{gap}})$.
The client steps a commanded speed $s$ toward it
(`MovementMath.StepTurnBrakedSpeed`): speed is shed exponentially, so the
creature plants into a turn, but regained no faster than the creature's
`Acceleration` $a$, the same rate the server uses from rest:

$$
s \leftarrow \min\Big(W,\;
\begin{cases}
s + \big(W B - s\big)\big(1 - e^{-k_b\,\Delta t}\big) & W B < s \\
\min\big(W B,\; s + a\,\Delta t\big) & \text{otherwise}
\end{cases}\Big),
\qquad k_b = 10\ \text{s}^{-1}
$$

Easing *out* exponentially as well used to recover at
$k_b (W - s)$ — about 690 studs/s² after a wolf's sprint 180, over 11× its
`Acceleration` of 60. Capped, the same recovery takes $(73 - 3.7) / 60 \approx 1.15$ s.
The HUD's `Break` is $s / W$.

The 90 and 180 turn overlays use this same curve, and may cap it lower while
a clip runs: the target becomes $\min(B(\theta_{\text{gap}}), \texttt{TurnInPlace.Brake})$.
The clips plant the paws, so without the cap the body kept travelling at the
curve's floor (wolf: $73 \times 0.2 = 14.6$ studs/s) and slid through the
footwork. The cap goes through the same easing, so the body settles into the
turn and accelerates back out at `Acceleration` when the clip ends. It is never zero, and the
overlays never zero velocity or report Idle while movement input is held. Releasing
input, aligning with the requested heading, reversing direction, starting an
action, or leaving the ground interrupts the current clip immediately, with a
0.1-second visual fade. Sustained sharp input repeats the clip without a gap.

`TurnInPlace` applies incremental rotation toward the live heading, paced by
the clip's smoothstep curve and capped by the gait's turn rate multiplied by
the selected row's `SpeedMultiplier`. This optional positive, finite value
defaults to `1`; it scales animation playback and rotation timing together.
At `1.3`, a one-second clip takes about 0.77 seconds and the turn's rate cap is
30% higher. Left and right clips share the row's multiplier. Ordinary steering
and the brake values are unchanged, although quicker alignment can reduce
time spent braking. It never
finishes a cached heading after input changes. Wolf uses authored clips for
both 90 and 180 degrees. The procedural `PawStepper` remains available through
a turn row with `Duration = 1.6` instead of `Left`/`Right` clip names; its
effective duration is also divided by `SpeedMultiplier`.

Because the scaled per-gait turn rate still caps rotation, a sharp turn demanded at a
slow-turning gait (Sprint) keeps $\theta_{\text{gap}}$ large for **more
frames**, so more total speed is shed — sharper turns at higher speeds cost
more distance, exactly as intended.

## 4. Velocity application

$$
\mathbf{v}_{\text{applied}} =
\begin{cases}
\mathbf{0} & \text{freezing action, or forward slope} > \texttt{MaxClimbAngle} \\[4pt]
\hat{\mathbf{f}}\,s & \text{otherwise}
\end{cases}
$$

written to the plane-locked `LinearVelocity` as `PlaneVelocity = (v_x, v_z)`.
A zero-velocity frame also resets $s$ to 0, so the creature accelerates away
again rather than jumping back to speed.

The velocity is **not** zeroed on input release: the server ramps
$W \to 0$ (see [Server Speed Authority](Server-Speed-Authority.md)) and the
applied magnitude follows it down, producing a natural deceleration instead of
the instant Roblox halt. Acceleration from rest is the same mechanism in
reverse.

## Debug surface

The controller exposes the live turning state for the debug HUD:
`GetTurnBrake()` (the eased $b$), `GetTurnAngle()`
($\theta_{\text{gap}}$ in degrees), `GetTurnRateFraction()`
(applied rate / effective cap — deliberately unclamped so a value $> 1$ would
reveal the cap being blown), `GetTurnRateRPS()`, `GetMaxTurnRate()` (includes
the turn multiplier on overlay frames) and
`GetCamYawRate()` (camera yaw angular velocity, for diagnosing camera-driven
heading noise).
