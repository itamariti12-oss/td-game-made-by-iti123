# Wheelie E-Bike — Beta

A Roblox wheelie game. One bike, one plain grey floor, no courses yet.

The bike is the **E Ride Pro Mini** — a 6kW / 60V electric mini pit-bike — built
out of Roblox parts at runtime. Ride it, hold the wheelie control, keep the
front wheel up.

## Play it

Open `build/WheelieBeta.rbxlx` in Roblox Studio (**File → Open from File**) and
hit Play. Everything is already in there — no plugins, no assets to upload.

Walk up to the bike and press **E** (or tap the *Ride* prompt) to get on.

### Playing it on a phone

The place file has to be published to Roblox first — that needs your account,
so it's a manual step:

1. Open `build/WheelieBeta.rbxlx` in Studio.
2. **File → Publish to Roblox As…**, give it a name, **Create**.
3. On the web: **Create → your game → Places → ⋯ → Configure**, then under
   **Playability** set it to **Public** and tick **Phone** under devices.
4. Open the Roblox app on your phone and it's under your own games.

Republishing after a change is **File → Publish to Roblox** (no "As"), which
overwrites the same place — the link stays the same.

The touch HUD keeps clear of Roblox's own controls: the movement thumbstick
owns the bottom-left corner and the jump button the bottom-right, so the
wheelie and jump buttons sit above them on the right, the trick buttons run up
the left edge, and reset and the paint shop sit along the top.

## Controls

| | PC | Mobile |
|---|---|---|
| Steer | `A` / `D` | thumbstick |
| Throttle | `W` | thumbstick up |
| **Brake** — saves a wheelie | `S` | thumbstick down |
| **Wheelie** (tap/hold) | `Q` | **WHEELIE** button |
| **Stand up** (hold) | `E` | **STAND UP** button |
| **No-hander** (hold) | `F` | **NO-HANDER** button |
| **Superman** (air only) | `G` | **SUPERMAN** button |
| **Can-can** (air only) | `H` | **CAN-CAN** button |
| **Jump** | `R` | **JUMP** button |
| Reset bike | `T` | **RESET** button |
| Paint shop | `C` | **BIKE** button |
| Toggle chase camera | `V` | — |

### The wheelie has a balance point

Holding `Q` will not hold a wheelie — it will loop you out in under two
seconds. The bike's pitch is a real inverted pendulum: below 34° gravity pulls
the nose back down, above 34° gravity takes you over backwards, and at 34° it
does nothing at all.

So you tap. Feather `Q` to sit just under the balance angle and the meter turns
green — that's the pocket, and you can hold it indefinitely. Go too far and
**brake with `S`**: that pulls the nose down and is how you save a wheelie
that's gone past the point of no return. Lift also fades out above the balance
angle, so you can't just power through it.

The meter along the bottom shows all of this: green band is the pocket, red
band is the zone you can't land from. Steering gets lighter the higher you are.

### Tricks

Four of them, each held on its own key. `E` stands you up on the pegs — that
one works any time, and it's the one to hold through a wheelie. `F` throws
both hands off the bars. `G` (superman) and `H` (can-can) only fire with both
wheels off the ground, so they're for jumps. Hold two at once and the later
one in the list wins. The trick's name shows above the balance meter while
it's running.

### Leaning

The bike banks into corners now rather than staying pinned flat — up to 30°,
scaled by how fast you're going, reaching full bank in about half a second.
Lean flattens out to a third as the front wheel comes up, because you can't
lean a bike that's balanced on its back tyre.

Jump only fires with a wheel on the ground, so no double-jumping in the air —
but you *can* pop it right on a ramp lip for extra height.

### Crashing

Loop out, or land nose-first or way too nose-high off a jump, and the rider
comes off and ragdolls while the bike tumbles. Everything resets after a few
seconds.

## What's in the beta

- One rideable bike: 362 parts, modelled on the E Ride Pro Mini's real
  proportions (26° rake, 7-stud wheelbase, 14"-front / 12"-rear wheel ratio,
  ~66 km/h top speed at game scale). Laced spokes, knobbly tread, drilled
  discs, a running chain over a toothed sprocket, a coil-over shock, gold
  stanchions with dust boots and fork guards, shrouds sweeping from the
  steering head into the seat, a bash plate, a rear brake pedal, and a bar
  dash that reads out your speed.
- A street map — a long avenue to wheelie down, cross streets, kerbed
  pavements, tower blocks and lamp posts, with the jumps dotted along the
  route: kickers getting bigger, a table-top, a landing ramp, a steep
  launcher in a side lot and a roller pair.
- A real balance-point wheelie you can loop out of, with a brake save.
- Leaning into corners.
- Four tricks: stand up, no-hander, superman, can-can.
- Ragdoll crashes.
- A paint shop: six frame colours, five rim colours, knobbly or street tyres.
- A chase camera that widens its field of view with speed, and an engine note
  that pitches with your wheel speed.
- Roll is always stabilised, so the bike never lies down on its side — the
  only way to come off is a crash.

## How it fits together

`src/` is the source of truth. `build/WheelieBeta.rbxlx` is generated from it.

```
src/ReplicatedStorage/BikeConfig.luau     every tuning number
src/ReplicatedStorage/BikeBuilder.luau    builds the bike out of parts
src/ReplicatedStorage/WorldBuilder.luau   the streets, buildings and jumps
src/ReplicatedStorage/RiderPose.luau      every rider pose and trick
src/ReplicatedStorage/Ragdoll.luau        limp on crash, back up afterwards
src/ServerScriptService/BikeServer.…      world, bike spawn, who is riding
src/StarterPlayer/…/BikeClient.…          input, balance, camera, sound, HUD
```

Studio's edit view only shows a placeholder floor and a spawn pad — the bike,
the city and everything else are built in code the moment you press Play.

The rider's client gets network ownership of the bike and simulates it, so
controls have no round-trip lag. The server holds the bike upright while it's
parked and hands control over when someone sits down.

One `AlignOrientation` on the chassis holds the bike pointed along the current
heading, pitched back by the wheelie angle, and banked by the lean angle. All
three axes are driven, so the bike can't fall over sideways by accident — but
it does lean like a bike should.

The pitch fed into it is simulated as an inverted pendulum, integrated every
frame: lift from the wheelie control (tapering off past the balance point),
gravity pulling toward or away from balance, nose-down torque from the brake,
and a one-way damper that's firm on the way up and softer on the way down.

Every rider animation is built the same way the bike is — in code, at runtime,
with no uploaded animation assets. Roblox animations are just `Motor6D.Transform`
values written every frame, so `RiderPose` writes them itself. Poses are
absolute rather than additive: whatever is on screen eases toward the active
pose each frame, so switching between any two tricks blends smoothly with no
bookkeeping. Which trick you're holding is relayed through the server (checked
against the config list) so every client poses every rider identically.

Only three parts collide with the world: the chassis and the two wheels.
Roblox only disables collisions between *welded* parts, so those three get
explicit `NoCollisionConstraints` — without them the tyres grind against the
frame and the bike won't move.

### Tuning it

Everything worth changing is in `BikeConfig.luau`:

```lua
BikeConfig.Wheelie = {
    BalanceAngle = 34,   -- where gravity stops fighting you
    LoopOutAngle = 63,   -- past this you go over the back
    LiftTorque = 190,    -- how hard Q lifts the nose
    NoseDownTorque = 250,-- how hard the brake saves you
    ...
}
```

These numbers were picked by simulating the pendulum against playability
targets: holding `Q` from flat loops out in 1.9s, releasing at 28° peaks at 34°
and settles, tapping holds the pocket 93% of the time, and braking recovers
from 52°.

Change a value, hit Play. No other file needs touching.

### Rebuilding the place file

After editing anything under `src/`:

```bash
python3 tools/build_place.py
```

If you'd rather live-sync instead, `default.project.json` is a
[Rojo](https://rojo.space) project — `rojo serve` works against the same `src/`.

### Sound

`BikeConfig.Audio` points at sounds that ship with Roblox, so the game makes
noise with nothing to upload — but they are placeholders, not a motor. Paste an
engine-whine asset id from the Creator Store into `Audio.EngineSoundId` for the
real thing; the pitch and volume already track wheel speed.

## History

Every request made on this project and what was built for it is logged in
[DEVLOG.md](DEVLOG.md), newest at the bottom.

## Not in the beta yet

More bikes, scoring, data saves, tricks beyond the wheelie.
