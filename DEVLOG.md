# Dev log

Every request made on this project and what was built in response, newest at
the bottom. Each entry records the prompt as it was written, the work done, and
the commit it landed in.

Kept up to date and pushed on every change.

---

## 1. First beta

**Commit:** [`e398baf`](../../commit/e398baf) · 2026-07-27

> I want to make a wheelie ebike game in Roblox ok and I want u to make a beta
> for now make it 1 ebike for now now courses just a plain grey floor with a
> model u created and if needed search the internet and find the ebike called
> eride pro mini I want to u to make a model of that for my Roblox wheelie ebike
> game ok just make it be able to wheelie for now and make it the wheelie button
> on pc is Q and for mobile it's a button named wheelie ok EXECUTE

**Steps taken**

1. Searched for the E Ride Pro Mini and found it is a 6kW / 60V electric mini
   pit-bike, not a pedal e-bike. Took its real numbers: 60/100-14 front tyre,
   80/100-12 rear, 680mm seat, 720mm bars, 42 mph top speed.
2. Set up the project: `src/` as the source of truth, a Python packer that
   builds a playable `.rbxlx`, and a Rojo project file for live-sync.
3. Wrote `BikeBuilder` to assemble the bike from parts at runtime, so the whole
   thing stays tunable from one config file. 96 parts.
4. Built the wheelie on a single `AlignOrientation`: aimed at the current
   heading, upright, pitched back by the wheelie angle. Roll pinned at zero so
   the bike could not tip over.
5. Bound `Q` on PC and a held **WHEELIE** button on mobile.
6. Gave the driving client network ownership so controls have no round-trip lag.

**Verification.** No Studio available, so the Luau was run through a Lua
runtime against a hand-written Roblox API shim. Confirmed all four files parse,
the model builds, every hinge's two attachments match to six decimal places in
both axis and position, the steering axis rakes back 26°, wheel spin axes match
their hinge axes exactly, and roll stays at zero through a turn.

---

## 2. Detail, jumps, and the stuck-in-place bug

**Commit:** [`a7ad651`](../../commit/a7ad651) · 2026-07-27

> ok well its good but i mean u need to make the bike detailed so take this and
> kinda mold it onto the bike ok and when i start throttleing backwards or
> forwards its stuck in place either till i wait some time or i wheelie ok so
> fix that and make the map bigger and for now main objective is make thje bike
> detailed ok and add 1 animation like make it in the way u jusrt made the beta
> make an animation when u stand up on it like this wheelie image i just gave ok
> and also refine the bike and add jumps onto the map so there is a tiny course
> where u can jump off of it ok and make a jump button binded to R ok

Two reference photos supplied: a black electric dirt bike, and a teal one being
wheelied.

**Steps taken**

1. **Diagnosed the stuck bug properly rather than guessing.** The chassis
   collision box overlapped both tyres. Roblox only skips collisions between
   *welded* parts — constraint-joined ones still collide — so the wheels were
   grinding against the frame. That is exactly why wheelie-ing freed it: it
   pitches the frame clear of the wheels. Fixed by shrinking the box clear of
   both tyres and adding explicit `NoCollisionConstraints`.
2. Took the bike from 96 to 362 parts, shaped on the photos: laced spokes,
   staggered knobbly tread, drilled floating discs, a chain over both sprockets,
   a coil-over shock with a real helical spring, gold stanchions with dust
   boots, motor cooling fins, a finned battery pack, a bar dash reading out
   speed.
3. Built the stand-up-on-the-pegs pose in code — Roblox animations are just
   `Motor6D.Transform` values written per frame, so `RiderPose` writes them
   itself. No uploaded assets.
4. Grew the map to 1024×1024 and added a jump course. Ramps are derived from the
   two ends of their riding surface and made thick enough to bury the toe below
   the floor, so no lip can catch a wheel.
5. Put jump on `R`, moved reset to `T`.

**Verification.** The harness caught two real bugs before they shipped: the
spring coils and chain links were missing their world transform and would have
rendered as a pile of debris at the map origin. Also confirmed every ramp toe
sits below ground.

---

## 3. Balance point, crashes, city, paint shop

**Commit:** [`a81c1e7`](../../commit/a81c1e7) · 2026-07-27

> [a TikTok link] tka e the video and make an exact copy of it ok with the bike
> anuimations anything but not the party where the fender falls off ok

**Blocked, and said so.** TikTok returns 403 to fetching and video cannot be
watched here at all, so "an exact copy" was not possible from a link. Asked
instead which mechanics to build. Answers: a real balance point, plus crashes,
a street map, customisation, and sound and camera work.

**Steps taken**

1. Replaced the fixed-angle wheelie with an inverted pendulum. Below the balance
   angle gravity pulls the nose down, above it gravity takes you over backwards,
   at it gravity does nothing. Lift fades out past the balance point so it
   cannot be powered through, and braking pulls the nose down as the save.
2. **Fitted the constants by simulation rather than guessing.** The first
   tuning gave a 0.23 s reaction window and looped out no matter what the player
   did — unplayable. Searched the parameter space against playability targets
   and landed on: holds the pocket 93% of the time when tapped, loops out in
   1.9 s held, a release at 28° settles back, and braking recovers from 52°.
3. Ragdoll crashes: loop out or land badly and the rider is thrown off while the
   bike tumbles free of its stabiliser. Every `Motor6D` is swapped for a ball
   socket and put back after, so it works on R6 and R15 alike.
4. Turned the map into a street — long avenue, cross streets, kerbed pavements,
   tower blocks with lit windows, lamp posts — with the jumps moved into town.
5. Added a paint shop, a chase camera that widens with speed and pulls in rather
   than clipping through buildings, and an engine note that pitches with wheel
   speed.

**Flagged:** the audio ids are Roblox's own built-ins. They make noise out of
the box but they are placeholders, not a motor — uploading a real sample is not
something that can be done from here.

---

## 4. Leaning, tricks, more detail

**Commit:** [`fb8e03a`](../../commit/fb8e03a) · 2026-07-28

> ok first when u turn u need to lean ok and make the bike detailed like take
> the image of the beike and just shape it on the bike ok and make like tricks u
> can o like remember the stand up wheelie like i have a bind set to that and
> that bind will be E ok ExECUTE

**Steps taken**

1. The bike banks into corners instead of staying pinned flat: up to 30°, scaled
   by speed, full bank in about half a second, flattening to a third as the
   front wheel comes up.
2. Four tricks, each held on its own key — `E` stand up, `F` no-hander, and
   `G` superman / `H` can-can which refuse to fire with a wheel on the ground.
   Removed the old automatic stand-up so `E` owns it.
3. The ride prompt also sat on `E`, so it is now disabled while someone is
   aboard rather than fighting the trick for the key.
4. Rebuilt `RiderPose` around absolute poses. Whatever is on screen eases toward
   the active pose each frame, so any two tricks cross-fade with no from-pose
   bookkeeping.
5. Added shrouds sweeping from the steering head into the seat — the thing that
   actually gives these bikes their silhouette — plus a bash plate, rear brake
   pedal, toothed sprocket, fork guards, shock linkage, hugger and chain roller.

**Verification.** Confirmed the bank goes the right way on both locks, that
adding roll leaves heading and pitch untouched, and that all five poses define
an identical fourteen-joint set so nothing is left stale when switching.

---

## 5. Publishing, and the phone HUD

**Commit:** [`e398507`](../../commit/e398507) · 2026-07-28

> publish the game so i can plkyay it on my phojne

**Could not publish it** — that needs a Roblox account login, which is not
available from here. Wrote up the manual steps instead (see the README), with
the two things Roblox defaults wrong: new places are private, and Phone has to
be ticked in the device list.

**Steps taken**

1. Found and fixed a real blocker for phone play first. Roblox owns two corners
   on touch devices — thumbstick bottom-left, jump button bottom-right — and the
   **WHEELIE** button was sitting directly under Roblox's jump button while the
   trick buttons were stacked on top of the thumbstick. Both would have been
   unpressable.
2. On touch, everything now moves clear: wheelie and jump above the jump button
   on the right, trick buttons up the left edge above the thumbstick, reset and
   the paint shop along the top, meter and trick readout lifted. Desktop layout
   unchanged.

---

## 6. This log

**Prompt**

> everything i do in here u document the steps and the prompts onto git huub
> immediatlely

Wrote this file covering everything above, and will add an entry and push on
every request from here on.

---

## Standing notes

Things flagged along the way that are still true:

- **The engine sound is a placeholder.** `BikeConfig.Audio` points at sounds
  that ship with Roblox so the game makes noise with nothing to upload, but it
  is not a motor. Paste an engine-whine asset id from the Creator Store into
  `Audio.EngineSoundId`; pitch and volume tracking already works.
- **Nothing here has been run in Roblox Studio.** Geometry, joint alignment,
  control signs and the balance maths are all verified by simulation against an
  API shim, but feel — grip, torque, camera distance, how the trick poses
  actually look — has never been seen. Those are the likeliest things to need a
  tweak.
- **The trick poses are unverified visually.** Limb angles are reasoned from the
  R15 rig. If an arm or leg comes out backwards it is a sign flip in
  `RiderPose.luau`.
- **The TikTok reference was never seen.** Everything built in entry 3 came from
  a set of chosen options, not from the video.
