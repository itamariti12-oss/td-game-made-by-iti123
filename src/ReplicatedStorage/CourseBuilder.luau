--!strict
-- CourseBuilder
-- The floor and the little jump course, built at runtime like the bike.
--
-- Ramps are described by the two ends of their riding surface, and the solid
-- is derived from that: a slab thick enough that its underside is buried below
-- the floor at both ends. That way the leading edge is always sunk into the
-- ground and a wheel can never catch on a lip.

local Config = require(script.Parent.BikeConfig)

local CourseBuilder = {}

local RAMP_COLOR = Color3.fromRGB(64, 66, 72)
local STRIPE_COLOR = Config.Colors.Frame

local function anchoredPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- `low` and `high` are the two ends of the riding surface, on the ground and
-- at the top of the ramp respectively.
local function ramp(parent: Instance, name: string, low: Vector3, high: Vector3, width: number)
	local delta = high - low
	local run = delta.Magnitude
	if run < 0.1 then
		return
	end

	local dir = delta.Unit
	-- Surface normal: perpendicular to the slope, in the vertical plane.
	local side = Vector3.new(dir.Z, 0, -dir.X)
	if side.Magnitude < 1e-3 then
		side = Vector3.new(1, 0, 0)
	end
	side = side.Unit
	local normal = side:Cross(dir).Unit
	if normal.Y < 0 then
		normal = -normal
	end

	-- Thick enough that the underside is below y = 0 at the high end too,
	-- so the ramp reads as solid and its toe is buried.
	local thickness = (high.Y - low.Y) / math.max(normal.Y, 0.2) + 2
	local centre = (low + high) * 0.5 - normal * (thickness * 0.5)

	local cf = CFrame.fromMatrix(centre, side, normal)
	anchoredPart(parent, name, Vector3.new(width, thickness, run), cf, RAMP_COLOR, Enum.Material.Concrete)

	-- Edge stripes so the take-off reads at speed.
	for _, s in { -1, 1 } do
		anchoredPart(
			parent,
			name .. "Stripe" .. (s < 0 and "L" or "R"),
			Vector3.new(0.9, 0.14, run),
			cf * CFrame.new(s * (width * 0.5 - 0.45), thickness * 0.5, 0),
			STRIPE_COLOR
		)
	end

	-- Lip marker across the take-off edge. `normal` is always flipped to point
	-- upward above, which leaves the frame's local +Z running toward the high
	-- end of the slope.
	anchoredPart(
		parent,
		name .. "Lip",
		Vector3.new(width, 0.14, 0.7),
		cf * CFrame.new(0, thickness * 0.5, run * 0.5 - 0.35),
		STRIPE_COLOR
	)
end

-- An up ramp, a flat deck, and a down ramp -- a table-top you can clear or roll.
local function tableTop(parent: Instance, name: string, centreZ: number, x: number, width: number, height: number, deck: number, approach: number)
	local upLow = Vector3.new(x, 0, centreZ + deck * 0.5 + approach)
	local upHigh = Vector3.new(x, height, centreZ + deck * 0.5)
	local downHigh = Vector3.new(x, height, centreZ - deck * 0.5)
	local downLow = Vector3.new(x, 0, centreZ - deck * 0.5 - approach)

	ramp(parent, name .. "Up", upLow, upHigh, width)
	anchoredPart(
		parent,
		name .. "Deck",
		Vector3.new(width, height, deck),
		CFrame.new(x, height * 0.5, centreZ),
		RAMP_COLOR,
		Enum.Material.Concrete
	)
	ramp(parent, name .. "Down", downLow, downHigh, width)
end

function CourseBuilder.Build(parent: Instance): Folder
	-- Clear anything from a previous build, plus the placeholder floor the
	-- place file ships so Studio's edit view is not empty.
	for _, name in { "Course", "Floor" } do
		local existing = parent:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local course = Instance.new("Folder")
	course.Name = "Course"
	course.Parent = parent

	local floorSize = Config.World.FloorSize
	anchoredPart(
		course,
		"Floor",
		floorSize,
		CFrame.new(0, -floorSize.Y * 0.5, 0),
		Config.World.FloorColor
	)

	-- A darker strip down the middle marks the main run.
	anchoredPart(course, "Lane", Vector3.new(34, 0.12, 700), CFrame.new(0, 0.06, -180), Color3.fromRGB(128, 128, 131))

	-- Main run, heading away from spawn (-Z), jumps getting bigger.
	ramp(course, "KickerSmall", Vector3.new(0, 0, -46), Vector3.new(0, 3, -58), 26)
	ramp(course, "KickerMedium", Vector3.new(0, 0, -96), Vector3.new(0, 5.5, -114), 28)
	tableTop(course, "TableTop", -180, 0, 30, 6.5, 22, 20)
	ramp(course, "KickerBig", Vector3.new(0, 0, -250), Vector3.new(0, 9.5, -274), 30)
	-- Landing ramp for the big kicker: slopes back down to the floor.
	ramp(course, "BigLanding", Vector3.new(0, 0, -330), Vector3.new(0, 7, -305), 34)

	-- A steep launcher off to one side for pure air.
	ramp(course, "Launcher", Vector3.new(-70, 0, -120), Vector3.new(-70, 11, -138), 22)

	-- A gentle roller you can wheelie straight over.
	ramp(course, "RollerUp", Vector3.new(70, 0, -80), Vector3.new(70, 2.5, -96), 26)
	ramp(course, "RollerDown", Vector3.new(70, 0, -128), Vector3.new(70, 2.5, -112), 26)

	-- A wide step-up nearer spawn, for a first attempt.
	ramp(course, "StepUp", Vector3.new(0, 0, 40), Vector3.new(0, 2, 30), 40)

	return course
end

return CourseBuilder
