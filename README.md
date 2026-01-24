## Inertial Banking System (Tilt)

The procedural banking effect simulates centripetal force by calculating the turning delta relative to the character's forward direction. 

1. **Local Space Conversion**: The global move vector $`\vec{v}_{world}`$ is transformed into the character's local object space relative to the RootPart's Coordinate Frame $`C_{hrp}`$. 

```math
    \vec{v}_{local} = C_{hrp}^{-1} \cdot \vec{v}_{world} = \text{hrpCframe.vectorToObjectSpace(moveVector)}
```

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

## Dynamics of Speed-Dependent Humanoid Turning Systems

### 1. Abstract

This document analyzes the mathematical model governing the movement controller implemented for the dinosaur entity. Unlike standard kinematic controllers which allow instantaneous directional changes, this system implements a dynamic coupling between Linear Velocity (Speed) and Angular Velocity (Turn Rate). The system ensures that the turning radius increases as speed increases, simulating inertia and mass, while enforcing server-side validation to prevent physics desynchronization.

### 2. Core Physics Model (Client-Side)

The fundamental principle of this system is that the maximum allowable Turn Rate ($\omega_{max}$) is inversely proportional to the current Linear Speed ($v$). This relationship prevents the entity from making sharp turns at high velocities.

### 2.1 Variable Definitions

Let us define the following parameters:

$\omega_{base}$: The Base Turn Rate (radians/second) when the entity is stationary.

$k_{decay}$: The Turn Speed Decay factor.

$v_{current}$: The current magnitude of the Assembly Linear Velocity.

$\theta_{diff}$: The angular difference between the current facing vector and the target input vector.

$k_{brake}$: The Turn Brake Sensitivity.

### 2.2 Speed-Dependent Turn Rate

The system calculates the maximum angular velocity allowed for the current frame based on the entity's speed. As speed approaches infinity, the turn rate approaches zero.
```math
\omega_{max}(v_{current}) = \frac{\omega_{base}}{1 + (v_{current} \cdot k_{decay})}
```

Physical Implication:

At $v = 0$, the entity turns at $\omega_{base}$.

As $v$ increases, the denominator increases, reducing $\omega_{max}$. This forces a larger turning radius at high speeds.

### 2.3 Angular Displacement Calculation

To determine the new orientation, the system first calculates the angle required to face the target direction ($\vec{d}_{target}$).
```math
\theta_{diff} = \arccos(\vec{d}_{current} \cdot \vec{d}_{target})
```

The actual rotation applied ($\Delta \theta$) is clamped by the maximum turn rate over the time step ($\Delta t$):
```math
\Delta \theta = \min(\theta_{diff}, \omega_{max} \cdot \Delta t)
```

### 2.4 Cornering Brake Logic

To allow the entity to make sharper turns than the current velocity permits, the system implements an automatic braking mechanism. If the player attempts a turn angle ($\theta_{diff}$) larger than what is comfortable, the velocity is throttled.

The Brake Factor ($\beta$) is a scalar between 0 and 1:
```math
\beta = \frac{1}{1 + (\theta_{diff} \cdot k_{brake})}
```

Behavior:

If $\theta_{diff} \approx 0$ (moving straight), $\beta \approx 1$ (Full Speed).

If $\theta_{diff}$ is large (sharp turn), $\beta$ decreases, reducing the walking speed.

### 3. Server-Side Validation & Enforcement

To prevent client-side exploitation (speed hacking or removing turn limits), the server runs an inverse physics calculation. Instead of calculating the Turn Rate from the Speed, the server observes the actual Turn Rate and calculates the Maximum Allowed Speed.

### 3.1 Inverse Derivation

Starting from the client-side equation:
```math
\omega_{obs} = \frac{\omega_{base}}{1 + (v_{limit} \cdot k_{decay})}
```

Where $\omega_{obs}$ is the observed angular velocity on the server. We solve for $v_{limit}$ (the speed limit):

Rearrange to isolate the denominator:
```math
1 + (v_{limit} \cdot k_{decay}) = \frac{\omega_{base}}{\omega_{obs}}
```

Subtract 1:
```math
v_{limit} \cdot k_{decay} = \frac{\omega_{base}}{\omega_{obs}} - 1
```

Solve for $v_{limit}$:
```math
v_{limit} = \frac{(\frac{\omega_{base}}{\omega_{obs}}) - 1}{k_{decay}}
```

### 3.2 Logic Implementation

On every simulation step, the server measures the entity's current angular velocity $\omega_{obs}$.

If $\omega_{obs} > 0.1$ (significant turning is occurring):

The server calculates $v_{limit}$.

If the player's requested speed ($v_{req}$) exceeds this limit:
```math
v_{final} = \min(v_{req}, v_{limit})
```

This ensures that a player cannot spin rapidly while simultaneously moving at maximum sprint speed. If they turn fast, the server forces them to slow down, matching the client-side physics model.

### 4. Visual Tilt Dynamics

While not affecting the velocity directly, the system calculates a visual tilt (Roll) based on the rate of turn to simulate shifting weight.

Let $\phi$ be the current tilt angle. The target tilt $\phi_{target}$ is derived from the turn rate:
```math
\phi_{target} = \text{clamp}(\frac{\Delta \theta}{\Delta t} \cdot k_{tilt\_sens}, -\phi_{max}, \phi_{max})
```

The tilt is applied via linear interpolation (Lerp) for smoothness:
```math
\phi_{new} = \phi_{current} + (\phi_{target} - \phi_{current}) \cdot \min(\Delta t \cdot S_{tilt}, 1)
```

### 5. Summary of Control Flow

Input: User provides a directional vector relative to the camera.

Constraint: Client calculates $\omega_{max}$ based on current speed.

Rotation: Entity rotates towards input, capped at $\omega_{max}$.

Braking: If the turn is sharp, speed is reduced by factor $\beta$.

Movement: Entity moves in the forward-facing direction (Tank Control style), not the input direction.

Validation: Server observes the turn, calculates the theoretical max speed for that turn, and throttles the player if they exceed it.