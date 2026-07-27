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
| Reset bike | `R` | **RESET** button |

The wheelie meter along the bottom of the screen fills as the front wheel
comes up. Steering gets lighter the higher you are, so a full wheelie is
harder to aim — that's deliberate.

## What's in the beta

- One rideable bike, modelled on the E Ride Pro Mini's real proportions
  (26° rake, 7-stud wheelbase, 14"-front / 12"-rear wheel ratio, ~66 km/h top
  speed at game scale).
- A 512 × 512 grey floor and a spawn pad. Nothing else — courses come later.
- Upright balancing, so the bike is always rideable and never lies on its side.
- Wheelie on `Q` / the WHEELIE button, with a smooth ramp up and back down.

## How it fits together

`src/` is the source of truth. `build/WheelieBeta.rbxlx` is generated from it.

```
src/ReplicatedStorage/BikeConfig.luau     every tuning number
src/ReplicatedStorage/BikeBuilder.luau    builds the bike out of parts
src/ServerScriptService/BikeServer.…      world, bike spawn, who is riding
src/StarterPlayer/…/BikeClient.…          input, wheelie physics, HUD
```

The rider's client gets network ownership of the bike and simulates it, so
controls have no round-trip lag. The server holds the bike upright while it's
parked and hands control over when someone sits down.

Balance and the wheelie both come from one `AlignOrientation` on the chassis:
it's told to face the current heading, upright, pitched back by the current
wheelie angle. Roll is always zero, so the bike can't tip over.

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

## Not in the beta yet

Courses, more bikes, scoring, saves, sound.
