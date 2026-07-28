# Project notes

A Roblox wheelie game. One bike (the E Ride Pro Mini), a street map with jumps,
a balance-point wheelie, tricks, and ragdoll crashes.

Read [DEVLOG.md](DEVLOG.md) for the history of what was asked for and why
things are the way they are.

## Layout

`src/` is the source of truth. `build/WheelieBeta.rbxlx` is generated from it
by `python3 tools/build_place.py` and is what actually gets opened in Studio.

```
src/ReplicatedStorage/BikeConfig.luau     every tuning number
src/ReplicatedStorage/BikeBuilder.luau    the bike, assembled from parts
src/ReplicatedStorage/WorldBuilder.luau   streets, buildings, jumps
src/ReplicatedStorage/RiderPose.luau      rider poses and tricks
src/ReplicatedStorage/Ragdoll.luau        limp on crash, back up after
src/ServerScriptService/BikeServer…       world, spawn, who rides, crashes
src/StarterPlayer/…/BikeClient…           input, balance, camera, sound, HUD
```

**Always rebuild the place file after touching `src/`**, or the `.rbxlx` and
the source drift apart.

## How it works

Everything — bike, city, HUD — is built in code at runtime. Nothing is
hand-modelled and no assets are uploaded, so the place file stays small and the
whole game is tunable from `BikeConfig.luau`.

One `AlignOrientation` on the chassis drives all three axes: heading, wheelie
pitch, and lean. The pitch fed into it is an inverted pendulum integrated every
frame — that is what makes the wheelie a balance problem rather than a fixed
angle.

The riding client owns network ownership and simulates the bike, so controls
have no round-trip lag. The server only takes over while the bike is parked or
crashed.

## Things that will bite

- **Constraint-joined parts still collide in Roblox.** Only *welds* disable
  collision. The chassis and both wheels need explicit
  `NoCollisionConstraints` — without them the tyres grind on the frame and the
  bike will not move. This cost a full debugging round once already.
- **Rider posing must release the rig.** `RiderPose.Release` has to run on
  every dismount path. Miss one and the character's `Animate` script stays
  disabled and its joints stay frozen — the player is stiff forever, on the
  bike and off it. This also cost a round.
- **Pose writes belong on `RenderStep` at `Character + 1`**, not `Heartbeat`,
  or Roblox's own animation step can overwrite them.
- **Geometry built in bike-local space needs `baseCF *`.** Forgetting it puts
  parts at the map origin instead of on the bike.

## Verifying without Studio

Studio is not available in this environment, so nothing here has ever been run
in the real engine. Luau is checked by running it against a hand-written Roblox
API shim (`CFrame`, `Vector3`, `Instance`, `Enum`), which catches syntax errors
and — more usefully — geometry mistakes: joint alignment, hinge axes, ground
clearance, control signs.

Physics tuning is fitted by simulation against playability targets rather than
guessed. See DEVLOG entry 3 for how the wheelie constants were chosen.

**What this cannot check is feel.** Grip, torque, camera distance, and how the
trick poses actually look are unverified. Say so rather than implying they were
tested.

## Working agreement

- Log every request and what was built for it in `DEVLOG.md`, then commit and
  push. This is standing, not per-request.
- Push to `claude/roblox-wheelie-ebike-beta-4e5w25`; it feeds PR #1.

## Installed skills

`.claude/skills/` holds the UI/UX Pro Max skill set (banner-design, brand,
design, design-system, slides, ui-styling, ui-ux-pro-max).

These target web and mobile UI — React, Next.js, Vue, Tailwind, shadcn,
SwiftUI, Flutter. **None of those stacks exist in this repo**, which is Luau,
so they will not fire on bike, physics or world code.

Where they can still earn their keep is the raw design data — colour palettes,
typography, spacing scales, accessibility and UX guidelines — which applies to
the Roblox HUD (balance meter, trick buttons, paint shop panel) even though the
implementation stack does not.
