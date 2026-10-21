# Animation System

> **Reference for the animation layers, crossfades and playback scaling.**
> New to the codebase? Start with [Getting Started](Getting-Started.md) and the
> [Code Tour](Code-Tour.md); this page assumes the vocabulary in the
> [Glossary](Glossary.md).

`AnimationController` plays everything through a **three-layer** model, with
phase-synchronized crossfades on the locomotion layer — the fix for the
visible "snap" when switching gait animations.

## Layers

| Layer | Priority | Cardinality | Driven by |
|---|---|---|---|
| **Gait** | `Movement` | exactly one track | `StateMachine.GaitChanged → PlayGait` |
| **Action** | `Action` | zero or more tracks | `StateMachine.ActionChanged → PlayAction/StopAction` |
| **Turn** | `Action` | at most one track | `TurnInPlace → PlayTurn/StopTurn` |

Actions *layer on top of* locomotion via Roblox's priority blending — a Fight
swing plays over the gait cycle without replacing it, so the gait keeps
running underneath and fading the action out always lands back in a live
mid-cycle pose. Freezing actions (Eat/Drink/Rest) additionally force the gait
to Idle through the state layer, not the animation layer.

Turn clips play at authored speed and loop while sharp steering continues.
Repeating the same clip keeps its phase; changing sides starts the opposite
clip. On cancellation, playback stops immediately and the held pose fades
back to the live gait over 0.1 seconds. Actions take precedence over turns.
Turn playback does not freeze movement or replace the locomotion state.

Tracks are loaded from the per-player `Animations` folder that
`SpawnService.setupAnimations` builds from the creature's `Animations` config
at morph time — every entry is preloaded at spawn, and `_resolveTrack` lazily
loads anything added later by name.

## The gait-snap problem and its fix

A locomotion cycle is a loop over the stride: paws strike at fixed normalized
times. Two different gaits (Trot and Sprint) are different loops with
different lengths, but the *phase* — where in the stride cycle the legs are —
is the shared quantity. The old implementation stopped the outgoing track and
played the incoming one from $t = 0$: mid-stride, the legs teleported to the
incoming animation's first frame. No fade length hides that discontinuity; it
reads as a snap.

`PlayGait` now performs a **phase-synchronized crossfade**:

1. Capture the outgoing loop's normalized phase:

$$
\varphi = \frac{t_{\text{prev}} \bmod L_{\text{prev}}}{L_{\text{prev}}}
$$

2. Start the incoming track with a fade (`Play(fade)`), then jump it to the
   same phase:

$$
t_{\text{new}} = \varphi \cdot L_{\text{new}}
$$

3. Only then stop the outgoing track with the same fade, so the animator
   weight-blends the overlap of two tracks that are at the *same point in the
   stride*.

The sync applies only when both tracks are loaded loops
(`Length > 0`, `Looped`); if the incoming asset hasn't streamed in yet the
blend still happens, just unphased. Locomotion crossfades use a slightly
longer fade than actions:

```lua
DEFAULT_FADE_TIME = 0.2  -- action layer
GAIT_FADE_TIME    = 0.3  -- locomotion layer (full-body cycle swaps)
```

### One-shots

The gait slot only ever holds looping locomotion cycles. If you add a
non-looped track on the action layer, two details matter:

* A stopped non-looped track parks its `TimePosition` wherever it was faded
  out (or at `Length` after a natural finish); replaying from there would
  re-finish instantly. Reset `TimePosition` on a fresh play.
* A non-looped track that reaches its natural end **hard-cuts** with no fade.
  Exit through `StopAction(name, fade)` before that can happen, so it blends
  back into the gait still playing underneath.

## Playback-rate scaling (foot-ground sync)

Once per frame the playing gait cycle is rescaled so stride frequency tracks
the actual speed (no foot-skating when the measured speed differs from the
gait's nominal speed):

$$
\text{rate} = \operatorname{clamp}\!\left(\frac{s}{S_{\text{gait}}},\ 0.5,\ 1.2\right)
$$

where $s$ is the **smoothed** speed from
[Gait Resolution](Gait-Resolution.md) (the same filtered signal that picks
the band, so playback rate doesn't shiver with physics jitter) and
$S_{\text{gait}}$ is the creature's configured speed for the current gait
(`info[gait .. "Speed"]` — asserted present; the gait slot only ever holds
locomotion gaits). Idle always plays at rate $1$.

## Lifecycle

* One `AnimationController` per character life, owned by the
  `MovementController`'s per-life `Trove`.
* `RefreshAnimator` rebuilds all track references after a respawn (tracks
  bound to a dead `Animator` are invalid).
* `Destroy` stops every track with a zero fade and clears all references.

## Adding a new animated state

1. Add the asset id to the creature's `Animations` table in `CreatureStats`
   (the key is the state name — `SpawnService` builds the folder from it).
2. Add the state row to `MovementStates.Definitions` (category, `animation`).
3. Route it: gaits flow through `SetGait`; actions through `RequestAction`
   with their declarative restrictions.

No animation code changes are needed — the controller resolves tracks by
state name.
