# Server Speed Authority

`MovementService` is the anti-exploit backbone: it is the **only** writer of
`Humanoid.WalkSpeed`. The client steers and brakes, but the magnitude it may
travel at comes exclusively from this Heartbeat loop.

## Input validation

The client reports its locomotion intent through the `SetState`
`RemoteSignal`. The handler treats it as untrusted:

```lua
if type(stateName) ~= "string" then return end
local def = MovementStates.Definitions[stateName]
if not def or def.category ~= MovementStates.Category.Gait then return end
player:SetAttribute("State", stateName)
```

Only the five locomotion gaits pass. Turn-in-place states (category `Turn`),
action names, and arbitrary strings are silently rejected — nothing a client
sends can make the speed loop look up a non-existent `"<state>Speed"` config
key.

## The per-player Heartbeat step (`updateSpeed`)

For every spawned player, each Heartbeat with step $\Delta t$:

### 1. Target speed from intent

$$
S_{\text{req}} = \texttt{info[state .. "Speed"]}
$$

This is an internal invariant (the state attribute is always a validated
gait), so a missing key **asserts** — fail loud, no fallback.

### 2. Health penalty

`StaminaMath.HealthBasedSpeedMultiplier` — full speed above the health
threshold, linear ramp down to $1 - p_{\max}$ at zero health:

$$
m_h =
\begin{cases}
1 & h \ge h_t \\[4pt]
1 - p_{\max}\left(1 - \dfrac{h}{h_t}\right) & h < h_t
\end{cases}
\qquad h_t = \texttt{HealthPenaltyThreshold} \cdot \text{MaxHealth}
$$

with $p_{\max}$ = `MaxHealthSpeedPenalty`.

### 3. Stamina drain / gain

Stamina is a normalized value $\sigma \in [0, 1]$ stored in
`player.PlayerStats.Stamina`. Every gait defines *either* a drain *or* a gain
(points per second, asserted to exist):

$$
\sigma \leftarrow \operatorname{clamp}\!\left(\sigma \pm \frac{\text{rate} \cdot \Delta t}{\texttt{MaxStamina}},\ 0,\ 1\right)
$$

Draining gaits (Run, Sprint) also pass through the stamina speed penalty
(`StaminaMath.GetStaminaPenalizedSpeed`). Above the threshold
$\sigma_t$ = `StaminaPenaltyThreshold` the full target speed is allowed; below
it the speed lerps down toward `TrotSpeed`:

$$
S_{\text{fin}} =
\begin{cases}
S_{\text{req}} & \sigma \ge \sigma_t \\[6pt]
S_{\text{trot}} + \big(S_{\text{req}} - S_{\text{trot}}\big)\dfrac{\sigma}{\sigma_t}
\; + \; \underbrace{S_{\text{trot}}\,\dfrac{S_{\text{sprint}} - S_{\text{run}}}{S_{\text{run}}}\,[\sigma > 0]}_{\text{Sprint-only bonus}}
& \sigma < \sigma_t
\end{cases}
$$

so an exhausted sprinter degrades gracefully toward a trot instead of
stopping dead.

### 4. Ramp toward the target (`MovementMath.Accelerate`)

`WalkSpeed` never jumps; it integrates toward the (health-scaled) target with
separate acceleration and deceleration rates:

$$
W \leftarrow
\begin{cases}
W + \min\big(a\,\Delta t,\ \Delta\big) & \Delta > 0 \\[4pt]
W + \max\big(-d\,\Delta t,\ \Delta\big) & \Delta < 0
\end{cases}
\qquad \Delta = S_{\text{fin}}\,m_h - W
$$

(snapping exactly to the target when $|\Delta| < 0.1$), with $a$ =
`Acceleration`, $d$ = `Deceleration` per creature.

## Why ramping produces the whole speed feel

The client applies $\hat{\mathbf{f}}(W \cdot b)$ every frame. Because $W$
ramps rather than jumps:

* **Press W:** intent `Walk` → $W$ ramps $0 \to S_{\text{walk}}$ → the
  creature accelerates from rest; the velocity-derived visual gait climbs the
  animation ladder in sync.
* **Release:** intent `Idle` → $W$ ramps to $0$ → the creature decelerates
  and coasts to a stop instead of the instant Roblox halt; the gait descends.
* **Exhaustion / injury:** the penalties shrink the target, and the same ramp
  glides the creature down to its degraded speed.

One mechanism — server-side target + ramp, client-side application — covers
acceleration, deceleration, stamina, health, and anti-speed-exploit at once.
