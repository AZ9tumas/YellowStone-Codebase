# Animation System

`AnimationController` plays everything through a **two-layer** model matching
the two state slots, with phase-synchronized crossfades on the locomotion
layer — the fix for the visible "snap" when switching gait animations.

## Layers

| Layer | Priority | Cardinality | Driven by |
|---|---|---|---|
| **Gait** | `Movement` | exactly one track | `StateMachine.GaitChanged → PlayGait` |
| **Action** | `Action` | zero or more tracks | `StateMachine.ActionChanged → PlayAction/StopAction` |

Actions *layer on top of* locomotion via Roblox's priority blending (a Fight
swing plays over a run cycle without replacing it); freezing actions
(Eat/Drink/Rest) additionally force the gait to Idle through the state layer,
not the animation layer.

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

### One-shots on the gait layer

Turn-in-place states pass `looped = false`. Two details matter for one-shots:

* A finished non-looped track parks at `TimePosition == Length`; replaying it
  from there would re-finish instantly. `PlayGait` resets it to $0$ on replay.
* When the one-shot ends by itself, the controller notices
  (`IsPlaying == false`) and the state layer swaps the gait slot back to a
  locomotion gait, which crossfades in normally.

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
(`info[gait .. "Speed"]`). Idle always plays at rate $1$. Turn-in-place
one-shots are skipped — they play at authored speed, and the **root rotation
is paced to them**, not the other way around
(see [Turn In Place](Turn-In-Place.md)).

## Lifecycle

* One `AnimationController` per character life, owned by the
  `MovementController`'s per-life `Trove`.
* `RefreshAnimator` rebuilds all track references after a respawn (tracks
  bound to a dead `Animator` are invalid).
* `Destroy` stops every track with a zero fade and clears all references.

## Adding a new animated state

1. Add the asset id to the creature's `Animations` table in `CreatureStats`
   (the key is the state name — `SpawnService` builds the folder from it).
2. Add the state row to `MovementStates.Definitions` (category, `animation`,
   and `looped = false` if it's a one-shot).
3. Route it: gaits/turns flow through `SetGait`; actions through
   `RequestAction` with their declarative restrictions.

No animation code changes are needed — the controller resolves tracks by
state name.
