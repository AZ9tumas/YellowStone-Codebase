# Turn In Place

When a creature is standing still and the player demands a heading far off the
current facing, the creature does not slide-rotate on the spot — it plays a
dedicated turn animation (90° or 180°, left or right) while the root rotates
**in sync with the animation**, exactly like The Isle. The turn brake holds the
creature planted until the turn resolves, then it accelerates out.

## States

Four dedicated states exist in `MovementStates` under their own category
`Turn` (not `Gait`, not `Action`):

| State | Animation asset (Wolf) | Looped |
|---|---|---|
| `Turn90Left` | `rbxassetid://140093023419940` | no (one-shot) |
| `Turn90Right` | `rbxassetid://76931076997938` | no |
| `Turn180Left` | `rbxassetid://101609312038608` | no |
| `Turn180Right` | `rbxassetid://133302248316884` | no |

Turn states live on the **gait slot** (`StateMachine:SetGait` accepts
categories `Gait` and `Turn`) because they own the single locomotion track,
but they get their own category because:

* they are triggered by the input/facing **angle**, not by speed;
* they must never be reported to the server — `MovementService.onSetState`
  rejects any state whose category is not `Gait`, so a malicious client
  cannot crash the server speed loop with `"Turn90LeftSpeed"` lookups;
* they are non-looping one-shots (`looped = false` in the definition, honoured
  by `AnimationController:PlayGait`).

## Per-creature configuration

Turn-in-place is opt-in per creature. A creature with no `TurnInPlace` table
in `CreatureStats` (currently Horsie and MuleDeer) never triggers it; the Wolf
ships with:

```lua
["TurnInPlace"] = {
    ["MaxSpeed"]  = 2.5, -- studs/s: at/below this actual speed the turn happens in place
    ["MinAngle"]  = 55,  -- deg input/facing gap that starts a turn-in-place
    ["Angle180"]  = 120, -- deg gap at/above which the 180 animation is used
    ["ExitAngle"] = 12,  -- deg gap below which the turn is considered finished
},
```

## Trigger conditions

A turn **starts** (`resolveTurnInPlace`) when *all* hold:

$$
\underbrace{\lVert \mathbf{v}_{xz} \rVert \le \texttt{MaxSpeed}}_{\text{near-stationary}}
\;\wedge\;
\underbrace{\theta_{\text{gap}} \ge \texttt{MinAngle}}_{\text{sharp demand}}
\;\wedge\;
\text{move input held}
\;\wedge\;
\text{grounded}
\;\wedge\;
\neg\text{resting}
\;\wedge\;
\neg\text{freezing action}
$$

plus two health checks on the animation itself (see *Hardening* below).

The animation is selected once, at trigger time, and **locked for the whole
turn** so camera wiggle cannot flicker between tracks mid-turn:

$$
\text{arc} =
\begin{cases}
\text{Turn180} & \theta_{\text{gap}} \ge \texttt{Angle180} \\
\text{Turn90} & \text{otherwise}
\end{cases}
\qquad
\text{side} =
\begin{cases}
\text{Left} & \sigma > 0 \\
\text{Right} & \sigma \le 0
\end{cases}
$$

where $\sigma = \operatorname{sign}\big((\hat{\mathbf{f}} \times \hat{\mathbf{t}})_y\big)$
($+1$ means the target is to the left / counter-clockwise seen from above).

A turn **ends** when any of:

* the gap closes: $\theta_{\text{gap}} < \texttt{ExitAngle}$;
* move input is released;
* a freezing action starts (Eat/Drink/Rest);
* the one-shot track finishes (`IsPlaying` goes false after having been seen
  playing);
* the stall timeout fires (below).

Residual angle after the exit is closed by the normal rate-capped turn path.
Because moving sharp turns bleed speed through the brake curve (the wolf's
curve reaches $0$ at $\ge 120°$), a reversal demanded at speed naturally
decelerates the creature *into* the trigger window — the two systems chain
into the full Isle behaviour: run → plant → turn animation → launch out.

## Animation-paced rotation

The root does not rotate at a fixed rate during the turn. Instead, each frame
the remaining gap is spread over the remaining animation time, so the rotation
finishes **exactly when the one-shot ends** and the feet stay planted in sync
with the body:

$$
\omega = \min\!\left(
\frac{\theta_{\text{gap}}}{\max\big(L - t,\ \tfrac{1}{30}\big)},\
\omega_{\max}
\right),
\qquad
\Delta\psi = \min\big(\theta_{\text{gap}},\ \omega\,\Delta t\big)
$$

where $L$ is `AnimationTrack.Length`, $t$ is `TimePosition`, and
$\omega_{\max} = 2\pi\ \text{rad/s}$ (360°/s) is a safety cap. This is
self-correcting: if the player keeps moving the camera mid-turn, the target
gap changes and the rate adapts so the turn still lands with the animation.
Until the track actually starts playing (at most one frame, bounded by the
stall timeout), the creature holds still.

While the turn is active:

* the **brake target is forced to 0** — the eased brake pins the applied
  velocity to zero, and the exit easing produces the accelerate-out;
* **banking tilt is suppressed** (a stationary pivot should not lean);
* the **intent keeps reporting the input gait** (e.g. `Walk`), so the server
  pre-ramps `WalkSpeed` during the turn and the creature launches immediately
  when the brake releases.

## Hardening against broken/slow assets

Turn-in-place must never be able to freeze a production creature. Three
independent rails (all verified in play testing against intentionally
unloadable assets):

1. **Playable-track gate at trigger time.** All tracks are preloaded at
   spawn, so if `track.Length == 0` at trigger the asset hasn't loaded (or is
   permission-blocked). The turn is skipped, a quiet 1-second retry window is
   set, and normal turning covers the gap — the gait layer is never handed an
   empty one-shot.
2. **Stall timeout while active.** A track that never becomes *healthy*
   (`IsPlaying and Length > 0`) within `0.5 s` aborts the turn with a `warn`.
   A permission-blocked track can report `IsPlaying = true` with zero length —
   that counts as stalled, not as running.
3. **Retry cooldown.** A stall sets a 3-second re-trigger cooldown so a
   permanently broken asset degrades to plain fast turning instead of a
   freeze/retry flicker loop.

> **Setup requirement:** the four turn animation assets must be shared with
> the experience (Creations → the asset → Permissions, or publish them under
> the experience owner). If they are not, the engine logs
> `The experience doesn't have access permission to use asset id …` and the
> system silently falls back to non-animated turning via the rails above.
