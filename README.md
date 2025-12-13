### Inertial Banking System (Tilt)

The procedural banking effect simulates centripetal force by calculating the turning delta relative to the character's forward direction.

1. **Local Space Conversion**: The global move vector $`\vec{v}_{world}`$ is transformed into the character's local object space relative to the RootPart's Coordinate Frame $`C_{hrp}`$. \\
$$\vec{v}_{local}$$ = `hrpCframe.vectorToObjectSpace(moveVector)`
\\
Here, `moveVector = ControlModule:GetMoveVector()`

2. **Target Angle Calculation**: The lateral component $x_{local}$ determines the target roll angle $\phi_{target}$. If the character moves right relative to its facing direction, it banks right.
```math
   $$\phi_{target} = -x_{local} \cdot \phi_{max}$$
```

3. **Smoothing (Interpolation)**: To prevent jitter, the current roll angle is interpolated towards the target using Linear Interpolation (Lerp) over delta time $\Delta t$ with a smoothing factor $k$.
```math
   \phi_{current} = \phi_{prev} + (\phi_{target} - \phi_{prev}) \cdot \min(k \cdot \Delta t, 1)
```

4. **Application**: The calculated roll is applied to the **Motor6D** (RootJoint) offset.
```math
C_{0, new} = C_{0, original} \cdot R_z(\phi_{current})
```