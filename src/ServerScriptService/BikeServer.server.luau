--!strict
-- BikeServer
-- Owns the world, the single beta bike, and who is riding it.
-- The riding client simulates the bike (it gets network ownership), so this
-- script only steers things while the bike is parked.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BikeConfig"))
local BikeBuilder = require(ReplicatedStorage:WaitForChild("BikeBuilder"))
local CourseBuilder = require(ReplicatedStorage:WaitForChild("CourseBuilder"))

--------------------------------------------------------------------------------
-- remotes
--------------------------------------------------------------------------------

local remotes = ReplicatedStorage:FindFirstChild("BikeRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "BikeRemotes"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = remotes
	return ev
end

local driverChanged = ensureRemote("DriverChanged")
local resetBike = ensureRemote("ResetBike")
local setStance = ensureRemote("SetStance") -- driver -> server
local stanceChanged = ensureRemote("StanceChanged") -- server -> everyone

--------------------------------------------------------------------------------
-- world
--------------------------------------------------------------------------------

CourseBuilder.Build(workspace)

if not workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "SpawnPad"
	spawnPad.Size = Vector3.new(14, 1, 14)
	spawnPad.Position = Vector3.new(0, 0.5, 0)
	spawnPad.Anchored = true
	spawnPad.Color = Color3.fromRGB(118, 118, 121)
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Parent = workspace
end

--------------------------------------------------------------------------------
-- the bike
--------------------------------------------------------------------------------

local bike: Model
local chassis: Part
local seat: VehicleSeat
local stabilizer: AlignOrientation
local rearHinge: HingeConstraint
local steerHinge: HingeConstraint
local currentDriver: Player? = nil

local function setNetworkOwner(player: Player?)
	for _, part in bike:GetDescendants() do
		if part:IsA("BasePart") then
			pcall(function()
				part:SetNetworkOwner(player)
			end)
		end
	end
end

local function parkPose()
	for _, part in bike:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	bike:PivotTo(Config.SpawnCFrame)
	stabilizer.CFrame = Config.SpawnCFrame.Rotation
	rearHinge.AngularVelocity = 0
	steerHinge.TargetAngle = 0
end

local function resetToSpawn()
	local driver = currentDriver
	setNetworkOwner(nil)
	parkPose()
	if driver then
		-- Give control back once the server has settled the new pose.
		task.delay(0.2, function()
			if currentDriver == driver then
				setNetworkOwner(driver)
			end
		end)
	end
end

local function onOccupantChanged()
	local occupant = seat.Occupant
	local player: Player? = nil
	if occupant then
		local character = occupant.Parent
		if character then
			player = Players:GetPlayerFromCharacter(character)
		end
	end

	local previous = currentDriver
	currentDriver = player
	setNetworkOwner(player)

	if previous and previous ~= player then
		stanceChanged:FireAllClients(previous, false)
	end
	driverChanged:FireAllClients(bike, player)
end

local function spawnBike()
	if bike then
		bike:Destroy()
	end

	bike = BikeBuilder.Build(Config.SpawnCFrame)
	bike.Parent = workspace

	chassis = bike:FindFirstChild("Chassis") :: Part
	seat = bike:FindFirstChild("DriverSeat") :: VehicleSeat
	stabilizer = chassis:FindFirstChild("Stabilizer") :: AlignOrientation
	rearHinge = chassis:FindFirstChild("RearHinge") :: HingeConstraint
	steerHinge = chassis:FindFirstChild("SteerHinge") :: HingeConstraint

	currentDriver = nil

	seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)

	local prompt = seat:FindFirstChild("RidePrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(player)
		if seat.Occupant then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			seat:Sit(humanoid)
		end
	end)

	driverChanged:FireAllClients(bike, nil)
end

spawnBike()

--------------------------------------------------------------------------------
-- upkeep
--------------------------------------------------------------------------------

local resetDebounce: { [Player]: number } = {}

resetBike.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if (resetDebounce[player] or 0) > now then
		return
	end
	resetDebounce[player] = now + 1.5

	-- Only whoever is riding it (or anyone, if it is parked) may reset it.
	if currentDriver ~= nil and currentDriver ~= player then
		return
	end
	resetToSpawn()
end)

-- The driver tells the server when they stand up; the server relays it so
-- every client poses that rider's rig the same way.
setStance.OnServerEvent:Connect(function(player, standing)
	if player ~= currentDriver or typeof(standing) ~= "boolean" then
		return
	end
	stanceChanged:FireAllClients(player, standing)
end)

Players.PlayerRemoving:Connect(function(player)
	resetDebounce[player] = nil
	if currentDriver == player then
		currentDriver = nil
		setNetworkOwner(nil)
	end
end)

RunService.Heartbeat:Connect(function()
	if not chassis or not chassis.Parent then
		return
	end

	if chassis.Position.Y < Config.World.FallResetY then
		resetToSpawn()
		return
	end

	-- While nobody is riding, hold the bike upright so it never lies on its
	-- side waiting for the next player. Once someone mounts, the driving
	-- client takes over these three properties.
	if seat.Occupant then
		return
	end

	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	stabilizer.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	rearHinge.AngularVelocity = 0
	steerHinge.TargetAngle = 0
end)
