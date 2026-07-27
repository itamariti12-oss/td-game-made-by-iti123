# Wheelie E-Bike — Beta

A Roblox wheelie game. One bike, one plain grey floor, no courses yet.

The bike is the **E Ride Pro Mini** — a 6kW / 60V electric mini pit-bike — built
out of Roblox parts at runtime. Ride it, hold the wheelie control, keep the
front wheel up.

## Play it

Open `build/WheelieBeta.rbxlx` in Roblox Studio (**File → Open from File**) and
hit Play. Everything is already in there — no plugins, no assets to upload.

Walk up to the bike and press **E** (or tap the *Ride* prompt) to get on.

## Controls

| | PC | Mobile |
|---|---|---|
| Throttle / brake | `W` / `S` | thumbstick |
| Steer | `A` / `D` | thumbstick |
| **Wheelie** (hold) | `Q` | **WHEELIE** button, bottom right |
| **Jump** | `R` | **JUMP** button |
| Reset bike | `T` | **RESET** button |

The wheelie meter along the bottom of the screen fills as the front wheel
comes up. Steering gets lighter the higher you are, so a full wheelie is
harder to aim — that's deliberate. Past about a third of full lift the rider
comes up off the seat and onto the pegs.

Jump only fires with a wheel on the ground, so you can't double-jump in the
air — but you *can* pop it right on a ramp lip for extra height.

## What's in the beta

- One rideable bike: 327 parts, modelled on the E Ride Pro Mini's real
  proportions (26° rake, 7-stud wheelbase, 14"-front / 12"-rear wheel ratio,
  ~66 km/h top speed at game scale). Laced spokes, knobbly tread, drilled
  discs, a running chain, a coil-over shock, gold stanchions with dust boots,
  and a bar dash that reads out your speed.
- A 1024 × 1024 floor with a small jump course: three kickers down the middle
  getting bigger, a table-top, a landing ramp, a steep launcher off to one
  side, and a roller pair you can wheelie straight over.
- Upright balancing, so the bike is always rideable and never lies on its side.
- Wheelie on `Q` / the WHEELIE button, with a smooth ramp up and back down.
- A stand-up-on-the-pegs pose that blends in as the front wheel comes up.
- Jump on `R` / the JUMP button.

## How it fits together

`src/` is the source of truth. `build/WheelieBeta.rbxlx` is generated from it.

```
src/ReplicatedStorage/BikeConfig.luau     every tuning number
src/ReplicatedStorage/BikeBuilder.luau    builds the bike out of parts
src/ReplicatedStorage/CourseBuilder.luau  the floor and the jumps
src/ReplicatedStorage/RiderPose.luau      the stand-up animation
src/ServerScriptService/BikeServer.…      world, bike spawn, who is riding
src/StarterPlayer/…/BikeClient.…          input, wheelie physics, jump, HUD
```

Studio's edit view only shows a floor and a spawn pad — the bike, the jumps
and everything else are built in code the moment you press Play.

The rider's client gets network ownership of the bike and simulates it, so
controls have no round-trip lag. The server holds the bike upright while it's
parked and hands control over when someone sits down.

Balance and the wheelie both come from one `AlignOrientation` on the chassis:
it's told to face the current heading, upright, pitched back by the current
wheelie angle. Roll is always zero, so the bike can't tip over.

The stand-up pose is built the same way the bike is — in code, at runtime,
with no uploaded animation assets. Roblox animations are just `Motor6D.Transform`
values written every frame, so `RiderPose` writes them itself, crossfading
between a seated pose and a standing one. Stance is relayed through the server
so every client poses every rider identically.

Only three parts collide with the world: the chassis and the two wheels.
Roblox only disables collisions between *welded* parts, so those three get
explicit `NoCollisionConstraints` — without them the tyres grind against the
frame and the bike won't move.

### Tuning it

Everything worth changing is in `BikeConfig.luau`:

```lua
BikeConfig.Wheelie = {
    MaxAngle = 46,   -- how far back a full wheelie goes
    RiseRate = 70,   -- degrees/sec on the way up  (~0.7s to full)
    FallRate = 110,  -- degrees/sec on the way down
    ...
}
```

Change a value, hit Play. No other file needs touching.

### Rebuilding the place file

After editing anything under `src/`:

```bash
python3 tools/build_place.py
```

If you'd rather live-sync instead, `default.project.json` is a
[Rojo](https://rojo.space) project — `rojo serve` works against the same `src/`.

### Colour

The bike is teal-framed with blacked-out components. For the all-black look
instead, point `Colors.Frame` and `Colors.FrameDark` at the same grey as
`Colors.Component` in `BikeConfig.luau`.

## Not in the beta yet

More bikes, scoring, saves, sound, tricks beyond the wheelie.
