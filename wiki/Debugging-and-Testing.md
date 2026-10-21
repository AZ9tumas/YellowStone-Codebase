# Debugging and Testing

Run `lune run tests/movement-regressions.luau` from the repository root for
gait downshifts, cruise jitter, turn interruption/reversal/looping, and steering
caps at 30/60/144 FPS. These use the production math and animation modules with
fake tracks. Studio playtesting remains necessary for physics and visual feel.

## The debug HUD

Built by `ui.client.luau`, live from the moment you spawn. The motion rows sit
at the top. `Accel`, `Peak`, `Cmd`, `Limit` and `Server` are created by the
script (cloned from `Speed`), so they don't need adding in Studio.

| Field | Source | What it means |
|---|---|---|
| `Speed` | `HRP.AssemblyLinearVelocity` (horizontal) | **Measured physics speed.** Not `WalkSpeed` — this is what the body is really doing. |
| `Accel` | change in measured `Speed` over 0.1 s | **Measured acceleration**, studs/s². Positive = speeding up |
| `Peak: +rise/-drop` | largest `Accel` either way over the last second | Read a burst after it's over, e.g. the recovery after a 180 |
| `Cmd: … WS: …` | `GetCommandedSpeed()`, `Humanoid.WalkSpeed` | What the controller handed the physics (WalkSpeed × Break), and the server's WalkSpeed. `Speed` should track `Cmd` |
| `Limit: +a/-d` | `Acceleration` / `Deceleration` config | The server's WalkSpeed ramp. Compare with `Peak` |
| `Server` | `State` attribute (+ `Swimming`) | The gait the server is driving speed for: your reported intent, mapped onto the swim ladder in water |
| `State` | `MovementController:GetState()` | Visual gait, plus `/ Action` when an action is running |
| `Break` | `GetTurnBrake()` | The eased turn brake, `0`–`1`. `1.00` = no penalty |
| `Angle` | `GetTurnAngle()` | Angle gap between facing and demanded heading, degrees |
| `TurnRate` | `GetTurnRateFraction()` | Applied rate ÷ the gait's cap. Should sit in `0`–`1` |
| `TurnRPS` | `GetTurnRateRPS()` | Raw applied turn rate, rad/s |
| `MaxTurn` | `GetMaxTurnRate()` | The current gait's turn cap, rad/s |
| `Spine / Neck / Tail` | `GetArticulationDebug()` | Procedural bend of each chain, degrees. `0.0` at rest; opposite signs on head vs tail mid-turn |
| `Bank / Gain / Omega` | `GetArticulationDebug()` | Chest roll (deg), the speed gain (`IdleScale` when standing still), and the root's physical yaw rate in rad/s — should track `TurnRPS` with a small lag |
| `FrontLeft … BackRight` | `GetLegIKDebug()` | Each paw's terrain correction in studs. Near `0` on flat ground; a stride's worth on a slope |
| `Feet: n/4  Drop` | `GetLegIKDebug()` | How many paws found ground (0/4 = airborne, and the layer relaxes itself) and the body drop in studs |
| `Look: yaw/pitch *` | `GetHeadLookDebug()` | Head aim off the body's facing, degrees. Trailing `*` = a target is acquired, `-` = relaxing onto the animation |
| `CamRate` | `GetCamYawRate()` | Camera yaw rate, rad/s — tells you whether *you* are the one turning |

`TurnRate` is deliberately **not clamped**. A value above `1.0` means the
per-frame turn cap was blown, which is a bug worth chasing.

## What healthy looks like

Spawn a wolf and run these four checks. They cover most of the system.

**1. The gait ladder.** Hold `W`, then add `Shift`.
`State` should climb `Idle → Walk → Trot → Run → Sprint` as `Speed` rises, and
descend again when you release. It should never flicker between two gaits while
you hold a steady speed — if it does, the two config speeds are too close, or
the hysteresis is too small.

**2. The turn brake.** Sprint, then swing the camera hard and hold a direction.
`Angle` spikes, `Break` drops well below `1.00`, `Speed` bleeds off, and as the
facing catches up `Break` eases back to `1.00` and speed recovers. It should
never reach `0.00` — a zero brake stops the creature dead.

**3. The turn cap.** While turning hard, `TurnRPS` should sit at or just under
`MaxTurn`, and `TurnRate` at or just under `1.00`. `MaxTurn` should *drop* as
you speed up (faster gaits configure lower turn rates).

**4. Terrain.** Run across a slope. The body should pitch and roll with the
ground and settle without jitter. Run up something too steep and you should stop
climbing rather than sliding up it.

## Reading the console

`View → Output` in Studio. Expect these on every run — they are **pre-existing**
and not caused by your change:

```
Slough Creek Water is not a valid member of Workspace
McBride Lake Water is not a valid member of Workspace
FootstepSFXClient:9: attempt to index nil with 'FindFirstChild'
Infinite yield possible on ... HUDMasterScript:WaitForChild("HUD")
```

Anything else is yours. Because config lookups `assert`, a data mistake shows up
as a loud stack trace pointing at the exact key — that's by design, so read the
message rather than adding a fallback.

## Debugging technique

**Print from `update()` sparingly.** It runs every frame; an unguarded print
floods the output and tanks the framerate. Gate it:

```lua
if object.VisualGait ~= object.__lastLogged then
    object.__lastLogged = object.VisualGait
    print("gait ->", object.VisualGait, "speed", object.SmoothedSpeed)
end
```

**Add a HUD field instead** when you want to watch a value continuously. Add a
`TextLabel` to the stats frame, a getter on `MovementController`, and one line
in `ui.client.luau`. That's usually faster than print-debugging a per-frame
value.

**Check the physics, not just the code.** A surprising amount of "the movement
is broken" turns out to be the rig: no collidable parts, a massless root, a
mis-set `HipHeight`. Select the character in the Explorer *while playing* and
read the real property values.

**Isolate client from server.** If speed is wrong, compare `Speed` with the
`Cmd` and `WS` values on the HUD. If `WalkSpeed` is right and
`Speed` is wrong, it's the client (brake, facing, body movers). If `Peak`
is far above `Limit`, something other than the server's ramp is changing
speed — on land that is the turn brake. If `WalkSpeed`
itself is wrong, it's `MovementService` (intent reporting, ramping, stamina).

## Before you call a movement change done

1. Run all four checks above and watch the actual numbers.
2. Test at least one creature **other** than the one you tuned.
3. Test on slopes, not just flat ground.
4. Check the console for new errors.
5. If you changed timing or rates, note the before/after numbers — "it feels
   better" is not reviewable; "180° pivot went from 0.5 s to 1.04 s" is.

## Studio vs the live game

Studio's Play mode runs client and server in one process, so latency is zero and
replication is instant. Anything that looks smooth in Studio may still stutter
live. When something depends on the client/server split, use
**Test → Clients and Servers → 1 player** to get real replication.
