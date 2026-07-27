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
BikeConfig.SpawnCFrame = CFrame.new(0, 4, -14)

-- Teal frame, blacked-out components, red shock -- the second reference bike.
-- For the all-black look instead, set Frame/FrameDark to the Component greys.
BikeConfig.Colors = {
	Frame = Color3.fromRGB(24, 128, 126),
	FrameDark = Color3.fromRGB(15, 90, 90),
	Component = Color3.fromRGB(26, 27, 30),
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

BikeConfig.Wheelie = {
	MaxAngle = 46, -- degrees of nose-up at a fully held wheelie
	RiseRate = 70, -- degrees/sec on the way up
	FallRate = 110, -- degrees/sec on the way down
	TurnPenalty = 0.45, -- fraction of steering lost at full wheelie
	StandThreshold = 0.35, -- fraction of MaxAngle before the rider stands up
}

BikeConfig.Jump = {
	Power = 58, -- studs/sec of upward launch
	ForwardBoost = 12, -- studs/sec added along the bike's heading
	Cooldown = 0.5,
	GroundCheck = 0.85, -- studs of clearance under the rear tyre that still counts as grounded
}

-- The stand-up-on-the-pegs pose. Angles are degrees; the rig is posed
-- procedurally rather than with an uploaded animation.
BikeConfig.Rider = {
	BlendSpeed = 7, -- how fast the pose crossfades
	StandLift = 1.25, -- studs the rider rises off the seat
	StandForward = 0.55, -- studs forward over the bars
	StandPitch = -8, -- degrees the whole rider pitches
}

BikeConfig.World = {
	FloorSize = Vector3.new(1024, 2, 1024),
	FloorColor = Color3.fromRGB(150, 150, 152),
	FallResetY = -50,
}

return BikeConfig
