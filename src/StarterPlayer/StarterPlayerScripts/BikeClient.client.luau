--!strict
-- BikeClient
-- Runs on whoever is sitting on the bike. That client has network ownership of
-- the whole assembly, so driving it from here is smooth and lag free.
--
-- It also poses every rider's rig, including other players', because stance is
-- relayed through the server.
--
-- Controls
--   W / S or the mobile thumbstick .. throttle & brake
--   A / D or the mobile thumbstick .. steer
--   Q  or the WHEELIE button (hold) .. wheelie, and the rider stands up
--   R  or the JUMP button .. jump
--   T  or the RESET button .. put the bike back on the pad

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BikeConfig"))
local RiderPose = require(ReplicatedStorage:WaitForChild("RiderPose"))

local remotes = ReplicatedStorage:WaitForChild("BikeRemotes")
local driverChanged = remotes:WaitForChild("DriverChanged") :: RemoteEvent
local resetBike = remotes:WaitForChild("ResetBike") :: RemoteEvent
local setStance = remotes:WaitForChild("SetStance") :: RemoteEvent
local stanceChanged = remotes:WaitForChild("StanceChanged") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WHEELIE_ACTION = "ERideWheelie"
local JUMP_ACTION = "ERideJump"
local RESET_ACTION = "ERideReset"

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local driving = false
local bike: Model? = nil
local chassis: Part? = nil
local frontWheel: Part? = nil
local rearWheel: Part? = nil
local seat: VehicleSeat? = nil
local stabilizer: AlignOrientation? = nil
local rearHinge: HingeConstraint? = nil
local steerHinge: HingeConstraint? = nil
local readout: TextLabel? = nil

local wheelieHeld = false
local wheelieAngle = 0
local heading: number? = nil
local nextJump = 0
local standing = false
local touchInputs: { [Enum.UserInputType]: TextButton } = {}

-- Everyone we are currently posing, driver included.
local riders: { [Player]: boolean } = {}

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "WheelieHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local function roundify(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local meter = Instance.new("Frame")
meter.Name = "WheelieMeter"
meter.AnchorPoint = Vector2.new(0.5, 1)
meter.Position = UDim2.new(0.5, 0, 1, -34)
meter.Size = UDim2.new(0, 320, 0, 22)
meter.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
meter.BackgroundTransparency = 0.25
meter.BorderSizePixel = 0
meter.Parent = gui
roundify(meter, 11)

local meterFill = Instance.new("Frame")
meterFill.Name = "Fill"
meterFill.Size = UDim2.new(0, 0, 1, 0)
meterFill.BackgroundColor3 = Config.Colors.Frame
meterFill.BorderSizePixel = 0
meterFill.Parent = meter
roundify(meterFill, 11)

local meterLabel = Instance.new("TextLabel")
meterLabel.Size = UDim2.fromScale(1, 1)
meterLabel.BackgroundTransparency = 1
meterLabel.Font = Enum.Font.GothamBold
meterLabel.Text = "WHEELIE"
meterLabel.TextSize = 13
meterLabel.TextColor3 = Color3.new(1, 1, 1)
meterLabel.Parent = meter

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -62)
hint.Size = UDim2.new(0, 620, 0, 20)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "W/S  throttle     A/D  steer     Q  wheelie     R  jump     T  reset"
hint.TextSize = 14
hint.TextColor3 = Color3.fromRGB(235, 235, 238)
hint.TextTransparency = 0.15
hint.Visible = not UserInputService.TouchEnabled
hint.Parent = gui

local function makeButton(name: string, text: string, size: UDim2, position: UDim2, color: Color3, radius: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.12
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBlack
	button.Text = text
	button.TextSize = 18
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Visible = UserInputService.TouchEnabled
	button.Parent = gui
	roundify(button, radius)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Transparency = 0.55
	stroke.Parent = button

	return button
end

local wheelieButton = makeButton("Wheelie", "WHEELIE", UDim2.new(0, 132, 0, 132), UDim2.new(1, -24, 1, -24), Config.Colors.Frame, 66)
local jumpButton = makeButton("Jump", "JUMP", UDim2.new(0, 104, 0, 104), UDim2.new(1, -170, 1, -34), Config.Colors.Accent, 52)
local resetButton = makeButton("Reset", "RESET", UDim2.new(0, 104, 0, 42), UDim2.new(1, -38, 1, -170), Color3.fromRGB(32, 33, 36), 12)

local wheelieStroke = wheelieButton:FindFirstChildOfClass("UIStroke") :: UIStroke

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function setWheelie(held: boolean)
	wheelieHeld = held
	wheelieStroke.Transparency = held and 0.05 or 0.55
	wheelieButton.BackgroundTransparency = held and 0 or 0.12
end

local function tryJump()
	if not driving then
		return
	end
	local wheel = rearWheel
	local body = chassis
	if not (wheel and body) then
		return
	end

	local now = os.clock()
	if now < nextJump then
		return
	end

	-- Only launch off something solid.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bike :: Instance, player.Character :: Instance }
	local reach = Config.Geometry.RearRadius + Config.Jump.GroundCheck
	if not workspace:Raycast(wheel.Position, Vector3.new(0, -reach, 0), params) then
		return
	end

	nextJump = now + Config.Jump.Cooldown

	local forward = body.CFrame.LookVector
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude > 1e-3 then
		flat = flat.Unit
	else
		flat = Vector3.zero
	end
	local velocity = Vector3.new(0, Config.Jump.Power, 0) + flat * Config.Jump.ForwardBoost

	-- The wheels are their own assemblies, so each needs its own impulse or
	-- the hinges would drag them back down.
	for _, part in { body, wheel, frontWheel } do
		if part then
			part:ApplyImpulse(velocity * part.AssemblyMass)
		end
	end

	if jumpButton.Visible then
		jumpButton.BackgroundTransparency = 0
		task.delay(0.12, function()
			jumpButton.BackgroundTransparency = 0.12
		end)
	end
end

local function onWheelieAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setWheelie(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setWheelie(false)
	end
	return Enum.ContextActionResult.Sink
end

local function onJumpAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		tryJump()
	end
	return Enum.ContextActionResult.Sink
end

local function onResetAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		resetBike:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

-- Hold-to-wheelie on touch. Releases are caught globally so sliding a thumb
-- off the button still drops the wheelie instead of sticking it on.
wheelieButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		touchInputs[input.UserInputType] = wheelieButton
		setWheelie(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if touchInputs[input.UserInputType] == wheelieButton then
		touchInputs[input.UserInputType] = nil
		setWheelie(false)
	end
end)

jumpButton.Activated:Connect(tryJump)
resetButton.Activated:Connect(function()
	resetBike:FireServer()
end)

local function bindControls()
	ContextActionService:BindAction(WHEELIE_ACTION, onWheelieAction, false, Enum.KeyCode.Q)
	ContextActionService:BindAction(JUMP_ACTION, onJumpAction, false, Enum.KeyCode.R)
	ContextActionService:BindAction(RESET_ACTION, onResetAction, false, Enum.KeyCode.T)
end

local function unbindControls()
	ContextActionService:UnbindAction(WHEELIE_ACTION)
	ContextActionService:UnbindAction(JUMP_ACTION)
	ContextActionService:UnbindAction(RESET_ACTION)
	setWheelie(false)
	table.clear(touchInputs)
end

--------------------------------------------------------------------------------
-- driving
--------------------------------------------------------------------------------

local function pushStance(value: boolean)
	if standing == value then
		return
	end
	standing = value
	setStance:FireServer(value)
	-- Pose ourselves immediately rather than waiting for the round trip.
	riders[player] = value
end

local function stopDriving()
	driving = false
	bike, chassis, frontWheel, rearWheel = nil, nil, nil, nil
	seat, stabilizer, rearHinge, steerHinge, readout = nil, nil, nil, nil, nil
	wheelieAngle = 0
	heading = nil
	standing = false
	riders[player] = false
	gui.Enabled = false
	unbindControls()
end

local function startDriving(model: Model)
	local body = model:FindFirstChild("Chassis")
	local vehicleSeat = model:FindFirstChild("DriverSeat")
	if not (body and body:IsA("Part") and vehicleSeat and vehicleSeat:IsA("VehicleSeat")) then
		return
	end

	bike = model
	chassis = body
	frontWheel = model:FindFirstChild("FrontWheel") :: Part
	rearWheel = model:FindFirstChild("RearWheel") :: Part
	seat = vehicleSeat
	stabilizer = body:FindFirstChild("Stabilizer") :: AlignOrientation
	rearHinge = body:FindFirstChild("RearHinge") :: HingeConstraint
	steerHinge = body:FindFirstChild("SteerHinge") :: HingeConstraint

	local dash = model:FindFirstChild("DashScreen")
	local display = dash and dash:FindFirstChild("Display")
	readout = display and display:FindFirstChild("Readout") :: TextLabel?

	wheelieAngle = 0
	heading = nil
	standing = false
	nextJump = 0
	driving = true
	gui.Enabled = true
	bindControls()
end

driverChanged.OnClientEvent:Connect(function(model: Model, driver: Player?)
	if driver == player then
		startDriving(model)
	elseif driving and model == bike then
		stopDriving()
	end
end)

stanceChanged.OnClientEvent:Connect(function(who: Player, value: boolean)
	riders[who] = value
end)

--------------------------------------------------------------------------------
-- simulation
--------------------------------------------------------------------------------

local function wrapAngle(a: number): number
	return (a + math.pi) % (math.pi * 2) - math.pi
end

RunService.Heartbeat:Connect(function(dt)
	-- Pose every rider we know about, ourselves included.
	for who, isStanding in riders do
		local character = who.Character
		if character and character.Parent then
			RiderPose.Update(character, isStanding, dt)
		end
	end

	if not driving then
		return
	end

	local body = chassis
	local vehicleSeat = seat
	local stab = stabilizer
	local rear = rearHinge
	local steerJoint = steerHinge

	if not (body and vehicleSeat and stab and rear and steerJoint) then
		return
	end
	if not body.Parent or vehicleSeat.Occupant == nil then
		local character = player.Character
		if character then
			RiderPose.Release(character)
		end
		stopDriving()
		return
	end

	local maxWheelie = Config.Wheelie.MaxAngle

	-- Wheelie angle eases toward its target so the bike rocks back instead of
	-- snapping to the angle.
	local target = wheelieHeld and maxWheelie or 0
	local rate = wheelieHeld and Config.Wheelie.RiseRate or Config.Wheelie.FallRate
	wheelieAngle += math.clamp(target - wheelieAngle, -rate * dt, rate * dt)

	-- Past a threshold the rider comes up off the seat onto the pegs.
	pushStance(wheelieAngle > maxWheelie * Config.Wheelie.StandThreshold)

	-- Current heading, taken from the chassis flattened onto the ground plane.
	local look = body.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local yaw = math.atan2(-flat.X, -flat.Z)

	if heading == nil then
		heading = yaw
	end

	-- The Float variants are analog, so a mobile thumbstick or a gamepad
	-- stick gives partial steering instead of full lock or nothing.
	local steer = math.clamp(vehicleSeat.SteerFloat, -1, 1)
	local throttle = math.clamp(vehicleSeat.ThrottleFloat, -1, 1)
	local speed = body.AssemblyLinearVelocity.Magnitude

	-- Steering bites more the faster you go, and less the higher the front
	-- wheel is -- a bike up on the back wheel does not turn on the front tyre.
	local speedFactor = math.clamp(speed / Config.Handling.TurnSpeedThreshold, 0, 1)
	local wheelieFactor = 1 - Config.Wheelie.TurnPenalty * (wheelieAngle / maxWheelie)

	local newHeading = heading - steer * math.rad(Config.Handling.TurnRate) * dt * speedFactor * wheelieFactor

	-- Never let the steering target run away from where the bike actually is,
	-- or a collision would leave the stabiliser fighting the world.
	local lag = math.clamp(wrapAngle(newHeading - yaw), -Config.Handling.MaxHeadingLag, Config.Handling.MaxHeadingLag)
	heading = yaw + lag

	-- Upright, pointed along the heading, pitched up by the wheelie angle.
	stab.CFrame = CFrame.Angles(0, heading, 0) * CFrame.Angles(math.rad(wheelieAngle), 0, 0)

	-- Drive.
	local drive = throttle
	if drive < 0 then
		drive *= Config.Drive.ReverseFactor
	end
	-- Coasting uses a weaker motor so the bike rolls to a stop instead of
	-- locking the rear wheel the instant the throttle is released.
	local coasting = math.abs(throttle) < 0.05
	rear.MotorMaxTorque = coasting and Config.Drive.BrakeTorque or Config.Drive.MotorTorque
	rear.AngularVelocity = -drive * Config.Drive.MaxWheelSpeed

	-- Point the forks where the rider is steering.
	steerJoint.TargetAngle = -steer * Config.Handling.MaxSteerAngle

	-- HUD and the bar-mounted dash.
	local pct = wheelieAngle / maxWheelie
	meterFill.Size = UDim2.new(pct, 0, 1, 0)
	meterLabel.Text = string.format("WHEELIE  %d%%", math.floor(pct * 100 + 0.5))

	if readout then
		readout.Text = string.format("%d\nKM/H", math.floor(speed * 0.28 * 3.6 + 0.5))
	end
end)
