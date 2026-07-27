--!strict
-- BikeBuilder
-- Builds the E Ride Pro Mini out of parts at runtime, so the bike can be
-- re-tuned from BikeConfig without re-modelling anything by hand.
--
-- Physical layout -- only three parts collide with the world:
--   Chassis      -- the body; everything cosmetic welds to it
--   FrontWheel   -- hinged to the SteerColumn (free spinning)
--   RearWheel    -- hinged to the Chassis (motor driven)
-- plus:
--   SteerColumn  -- hinged to the chassis on the raked steering axis (servo)
--   Stabilizer   -- AlignOrientation on the chassis; keeps the bike upright and
--                   is also what pitches it back for the wheelie
--
-- Roblox only disables collisions between *welded* parts, so the three
-- colliding bodies get explicit NoCollisionConstraints between them. Without
-- those the tyres grind against the frame and the bike refuses to move.

local Config = require(script.Parent.BikeConfig)

local BikeBuilder = {}

local G = Config.Geometry
local C = Config.Colors

local CHASSIS_PROPS = PhysicalProperties.new(6.0, 0.35, 0.15, 1, 1)
local WHEEL_PROPS = PhysicalProperties.new(1.6, 2.4, 0.1, 12, 1)
local COLUMN_PROPS = PhysicalProperties.new(1.0, 0.30, 0.20, 1, 1)

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
	paint: string?, -- marks the part as repaintable: "Frame", "Rim", "Tyre", "Knob"
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
	if o.paint then
		p:SetAttribute("Paint", o.paint)
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

local function noCollide(a: BasePart, b: BasePart)
	local nc = Instance.new("NoCollisionConstraint")
	nc.Part0 = a
	nc.Part1 = b
	nc.Parent = a
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

-- A tube running between two points. Returns a CFrame with its long axis on Z,
-- plus the length -- ready to feed straight into newPart.
local function tube(from: Vector3, to: Vector3): (CFrame, number)
	local delta = to - from
	local length = delta.Magnitude
	local up = Vector3.new(0, 1, 0)
	if math.abs(delta.Unit:Dot(up)) > 0.99 then
		up = Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt((from + to) * 0.5, to, up), length
end

-- A frame sitting at `from` and looking down the axis toward `to`, so local
-- -Z advances along the axis. Used for laying things out on a helix or a line.
local function axisFrame(from: Vector3, to: Vector3): (CFrame, number)
	local delta = to - from
	local dir = delta.Unit
	local up = Vector3.new(0, 1, 0)
	if math.abs(dir:Dot(up)) > 0.99 then
		up = Vector3.new(0, 0, 1)
	end
	local right = dir:Cross(up).Unit
	return CFrame.fromMatrix(from, right, right:Cross(dir)), delta.Magnitude
end

--------------------------------------------------------------------------------
-- wheels
--------------------------------------------------------------------------------

local function buildWheel(model: Model, name: string, center: Vector3, radius: number, width: number, base: CFrame): Part
	local wheelCF = base * CFrame.new(center)

	-- Cylinder parts spin about their local X axis, which is the rider's
	-- right/left -- exactly the axle direction we want.
	local wheel = newPart(model, name, Vector3.new(width, radius * 2, radius * 2), wheelCF, C.Rubber, {
		shape = Enum.PartType.Cylinder,
		collide = true,
		massless = false,
		physical = WHEEL_PROPS,
		paint = "Tyre",
	})

	local function bolt(p: Part)
		weld(wheel, p)
	end

	-- Rim: a black barrel with a machined lip on each shoulder.
	bolt(newPart(model, name .. "Rim", Vector3.new(width * 0.86, radius * 1.20, radius * 1.20), wheelCF, C.Rim, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
		reflectance = 0.06,
		paint = "Rim",
	}))
	for _, side in { -1, 1 } do
		bolt(newPart(
			model,
			name .. "RimLip" .. (side < 0 and "L" or "R"),
			Vector3.new(0.1, radius * 1.34, radius * 1.34),
			wheelCF * CFrame.new(side * width * 0.42, 0, 0),
			C.Silver,
			{ shape = Enum.PartType.Cylinder, material = Enum.Material.Metal, reflectance = 0.2 }
		))
	end

	-- Hub and axle.
	bolt(newPart(model, name .. "Hub", Vector3.new(width * 1.12, radius * 0.46, radius * 0.46), wheelCF, C.Silver, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
		reflectance = 0.15,
	}))
	bolt(newPart(model, name .. "Axle", Vector3.new(width * 1.55, 0.22, 0.22), wheelCF, C.DarkMetal, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
	}))

	for i = 1, G.SpokeCount do
		local a = (i / G.SpokeCount) * math.pi * 2
		-- Alternate spokes lace to opposite rim shoulders, like a real wheel.
		local lace = (i % 2 == 0) and 1 or -1
		bolt(newPart(
			model,
			name .. "Spoke" .. i,
			Vector3.new(0.06, radius * 0.92, 0.06),
			wheelCF * CFrame.new(lace * width * 0.22, 0, 0) * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius * 0.52, 0),
			C.Silver,
			{ material = Enum.Material.Metal, reflectance = 0.2 }
		))
	end

	-- Knobbly dirt tread: staggered inner and outer rows.
	for i = 1, G.TreadCount do
		local a = (i / G.TreadCount) * math.pi * 2
		local offset = (i % 2 == 0) and width * 0.22 or -width * 0.22
		bolt(newPart(
			model,
			name .. "Knob" .. i,
			Vector3.new(width * 0.44, 0.17, radius * 0.30),
			wheelCF * CFrame.Angles(a, 0, 0) * CFrame.new(offset, radius, 0),
			C.Rubber,
			{ paint = "Knob" }
		))
		bolt(newPart(
			model,
			name .. "Shoulder" .. i,
			Vector3.new(width * 0.2, 0.14, radius * 0.24),
			wheelCF * CFrame.Angles(a + math.pi / G.TreadCount, 0, 0) * CFrame.new(-offset * 1.9, radius * 0.96, 0),
			C.Rubber,
			{ paint = "Knob" }
		))
	end

	-- Brake rotor on the rider's left, drilled, with a floating carrier.
	local rotorX = -(width * 0.5 + 0.1)
	bolt(newPart(model, name .. "Rotor", Vector3.new(0.08, radius * 1.42, radius * 1.42), wheelCF * CFrame.new(rotorX, 0, 0), C.Silver, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
		reflectance = 0.25,
	}))
	bolt(newPart(model, name .. "RotorCarrier", Vector3.new(0.1, radius * 0.62, radius * 0.62), wheelCF * CFrame.new(rotorX, 0, 0), C.Gold, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
	}))
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		bolt(newPart(
			model,
			name .. "RotorHole" .. i,
			Vector3.new(0.12, 0.2, 0.2),
			wheelCF * CFrame.new(rotorX, 0, 0) * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius * 0.55, 0),
			C.Component,
			{ shape = Enum.PartType.Cylinder }
		))
	end

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

	local function tubePart(host: BasePart, name: string, from: Vector3, to: Vector3, thickness: number, color: Color3, material: Enum.Material?): Part
		local cf, length = tube(from, to)
		local p = newPart(model, name, Vector3.new(thickness, thickness, length), baseCF * cf, color, {
			material = material or Enum.Material.Metal,
		})
		weld(host, p)
		return p
	end

	----------------------------------------------------------------------------
	-- chassis
	----------------------------------------------------------------------------

	local chassis = newPart(model, "Chassis", G.ChassisSize, baseCF * CFrame.new(G.ChassisCentre), C.Frame, {
		collide = true,
		massless = false,
		transparency = 1,
		physical = CHASSIS_PROPS,
	})
	model.PrimaryPart = chassis

	local function onFrame(p: Part): Part
		weld(chassis, p)
		return p
	end

	-- Battery pack: the big swappable box that fills the frame triangle.
	onFrame(newPart(model, "BatteryBox", Vector3.new(1.42, 2.05, 2.45), L(0, 2.45, 0.35), C.Component, {
		material = Enum.Material.Metal,
	}))
	onFrame(newPart(model, "BatteryTrim", Vector3.new(1.48, 0.2, 2.5), L(0, 1.50, 0.35), C.Frame, {
		material = Enum.Material.Metal,
	}))
	onFrame(newPart(model, "BatteryTop", Vector3.new(1.44, 0.42, 1.0), L(0, 3.30, 0.30), C.DarkMetal, {
		material = Enum.Material.DiamondPlate,
	}))
	onFrame(newPart(model, "ChargePort", Vector3.new(0.3, 0.3, 0.22), L(0.72, 2.9, 1.35), C.Frame, {
		material = Enum.Material.Metal,
	}))
	-- Cooling fins down each flank of the pack.
	for i = 0, 4 do
		for _, side in { -1, 1 } do
			onFrame(newPart(
				model,
				"BatteryFin" .. i .. (side < 0 and "L" or "R"),
				Vector3.new(0.06, 1.3, 0.16),
				L(side * 0.74, 2.35, -0.55 + i * 0.44),
				C.DarkMetal,
				{ material = Enum.Material.Metal }
			))
		end
	end

	-- Frame: twin-spar tubes in the frame colour.
	tubePart(chassis, "TopTube", G.SteerHead, Vector3.new(0, 3.55, -0.30), 0.34, C.Frame)
	tubePart(chassis, "TopTubeRear", Vector3.new(0, 3.55, -0.30), Vector3.new(0, 3.52, 0.95), 0.30, C.Frame)
	tubePart(chassis, "DownTube", Vector3.new(0, 2.40, -2.60), Vector3.new(0, 1.72, -0.55), 0.36, C.Frame)
	tubePart(chassis, "CradleTube", Vector3.new(0, 1.72, -0.55), Vector3.new(0, 1.80, 1.00), 0.32, C.Frame)
	tubePart(chassis, "HeadGusset", G.SteerHead, Vector3.new(0, 2.40, -2.60), 0.44, C.Frame)
	tubePart(chassis, "HeadStay", Vector3.new(0, 3.20, -2.75), Vector3.new(0, 2.55, -2.10), 0.24, C.Frame)

	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		tubePart(chassis, "Subframe" .. tag, Vector3.new(side * 0.42, 3.50, -0.10), Vector3.new(side * 0.40, 3.62, 2.70), 0.26, C.Frame)
		tubePart(chassis, "SubBrace" .. tag, Vector3.new(side * 0.44, 2.30, 1.05), Vector3.new(side * 0.40, 3.55, 1.90), 0.22, C.Frame)
		tubePart(chassis, "PegMount" .. tag, Vector3.new(side * 0.42, 1.90, 0.85), Vector3.new(side * 0.92, 1.95, 0.85), 0.26, C.FrameDark)

		-- Swingarm: tapered box-section arm with a chain slider and adjuster.
		tubePart(chassis, "Swingarm" .. tag, Vector3.new(side * 0.55, 2.05, 0.95), Vector3.new(side * 0.62, 1.55, 3.20), 0.38, C.Silver)
		tubePart(chassis, "SwingBrace" .. tag, Vector3.new(side * 0.55, 2.05, 1.15), Vector3.new(side * 0.60, 1.72, 2.30), 0.20, C.Silver)
		onFrame(newPart(model, "AxleAdjuster" .. tag, Vector3.new(0.16, 0.5, 0.7), L(side * 0.62, 1.55, 3.18), C.DarkMetal, {
			material = Enum.Material.Metal,
		}))
	end
	onFrame(newPart(model, "SwingPivot", Vector3.new(1.5, 0.4, 0.4), L(0, 2.05, 0.95), C.DarkMetal, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
	}))
	onFrame(newPart(model, "ChainSlider", Vector3.new(0.2, 0.22, 1.5), L(0.66, 2.02, 1.55), C.Component))

	-- Rear monoshock with a visible coil spring.
	local shockTop = Vector3.new(0, 3.30, 1.05)
	local shockBottom = Vector3.new(0, 1.95, 2.20)
	local shockCF, shockLen = tube(shockTop, shockBottom)
	onFrame(newPart(model, "ShockBody", Vector3.new(0.34, 0.34, shockLen), baseCF * shockCF, C.DarkMetal, {
		material = Enum.Material.Metal,
	}))
	onFrame(newPart(model, "ShockReservoir", Vector3.new(0.28, 0.28, 0.7), baseCF * tube(Vector3.new(0.3, 3.05, 1.35), Vector3.new(0.3, 2.65, 1.70)), C.Gold, {
		material = Enum.Material.Metal,
	}))

	local springFrame, springLen = axisFrame(shockTop, shockBottom)
	for i = 0, G.SpringCoils do
		local t = i / G.SpringCoils
		local a = t * math.pi * 2 * 4.5
		onFrame(newPart(
			model,
			"SpringCoil" .. i,
			Vector3.new(0.16, 0.16, 0.16),
			baseCF * springFrame * CFrame.new(math.cos(a) * 0.26, math.sin(a) * 0.26, -t * springLen),
			C.Accent,
			{ shape = Enum.PartType.Ball, material = Enum.Material.Metal }
		))
	end

	-- Mid-mounted motor with cooling fins.
	onFrame(newPart(model, "MotorCase", Vector3.new(1.0, 1.45, 1.45), L(0, 1.95, 0.55), C.DarkMetal, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
		reflectance = 0.1,
	}))
	for i = 0, 4 do
		onFrame(newPart(model, "MotorFin" .. i, Vector3.new(0.07, 1.6, 1.6), L(-0.4 + i * 0.2, 1.95, 0.55), C.Silver, {
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Metal,
		}))
	end
	onFrame(newPart(model, "MotorCover", Vector3.new(0.18, 1.0, 1.0), L(-0.56, 1.95, 0.55), C.Component, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
	}))
	onFrame(newPart(model, "Controller", Vector3.new(0.9, 0.6, 0.5), L(0, 1.62, 1.55), C.Component, {
		material = Enum.Material.Metal,
	}))

	-- Chain: front sprocket on the motor, rear sprocket on the wheel.
	local frontSprocketR = 0.40
	local rearSprocketR = 0.85
	local chainX = 0.66
	onFrame(newPart(model, "FrontSprocket", Vector3.new(0.14, frontSprocketR * 2, frontSprocketR * 2), L(chainX, 1.95, 0.55), C.Silver, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
	}))

	local runs = {
		{ Vector3.new(chainX, 1.95 + frontSprocketR, 0.55), Vector3.new(chainX, 1.55 + rearSprocketR, 3.20) },
		{ Vector3.new(chainX, 1.95 - frontSprocketR, 0.55), Vector3.new(chainX, 1.55 - rearSprocketR, 3.20) },
	}
	for r, run in runs do
		local runFrame, runLen = axisFrame(run[1], run[2])
		for i = 0, G.ChainLinks do
			onFrame(newPart(
				model,
				"ChainLink" .. r .. "_" .. i,
				Vector3.new(0.1, 0.2, 0.16),
				baseCF * runFrame * CFrame.new(0, 0, -(i / G.ChainLinks) * runLen),
				C.DarkMetal,
				{ material = Enum.Material.Metal, reflectance = 0.2 }
			))
		end
	end
	onFrame(newPart(model, "ChainGuard", Vector3.new(0.12, 0.42, 2.2), L(chainX + 0.14, 2.42, 1.9), C.Component, {
		material = Enum.Material.Metal,
	}))

	-- Rear brake.
	onFrame(newPart(model, "RearCaliper", Vector3.new(0.24, 0.46, 0.6), L(-0.62, 1.95, 3.10), C.Accent, {
		material = Enum.Material.Metal,
	}))
	tubePart(chassis, "RearBrakeLine", Vector3.new(-0.55, 2.05, 2.9), Vector3.new(-0.5, 2.4, 1.2), 0.08, C.Component)

	-- Footpegs, serrated.
	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		onFrame(newPart(model, "Footpeg" .. tag, Vector3.new(0.95, 0.14, 0.34), L(side * 1.05, 1.95, 0.85), C.Silver, {
			material = Enum.Material.DiamondPlate,
		}))
		for i = 0, 3 do
			onFrame(newPart(model, "PegTooth" .. tag .. i, Vector3.new(0.12, 0.1, 0.4), L(side * (0.72 + i * 0.22), 2.02, 0.85), C.Silver, {
				material = Enum.Material.Metal,
			}))
		end

		-- Side panel with the model name on it.
		local plate = onFrame(newPart(model, "SidePlate" .. tag, Vector3.new(0.1, 1.1, 1.45), L(side * 0.80, 2.88, 0.95), C.Frame))

		local plateGui = Instance.new("SurfaceGui")
		plateGui.Face = side < 0 and Enum.NormalId.Left or Enum.NormalId.Right
		plateGui.CanvasSize = Vector2.new(290, 220)
		plateGui.LightInfluence = 0
		plateGui.Parent = plate

		local plateLabel = Instance.new("TextLabel")
		plateLabel.Size = UDim2.fromScale(1, 1)
		plateLabel.BackgroundTransparency = 1
		plateLabel.Font = Enum.Font.GothamBlack
		plateLabel.Text = "E RIDE\nPRO"
		plateLabel.TextColor3 = Color3.new(1, 1, 1)
		plateLabel.TextScaled = true
		plateLabel.Parent = plateGui
	end

	-- Seat: tapered pad with a grippy top and a rear hump.
	onFrame(newPart(model, "SeatBase", Vector3.new(1.2, 0.3, 3.0), L(0, 3.62, 1.05) * CFrame.Angles(math.rad(-3), 0, 0), C.Component, {
		material = Enum.Material.Metal,
	}))
	onFrame(newPart(model, "SeatPad", Vector3.new(1.14, 0.28, 2.9), L(0, 3.84, 1.05) * CFrame.Angles(math.rad(-3), 0, 0), C.Component, {
		material = Enum.Material.Fabric,
	}))
	onFrame(newPart(model, "SeatNose", Vector3.new(0.9, 0.24, 0.8), L(0, 3.78, -0.35) * CFrame.Angles(math.rad(-9), 0, 0), C.Component, {
		material = Enum.Material.Fabric,
	}))
	onFrame(newPart(model, "SeatHump", Vector3.new(1.05, 0.3, 0.8), L(0, 4.0, 2.3) * CFrame.Angles(math.rad(-14), 0, 0), C.Component, {
		material = Enum.Material.Fabric,
	}))

	-- Tail.
	onFrame(newPart(model, "RearFender", Vector3.new(1.15, 0.2, 2.0), L(0, 3.98, 2.75) * CFrame.Angles(math.rad(-12), 0, 0), C.Frame))
	onFrame(newPart(model, "Taillight", Vector3.new(0.48, 0.22, 0.14), L(0, 3.92, 3.60), C.Taillight, {
		material = Enum.Material.Neon,
	}))
	tubePart(chassis, "TailTidy", Vector3.new(0, 3.70, 3.15), Vector3.new(0, 3.35, 3.45), 0.14, C.Component)

	-- Kickstand, folded up along the swingarm.
	tubePart(chassis, "Kickstand", Vector3.new(-0.62, 1.95, 1.25), Vector3.new(-0.72, 1.60, 2.35), 0.16, C.Component)

	----------------------------------------------------------------------------
	-- steering column (everything that turns with the bars)
	----------------------------------------------------------------------------

	local column = newPart(model, "SteerColumn", Vector3.new(0.42, 1.6, 0.42), L(0, 3.42, -2.87) * raked, C.DarkMetal, {
		massless = false,
		material = Enum.Material.Metal,
		physical = COLUMN_PROPS,
	})

	local function onColumn(p: Part): Part
		weld(column, p)
		return p
	end

	local function columnTube(name: string, from: Vector3, to: Vector3, thickness: number, color: Color3): Part
		local cf, length = tube(from, to)
		local p = newPart(model, name, Vector3.new(thickness, thickness, length), baseCF * cf, color, {
			material = Enum.Material.Metal,
		})
		weld(column, p)
		return p
	end

	onColumn(newPart(model, "TripleClampTop", Vector3.new(1.05, 0.24, 0.58), L(0, 3.90, -2.69) * raked, C.Silver, {
		material = Enum.Material.Metal,
		reflectance = 0.15,
	}))
	onColumn(newPart(model, "TripleClampBottom", Vector3.new(1.05, 0.24, 0.58), L(0, 3.08, -3.09) * raked, C.Silver, {
		material = Enum.Material.Metal,
		reflectance = 0.15,
	}))
	onColumn(newPart(model, "SteerNut", Vector3.new(0.3, 0.18, 0.3), L(0, 4.02, -2.63) * raked, C.Gold, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Metal,
	}))

	-- Upside-down forks: black lowers, gold stanchions, rubber boots.
	local axle = G.FrontAxle
	local forkDir = Vector3.new(0, math.cos(rake), math.sin(rake))
	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		local bottom = Vector3.new(side * 0.46, axle.Y, axle.Z)
		local seal = bottom + forkDir * 1.30
		local top = bottom + forkDir * 2.48

		columnTube("ForkLower" .. tag, bottom, seal, 0.40, C.Component)
		columnTube("ForkStanchion" .. tag, seal, top, 0.30, C.Gold)

		local sealCF = baseCF * CFrame.new(seal) * CFrame.Angles(rake, 0, 0)
		onColumn(newPart(model, "ForkSeal" .. tag, Vector3.new(0.44, 0.16, 0.44), sealCF, C.Component, {
			material = Enum.Material.Metal,
		}))
		-- Accordion dust boot above the seal.
		for i = 1, 3 do
			onColumn(newPart(
				model,
				"ForkBoot" .. tag .. i,
				Vector3.new(0.38, 0.1, 0.38),
				baseCF * CFrame.new(seal + forkDir * (0.18 * i)) * CFrame.Angles(rake, 0, 0),
				C.Component
			))
		end
		-- Axle clamp at the fork foot.
		onColumn(newPart(model, "AxleClamp" .. tag, Vector3.new(0.34, 0.5, 0.5), baseCF * CFrame.new(bottom), C.Component, {
			material = Enum.Material.Metal,
		}))
	end

	onColumn(newPart(model, "FrontCaliper", Vector3.new(0.26, 0.5, 0.72), L(-0.6, 2.35, -3.5), C.Accent, {
		material = Enum.Material.Metal,
	}))
	columnTube("FrontBrakeLine", Vector3.new(-0.55, 2.6, -3.42), Vector3.new(-0.5, 3.95, -2.85), 0.08, C.Component)
	columnTube("ForkBrace", Vector3.new(-0.46, 2.95, -3.2), Vector3.new(0.46, 2.95, -3.2), 0.18, C.Silver)

	-- Bars, controls and dash.
	onColumn(newPart(model, "BarRiser", Vector3.new(0.75, 0.44, 0.32), L(0, 4.12, -2.62) * raked, C.Silver, {
		material = Enum.Material.Metal,
	}))
	onColumn(newPart(model, "Handlebar", Vector3.new(3.6, 0.2, 0.2), L(0, 4.36, -2.54), C.Component, {
		material = Enum.Material.Metal,
	}))
	onColumn(newPart(model, "BarPad", Vector3.new(1.1, 0.34, 0.34), L(0, 4.36, -2.54), C.Frame))

	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		onColumn(newPart(model, "Grip" .. tag, Vector3.new(0.86, 0.26, 0.26), L(side * 1.44, 4.36, -2.54), C.Component))
		for i = 0, 3 do
			onColumn(newPart(model, "GripRib" .. tag .. i, Vector3.new(0.08, 0.3, 0.3), L(side * (1.16 + i * 0.19), 4.36, -2.54), C.Component, {
				shape = Enum.PartType.Cylinder,
			}))
		end
		onColumn(newPart(model, "BarEnd" .. tag, Vector3.new(0.14, 0.3, 0.3), L(side * 1.88, 4.36, -2.54), C.Gold, {
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Metal,
		}))
		onColumn(newPart(model, "Lever" .. tag, Vector3.new(0.74, 0.08, 0.12), L(side * 1.02, 4.28, -2.76), C.Silver, {
			material = Enum.Material.Metal,
			reflectance = 0.2,
		}))
		onColumn(newPart(model, "Perch" .. tag, Vector3.new(0.22, 0.24, 0.24), L(side * 0.96, 4.36, -2.58), C.Component, {
			material = Enum.Material.Metal,
		}))
	end

	local dash = onColumn(newPart(model, "DashScreen", Vector3.new(0.9, 0.55, 0.12), L(0, 4.42, -2.86) * CFrame.Angles(math.rad(38), 0, 0), C.Screen, {
		material = Enum.Material.SmoothPlastic,
	}))
	local dashGui = Instance.new("SurfaceGui")
	dashGui.Name = "Display"
	dashGui.Face = Enum.NormalId.Front
	dashGui.CanvasSize = Vector2.new(220, 140)
	dashGui.LightInfluence = 0
	dashGui.Parent = dash

	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.Size = UDim2.fromScale(1, 1)
	readout.BackgroundTransparency = 1
	readout.Font = Enum.Font.Code
	readout.Text = "0\nKM/H"
	readout.TextColor3 = Color3.fromRGB(120, 255, 210)
	readout.TextScaled = true
	readout.Parent = dashGui

	-- Front plate, fender and light.
	onColumn(newPart(model, "NumberPlate", Vector3.new(1.45, 1.3, 0.12), L(0, 3.58, -3.36) * raked, C.Frame))
	onColumn(newPart(model, "PlateTrim", Vector3.new(1.5, 0.16, 0.14), L(0, 4.14, -3.09) * raked, C.Plate))
	onColumn(newPart(model, "HeadlightShell", Vector3.new(1.0, 0.6, 0.26), L(0, 3.96, -3.22) * raked, C.Component, {
		material = Enum.Material.Metal,
	}))
	onColumn(newPart(model, "Headlight", Vector3.new(0.84, 0.42, 0.16), L(0, 3.96, -3.34) * raked, C.Headlight, {
		material = Enum.Material.Neon,
	}))
	onColumn(newPart(model, "FrontFender", Vector3.new(1.2, 0.18, 2.0), L(0, 3.06, -3.78) * CFrame.Angles(math.rad(12), 0, 0), C.Frame))
	onColumn(newPart(model, "FenderStay", Vector3.new(0.9, 0.12, 0.5), L(0, 3.02, -3.24), C.Frame))

	----------------------------------------------------------------------------
	-- wheels + joints
	----------------------------------------------------------------------------

	local frontWheel = buildWheel(model, "FrontWheel", G.FrontAxle, G.FrontRadius, G.FrontWidth, baseCF)
	local rearWheel = buildWheel(model, "RearWheel", G.RearAxle, G.RearRadius, G.RearWidth, baseCF)

	local sprocket = newPart(
		model,
		"RearSprocket",
		Vector3.new(0.14, rearSprocketR * 2, rearSprocketR * 2),
		baseCF * CFrame.new(G.RearAxle) * CFrame.new(chainX, 0, 0),
		C.Gold,
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Metal }
	)
	weld(rearWheel, sprocket)

	-- Parts joined by constraints still collide, so the three colliding
	-- bodies are told explicitly not to touch each other.
	noCollide(chassis, frontWheel)
	noCollide(chassis, rearWheel)
	noCollide(frontWheel, rearWheel)

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
	seat.CFrame = L(0, 3.98, 1.05)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- legacy Motor driving is unused; the scripts drive the hinge
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model
	weld(chassis, seat)

	-- The frame colour is used only by frame parts, so one pass tags them all
	-- as repaintable rather than threading an option through every call.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") == nil and part.Color == C.Frame then
			part:SetAttribute("Paint", "Frame")
		end
	end

	local engine = Instance.new("Sound")
	engine.Name = "Engine"
	engine.SoundId = Config.Audio.EngineSoundId
	engine.Looped = true
	engine.Volume = 0
	engine.RollOffMaxDistance = 220
	engine.RollOffMinDistance = 12
	engine.Parent = chassis

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
