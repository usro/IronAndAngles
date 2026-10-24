# Game Design Document: "Iron & Angles" (Working Title)

## 1. High-Level Concept
**Genre:** 2D Physics Artillery / Strategic Simulation
**Target Audience:** Players who enjoy deep, tactical mechanics, technical precision, and economic management.
**Elevator Pitch:** Command an independent artillery battery. Bid against rival commanders for lucrative siege contracts, then take to the battlefield where you must manually calculate windage, elevation, and projectile drop to eliminate targets with maximum efficiency. The less ammo you use, the higher your profit margin.

## 2. Core Gameplay Loop
The game is divided into two distinct phases that feed into each other:

### Phase 1: The Tactical Layer (Action/Physics)
*   **The Mechanic:** Players do not have a simple "point and click" aim. They must dial in the specific elevation angle and powder charge/power level.
*   **Environmental Variables:** Weather impacts the ballistics. Players must adjust for crosswinds, heavy rain (which might reduce incendiary effectiveness), and varying gravity or air density at different altitudes.
*   **Precision Focus:** Emphasize the technical precision of target shooting. Missing a shot not only wastes money but alerts enemy counter-battery fire to your position.

### Phase 2: The Strategy Layer (Economic Meta-Game)
*   **The Auction:** Before a battle, you view a map of the region. You and rival AI commanders bid on specific land plots or defense contracts. Winning the right plot dictates your terrain advantage for the next battle.
*   **Profit Margins:** Your payout is fixed by the contract. Every shell fired costs money. To succeed on harder difficulties, players must optimize their shots to preserve their profit margins.
*   **Reinvestment:** Profits are used to repair equipment, buy rare specialty ammo, and unlock new tech.

## 3. Progression & Tech Tree (The Artillery Eras)
Players progress through historical and experimental eras, changing how they play:
*   **Tier 1 (Medieval/Early Gunpowder):** Trebuchets and crude mortars. High arc, highly affected by wind, unpredictable bounce mechanics.
*   **Tier 2 (Industrial/WW1):** Rifled cannons and heavy howitzers. Flatter trajectories, armor-piercing shells, introduction of shrapnel bursts.
*   **Tier 3 (Modern):** MLRS (Multiple Launch Rocket Systems) and laser-guided munitions. Focus shifts from single-shot precision to managing reload times and area-of-effect saturation.
*   **Tier 4 (Experimental):** Railguns and orbital strikes. Extremely high velocity, zero wind drift, but massive energy costs and long cooldowns.

## 4. Technical Architecture & Constraints
*   **Engine/Framework:** Lightweight 2D engine like Godot, or a custom web-based canvas engine.
*   **Physics Backend:** Because the trajectory math and collision detection need to be highly accurate and performant, the core physics calculations and event handling could be decoupled (e.g., writing the ballistics and state management in a fast language like Go for rapid execution).
*   **Perspective:** 2D Side-scrolling or orthographic 2D, with dynamic camera zoom that follows the projectile.

## 5. Art & Audio Direction
*   **Visuals:** Clean, blueprint-style UI for the management phases. The battlefields should have destructible terrain (voxels or 2D boolean subtraction).
*   **Audio:** Highly satisfying, punchy sound design. The heavy, metallic *clank* of loading a shell, the boom of the launch, and the delayed impact sound based on distance.