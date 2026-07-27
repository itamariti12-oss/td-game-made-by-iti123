--!strict
-- BikeConfig
-- Every tuning number for the beta lives here. Change a value, hit Play,
-- see the difference -- no other file needs touching.
--
-- The bike is the "E Ride Pro Mini": a 6kW / 60V electric mini pit-bike.
-- Real-world numbers it is modelled on:
--   front tyre 60/100-14, rear tyre 80/100-12, seat height 680mm,
--   handlebar width 720mm, 42 mph top speed, 210 N.m peak wheel torque.
-- Those proportions are kept, but scaled up so a Roblox character fits on it.

local BikeConfig = {}

BikeConfig.ModelName = "ERideProMini"
BikeConfig.DisplayName = "E Ride Pro Mini"

-- Where the bike parks itself, and where it returns to on RESET.
BikeConfig.SpawnCFrame = CFrame.new(0, 4, 40)

-- Teal frame, blacked-out components, red shock. Riders can repaint the frame
-- and rims in game; these are the defaults.
BikeConfig.Colors = {
	Frame = Color3.fromRGB(24, 128, 126),
	FrameDark = Color3.fromRGB(15, 90, 90),
	Component = Color3.fromRGB(26, 27, 30),
	Rim = Color3.fromRGB(26, 27, 30),
	Rubber = Color3.fromRGB(18, 18, 20),
	Accent = Color3.fromRGB(196, 32, 38),
	Silver = Color3.fromRGB(190, 194, 200),
	DarkMetal = Color3.fromRGB(58, 60, 64),
	Gold = Color3.fromRGB(198, 158, 72),
	Plate = Color3.fromRGB(232, 233, 236),
	Headlight = Color3.fromRGB(255, 246, 214),
	Taillight = Color3.fromRGB(255, 40, 40),
	Screen = Color3.fromRGB(12, 16, 18),
}

-- All geometry is in studs, in bike-local space:
--   +X = rider's right, +Y = up, -Z = forward.
BikeConfig.Geometry = {
	Rake = 26, -- steering head angle, degrees back from vertical

	FrontAxle = Vector3.new(0, 1.65, -3.8),
	RearAxle = Vector3.new(0, 1.55, 3.2),
	SteerHead = Vector3.new(0, 3.30, -2.95),

	FrontRadius = 1.65,
	FrontWidth = 0.95,
	RearRadius = 1.55,
	RearWidth = 1.25,

	-- The one colliding body part. Kept clear of both tyres: parts joined by
	-- constraints still collide with each other, so any overlap here would
	-- jam the wheels against the frame.
	ChassisSize = Vector3.new(1.35, 1.45, 3.10),
	ChassisCentre = Vector3.new(0, 2.62, -0.15),

	TreadCount = 20,
	SpokeCount = 16,
	ChainLinks = 24,
	SpringCoils = 14,
}

BikeConfig.Drive = {
	MaxWheelSpeed = 42, -- rad/s at the rear wheel (~65 studs/s)
	MotorTorque = 260000,
	MotorAcceleration = 340,
	ReverseFactor = 0.35,
	BrakeTorque = 25000, -- weak, so releasing the throttle coasts
}

BikeConfig.Handling = {
	MaxSteerAngle = 32, -- visual front-wheel lock, degrees
	SteerSpeed = 14, -- rad/s the servo can move the forks
	TurnRate = 105, -- degrees/sec of chassis yaw at full steer
	TurnSpeedThreshold = 12, -- studs/s needed before steering has full bite
	MaxHeadingLag = 0.40, -- radians the steering target may lead the chassis
	StabilizerTorque = 4e6,
	StabilizerResponsiveness = 45,
}

-- The wheelie is a real balance problem, not a fixed angle. The bike's pitch
-- is an inverted pendulum: below BalanceAngle gravity pulls the nose down,
-- above it gravity pulls you over backwards, and at BalanceAngle it does
-- nothing. Holding the wheelie control adds lift. Feathering it to sit in the
-- pocket is the skill of the whole game.
BikeConfig.Wheelie = {
	BalanceAngle = 34, -- degrees where gravity is neutral
	SweetSpot = 6, -- +/- degrees around it that counts as balanced
	LoopOutAngle = 63, -- past this you go over the back
	MinAngle = -16, -- how far the nose can drop (airborne only)

	LiftTorque = 190, -- deg/s^2 while the wheelie control is held
	ThrottleAssist = 50, -- extra lift per unit of throttle
	LiftFalloff = 16, -- degrees past balance over which lift fades out, so you
	LiftFloor = 0.3, -- cannot simply power through the tipping point
	ReleaseTorque = 50, -- chopping the throttle actively drops the nose
	NoseDownTorque = 250, -- braking pulls it down -- the save, on road or in air
	GravityTorque = 120, -- deg/s^2 of pendulum gravity, at 90 deg from balance
	Damping = 4.5, -- 1/s while the nose is rising
	FallDamping = 2.6, -- less on the way down, so it drops with some weight
	AirGravityScale = 0.12, -- gravity barely acts on pitch while airborne

	TurnPenalty = 0.45, -- fraction of steering lost at full lift
	StandThreshold = 0.4, -- fraction of BalanceAngle before the rider stands up
}

BikeConfig.Jump = {
	Power = 58, -- studs/sec of upward launch
	ForwardBoost = 12, -- studs/sec added along the bike's heading
	Cooldown = 0.5,
	GroundCheck = 0.85, -- clearance under a tyre that still counts as grounded
}

BikeConfig.Crash = {
	LandingSafeMin = -13, -- land nose-down past this and you case it
	LandingSafeMax = 56, -- land nose-up past this and you loop out
	ImpactSpeed = 115, -- studs/s of downward speed that always crashes
	RagdollTime = 2.8, -- seconds on the floor before you get back up
	EjectImpulse = 46, -- how hard the rider is thrown off
}

-- The stand-up-on-the-pegs pose. Angles are degrees; the rig is posed
-- procedurally rather than with an uploaded animation.
BikeConfig.Rider = {
	BlendSpeed = 7,
	StandLift = 1.25,
	StandForward = 0.55,
	StandPitch = -8,
}

BikeConfig.Camera = {
	Enabled = true, -- riders can toggle back to the default camera with V
	Distance = 23,
	Height = 7.5,
	LookHeight = 3.2,
	Smoothness = 9, -- higher follows more tightly
	BaseFov = 70,
	MaxFov = 88,
	FovSpeed = 70, -- studs/s at which MaxFov is reached
	MinDistance = 6, -- how close it may pull in to clear a wall
}

BikeConfig.Audio = {
	-- PLACEHOLDER. These are sounds that ship with Roblox, so the game makes
	-- noise out of the box with nothing to upload. For a real motor, paste an
	-- engine-whine asset id from the Creator Store into EngineSoundId.
	EngineSoundId = "rbxasset://sounds/action_swim.mp3",
	EngineVolume = 0.5,
	IdlePitch = 0.5,
	MaxPitch = 2.2,
	LandSoundId = "rbxasset://sounds/impact_water.mp3",
	LandVolume = 0.45,
	CrashSoundId = "rbxasset://sounds/snap.mp3",
	CrashVolume = 0.8,
}

-- What riders can change on the bike. The client only ever sends an index
-- into these lists, so a bad message cannot paint the bike an arbitrary value.
BikeConfig.Paint = {
	Frame = {
		{ Name = "Teal", Color = Color3.fromRGB(24, 128, 126) },
		{ Name = "Black", Color = Color3.fromRGB(26, 27, 30) },
		{ Name = "Red", Color = Color3.fromRGB(178, 32, 38) },
		{ Name = "Orange", Color = Color3.fromRGB(226, 118, 26) },
		{ Name = "Purple", Color = Color3.fromRGB(108, 56, 168) },
		{ Name = "White", Color = Color3.fromRGB(228, 230, 234) },
	},
	Rim = {
		{ Name = "Black", Color = Color3.fromRGB(26, 27, 30) },
		{ Name = "Gold", Color = Color3.fromRGB(198, 158, 72) },
		{ Name = "Silver", Color = Color3.fromRGB(190, 194, 200) },
		{ Name = "Red", Color = Color3.fromRGB(178, 32, 38) },
		{ Name = "Teal", Color = Color3.fromRGB(24, 128, 126) },
	},
	Tyre = { "Knobbly", "Street" },
}

BikeConfig.World = {
	FloorSize = Vector3.new(1024, 2, 1024),
	FloorColor = Color3.fromRGB(126, 127, 130),
	FallResetY = -50,
}

return BikeConfig
