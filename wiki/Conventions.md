# Conventions

The house rules. These aren't style preferences — each one exists because
breaking it caused a real bug.

## 1. Data lives in config, not in code

Every tuning number belongs in `CreatureStats`. If you find yourself typing a
magic number into `MovementController`, ask whether it's a *creature* property
(→ config) or a *system* feel knob (→ a named constant at the top of the file,
with a comment saying what raising and lowering it does).

Never a bare literal in the middle of a function.

## 2. Fail loud on data, validate softly on input

Two different rules, and mixing them up is a common mistake.

**Internal data → `assert`.** A missing config key or malformed curve is a bug.
Surface it immediately with a message naming the key:

```lua
assert(targetSpeed, `MovementController: no "{gait}Speed" configured`)
```

**Client input → early return.** Anything crossing a remote is untrusted and
being wrong is *expected*, not a bug. Reject it:

```lua
if type(charName) ~= "string" then
    return false, "Invalid spawn arguments"
end
```

A fallback is only acceptable when a genuine alternative source exists and is
documented as such — `info[gait .. "TurnRate"] or info.BaseTurnRate` is fine
because `BaseTurnRate` is the guaranteed value. `or 0` to dodge a crash is not.

## 3. Derive state, don't command it

The visual gait is a pure function of measured speed. Nothing *sets* it to
`Run`; it *becomes* `Run` because the creature is moving that fast. This is why
the animation can never desync from the physics.

Prefer deriving over storing. Rest depth is derived from the action name rather
than kept in a second field, for the same reason: there's no second value to
fall out of sync.

## 4. Framerate independence, always

Ease with the exponential form:

```lua
value += (target - value) * (1 - math.exp(-RESPONSE * dt))   -- ✅
value += (target - value) * math.min(RESPONSE * dt, 1)       -- ❌
```

The second converges differently at different framerates. This was a real bug:
a brake factor computed per-frame behaved differently at 60 and 240 FPS.

For the same reason, drive penalties from **angles**, not per-frame rates. An
angle is frame-rate invariant; `angle / dt` explodes at high FPS for the same
tiny heading gap.

## 5. Respect the authority split

* The **server** owns speed magnitude (`Humanoid.WalkSpeed`).
* The **client** owns direction (`Facing`) and may only ever *reduce* the
  magnitude, via a multiplier in `[0, 1]`.

Keep it that way. If you find yourself wanting the client to set `WalkSpeed`
directly, or the server to set `Facing`, stop — that's a design change, not an
implementation detail. Discuss it first.

Network **intent**, not state, and only on change. The client reports the gait
the player is *asking for*, once, when it changes — not every frame, and never
its physical state.

## 6. Per-life state goes in the object, owned by a Trove

Don't stash character state on the controller itself; it will survive a respawn
and haunt you. Put it in the per-life `object` table and register every
connection with the `Trove` so one `Destroy()` cleans up the whole life.

## 7. Comments explain *why*

The code says what it does. A comment earns its place by explaining the reason,
especially when the obvious approach is wrong:

```lua
-- Cap at the server-driven WalkSpeed. Anything above it is a physics artifact
-- (the AlignOrientation whipping the body measures ~2x WalkSpeed) that would
-- spike the gait a band too high.
```

That is worth reading. `-- clamp the speed` is not. Don't narrate the obvious,
and don't leave a comment describing behaviour that no longer exists — a stale
comment is worse than no comment.

## 8. Prefer simple over clever

If a more complicated approach buys a small efficiency win, take the simple one.
Optimise only when the impact is real and measured. The priority is code that
the next person can pick up and change safely.

Concretely: a fixed-order pipeline of plain functions over one state table is
*better* here than an object graph that does the same job, because the whole
per-frame contract is legible in five lines. Don't add indirection until a
second caller actually needs it.

## 9. One source of truth

The gait ladder is defined in exactly one place (`MovementStates.GaitOrder`) and
read everywhere else. It used to be declared in four, and adding a gait meant
finding all four. If you catch yourself copying a list or a constant, export the
original instead.

## Luau style

* Tabs for indentation.
* Type annotations on module boundaries and exported types; inference is fine
  inside a function body.
* `local function` for file-private helpers; `Module:Method()` for public API.
* Backtick interpolation in messages: `` `Module: bad thing "{name}"` ``.
* `--[[ ... ]]` header block on every module saying what it owns and why.

## Commits

Present tense, and say what changed and why. `"turn brake now uses demanded
angle instead of per-frame rate (framerate bug)"` beats `"fix movement"`. If a
change alters feel, put the before/after numbers in the message.
