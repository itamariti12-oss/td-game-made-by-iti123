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

## 7. Rider was frozen; smoothing the bike

**Prompt**

> ok so listen when im on the bike im stiff im not moving my body for the
> tricks and make a button for a trick when u wheelie like this but whem u just
> normal wheelieng u are sitting ok and dont make the ebikes oyu of blocks make
> it like us blender to do the clours and the shape and make it really look lik
> it then put it into the game ok'

**Steps taken**

1. **Found why the rider was stiff.** `stopDriving()` cleared all the driving
   state but never called `RiderPose.Release`. On the normal dismount path that
   left the character's `Animate` script disabled forever and its joints frozen
   on the last pose written — so the rider stopped animating entirely, on the
   bike and off it. Release is now called on every dismount path.
2. Moved pose writing from `Heartbeat` to `BindToRenderStep` at
   `Character + 1` priority, so it lands after Roblox's own character animation
   step instead of racing it.
3. Made posing work on R6 rigs, not just R15. Poses are written in character
   space and conjugated into each joint's own frame by its `C0` rotation, so
   one set of pose data now drives both rigs.
4. Normal wheelie stays seated and `E` is the stand-up trick — already the
   behaviour, and it should now actually be visible.
5. Smoothing pass on the bike: every frame tube is round tubing rather than a
   square-section box, with balls at the junctions so the welds read; bars,
   grips, bar pad, shock body, spokes and the headlight lens are round; fenders
   sweep around the wheels as arcs instead of hovering as flat slabs; the
   battery pack and seat get rolled edges.

**Not done, and why.** A Blender-authored mesh is not possible from here:
Blender is not installed, and a mesh has to be uploaded to Roblox as an asset,
which needs the account. Offered instead to generate an importable `.obj` +
`.mtl` that Studio's **Import 3D** can bring in locally — that would allow
genuinely smooth surfaces, at the cost of losing the runtime paint shop and
config-driven tuning.

**Verification.** Shape census before and after; fender arcs confirmed to clear
both tyres by 0.42–0.55 studs; steering and rear hinges still aligned to six
decimals; wheels still exactly on the ground at spawn.

---

## 8. Installed the UI/UX Pro Max skill

**Prompt**

> $ uipro init --ai claude
>
> install this

**Steps taken**

1. `uipro` is not a package — the npm package is **`uipro-cli`**, which
   provides a `uipro` binary. Checked npm and PyPI before running anything.
2. Pulled the tarball and read it before executing: no install hooks (only
   `build` / `dev` / `prepublishOnly`, none of which run on install), four
   common dependencies, and it writes a skill rather than touching project
   code.
3. Ran `npx uipro-cli@2.2.3 init --ai claude`. It created
   `.claude/skills/ui-ux-pro-max/` — a `SKILL.md`, CSV design data, and three
   Python search scripts.
4. Deleted the `__pycache__` bytecode the package ships and added a
   `.claude/.gitignore` for it. Smoke-tested `search.py`.
5. Committed it. This container is ephemeral, so an uncommitted install would
   have disappeared with the session.

**Worth knowing.** The skill is web and mobile UI design — React, Next.js,
Vue, Tailwind, shadcn, SwiftUI, Flutter. None of those exist in this repo,
which is Luau, so it will not fire on the bike or physics work. The parts that
could still earn their keep are the palette, typography, spacing and
accessibility data, which apply to the Roblox HUD even though the stack does
not.

---

## 9. Full skill set from the uploaded repo, plus project memory

**Prompt**

> [uploaded ui-ux-pro-max-skill-main.zip] open it and implement it to ur claude
> memory and tools ok

**Steps taken**

1. Opened the zip: it is the whole upstream repo, not just the one skill the
   CLI installed last time. It carries **seven** skills — `ui-ux-pro-max`,
   `ui-styling`, `design`, `design-system`, `brand`, `slides` and
   `banner-design`.
2. The zip's `ui-ux-pro-max` is **v2.11.0** (84 styles, 192 palettes) against
   the CLI's **v2.2.3** (67 styles, 96 palettes), so the upload is newer and
   richer. Replaced the installed copy rather than merging.
3. Checked the 5.5 MB in `ui-styling` before committing binaries: 54 Google
   Font `.ttf` files, each shipped with its OFL licence text, so fine to
   redistribute.
4. Installed all seven into `.claude/skills/`, stripped `__pycache__`.
5. Wrote `CLAUDE.md` for the "memory" half — project layout, how the runtime
   build works, the traps that have already cost a debugging round each
   (constraint parts still collide; the rig must be released on every dismount;
   pose writes belong on RenderStep; bike-local geometry needs `baseCF *`), how
   verification works without Studio, and the standing agreement to log every
   request here.

**Worth knowing.** These skills target web and mobile UI stacks — React,
Next.js, Vue, Tailwind, shadcn, SwiftUI, Flutter. None exist in this repo, so
they will not fire on bike, physics or world code. The parts that transfer are
the palette, typography, spacing and accessibility data, which apply to the
Roblox HUD regardless of stack.

---

## 10. Gemini / Nano Banana generators

**Prompt**

> ok can u fix the gemini and nano bana apii problem fix it

**What was actually broken.** Two things, neither of them the model ids.

1. The `google-genai` SDK was not installed, so every generator stopped at its
   import guard.
2. Installing it was not enough. `import google.genai` still died with a Rust
   panic out of `cryptography` — the image ships one whose bindings need
   `_cffi_backend`, and `cffi` was missing. Upgrading `cffi` fixed it. The
   symptom looks nothing like the cause, which is worth remembering.

**Checked and found fine.** All three model ids are current:
`gemini-2.5-flash-image` (Nano Banana), `gemini-3-pro-image-preview` (Nano
Banana Pro) and `gemini-3.1-pro-preview` for SVG icons. The deprecated one is
`gemini-3-pro-preview`, which these scripts do not use. Nothing to change.

**Steps taken**

1. Installed `google-genai`, then `cffi` to repair the import.
2. Confirmed all three generators (`logo`, `icon`, `cip`) now load and parse
   their arguments.
3. Added a `SessionStart` hook in `.claude/settings.json` that reinstalls both
   if missing. The container is ephemeral, so without this the fix would have
   lasted exactly one session. It is async so it never blocks startup, and the
   already-installed path costs 1.5 s. Pipe-tested both branches and validated
   the JSON nesting with `jq -e`.
4. Documented the setup in `CLAUDE.md`.

**Still outstanding, and not fixable from here.** `GEMINI_API_KEY` is not set.
That is a personal credential from https://aistudio.google.com/apikey and does
not belong in the repo — `export GEMINI_API_KEY="..."` before running the
generators. The scripts stop with a clear message until then.

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
