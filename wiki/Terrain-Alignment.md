# Terrain Alignment

The creature's body aligns to the ground it stands on — pitching up slopes,
rolling across side-hills — while banking into turns and leaning into rest
postures. Everything composes into a single goal CFrame written to the
force-based `AlignOrientation` each frame (`updateOrientation`).

## 1. Ground probe (`detectGround`)

Four rays are cast downward from a facing-aligned rectangle around the
`HumanoidRootPart`:

```
        fwd
   1 ───────── 2        origins: hrp.Position ± fwd·halfZ ± right·halfX,
   │           │                 raised by halfY/2
   │    HRP    │        ray:     (0, -(halfY + TerrainRaycastDistance), 0)
   3 ───────── 4        filter:  exclude the character
```

with `halfX = max(size.X/2, 0.5)`, `halfZ = max(size.Z/2, 0.5)` and
`fwd` the facing flattened to the XZ plane (falling back to the root's look
vector if degenerate). The probe rectangle rotates with the facing, so the
footprint matches the body regardless of heading.

* **Grounded** requires at least 2 hits.
* **Normal estimation:**
  * With **3–4 hits**, a plane is fitted by summing the normalized cross
    products of every hit-point triple (sign-corrected to point upward):

$$
\mathbf{n} = \sum_{i<j<k} \widehat{(\mathbf{p}_j - \mathbf{p}_i) \times (\mathbf{p}_k - \mathbf{p}_i)},
\qquad \hat{\mathbf{n}} = \frac{\mathbf{n}}{\lVert \mathbf{n} \rVert}
$$

    (degenerate triples with a near-zero cross are skipped; if all are
    degenerate the averaged surface normals of the hits are used instead).
  * With exactly **2 hits**, the averaged surface normals are used.
* **Forward slope** — the signed angle of the facing projected onto the fitted
  plane, used for the climb gate:

$$
\mathbf{p} = \hat{\mathbf{f}} - \hat{\mathbf{n}}\,(\hat{\mathbf{f}} \cdot \hat{\mathbf{n}}),
\qquad
\text{slope} = \arcsin\big(\operatorname{clamp}(\hat{\mathbf{p}}_y, -1, 1)\big)
$$

If `slope > MaxClimbAngle` the applied velocity is zeroed — the creature
physically cannot walk up faces steeper than its configured limit.

## 2. Normal clamping

The target normal is clamped to the creature's maximum body tilt
(`MaxTerrainAngle`): if the fitted normal deviates from world-up by more than
$\theta_{\max}$, it is rotated back to exactly $\theta_{\max}$ about the axis
$\hat{\mathbf{y}} \times \hat{\mathbf{n}}$:

$$
\hat{\mathbf{n}}' =
\begin{cases}
R_{\hat{\mathbf{a}}}(\theta_{\max})\, \hat{\mathbf{y}}, \quad \hat{\mathbf{a}} = \widehat{\hat{\mathbf{y}} \times \hat{\mathbf{n}}}
& \text{if } \angle(\hat{\mathbf{n}}, \hat{\mathbf{y}}) > \theta_{\max} \\[4pt]
\hat{\mathbf{n}} & \text{otherwise}
\end{cases}
$$

When airborne (fewer than 2 hits) the target normal snaps to world-up.

## 3. Normal smoothing + re-normalization

The working normal eases toward the target exponentially
(framerate-independent) and is **re-normalized after the lerp** — the linear
interpolation of two unit vectors is shorter than unit length, and feeding a
non-unit up-vector into `CFrame.fromMatrix` would shear the orientation the
`AlignOrientation` chases:

$$
\alpha = 1 - e^{-k_t\,\Delta t}, \qquad
\hat{\mathbf{n}}_{\text{cur}} \leftarrow
\widehat{\operatorname{lerp}\big(\hat{\mathbf{n}}_{\text{cur}},\ \hat{\mathbf{n}}',\ \alpha\big)}
$$

with $k_t$ = `TerrainAlignmentSpeed` (per creature; Wolf/Deer 6, Horse 3).

## 4. Banking tilt and rest lean

The banking (roll into a turn) targets the current *actual* yaw rate of the
facing, measured from consecutive frames, scaled and clamped:

$$
\omega_{\text{yaw}} = \frac{\arcsin\big((\hat{\mathbf{f}}_{\text{prev}} \times \hat{\mathbf{f}})_y\big)}{\Delta t},
\qquad
\tau_{\text{target}} = \operatorname{clamp}\big(\omega_{\text{yaw}} \cdot \texttt{TiltSensitivity},\ \pm\texttt{MaxTiltAngle}\big)
$$

then eases with $\alpha = 1 - e^{-\texttt{TiltSpeed}\,\Delta t}$. While a
**turn-in-place** is active the target is forced to $0$ — a stationary pivot
does not lean.

The resting lean is a placeholder nose-down pitch per rest depth
($-15°$ for Rest1, $-32°$ for Rest2, response $6\ \text{s}^{-1}$), applied
through the same pipeline; it will be deleted when real rest animations land.

## 5. Composition

The final orientation builds an orthonormal basis from the facing and the
smoothed normal:

$$
\hat{\mathbf{r}} = \widehat{\hat{\mathbf{f}} \times \hat{\mathbf{n}}_{\text{cur}}},
\qquad
\text{CF} = \operatorname{fromMatrix}\big(\mathbf{0},\ \hat{\mathbf{r}},\ \hat{\mathbf{n}}_{\text{cur}}\big)
\cdot R_x(\tau_{\text{rest}}) \cdot R_z(\tau_{\text{tilt}})
$$

$\hat{\mathbf{r}}$ is perpendicular to $\hat{\mathbf{n}}_{\text{cur}}$ by
construction (cross product), so after normalizing it the matrix is a clean
rotation whose look vector is the facing projected onto the ground plane.
The result is written to `AlignOrientation.CFrame`; the constraint is
force-based (`RigidityEnabled = false`) so the body is *pulled* toward the
goal rather than teleport-rotated through geometry.

## Why exponential easing everywhere

Every smoothing step in the orientation pipeline (brake, tilt, rest pitch,
terrain normal, speed filter) uses

$$
x \leftarrow x + (x_{\text{target}} - x)\big(1 - e^{-k\,\Delta t}\big)
$$

rather than `min(k·Δt, 1)` lerp factors. The exponential form is the exact
solution of $\dot{x} = k\,(x_{\text{target}} - x)$ over a step of $\Delta t$,
so it **composes**: stepping twice with $\Delta t/2$ gives the identical
result as once with $\Delta t$. Framerate cannot change the feel — the same
class of bug as the fixed "higher frames → lower break factor" regression,
eliminated structurally.

## Tuning per creature

| Key | Meaning |
|---|---|
| `TerrainAlignmentEnabled` | Master switch for the probe + alignment |
| `TerrainAlignmentSpeed` | Normal-easing rate $k_t$ (higher = snappier adaptation) |
| `MaxTerrainAngle` | Hard cap on body tilt from terrain (deg) |
| `MaxClimbAngle` | Forward slope beyond which movement is blocked (deg) |
| `TerrainRaycastDistance` | Probe depth below the root (studs) |
| `MaxTiltAngle`, `TiltSensitivity`, `TiltSpeed` | Banking clamp, gain, easing rate |
