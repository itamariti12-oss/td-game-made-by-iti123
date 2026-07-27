--!strict
-- BikeBuilder
-- Builds the E Ride Pro Mini out of parts at runtime, so the bike can be
-- re-tuned from BikeConfig without re-modelling anything by hand.
--
-- Physical layout:
--   Chassis      -- the only colliding body part, everything cosmetic welds to it
--   SteerColumn  -- hinged to the chassis on the raked steering axis (servo)
--   FrontWheel   -- hinged to the SteerColumn (free spinning)
--   RearWheel    -- hinged to the Chassis (motor driven)
--   Stabilizer   -- AlignOrientation on the chassis; keeps the bike upright and
--                   is also what pitches it back for the wheelie

local Config = require(script.Parent.BikeConfig)

local BikeBuilder = {}

local G = Config.Geometry
local C = Config.Colors

local CHASSIS_PROPS = PhysicalProperties.new(3.2, 0.35, 0.15, 1, 1)
local WHEEL_PROPS = PhysicalProperties.new(1.6, 2.4, 0.1, 12, 1)

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

type PartOpts = {
	shape: Enum.PartType?,
	collide: boolean?,
	massless: boolean?,
	transparency: number?,
	material: Enum.Material?,
	physical: PhysicalProperties?,
	reflectance: number?,
}

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, opts: PartOpts?): Part
	local o: PartOpts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Shape = o.shape or Enum.PartType.Block
	p.Anchored = false
	p.CanCollide = o.collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = o.massless ~= false
	p.Transparency = o.transparency or 0
	p.Reflectance = o.reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.physical then
		p.CustomPhysicalProperties = o.physical
	end
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Two attachments sharing one world-space frame, one on each part.
local function attachPair(a: BasePart, b: BasePart, worldCF: CFrame, name: string): (Attachment, Attachment)
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "A"
	a0.CFrame = a.CFrame:Inverse() * worldCF
	a0.Parent = a

	local a1 = Instance.new("Attachment")
	a1.Name = name .. "B"
	a1.CFrame = b.CFrame:Inverse() * worldCF
	a1.Parent = b

	return a0, a1
end

-- A tube running between two local-space points. Returns the CFrame (long axis
-- on Z) and the length, ready to feed straight into newPart.
local function tube(from: Vector3, to: Vector3): (CFrame, number)
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) * 0.5
	local up = Vector3.new(0, 1, 0)
	if math.abs(delta.Unit:Dot(up)) > 0.99 then
		up = Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt(mid, to, up), length
end

--------------------------------------------------------------------------------
-- wheels
--------------------------------------------------------------------------------

local function buildWheel(model: Model, name: string, center: Vector3, radius: number, width: number, base: CFrame): Part
	local wheelCF = base * CFrame.new(center)

	-- Cylinder parts spin about their local X axis, which is the rider's
	-- right/left -- exactly the axle direction we want.
	local wheel = newPart(model, name, Vector3.new(width, radius * 2, radius * 2), wheelCF, C.Tire, {
		shape = Enum.PartType.Cylinder,
		collide = true,
		massless = false,
		physical = WHEEL_PROPS,
	})

	local rim = newPart(model, name .. "Rim", Vector3.new(width * 0.92, radius * 1.24, radius * 1.24), wheelCF, C.Accent, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
		reflectance = 0.05,
	})
	weld(wheel, rim)

	local hub = newPart(model, name .. "Hub", Vector3.new(width * 1.15, radius * 0.44, radius * 0.44), wheelCF, C.Silver, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
	})
	weld(wheel, hub)

	for i = 1, G.SpokeCount do
		local a = (i / G.SpokeCount) * math.pi * 2
		local spoke = newPart(
			model,
			name .. "Spoke" .. i,
			Vector3.new(0.07, radius * 0.95, 0.07),
			wheelCF * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius * 0.5, 0),
			C.Silver,
			{ material = Enum.Material.Metal }
		)
		weld(wheel, spoke)
	end

	-- Knobbly dirt-bike tread.
	for i = 1, G.TreadCount do
		local a = (i / G.TreadCount) * math.pi * 2
		local knob = newPart(
			model,
			name .. "Knob" .. i,
			Vector3.new(width * 0.86, 0.16, radius * 0.34),
			wheelCF * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius, 0),
			C.Tire
		)
		weld(wheel, knob)
	end

	-- Rotors sit on the rider's left on both wheels, like the real bike.
	local rotor = newPart(
		model,
		name .. "Rotor",
		Vector3.new(0.09, radius * 0.78, radius * 0.78),
		wheelCF * CFrame.new(-(width * 0.5 + 0.09), 0, 0),
		C.Silver,
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Metal, reflectance = 0.12 }
	)
	weld(wheel, rotor)

	return wheel
end

--------------------------------------------------------------------------------
-- build
--------------------------------------------------------------------------------

function BikeBuilder.Build(baseCF: CFrame): Model
	local model = Instance.new("Model")
	model.Name = Config.ModelName

	local rake = math.rad(G.Rake)
	local raked = CFrame.Angles(rake, 0, 0) -- +X rotation tips the top backwards

	local function L(x: number, y: number, z: number): CFrame
		return baseCF * CFrame.new(x, y, z)
	end

	local function tubePart(parent: BasePart, name: string, from: Vector3, to: Vector3, thickness: number, color: Color3, material: Enum.Material?)
		local cf, length = tube(from, to)
		local p = newPart(model, name, Vector3.new(thickness, thickness, length), baseCF * cf, color, {
			material = material or Enum.Material.Metal,
		})
		weld(parent, p)
		return p
	end

	----------------------------------------------------------------------------
	-- chassis
	----------------------------------------------------------------------------

	local chassis = newPart(model, "Chassis", Vector3.new(1.5, 1.7, 4.6), L(0, 2.55, -0.2), C.Frame, {
		collide = true,
		massless = false,
		transparency = 1,
		physical = CHASSIS_PROPS,
	})
	model.PrimaryPart = chassis

	-- Signature swappable battery box that fills the frame triangle.
	local battery = newPart(model, "BatteryBox", Vector3.new(1.45, 2.1, 2.5), L(0, 2.45, 0.35), C.Frame, {
		material = Enum.Material.Metal,
	})
	weld(chassis, battery)

	local batteryTrim = newPart(model, "BatteryTrim", Vector3.new(1.5, 0.22, 2.54), L(0, 1.52, 0.35), C.Accent, {
		material = Enum.Material.Metal,
	})
	weld(chassis, batteryTrim)

	local batteryVent = newPart(model, "BatteryVent", Vector3.new(1.48, 0.5, 0.9), L(0, 3.2, 0.35), C.DarkMetal, {
		material = Enum.Material.DiamondPlate,
	})
	weld(chassis, batteryVent)

	-- Frame tubes.
	tubePart(chassis, "TopTube", G.SteerHead, Vector3.new(0, 3.55, -0.30), 0.32, C.Frame)
	tubePart(chassis, "DownTube", Vector3.new(0, 2.40, -2.60), Vector3.new(0, 1.72, -0.55), 0.34, C.Frame)
	tubePart(chassis, "CradleTube", Vector3.new(0, 1.72, -0.55), Vector3.new(0, 1.80, 1.00), 0.32, C.Frame)
	tubePart(chassis, "HeadGusset", G.SteerHead, Vector3.new(0, 2.40, -2.60), 0.40, C.Frame)

	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		tubePart(chassis, "Subframe" .. tag, Vector3.new(side * 0.42, 3.50, -0.10), Vector3.new(side * 0.40, 3.62, 2.70), 0.26, C.Frame)
		tubePart(chassis, "Swingarm" .. tag, Vector3.new(side * 0.55, 2.05, 0.95), Vector3.new(side * 0.60, 1.55, 3.20), 0.36, C.Silver)
		tubePart(chassis, "SubBrace" .. tag, Vector3.new(side * 0.44, 2.30, 1.05), Vector3.new(side * 0.40, 3.55, 1.90), 0.22, C.Frame)
	end

	-- Rear monoshock.
	local shockCF, shockLen = tube(Vector3.new(0, 3.30, 1.05), Vector3.new(0, 1.95, 2.20))
	local shock = newPart(model, "RearShock", Vector3.new(0.42, 0.42, shockLen), baseCF * shockCF, C.Accent, {
		material = Enum.Material.Metal,
	})
	weld(chassis, shock)

	-- Mid-mounted motor + drive.
	local motor = newPart(model, "Motor", Vector3.new(1.05, 1.5, 1.5), L(0, 1.95, 0.60), C.DarkMetal, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
		reflectance = 0.08,
	})
	weld(chassis, motor)

	local chainGuard = newPart(model, "ChainGuard", Vector3.new(0.12, 0.46, 2.5), L(0.68, 1.85, 1.95), C.Frame, {
		material = Enum.Material.Metal,
	})
	weld(chassis, chainGuard)

	-- Footpegs.
	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		local peg = newPart(model, "Footpeg" .. tag, Vector3.new(0.95, 0.16, 0.34), L(side * 0.98, 1.95, 0.85), C.Silver, {
			material = Enum.Material.DiamondPlate,
		})
		weld(chassis, peg)

		-- Side number plate with the model name on it.
		local plate = newPart(model, "SidePlate" .. tag, Vector3.new(0.10, 1.15, 1.5), L(side * 0.80, 2.85, 0.90), C.Accent, {
			material = Enum.Material.SmoothPlastic,
		})
		weld(chassis, plate)

		local gui = Instance.new("SurfaceGui")
		gui.Face = side < 0 and Enum.NormalId.Left or Enum.NormalId.Right
		gui.CanvasSize = Vector2.new(300, 220)
		gui.LightInfluence = 0
		gui.Parent = plate

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.Text = "E RIDE\nPRO"
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Parent = gui
	end

	-- Seat + tail.
	local seatPad = newPart(model, "SeatPad", Vector3.new(1.25, 0.46, 3.0), L(0, 3.72, 1.05) * CFrame.Angles(math.rad(-3), 0, 0), C.Frame, {
		material = Enum.Material.Fabric,
	})
	weld(chassis, seatPad)

	local tail = newPart(model, "RearFender", Vector3.new(1.2, 0.24, 2.2) , L(0, 3.88, 2.55) * CFrame.Angles(math.rad(-8), 0, 0), C.Accent)
	weld(chassis, tail)

	local taillight = newPart(model, "Taillight", Vector3.new(0.52, 0.26, 0.16), L(0, 3.86, 3.42), C.Taillight, {
		material = Enum.Material.Neon,
	})
	weld(chassis, taillight)

	----------------------------------------------------------------------------
	-- steering column (everything that turns with the bars)
	----------------------------------------------------------------------------

	local column = newPart(model, "SteerColumn", Vector3.new(0.42, 1.6, 0.42), L(0, 3.42, -2.87) * raked, C.DarkMetal, {
		massless = false,
		material = Enum.Material.Metal,
		physical = PhysicalProperties.new(1.0, 0.3, 0.2, 1, 1),
	})

	local clampTop = newPart(model, "TripleClampTop", Vector3.new(1.0, 0.22, 0.55), L(0, 3.88, -2.70) * raked, C.Silver, {
		material = Enum.Material.Metal,
	})
	weld(column, clampTop)

	local clampBottom = newPart(model, "TripleClampBottom", Vector3.new(1.0, 0.22, 0.55), L(0, 3.10, -3.08) * raked, C.Silver, {
		material = Enum.Material.Metal,
	})
	weld(column, clampBottom)

	-- Upside-down forks: black lowers, silver stanchions.
	local axle = G.FrontAxle
	local forkDir = Vector3.new(0, math.cos(rake), math.sin(rake))
	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		local bottom = Vector3.new(side * 0.46, axle.Y, axle.Z)
		local mid = bottom + forkDir * 1.25
		local top = bottom + forkDir * 2.45

		local lowCF, lowLen = tube(bottom, mid)
		local lower = newPart(model, "ForkLower" .. tag, Vector3.new(0.36, 0.36, lowLen), baseCF * lowCF, C.Frame, {
			material = Enum.Material.Metal,
		})
		weld(column, lower)

		local upCF, upLen = tube(mid, top)
		local upper = newPart(model, "ForkUpper" .. tag, Vector3.new(0.30, 0.30, upLen), baseCF * upCF, C.Silver, {
			material = Enum.Material.Metal,
			reflectance = 0.15,
		})
		weld(column, upper)
	end

	local caliper = newPart(model, "FrontCaliper", Vector3.new(0.26, 0.5, 0.34), L(-0.55, 2.25, -3.55), C.Accent, {
		material = Enum.Material.Metal,
	})
	weld(column, caliper)

	-- Bars.
	local riser = newPart(model, "BarRiser", Vector3.new(0.7, 0.42, 0.3), L(0, 4.10, -2.62) * raked, C.Silver, {
		material = Enum.Material.Metal,
	})
	weld(column, riser)

	local bars = newPart(model, "Handlebar", Vector3.new(3.6, 0.20, 0.20), L(0, 4.34, -2.56), C.Frame, {
		material = Enum.Material.Metal,
	})
	weld(column, bars)

	local barPad = newPart(model, "BarPad", Vector3.new(1.15, 0.36, 0.36), L(0, 4.34, -2.56), C.Accent)
	weld(column, barPad)

	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		local grip = newPart(model, "Grip" .. tag, Vector3.new(0.9, 0.26, 0.26), L(side * 1.42, 4.34, -2.56), C.Frame)
		weld(column, grip)

		local lever = newPart(model, "Lever" .. tag, Vector3.new(0.72, 0.08, 0.12), L(side * 1.06, 4.26, -2.76), C.Silver, {
			material = Enum.Material.Metal,
		})
		weld(column, lever)
	end

	-- Front plate, fender and light.
	local numberPlate = newPart(model, "NumberPlate", Vector3.new(1.5, 1.35, 0.14), L(0, 3.60, -3.34) * raked, C.Plate)
	weld(column, numberPlate)

	local headlight = newPart(model, "Headlight", Vector3.new(0.92, 0.46, 0.18), L(0, 3.92, -3.30) * raked, C.Headlight, {
		material = Enum.Material.Neon,
	})
	weld(column, headlight)

	local frontFender = newPart(model, "FrontFender", Vector3.new(1.25, 0.20, 2.1), L(0, 3.02, -3.72) * CFrame.Angles(math.rad(10), 0, 0), C.Accent)
	weld(column, frontFender)

	----------------------------------------------------------------------------
	-- wheels + joints
	----------------------------------------------------------------------------

	local frontWheel = buildWheel(model, "FrontWheel", G.FrontAxle, G.FrontRadius, G.FrontWidth, baseCF)
	local rearWheel = buildWheel(model, "RearWheel", G.RearAxle, G.RearRadius, G.RearWidth, baseCF)

	local sprocket = newPart(
		model,
		"RearSprocket",
		Vector3.new(0.16, G.RearRadius * 0.72, G.RearRadius * 0.72),
		baseCF * CFrame.new(G.RearAxle) * CFrame.new(G.RearWidth * 0.5 + 0.1, 0, 0),
		C.Accent,
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Metal }
	)
	weld(rearWheel, sprocket)

	-- Steering hinge: axis runs up the raked steering head.
	local steerAxisX = Vector3.new(0, math.cos(rake), math.sin(rake))
	local steerAxisY = Vector3.new(0, -math.sin(rake), math.cos(rake))
	local steerWorld = baseCF * CFrame.fromMatrix(G.SteerHead, steerAxisX, steerAxisY)

	local sc0, sc1 = attachPair(chassis, column, steerWorld, "Steer")
	local steerHinge = Instance.new("HingeConstraint")
	steerHinge.Name = "SteerHinge"
	steerHinge.Attachment0 = sc0
	steerHinge.Attachment1 = sc1
	steerHinge.ActuatorType = Enum.ActuatorType.Servo
	steerHinge.ServoMaxTorque = 60000
	steerHinge.AngularSpeed = Config.Handling.SteerSpeed
	steerHinge.TargetAngle = 0
	steerHinge.LimitsEnabled = true
	steerHinge.LowerAngle = -Config.Handling.MaxSteerAngle
	steerHinge.UpperAngle = Config.Handling.MaxSteerAngle
	steerHinge.Parent = chassis

	-- Front axle: free spinning.
	local fw0, fw1 = attachPair(column, frontWheel, baseCF * CFrame.new(G.FrontAxle), "FrontAxle")
	local frontHinge = Instance.new("HingeConstraint")
	frontHinge.Name = "FrontHinge"
	frontHinge.Attachment0 = fw0
	frontHinge.Attachment1 = fw1
	frontHinge.ActuatorType = Enum.ActuatorType.None
	frontHinge.Parent = column

	-- Rear axle: the driven wheel.
	local rw0, rw1 = attachPair(chassis, rearWheel, baseCF * CFrame.new(G.RearAxle), "RearAxle")
	local rearHinge = Instance.new("HingeConstraint")
	rearHinge.Name = "RearHinge"
	rearHinge.Attachment0 = rw0
	rearHinge.Attachment1 = rw1
	rearHinge.ActuatorType = Enum.ActuatorType.Motor
	rearHinge.MotorMaxTorque = Config.Drive.MotorTorque
	rearHinge.MotorMaxAcceleration = Config.Drive.MotorAcceleration
	rearHinge.AngularVelocity = 0
	rearHinge.Parent = chassis

	----------------------------------------------------------------------------
	-- stabiliser -- upright balance AND the wheelie pitch
	----------------------------------------------------------------------------

	local stabAtt = Instance.new("Attachment")
	stabAtt.Name = "StabilizerAttachment"
	stabAtt.Parent = chassis

	local stabilizer = Instance.new("AlignOrientation")
	stabilizer.Name = "Stabilizer"
	stabilizer.Mode = Enum.OrientationAlignmentMode.OneAttachment
	stabilizer.Attachment0 = stabAtt
	stabilizer.RigidityEnabled = false
	stabilizer.MaxTorque = Config.Handling.StabilizerTorque
	stabilizer.MaxAngularVelocity = math.huge
	stabilizer.Responsiveness = Config.Handling.StabilizerResponsiveness
	stabilizer.CFrame = baseCF.Rotation
	stabilizer.Parent = chassis

	----------------------------------------------------------------------------
	-- rider seat
	----------------------------------------------------------------------------

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.4, 0.5, 1.7)
	seat.CFrame = L(0, 3.95, 1.05)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- legacy Motor driving is unused; the scripts drive the hinge
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model
	weld(chassis, seat)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RidePrompt"
	prompt.ActionText = "Ride"
	prompt.ObjectText = Config.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	return model
end

return BikeBuilder
