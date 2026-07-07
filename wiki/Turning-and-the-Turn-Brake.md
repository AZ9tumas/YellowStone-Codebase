# Turning and the Turn Brake

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
turn direction from the cross-product sign. Faster gaits configure lower
turn rates (e.g. Wolf: Idle $10$, Walk/Trot $6$, Run/Sprint $4$ rad/s), which
produces wide, momentum-respecting arcs at speed.

While **resting**, rotation is disabled entirely. While a **turn-in-place**
state is active, this branch is replaced by animation-paced rotation
(see [Turn In Place](Turn-In-Place.md)).

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
| 75–90 | 0.20 | 0.25 | 0.28 |
| 120 | **0.00** | — | — |
| 180 | **0.00** | 0.25 | 0.28 |

The wolf **plants**: at a demanded heading change of $120°$ or more the brake
reaches exactly $0$, so a demanded reversal stops it completely and resolves
as a turn-in-place — the Isle behaviour. The horse and deer always keep some
momentum through a turn (curves bottom out above zero). This is the intended
axis of species differentiation: give each creature whatever curve shape fits
its body mass and agility.

## 3. Easing — decelerate in, accelerate out

The instantaneous curve value is a *target*; the applied brake eases toward
it exponentially so the creature visibly decelerates into a turn and
accelerates back out:

$$
b \leftarrow b + \big(B(\theta_{\text{gap}}) - b\big)\big(1 - e^{-k_b\,\Delta t}\big),
\qquad k_b = 10\ \text{s}^{-1}
$$

While a turn-in-place is active the target is forced to $0$ (the creature
holds its ground); on exit the same easing ramps $b \to 1$, producing the
smooth launch out of the turn.

Because the per-gait turn rate still caps rotation, a sharp turn demanded at a
slow-turning gait (Sprint) keeps $\theta_{\text{gap}}$ large for **more
frames**, so more total speed is shed — sharper turns at higher speeds cost
more distance, exactly as intended.

## 4. Velocity application

$$
\mathbf{v}_{\text{applied}} =
\begin{cases}
\mathbf{0} & \text{freezing action, or forward slope} > \texttt{MaxClimbAngle} \\[4pt]
\hat{\mathbf{f}}\,\big(W \cdot b\big) & \text{otherwise}
\end{cases}
$$

written to the plane-locked `LinearVelocity` as `PlaneVelocity = (v_x, v_z)`.

The velocity is **not** zeroed on input release: the server ramps
$W \to 0$ (see [Server Speed Authority](Server-Speed-Authority.md)) and the
applied magnitude follows it down, producing a natural deceleration instead of
the instant Roblox halt. Acceleration from rest is the same mechanism in
reverse.

## Debug surface

The controller exposes the live turning state for the debug HUD:
`GetTurnBrake()` (the eased $b$), `GetTurnAngle()`
($\theta_{\text{gap}}$ in degrees), `GetTurnRateFraction()`
(applied rate / gait max — deliberately unclamped so a value $> 1$ would
reveal the cap being blown), `GetTurnRateRPS()`, `GetMaxTurnRate()` and
`GetCamYawRate()` (camera yaw angular velocity, for diagnosing camera-driven
heading noise).
