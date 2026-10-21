# Common Tasks

Recipes for the changes you're most likely to make. Each one lists every file
you need to touch — if a recipe doesn't mention a file, you shouldn't need it.

---

## Tune how a creature feels

**Files: `Stats/CreatureStats.luau` only.**

Every tuning number lives in one row per species and gender. Nothing is
hardcoded in a controller. Edit, save, and Rojo pushes it — no restart needed
for the next spawn.

| Symptom | Knob |
|---|---|
| Too fast / too slow | `WalkSpeed`, `TrotSpeed`, `RunSpeed`, `SprintSpeed` |
| Sluggish launch, harsh stops | `Acceleration`, `Deceleration` |
| Turns too tightly at speed | Lower `RunTurnRate` / `SprintTurnRate` |
| Ice-skates through corners | Deepen the mid-range of `TurnBrakeCurve` |
| Loses speed running straight | Widen the curve's free zone (first points at `Brake = 1`) |
| Animation flickers between two gaits | Two adjacent speed values are too close together |
| Body lags terrain changes | Raise `TerrainAlignmentSpeed` |
| Body jitters on rough ground | Lower `TerrainAlignmentSpeed`, or raise `TerrainRaycastDistance` |
| Leans too hard into turns | Lower `TiltSensitivity` or `MaxTiltAngle` (or `BodyArticulation.Bank.MaxRoll` if the creature banks through the bone layer) |
| Turns look rigid — body rotates as one block | Add or tune a `BodyArticulation` block; see [Body Articulation](Body-Articulation.md) |

Full key-by-key reference: [Creature Configuration](Creature-Configuration.md).

---

## Add an animation to an existing creature

**Files: `Stats/CreatureStats.luau` only.**

```lua
["Animations"] = {
    ["Idle"] = "rbxassetid://78565435936342",
    -- ...
    ["Eat"]  = "rbxassetid://<your id>",   -- key == state name
},
```

The key **is** the state name. `SpawnService` turns this table into the player's
`Animations` folder at morph time, and `AnimationController` resolves tracks by
that name. No code change.

Extra entries are harmless — they preload and simply never play if nothing
drives that state.

> **The asset must be shared with the experience** (or owned by it), or it fails
> to load at runtime with a permission error and the track silently never plays.
> Creations → the asset → Permissions.

---

## Add a new creature

1. **Model** → `ServerStorage.Models.<Gender>.<CreatureName>` in Studio, then
   save the `.rbxl`. It needs a `Humanoid` and a `HumanoidRootPart`
   (set as `PrimaryPart`).
2. **Stats row** → `CreatureStats[<CreatureName>][<Gender>]`. Copy an existing
   creature and retune; every non-optional key must be present, because missing
   keys fail loudly on first use by design.
3. **Animations** → the five gaits are required (`Idle`, `Walk`, `Trot`, `Run`,
   `Sprint`).
4. **Menu button** → add a `TextButton` to `StarterGui.Menu` whose **`Name` is
   the creature name**; `ui.client.luau` sends `button.Name` straight to
   `SpawnService:Spawn`.
5. **Check the rig physics** — read [Known Issues](Known-Issues.md#creatures-fall-through-terrain)
   before you ship it. A rig with no collidable parts falls through the world.

Test with all four in place; the name must match exactly across the model
folder, the stats key, and the button name.

---

## Add a movement state

**Files: `Movement/MovementStates.luau`, plus the creature's `Animations`.**

One row in `MovementStates.Definitions`:

```lua
Sleep = {
    category = "Action",
    animation = "Sleep",
    freezesMovement = true,          -- suppress locomotion while active
    abortOnMove = true,              -- movement input cancels it
    blockedGaits = { Run = true, Sprint = true },   -- can't start from these
    guard = function(ctx)            -- optional, for anything the above can't express
        return ctx.currentSpeed < 1
    end,
},
```

Restrictions are **declarative** — the `StateMachine` enforces them at request
time, so you never write an `if` chain for them. Trigger it with
`MovementController:RequestAction("Sleep")`, which returns
`(false, reason)` when a restriction blocks it.

Adding a **gait** is rarer: add it to `MovementStates.GaitOrder` *and* add its
row, then give every creature a matching `<Name>Speed` and animation. The ladder
is defined in exactly one place, so nothing else needs updating.

---

## Add a client system

**File: one new ModuleScript in `StarterPlayerScripts/Controllers/`.**

```lua
local Knit = require(game.ReplicatedStorage.Packages.Knit)

local MyController = Knit.CreateController({ Name = "MyController" })

function MyController:KnitInit()
    -- set up your own state; do NOT reach for other controllers yet
end

function MyController:KnitStart()
    -- every controller has Init'd; now it's safe to grab others
    self.MovementController = Knit.GetController("MovementController")
    self.SomeService = Knit.GetService("SomeService")
end

return MyController
```

Knit registers it automatically — there is no list to update. `KnitInit` runs
for *all* modules before *any* `KnitStart`, which is why cross-module lookups
belong in `KnitStart`.

---

## Add a server system

**File: one new ModuleScript in `ServerScriptService/Services/`.**

```lua
local Knit = require(game.ReplicatedStorage.Packages.Knit)

local MyService = Knit.CreateService({
    Name = "MyService",
    Client = {
        Changed = Knit.CreateSignal(),   -- becomes a RemoteEvent
    },
})

-- becomes a RemoteFunction; `player` is injected, never trust the rest
function MyService.Client:DoThing(player: Player, amount: number)
    if type(amount) ~= "number" then
        return false, "bad input"
    end
    return self.Server:DoThing(player, amount)
end

function MyService:DoThing(player: Player, amount: number) end

return MyService
```

**Validate, don't assert, on anything from a client.** Client input is
untrusted: reject it with an early return. Asserts are for *internal* invariants
— see [Conventions](Conventions.md).

---

## Change something about turning

Read [Turning and the Turn Brake](Turning-and-the-Turn-Brake.md) first, then:

* **How fast it can rotate** → `<Gait>TurnRate` / `BaseTurnRate` in the config.
* **How much speed a turn costs** → `TurnBrakeCurve` in the config.
* **How sharply the brake engages/releases** → `TURN_BRAKE_RESPONSE` in
  `MovementController` (a global feel knob, not per-creature).
* **The rotation itself** → the single turn branch in
  `MovementController.updateMovement`.
* **How the body *looks* while it turns** (spine bend, head lead, tail, bank)
  → `BodyArticulation` config; nothing here touches the physics. See
  [Body Articulation](Body-Articulation.md).

---

## Verify your change

Never merge a movement change on reasoning alone — the debug HUD exists so you
can watch the numbers. See [Debugging and Testing](Debugging-and-Testing.md).
