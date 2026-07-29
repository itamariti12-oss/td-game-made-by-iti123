--!strict
-- BikeServer
-- Owns the world, the single beta bike, who is riding it, and what happens
-- when they bin it. The riding client simulates the bike (it gets network
-- ownership), so this script only takes the wheel while the bike is parked
-- or crashed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BikeConfig"))
local BikeBuilder = require(ReplicatedStorage:WaitForChild("BikeBuilder"))
local WorldBuilder = require(ReplicatedStorage:WaitForChild("WorldBuilder"))
local Ragdoll = require(ReplicatedStorage:WaitForChild("Ragdoll"))

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
local setStance = ensureRemote("SetStance") -- driver -> server, which trick they are holding
local stanceChanged = ensureRemote("StanceChanged") -- server -> everyone
local crashBike = ensureRemote("CrashBike")
local crashed = ensureRemote("Crashed")
local paintBike = ensureRemote("PaintBike")

--------------------------------------------------------------------------------
-- world
--------------------------------------------------------------------------------

WorldBuilder.Build(workspace)

local existingSpawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
if existingSpawn then
	existingSpawn.Position = Vector3.new(0, 1.2, 62)
else
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "SpawnPad"
	spawnPad.Size = Vector3.new(14, 1, 14)
	spawnPad.Position = Vector3.new(0, 1.2, 62)
	spawnPad.Anchored = true
	spawnPad.Color = Color3.fromRGB(118, 118, 121)
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Parent = workspace
end

--------------------------------------------------------------------------------
-- the bike
--------------------------------------------------------------------------------

local validTricks: { [string]: boolean } = {}
for _, trick in Config.Tricks do
	validTricks[trick.Id] = true
end

local bike: Model
local chassis: Part
local seat: VehicleSeat
local stabilizer: AlignOrientation
local rearHinge: HingeConstraint
local steerHinge: HingeConstraint

local currentDriver: Player? = nil
local crashing = false

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
	stabilizer.MaxTorque = Config.Handling.StabilizerTorque
	rearHinge.AngularVelocity = 0
	steerHinge.TargetAngle = 0
end

local function resetToSpawn()
	local driver = currentDriver
	setNetworkOwner(nil)
	parkPose()
	if driver then
		task.delay(0.2, function()
			if currentDriver == driver then
				setNetworkOwner(driver)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- crashing
--------------------------------------------------------------------------------

local function doCrash(reason: string)
	if crashing then
		return
	end

	local occupant = seat.Occupant
	local character = occupant and occupant.Parent :: Model?
	local rider = currentDriver
	if not (occupant and character and rider) then
		return
	end

	crashing = true

	-- Throw the rider off. Breaking the seat weld first stops the humanoid
	-- being dragged along by the bike as it tumbles.
	local launch = chassis.AssemblyLinearVelocity
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	occupant.Sit = false

	Ragdoll.Enable(character)

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local up = Vector3.new(0, Config.Crash.EjectImpulse, 0)
		local spin = chassis.CFrame.LookVector * (reason == "LoopOut" and -18 or 22)
		root:ApplyImpulse((launch * 0.6 + up + spin) * root.AssemblyMass)
	end

	-- Let the bike tumble on its own instead of snapping back upright.
	stabilizer.MaxTorque = 0
	setNetworkOwner(nil)

	stanceChanged:FireAllClients(rider, nil)
	crashed:FireAllClients(rider, reason)

	task.delay(Config.Crash.RagdollTime, function()
		if character.Parent then
			Ragdoll.Disable(character)
		end
		parkPose()
		crashing = false
	end)
end

--------------------------------------------------------------------------------
-- mounting
--------------------------------------------------------------------------------

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
		stanceChanged:FireAllClients(previous, nil)
	end

	-- The ride prompt also lives on E, so it has to get out of the way while
	-- someone is aboard or it would fight the stand-up trick.
	local prompt = seat:FindFirstChild("RidePrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = player == nil
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
	crashing = false

	seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)

	local prompt = seat:FindFirstChild("RidePrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(player)
		if seat.Occupant or crashing then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not Ragdoll.IsRagdolled(character :: Model) then
			seat:Sit(humanoid)
		end
	end)

	driverChanged:FireAllClients(bike, nil)
end

spawnBike()

--------------------------------------------------------------------------------
-- customisation
--------------------------------------------------------------------------------

local paintState = { frame = 1, rim = 1, tyre = 1 }

local function applyPaint()
	local frameColor = Config.Paint.Frame[paintState.frame].Color
	local rimColor = Config.Paint.Rim[paintState.rim].Color
	local street = Config.Paint.Tyre[paintState.tyre] == "Street"

	for _, part in bike:GetDescendants() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("Paint")
			if role == "Frame" then
				part.Color = frameColor
			elseif role == "Rim" then
				part.Color = rimColor
			elseif role == "Knob" then
				-- The street tyre is the same carcass with the tread hidden.
				part.Transparency = street and 1 or 0
			end
		end
	end
end

paintBike.OnServerEvent:Connect(function(player, frameIndex, rimIndex, tyreIndex)
	if typeof(frameIndex) ~= "number" or typeof(rimIndex) ~= "number" or typeof(tyreIndex) ~= "number" then
		return
	end
	-- Only ever index into the palette, so a crafted message cannot set an
	-- arbitrary colour or property.
	local frame = math.clamp(math.floor(frameIndex), 1, #Config.Paint.Frame)
	local rim = math.clamp(math.floor(rimIndex), 1, #Config.Paint.Rim)
	local tyre = math.clamp(math.floor(tyreIndex), 1, #Config.Paint.Tyre)

	paintState.frame, paintState.rim, paintState.tyre = frame, rim, tyre
	applyPaint()
end)

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

	if currentDriver ~= nil and currentDriver ~= player then
		return
	end
	resetToSpawn()
end)

crashBike.OnServerEvent:Connect(function(player, reason)
	if player ~= currentDriver or typeof(reason) ~= "string" then
		return
	end
	doCrash(reason)
end)

setStance.OnServerEvent:Connect(function(player, trick)
	if player ~= currentDriver then
		return
	end
	-- nil means "back to the plain seated pose"; anything else has to name a
	-- trick that actually exists.
	if trick ~= nil and (typeof(trick) ~= "string" or not validTricks[trick]) then
		return
	end
	stanceChanged:FireAllClients(player, trick)
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
	-- client takes over these three properties -- and while it is crashing,
	-- nobody does, so it can tumble.
	if seat.Occupant or crashing then
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
