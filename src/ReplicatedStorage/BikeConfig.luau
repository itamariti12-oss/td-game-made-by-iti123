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

BikeConfig.Colors = {
	Frame = Color3.fromRGB(26, 27, 30),
	Accent = Color3.fromRGB(198, 26, 38),
	Silver = Color3.fromRGB(188, 192, 198),
	DarkMetal = Color3.fromRGB(58, 60, 64),
	Tire = Color3.fromRGB(18, 18, 20),
	Plate = Color3.fromRGB(236, 236, 238),
	Headlight = Color3.fromRGB(255, 246, 214),
	Taillight = Color3.fromRGB(255, 40, 40),
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

	TreadCount = 14,
	SpokeCount = 8,
}

BikeConfig.Drive = {
	MaxWheelSpeed = 42, -- rad/s at the rear wheel (~65 studs/s)
	MotorTorque = 260000,
	MotorAcceleration = 320,
	ReverseFactor = 0.35,
	BrakeTorque = 90000,
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
	RiseRate = 70, -- degrees/sec going up
	FallRate = 110, -- degrees/sec coming down
	TurnPenalty = 0.45, -- fraction of steering lost at full wheelie
}

BikeConfig.World = {
	FloorSize = Vector3.new(512, 2, 512),
	FloorColor = Color3.fromRGB(150, 150, 152),
	FallResetY = -50,
}

return BikeConfig
