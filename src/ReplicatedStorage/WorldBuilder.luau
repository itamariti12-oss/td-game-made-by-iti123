--!strict
-- WorldBuilder
-- The street map, built at runtime like everything else.
--
-- Layout: one long avenue running away from spawn to wheelie down, cross
-- streets, kerbed pavements, blocks of buildings either side, and ramps
-- scattered along the route so the jumps survive the move into town.
--
-- Ramps are described by the two ends of their riding surface, and the solid
-- is derived from that: a slab thick enough that its underside is buried below
-- the road at both ends. That way the leading edge is always sunk into the
-- ground and a wheel can never catch on a lip.

local Config = require(script.Parent.BikeConfig)

local WorldBuilder = {}

local ROAD = Color3.fromRGB(58, 59, 63)
local PAVEMENT = Color3.fromRGB(146, 147, 150)
local KERB = Color3.fromRGB(178, 179, 182)
local LINE = Color3.fromRGB(226, 222, 190)
local RAMP_COLOR = Color3.fromRGB(70, 72, 78)

local BUILDING_COLORS = {
	Color3.fromRGB(96, 88, 82),
	Color3.fromRGB(118, 112, 104),
	Color3.fromRGB(78, 84, 92),
	Color3.fromRGB(134, 118, 106),
	Color3.fromRGB(88, 94, 88),
}

local AVENUE_HALF = 22 -- half width of the main road
local PAVEMENT_W = 10
local KERB_H = 0.6

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
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

--------------------------------------------------------------------------------
-- ramps
--------------------------------------------------------------------------------

-- `low` and `high` are the two ends of the riding surface, on the ground and
-- at the top of the ramp respectively.
local function ramp(parent: Instance, name: string, low: Vector3, high: Vector3, width: number)
	local delta = high - low
	local run = delta.Magnitude
	if run < 0.1 then
		return
	end

	local dir = delta.Unit
	local side = Vector3.new(dir.Z, 0, -dir.X)
	if side.Magnitude < 1e-3 then
		side = Vector3.new(1, 0, 0)
	end
	side = side.Unit

	-- side:Cross(dir) always comes out pointing down for a horizontal `side`,
	-- so the flip below is guaranteed -- which leaves the frame's local +Z
	-- running toward the high end of the slope.
	local normal = side:Cross(dir).Unit
	if normal.Y < 0 then
		normal = -normal
	end

	-- Thick enough that the underside is below y = 0 at the high end too,
	-- so the ramp reads as solid and its toe is buried.
	local thickness = (high.Y - low.Y) / math.max(normal.Y, 0.2) + 2
	local centre = (low + high) * 0.5 - normal * (thickness * 0.5)
	local cf = CFrame.fromMatrix(centre, side, normal)

	part(parent, name, Vector3.new(width, thickness, run), cf, RAMP_COLOR, Enum.Material.Concrete)

	for _, s in { -1, 1 } do
		part(
			parent,
			name .. "Stripe" .. (s < 0 and "L" or "R"),
			Vector3.new(0.9, 0.14, run),
			cf * CFrame.new(s * (width * 0.5 - 0.45), thickness * 0.5, 0),
			Config.Colors.Frame
		)
	end

	part(
		parent,
		name .. "Lip",
		Vector3.new(width, 0.14, 0.7),
		cf * CFrame.new(0, thickness * 0.5, run * 0.5 - 0.35),
		Config.Colors.Frame
	)
end

local function tableTop(parent: Instance, name: string, x: number, centreZ: number, width: number, height: number, deck: number, approach: number)
	ramp(parent, name .. "Up", Vector3.new(x, 0, centreZ + deck * 0.5 + approach), Vector3.new(x, height, centreZ + deck * 0.5), width)
	part(parent, name .. "Deck", Vector3.new(width, height, deck), CFrame.new(x, height * 0.5, centreZ), RAMP_COLOR, Enum.Material.Concrete)
	ramp(parent, name .. "Down", Vector3.new(x, 0, centreZ - deck * 0.5 - approach), Vector3.new(x, height, centreZ - deck * 0.5), width)
end

--------------------------------------------------------------------------------
-- street furniture
--------------------------------------------------------------------------------

local function building(parent: Instance, name: string, x: number, z: number, w: number, d: number, h: number, color: Color3)
	part(parent, name, Vector3.new(w, h, d), CFrame.new(x, h * 0.5, z), color, Enum.Material.Brick)

	-- Window bands, inset a touch so they read as glass rather than paint.
	local floors = math.max(1, math.floor(h / 12))
	for i = 1, floors do
		local y = (i / (floors + 1)) * h
		part(parent, name .. "Glass" .. i, Vector3.new(w + 0.2, 3.2, d * 0.86), CFrame.new(x, y, z), Color3.fromRGB(58, 74, 88), Enum.Material.Glass)
		part(parent, name .. "Glass" .. i .. "B", Vector3.new(w * 0.86, 3.2, d + 0.2), CFrame.new(x, y, z), Color3.fromRGB(58, 74, 88), Enum.Material.Glass)
	end

	part(parent, name .. "Parapet", Vector3.new(w + 1.2, 1.4, d + 1.2), CFrame.new(x, h + 0.7, z), color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Concrete)
end

local function lamp(parent: Instance, name: string, x: number, z: number, facing: number)
	part(parent, name .. "Post", Vector3.new(0.5, 16, 0.5), CFrame.new(x, 8, z), Color3.fromRGB(48, 50, 54), Enum.Material.Metal)
	part(parent, name .. "Arm", Vector3.new(3.4, 0.4, 0.4), CFrame.new(x + facing * 1.7, 15.8, z), Color3.fromRGB(48, 50, 54), Enum.Material.Metal)
	local head = part(parent, name .. "Head", Vector3.new(2.2, 0.5, 1.0), CFrame.new(x + facing * 3.2, 15.5, z), Color3.fromRGB(255, 236, 190), Enum.Material.Neon)
	head.CanCollide = false

	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 34
	light.Angle = 110
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(255, 238, 200)
	light.Parent = head
end

--------------------------------------------------------------------------------
-- build
--------------------------------------------------------------------------------

function WorldBuilder.Build(parent: Instance): Folder
	-- Clear anything from a previous build, plus the placeholder floor the
	-- place file ships so Studio's edit view is not empty.
	for _, name in { "City", "Course", "Floor" } do
		local existing = parent:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = parent

	local floorSize = Config.World.FloorSize
	part(city, "Ground", floorSize, CFrame.new(0, -floorSize.Y * 0.5, 0), Config.World.FloorColor, Enum.Material.Concrete)

	----------------------------------------------------------------------------
	-- roads
	----------------------------------------------------------------------------

	local avenueFrom, avenueTo = 120, -460
	local avenueLength = avenueFrom - avenueTo
	local avenueZ = (avenueFrom + avenueTo) * 0.5

	part(city, "Avenue", Vector3.new(AVENUE_HALF * 2, 0.4, avenueLength), CFrame.new(0, 0.2, avenueZ), ROAD, Enum.Material.Asphalt)

	-- Centre dashes.
	for z = avenueTo + 10, avenueFrom - 10, 20 do
		part(city, "Dash" .. z, Vector3.new(1.1, 0.12, 9), CFrame.new(0, 0.44, z), LINE)
	end
	-- Edge lines.
	for _, s in { -1, 1 } do
		part(city, "EdgeLine" .. (s < 0 and "L" or "R"), Vector3.new(0.7, 0.12, avenueLength), CFrame.new(s * (AVENUE_HALF - 2.5), 0.44, avenueZ), LINE)
	end

	-- Pavements and kerbs down both sides.
	for _, s in { -1, 1 } do
		local tag = s < 0 and "L" or "R"
		local kerbX = s * (AVENUE_HALF + 0.6)
		part(city, "Kerb" .. tag, Vector3.new(1.2, KERB_H + 0.4, avenueLength), CFrame.new(kerbX, (KERB_H + 0.4) * 0.5, avenueZ), KERB, Enum.Material.Concrete)
		part(
			city,
			"Pavement" .. tag,
			Vector3.new(PAVEMENT_W, KERB_H + 0.4, avenueLength),
			CFrame.new(s * (AVENUE_HALF + 1.2 + PAVEMENT_W * 0.5), (KERB_H + 0.4) * 0.5, avenueZ),
			PAVEMENT,
			Enum.Material.Concrete
		)
	end

	-- Cross streets.
	local crossZ = { 60, -60, -190, -330 }
	for i, z in crossZ do
		part(city, "Cross" .. i, Vector3.new(380, 0.4, 34), CFrame.new(0, 0.2, z), ROAD, Enum.Material.Asphalt)
		for x = -170, 170, 20 do
			part(city, "CrossDash" .. i .. "_" .. x, Vector3.new(9, 0.12, 1.1), CFrame.new(x, 0.44, z), LINE)
		end
	end

	----------------------------------------------------------------------------
	-- buildings
	----------------------------------------------------------------------------

	local plots = {
		{ z = 100, d = 46 },
		{ z = 20, d = 54 },
		{ z = -120, d = 78 },
		{ z = -250, d = 60 },
		{ z = -395, d = 66 },
	}
	local index = 0
	for _, plot in plots do
		for _, s in { -1, 1 } do
			index += 1
			local w = 44 + (index % 3) * 12
			local h = 34 + ((index * 17) % 5) * 16
			local x = s * (AVENUE_HALF + 1.2 + PAVEMENT_W + w * 0.5 + 2)
			building(city, "Block" .. index, x, plot.z, w, plot.d, h, BUILDING_COLORS[(index % #BUILDING_COLORS) + 1])
		end
	end

	-- Lamp posts alternating down the avenue.
	local lampIndex = 0
	for z = avenueFrom - 30, avenueTo + 30, -70 do
		lampIndex += 1
		local s = (lampIndex % 2 == 0) and 1 or -1
		lamp(city, "Lamp" .. lampIndex, s * (AVENUE_HALF + 3), z, -s)
	end

	----------------------------------------------------------------------------
	-- jumps, dotted along the route
	----------------------------------------------------------------------------

	-- A gentle one right off the spawn, to learn on.
	ramp(city, "StepUp", Vector3.new(0, 0, 96), Vector3.new(0, 2, 84), 38)

	-- Kickers down the avenue, getting bigger.
	ramp(city, "KickerSmall", Vector3.new(0, 0, 12), Vector3.new(0, 3.2, 0), 26)
	ramp(city, "KickerMedium", Vector3.new(0, 0, -100), Vector3.new(0, 5.5, -118), 28)
	tableTop(city, "TableTop", 0, -230, 30, 6.5, 22, 20)
	ramp(city, "KickerBig", Vector3.new(0, 0, -368), Vector3.new(0, 9.5, -392), 30)
	ramp(city, "BigLanding", Vector3.new(0, 0, -448), Vector3.new(0, 7, -423), 34)

	-- A steep launcher in the side lot off the second cross street.
	part(city, "Lot", Vector3.new(90, 0.4, 90), CFrame.new(-118, 0.2, -60), ROAD, Enum.Material.Asphalt)
	ramp(city, "Launcher", Vector3.new(-118, 0, -30), Vector3.new(-118, 11, -48), 22)

	-- A roller pair on the far pavement -- wheelie straight over both.
	ramp(city, "RollerUp", Vector3.new(118, 0, -160), Vector3.new(118, 2.5, -176), 26)
	ramp(city, "RollerDown", Vector3.new(118, 0, -208), Vector3.new(118, 2.5, -192), 26)
	part(city, "RollerLot", Vector3.new(60, 0.4, 120), CFrame.new(118, 0.2, -184), ROAD, Enum.Material.Asphalt)

	return city
end

return WorldBuilder
