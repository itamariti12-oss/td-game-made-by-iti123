--!strict
-- BikeClient
-- Runs on whoever is sitting on the bike. That client has network ownership of
-- the whole assembly, so driving it from here is smooth and lag free.
--
-- Controls
--   W / S or the mobile thumbstick .. throttle & brake
--   A / D or the mobile thumbstick .. steer
--   Q  or the on-screen WHEELIE button (hold) .. wheelie
--   R  or the on-screen RESET button .. put the bike back on the pad

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BikeConfig"))

local remotes = ReplicatedStorage:WaitForChild("BikeRemotes")
local driverChanged = remotes:WaitForChild("DriverChanged") :: RemoteEvent
local resetBike = remotes:WaitForChild("ResetBike") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WHEELIE_ACTION = "ERideWheelie"
local RESET_ACTION = "ERideReset"

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local driving = false
local bike: Model? = nil
local chassis: Part? = nil
local seat: VehicleSeat? = nil
local stabilizer: AlignOrientation? = nil
local rearHinge: HingeConstraint? = nil
local steerHinge: HingeConstraint? = nil

local wheelieHeld = false
local wheelieAngle = 0
local heading: number? = nil
local touchInput: InputObject? = nil

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

-- Wheelie meter.
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
meterFill.BackgroundColor3 = Config.Colors.Accent
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
hint.Size = UDim2.new(0, 520, 0, 20)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "W/S  throttle     A/D  steer     Q  wheelie     R  reset"
hint.TextSize = 14
hint.TextColor3 = Color3.fromRGB(235, 235, 238)
hint.TextTransparency = 0.15
hint.Visible = not UserInputService.TouchEnabled
hint.Parent = gui

-- Mobile buttons.
local wheelieButton = Instance.new("TextButton")
wheelieButton.Name = "Wheelie"
wheelieButton.AnchorPoint = Vector2.new(1, 1)
wheelieButton.Position = UDim2.new(1, -28, 1, -28)
wheelieButton.Size = UDim2.new(0, 132, 0, 132)
wheelieButton.BackgroundColor3 = Config.Colors.Accent
wheelieButton.BackgroundTransparency = 0.12
wheelieButton.AutoButtonColor = false
wheelieButton.Font = Enum.Font.GothamBlack
wheelieButton.Text = "WHEELIE"
wheelieButton.TextSize = 20
wheelieButton.TextColor3 = Color3.new(1, 1, 1)
wheelieButton.Visible = UserInputService.TouchEnabled
wheelieButton.Parent = gui
roundify(wheelieButton, 66)

local wheelieStroke = Instance.new("UIStroke")
wheelieStroke.Color = Color3.new(1, 1, 1)
wheelieStroke.Thickness = 3
wheelieStroke.Transparency = 0.55
wheelieStroke.Parent = wheelieButton

local resetButton = Instance.new("TextButton")
resetButton.Name = "Reset"
resetButton.AnchorPoint = Vector2.new(1, 1)
resetButton.Position = UDim2.new(1, -28, 1, -178)
resetButton.Size = UDim2.new(0, 132, 0, 46)
resetButton.BackgroundColor3 = Color3.fromRGB(32, 33, 36)
resetButton.BackgroundTransparency = 0.15
resetButton.AutoButtonColor = false
resetButton.Font = Enum.Font.GothamBold
resetButton.Text = "RESET"
resetButton.TextSize = 16
resetButton.TextColor3 = Color3.new(1, 1, 1)
resetButton.Visible = UserInputService.TouchEnabled
resetButton.Parent = gui
roundify(resetButton, 12)

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function setWheelie(held: boolean)
	wheelieHeld = held
	wheelieStroke.Transparency = held and 0.05 or 0.55
	wheelieButton.BackgroundTransparency = held and 0.0 or 0.12
end

local function onWheelieAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setWheelie(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setWheelie(false)
	end
	return Enum.ContextActionResult.Sink
end

local function onResetAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		resetBike:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

wheelieButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		touchInput = input
		setWheelie(true)
	end
end)

-- Catching the release globally means sliding a thumb off the button still
-- drops the wheelie instead of sticking it on.
UserInputService.InputEnded:Connect(function(input)
	if touchInput == input then
		touchInput = nil
		setWheelie(false)
	end
end)

resetButton.Activated:Connect(function()
	resetBike:FireServer()
end)

local function bindControls()
	ContextActionService:BindAction(WHEELIE_ACTION, onWheelieAction, false, Enum.KeyCode.Q)
	ContextActionService:BindAction(RESET_ACTION, onResetAction, false, Enum.KeyCode.R)
end

local function unbindControls()
	ContextActionService:UnbindAction(WHEELIE_ACTION)
	ContextActionService:UnbindAction(RESET_ACTION)
	setWheelie(false)
	touchInput = nil
end

--------------------------------------------------------------------------------
-- driving
--------------------------------------------------------------------------------

local function stopDriving()
	driving = false
	bike, chassis, seat, stabilizer, rearHinge, steerHinge = nil, nil, nil, nil, nil, nil
	wheelieAngle = 0
	heading = nil
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
	seat = vehicleSeat
	stabilizer = body:FindFirstChild("Stabilizer") :: AlignOrientation
	rearHinge = body:FindFirstChild("RearHinge") :: HingeConstraint
	steerHinge = body:FindFirstChild("SteerHinge") :: HingeConstraint

	wheelieAngle = 0
	heading = nil
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

--------------------------------------------------------------------------------
-- simulation
--------------------------------------------------------------------------------

local function wrapAngle(a: number): number
	return (a + math.pi) % (math.pi * 2) - math.pi
end

RunService.Heartbeat:Connect(function(dt)
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
		stopDriving()
		return
	end

	local maxWheelie = Config.Wheelie.MaxAngle

	-- Wheelie angle eases toward its target so the bike rocks back instead of
	-- snapping to the angle.
	local target = wheelieHeld and maxWheelie or 0
	local rate = wheelieHeld and Config.Wheelie.RiseRate or Config.Wheelie.FallRate
	wheelieAngle += math.clamp(target - wheelieAngle, -rate * dt, rate * dt)

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

	-- HUD.
	local pct = wheelieAngle / maxWheelie
	meterFill.Size = UDim2.new(pct, 0, 1, 0)
	meterLabel.Text = string.format("WHEELIE  %d%%", math.floor(pct * 100 + 0.5))
end)
