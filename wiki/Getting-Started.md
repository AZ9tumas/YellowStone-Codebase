# Getting Started

Everything you need to go from a fresh clone to a creature running around in
Studio. Budget 15 minutes.

## 1. What you're working on

YellowStone is a Roblox survival game where you play as an animal. You pick a
creature (wolf, mule deer, horse), and it moves with weight: it accelerates and
decelerates instead of snapping to speed, it sheds speed when you turn sharply,
its legs stay planted on slopes, and the animation you see is derived from how
fast it is *actually* moving rather than from what key you pressed.

Most of the code in this repo is that locomotion system. The movement model is
inspired by *The Isle*.

## 2. Prerequisites

| Tool | Why | Install |
|---|---|---|
| **Roblox Studio** | Runs the game | [roblox.com/create](https://www.roblox.com/create) |
| **Aftman** | Installs the pinned Rojo version | [github.com/LPGhatguy/aftman](https://github.com/LPGhatguy/aftman) |
| **Rojo plugin** for Studio | Receives file changes from your editor | Studio → Toolbox → Plugins → "Rojo" |
| **Rokit** *(optional)* | Only needed for the Lune scripts (`remodel.luau`, `decompose.luau`) | [github.com/rojo-rbx/rokit](https://github.com/rojo-rbx/rokit) |

Versions are pinned in `aftman.toml` (Rojo `7.7.0-rc.1`) and `rokit.toml`
(Lune `0.10.4`). Don't install Rojo globally by hand — let Aftman give you the
pinned version, or you'll hit protocol mismatches with the plugin.

## 3. Set up

```bash
git clone https://github.com/AZ9tumas/YellowStone-Codebase.git
cd YellowStone-Codebase
aftman install
```

## 4. Run it

**Terminal — start the sync server:**

```bash
rojo serve
```

**Studio:**

1. Open `YellowStone.rbxl` from the repo root.
2. Open the **Rojo** plugin panel → **Connect**. It should say "Connected".
3. Press **Play** (F5).
4. The creature-select menu appears — click **Wolf**.

You should now be controlling a wolf.

### Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D` | Move (camera-relative) |
| `Shift` (hold) | Use the fast gait instead of the slow one |
| `Z` | Toggle slow gait: Walk ⇄ Trot |
| `X` | Toggle fast gait: Run ⇄ Sprint |
| `R` | Rest — press again to go deeper (Rest1 → Rest2); moving stands you back up |

Movement is **tank-style**: the creature always moves along its own facing, and
your input steers that facing. It does not strafe.

## 5. How the sync works — read this before you edit anything

`rojo serve` is **one-way: files → Studio.** This has three consequences that
bite everyone once.

* **Edit the `.luau` files in your editor, not the scripts in Studio.** Anything
  you type into a script inside Studio is overwritten the next time Rojo pushes
  that file. If you want to experiment in Studio, that's fine — just copy the
  result back into the file before you touch the source again.

* **The `.rbxl` holds everything Rojo does *not* manage** — the map, terrain,
  models under `ServerStorage`, GUIs, lighting. Those you *do* edit in Studio,
  and you save the place file. Rojo owns `src/`; the `.rbxl` owns the world.

* **`$ignoreUnknownInstances` is set on every branch** (see
  `default.project.json`). That means deleting a `.luau` file does **not**
  delete the corresponding script from the `.rbxl` — the stale script keeps
  running until you delete it in Studio by hand and re-save the place. If you
  remove a module and it seems to still be alive, this is why.

## 6. Verify your setup

With the game running and a wolf spawned, the debug HUD in the corner should be
live. Hold `W` and watch `Speed` climb and `State` walk up the ladder
`Idle → Walk → Trot → Run → Sprint`. Turn hard and watch `Break` drop below
`1.00` and `Angle` spike. If those move, everything is wired correctly.

See [Debugging and Testing](Debugging-and-Testing.md) for what every HUD field
means.

## 7. Where to go next

1. [Repository Map](Repository-Map.md) — what lives where.
2. [Code Tour](Code-Tour.md) — one keypress, followed all the way to the screen.
3. [Glossary](Glossary.md) — the vocabulary this codebase uses.
4. [Conventions](Conventions.md) — the house rules, before you write code.

> **Ignore `README.md` in the repo root.** It documents a movement model that no
> longer exists (speed-dependent turn rates, server-side inverse speed
> validation, Motor6D tilt). This wiki is the current source of truth. See
> [Known Issues](Known-Issues.md).
