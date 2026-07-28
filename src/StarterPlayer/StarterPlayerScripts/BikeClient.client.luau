--!strict
-- BikeClient
-- Runs on whoever is sitting on the bike. That client has network ownership of
-- the whole assembly, so driving it from here is smooth and lag free.
--
-- It also poses every rider's rig and drives the engine note for everyone,
-- because both are observable from the replicated bike.
--
-- Controls
--   W / S or the mobile thumbstick .. throttle & brake
--   A / D or the mobile thumbstick .. steer
--   Q  or the WHEELIE button (hold) .. lift the front wheel
--   E / F / G / H or the trick buttons (hold) .. tricks
--   R  or the JUMP button .. jump
--   T  or the RESET button .. put the bike back on the pad
--   C  or the BIKE button .. paint shop
--   V .. toggle the chase camera

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
local crashBike = remotes:WaitForChild("CrashBike") :: RemoteEvent
local crashed = remotes:WaitForChild("Crashed") :: RemoteEvent
local paintBike = remotes:WaitForChild("PaintBike") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local W = Config.Wheelie
local TOP_SPEED = Config.Drive.MaxWheelSpeed * Config.Geometry.RearRadius

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

-- The bike as it exists in the world, whether or not we are on it. Used for
-- the engine note so bystanders hear it too.
local worldChassis: Part? = nil
local worldSeat: VehicleSeat? = nil
local engineSound: Sound? = nil

local wheelieHeld = false
local pitch = 0 -- degrees of nose-up; the thing being balanced
local pitchVel = 0 -- degrees/sec
local lean = 0 -- radians of bank, positive is left
local heading: number? = nil
local nextJump = 0
local heldTricks: { [string]: boolean } = {}
local activeTrick: string? = nil
local wasGrounded = true
local mountedAt = 0
local crashSent = false
local touchInputs: { [Enum.UserInputType]: TextButton } = {}

local cameraEnabled = Config.Camera.Enabled
-- Pose name per rider, "Seated" when they are not doing anything.
local riders: { [Player]: string } = {}

local paintChoice = { frame = 1, rim = 1, tyre = 1 }

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

local function roundify(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local gui = Instance.new("ScreenGui")
gui.Name = "WheelieHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

-- Balance meter. The bar runs 0 .. loop-out, with the balance pocket marked
-- in green and the danger zone in red, so the skill is legible at a glance.
local meter = Instance.new("Frame")
meter.Name = "BalanceMeter"
meter.AnchorPoint = Vector2.new(0.5, 1)
meter.Position = UDim2.new(0.5, 0, 1, -34)
meter.Size = UDim2.new(0, 360, 0, 24)
meter.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
meter.BackgroundTransparency = 0.25
meter.BorderSizePixel = 0
meter.ZIndex = 2
meter.Parent = gui
roundify(meter, 12)

local sweetZone = Instance.new("Frame")
sweetZone.Name = "SweetZone"
sweetZone.BackgroundColor3 = Color3.fromRGB(64, 200, 120)
sweetZone.BackgroundTransparency = 0.55
sweetZone.BorderSizePixel = 0
sweetZone.ZIndex = 3
sweetZone.Position = UDim2.new((W.BalanceAngle - W.SweetSpot) / W.LoopOutAngle, 0, 0, 0)
sweetZone.Size = UDim2.new((W.SweetSpot * 2) / W.LoopOutAngle, 0, 1, 0)
sweetZone.Parent = meter

local dangerZone = Instance.new("Frame")
dangerZone.Name = "DangerZone"
dangerZone.BackgroundColor3 = Color3.fromRGB(220, 60, 55)
dangerZone.BackgroundTransparency = 0.55
dangerZone.BorderSizePixel = 0
dangerZone.ZIndex = 3
dangerZone.Position = UDim2.new(Config.Crash.LandingSafeMax / W.LoopOutAngle, 0, 0, 0)
dangerZone.Size = UDim2.new(1 - Config.Crash.LandingSafeMax / W.LoopOutAngle, 0, 1, 0)
dangerZone.Parent = meter

local meterFill = Instance.new("Frame")
meterFill.Name = "Fill"
meterFill.Size = UDim2.new(0, 0, 1, 0)
meterFill.BackgroundColor3 = Config.Colors.Frame
meterFill.BackgroundTransparency = 0.15
meterFill.BorderSizePixel = 0
meterFill.ZIndex = 4
meterFill.Parent = meter
roundify(meterFill, 12)

local meterLabel = Instance.new("TextLabel")
meterLabel.Size = UDim2.fromScale(1, 1)
meterLabel.BackgroundTransparency = 1
meterLabel.Font = Enum.Font.GothamBold
meterLabel.Text = "WHEELIE"
meterLabel.TextSize = 13
meterLabel.TextColor3 = Color3.new(1, 1, 1)
meterLabel.ZIndex = 5
meterLabel.Parent = meter

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -64)
hint.Size = UDim2.new(0, 720, 0, 20)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "W throttle   S brake (saves a wheelie)   A/D steer   Q wheelie   R jump   T reset   C paint   V camera"
hint.TextSize = 14
hint.TextColor3 = Color3.fromRGB(235, 235, 238)
hint.TextTransparency = 0.15
hint.Visible = not UserInputService.TouchEnabled
hint.Parent = gui

local trickLabel = Instance.new("TextLabel")
trickLabel.Name = "Trick"
trickLabel.AnchorPoint = Vector2.new(0.5, 1)
trickLabel.Position = UDim2.new(0.5, 0, 1, -88)
trickLabel.Size = UDim2.new(0, 400, 0, 30)
trickLabel.BackgroundTransparency = 1
trickLabel.Font = Enum.Font.GothamBlack
trickLabel.Text = ""
trickLabel.TextSize = 24
trickLabel.TextColor3 = Color3.fromRGB(96, 226, 160)
trickLabel.Parent = gui

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 90)
banner.Size = UDim2.new(0, 460, 0, 44)
banner.BackgroundTransparency = 1
banner.Font = Enum.Font.GothamBlack
banner.Text = ""
banner.TextSize = 30
banner.TextColor3 = Color3.fromRGB(255, 92, 84)
banner.Visible = false
banner.Parent = gui

local function makeButton(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, color: Color3, radius: number): TextButton
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
	button.Parent = parent
	roundify(button, radius)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Transparency = 0.55
	stroke.Parent = button

	return button
end

local wheelieButton = makeButton(gui, "Wheelie", "WHEELIE", UDim2.new(0, 132, 0, 132), UDim2.new(1, -24, 1, -24), Config.Colors.Frame, 66)
local jumpButton = makeButton(gui, "Jump", "JUMP", UDim2.new(0, 104, 0, 104), UDim2.new(1, -170, 1, -34), Config.Colors.Accent, 52)
local resetButton = makeButton(gui, "Reset", "RESET", UDim2.new(0, 104, 0, 42), UDim2.new(1, -38, 1, -170), Color3.fromRGB(32, 33, 36), 12)
local wheelieStroke = wheelieButton:FindFirstChildOfClass("UIStroke") :: UIStroke

-- One touch button per trick, stacked up the left edge.
local trickButtons: { [string]: TextButton } = {}
for i, trick in Config.Tricks do
	local b = makeButton(
		gui,
		"Trick" .. trick.Id,
		trick.Name,
		UDim2.new(0, 118, 0, 44),
		UDim2.new(0, 142, 1, -24 - (i - 1) * 52),
		Color3.fromRGB(38, 40, 44),
		10
	)
	b.AnchorPoint = Vector2.new(1, 1)
	b.TextSize = 13
	trickButtons[trick.Id] = b
end

--------------------------------------------------------------------------------
-- paint shop
--------------------------------------------------------------------------------

local shopGui = Instance.new("ScreenGui")
shopGui.Name = "PaintShop"
shopGui.ResetOnSpawn = false
shopGui.IgnoreGuiInset = true
shopGui.Parent = playerGui

local shopToggle = Instance.new("TextButton")
shopToggle.Name = "Toggle"
shopToggle.AnchorPoint = Vector2.new(0, 0)
shopToggle.Position = UDim2.new(0, 20, 0, 20)
shopToggle.Size = UDim2.new(0, 96, 0, 38)
shopToggle.BackgroundColor3 = Color3.fromRGB(30, 31, 34)
shopToggle.BackgroundTransparency = 0.15
shopToggle.AutoButtonColor = false
shopToggle.Font = Enum.Font.GothamBold
shopToggle.Text = "BIKE"
shopToggle.TextSize = 16
shopToggle.TextColor3 = Color3.new(1, 1, 1)
shopToggle.Parent = shopGui
roundify(shopToggle, 10)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.new(0, 20, 0, 68)
panel.Size = UDim2.new(0, 330, 0, 250)
panel.BackgroundColor3 = Color3.fromRGB(22, 23, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = shopGui
roundify(panel, 14)

local function sendPaint()
	paintBike:FireServer(paintChoice.frame, paintChoice.rim, paintChoice.tyre)
end

-- One row of swatches. `key` is which part of paintChoice the row edits.
local function swatchRow(title: string, y: number, entries: { any }, key: string, isColor: boolean)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 16, 0, y)
	label.Size = UDim2.new(1, -32, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = title
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(180, 182, 188)
	label.Parent = panel

	local buttons: { TextButton } = {}
	local function refresh()
		for i, b in buttons do
			local chosen = paintChoice[key] == i
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = chosen and 0 or 0.75
				stroke.Thickness = chosen and 3 or 1
			end
		end
	end

	for i, entry in entries do
		local b = Instance.new("TextButton")
		b.Size = isColor and UDim2.new(0, 40, 0, 40) or UDim2.new(0, 128, 0, 34)
		b.Position = isColor and UDim2.new(0, 16 + (i - 1) * 48, 0, y + 22) or UDim2.new(0, 16 + (i - 1) * 140, 0, y + 22)
		b.BackgroundColor3 = isColor and entry.Color or Color3.fromRGB(44, 46, 50)
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold
		b.Text = isColor and "" or entry
		b.TextSize = 14
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = panel
		roundify(b, isColor and 20 or 8)

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 1
		stroke.Transparency = 0.75
		stroke.Parent = b

		buttons[i] = b
		b.Activated:Connect(function()
			paintChoice[key] = i
			refresh()
			sendPaint()
		end)
	end

	refresh()
end

do
	local title = Instance.new("TextLabel")
	title.Position = UDim2.new(0, 16, 0, 12)
	title.Size = UDim2.new(1, -32, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "PAINT SHOP"
	title.TextSize = 17
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = panel

	swatchRow("FRAME", 44, Config.Paint.Frame, "frame", true)
	swatchRow("RIMS", 114, Config.Paint.Rim, "rim", true)
	swatchRow("TYRES", 184, Config.Paint.Tyre, "tyre", false)
end

local function toggleShop()
	panel.Visible = not panel.Visible
end

shopToggle.Activated:Connect(toggleShop)

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function setWheelie(held: boolean)
	wheelieHeld = held
	wheelieStroke.Transparency = held and 0.05 or 0.55
	wheelieButton.BackgroundTransparency = held and 0 or 0.12
end

local function groundedRay(part: Part?, radius: number): boolean
	if not part then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bike :: Instance, player.Character :: Instance }
	local reach = radius + Config.Jump.GroundCheck
	return workspace:Raycast(part.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

local function tryJump()
	if not driving then
		return
	end
	local body = chassis
	if not body then
		return
	end

	local now = os.clock()
	if now < nextJump then
		return
	end
	if not groundedRay(rearWheel, Config.Geometry.RearRadius) and not groundedRay(frontWheel, Config.Geometry.FrontRadius) then
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
	for _, part in { body, rearWheel, frontWheel } do
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

local function setTrickHeld(id: string, held: boolean)
	heldTricks[id] = held or nil
	local button = trickButtons[id]
	if button then
		button.BackgroundTransparency = held and 0 or 0.12
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
-- off the button still drops the front wheel instead of sticking it up.
wheelieButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		touchInputs[input.UserInputType] = wheelieButton
		setWheelie(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local target = touchInputs[input.UserInputType]
	if not target then
		return
	end
	touchInputs[input.UserInputType] = nil
	if target == wheelieButton then
		setWheelie(false)
	else
		for id, button in trickButtons do
			if button == target then
				setTrickHeld(id, false)
			end
		end
	end
end)

for id, button in trickButtons do
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touchInputs[input.UserInputType] = button
			setTrickHeld(id, true)
		end
	end)
end

jumpButton.Activated:Connect(tryJump)
resetButton.Activated:Connect(function()
	resetBike:FireServer()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.C then
		toggleShop()
	elseif input.KeyCode == Enum.KeyCode.V then
		cameraEnabled = not cameraEnabled
		if not cameraEnabled then
			local camera = workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = Config.Camera.BaseFov
		end
	end
end)

local function bindControls()
	ContextActionService:BindAction("ERideWheelie", onWheelieAction, false, Enum.KeyCode.Q)
	ContextActionService:BindAction("ERideJump", onJumpAction, false, Enum.KeyCode.R)
	ContextActionService:BindAction("ERideReset", onResetAction, false, Enum.KeyCode.T)

	for _, trick in Config.Tricks do
		local keyCode = (Enum.KeyCode :: any)[trick.Key]
		if keyCode then
			ContextActionService:BindAction("ERideTrick" .. trick.Id, function(_, state)
				if state == Enum.UserInputState.Begin then
					setTrickHeld(trick.Id, true)
				elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
					setTrickHeld(trick.Id, false)
				end
				return Enum.ContextActionResult.Sink
			end, false, keyCode)
		end
	end
end

local function unbindControls()
	ContextActionService:UnbindAction("ERideWheelie")
	ContextActionService:UnbindAction("ERideJump")
	ContextActionService:UnbindAction("ERideReset")
	for _, trick in Config.Tricks do
		ContextActionService:UnbindAction("ERideTrick" .. trick.Id)
		setTrickHeld(trick.Id, false)
	end
	setWheelie(false)
	table.clear(touchInputs)
end

--------------------------------------------------------------------------------
-- mounting
--------------------------------------------------------------------------------

local function pushTrick(id: string?)
	if activeTrick == id then
		return
	end
	activeTrick = id
	setStance:FireServer(id)
	-- Pose ourselves immediately rather than waiting for the round trip.
	riders[player] = id or "Seated"
end

-- The held trick that is actually allowed right now. Later entries in the
-- config win when several are held at once.
local function pickTrick(grounded: boolean): string?
	for i = #Config.Tricks, 1, -1 do
		local trick = Config.Tricks[i]
		if heldTricks[trick.Id] and (not trick.AirOnly or not grounded) then
			return trick.Id
		end
	end
	return nil
end

local function releaseCamera()
	local camera = workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = Config.Camera.BaseFov
	end
end

local function stopDriving()
	driving = false
	bike, chassis, frontWheel, rearWheel = nil, nil, nil, nil
	seat, stabilizer, rearHinge, steerHinge, readout = nil, nil, nil, nil, nil
	pitch, pitchVel, lean = 0, 0, 0
	heading = nil
	activeTrick = nil
	trickLabel.Text = ""
	riders[player] = nil
	gui.Enabled = false
	unbindControls()
	releaseCamera()
end

local function attachWorldBike(model: Model)
	worldChassis = model:FindFirstChild("Chassis") :: Part?
	worldSeat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
	engineSound = worldChassis and worldChassis:FindFirstChild("Engine") :: Sound?
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

	pitch, pitchVel, lean = 0, 0, 0
	heading = nil
	activeTrick = nil
	riders[player] = "Seated"
	nextJump = 0
	crashSent = false
	wasGrounded = true
	mountedAt = os.clock()
	driving = true
	gui.Enabled = true
	bindControls()
end

driverChanged.OnClientEvent:Connect(function(model: Model, driver: Player?)
	attachWorldBike(model)
	if driver == player then
		startDriving(model)
	elseif driving and model == bike then
		stopDriving()
	end
end)

stanceChanged.OnClientEvent:Connect(function(who: Player, trick: string?)
	riders[who] = trick or "Seated"
end)

crashed.OnClientEvent:Connect(function(who: Player, reason: string)
	riders[who] = nil
	local character = who.Character
	if character then
		RiderPose.Release(character)
	end

	if worldChassis then
		local thud = Instance.new("Sound")
		thud.SoundId = Config.Audio.CrashSoundId
		thud.Volume = Config.Audio.CrashVolume
		thud.Parent = worldChassis
		thud:Play()
		task.delay(3, function()
			thud:Destroy()
		end)
	end

	if who == player then
		banner.Text = reason == "LoopOut" and "LOOPED OUT" or "CASED IT"
		banner.Visible = true
		task.delay(1.8, function()
			banner.Visible = false
		end)
	end
end)

-- A client that joins after the bike already exists never sees the startup
-- broadcast, so find it directly too.
task.spawn(function()
	local model = workspace:WaitForChild(Config.ModelName, 30)
	if model and model:IsA("Model") and not worldChassis then
		attachWorldBike(model)
	end
end)

--------------------------------------------------------------------------------
-- chase camera
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
	local body = chassis
	if not (driving and cameraEnabled and body and body.Parent) then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local look = body.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	local focus = body.Position + Vector3.new(0, Config.Camera.LookHeight, 0)
	local want = focus - flat * Config.Camera.Distance + Vector3.new(0, Config.Camera.Height, 0)

	-- Pull in rather than clipping through a building.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bike :: Instance, player.Character :: Instance }
	local blocked = workspace:Raycast(focus, want - focus, params)
	if blocked then
		local pullBack = (want - focus).Unit * Config.Camera.MinDistance
		want = blocked.Position - (want - focus).Unit * 1.5
		if (want - focus).Magnitude < Config.Camera.MinDistance then
			want = focus + pullBack
		end
	end

	local alpha = 1 - math.exp(-Config.Camera.Smoothness * dt)
	camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(want, focus), alpha)

	local speed = body.AssemblyLinearVelocity.Magnitude
	local fov = Config.Camera.BaseFov
		+ (Config.Camera.MaxFov - Config.Camera.BaseFov) * math.clamp(speed / Config.Camera.FovSpeed, 0, 1)
	camera.FieldOfView += (fov - camera.FieldOfView) * alpha
end)

--------------------------------------------------------------------------------
-- simulation
--------------------------------------------------------------------------------

local function wrapAngle(a: number): number
	return (a + math.pi) % (math.pi * 2) - math.pi
end

local function sendCrash(reason: string)
	if crashSent then
		return
	end
	crashSent = true
	crashBike:FireServer(reason)
end

RunService.Heartbeat:Connect(function(dt)
	-- Pose every rider we know about, ourselves included.
	for who, pose in riders do
		local character = who.Character
		if character and character.Parent then
			RiderPose.Update(character, pose, dt)
		end
	end

	-- Engine note, for everyone in earshot rather than only the rider.
	if engineSound and worldChassis and worldChassis.Parent then
		local occupied = worldSeat ~= nil and worldSeat.Occupant ~= nil
		local speed = worldChassis.AssemblyLinearVelocity.Magnitude
		local revs = math.clamp(speed / TOP_SPEED, 0, 1)
		if occupied and engineSound.SoundId ~= "" then
			if not engineSound.IsPlaying then
				engineSound:Play()
			end
			engineSound.PlaybackSpeed = Config.Audio.IdlePitch
				+ (Config.Audio.MaxPitch - Config.Audio.IdlePitch) * revs
			engineSound.Volume = Config.Audio.EngineVolume * (0.35 + 0.65 * revs)
		elseif engineSound.IsPlaying then
			engineSound:Stop()
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

	local steer = math.clamp(vehicleSeat.SteerFloat, -1, 1)
	local throttle = math.clamp(vehicleSeat.ThrottleFloat, -1, 1)
	local velocity = body.AssemblyLinearVelocity
	local speed = velocity.Magnitude

	local grounded = groundedRay(rearWheel, Config.Geometry.RearRadius)
		or groundedRay(frontWheel, Config.Geometry.FrontRadius)

	-- Landing check, using the pitch we were carrying through the air.
	local settled = os.clock() - mountedAt > 0.75
	if grounded and not wasGrounded and settled then
		if pitch > Config.Crash.LandingSafeMax or pitch < Config.Crash.LandingSafeMin or -velocity.Y > Config.Crash.ImpactSpeed then
			sendCrash("Landing")
		elseif worldChassis then
			local thud = Instance.new("Sound")
			thud.SoundId = Config.Audio.LandSoundId
			thud.Volume = Config.Audio.LandVolume
			thud.Parent = worldChassis
			thud:Play()
			task.delay(2, function()
				thud:Destroy()
			end)
		end
	end
	wasGrounded = grounded

	----------------------------------------------------------------------------
	-- balance: the bike's pitch is an inverted pendulum about the rear contact
	----------------------------------------------------------------------------

	local acc = 0
	if wheelieHeld then
		-- Lift fades out past the balance point, so you cannot just hold the
		-- button and power through the tipping point.
		local scale = 1
		if pitch > W.BalanceAngle then
			scale = math.max(W.LiftFloor, 1 - (pitch - W.BalanceAngle) / W.LiftFalloff)
		end
		acc += (W.LiftTorque + W.ThrottleAssist * math.max(throttle, 0)) * scale
	elseif grounded then
		acc -= W.ReleaseTorque
	end

	-- Braking is the save: it pulls the nose down on the road as well as in
	-- the air, which is how you rescue a wheelie that has gone too far.
	if throttle < 0 then
		acc += W.NoseDownTorque * throttle
	end

	-- Below the balance angle gravity drops the nose; above it, it takes you
	-- over the back. Airborne, it barely acts at all.
	local gravityScale = grounded and 1 or W.AirGravityScale
	acc += W.GravityTorque * gravityScale * math.sin(math.rad(pitch - W.BalanceAngle))

	-- A one-way damper: firm while the nose rises, softer on the way down so
	-- it drops with some weight instead of floating.
	local damping = W.Damping
	if pitchVel < 0 then
		damping = W.FallDamping
	end
	acc -= damping * pitchVel

	pitchVel += acc * dt
	pitch += pitchVel * dt

	if grounded and pitch < 0 then
		-- The front wheel is resting on the road; it cannot go lower.
		pitch = 0
		pitchVel = math.max(pitchVel, 0)
	elseif pitch < W.MinAngle then
		pitch = W.MinAngle
		pitchVel = math.max(pitchVel, 0)
	end

	if pitch > W.LoopOutAngle then
		sendCrash("LoopOut")
		pitch = W.LoopOutAngle
	end

	pushTrick(pickTrick(grounded))

	----------------------------------------------------------------------------
	-- steering and drive
	----------------------------------------------------------------------------

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

	local speedFactor = math.clamp(speed / Config.Handling.TurnSpeedThreshold, 0, 1)
	local wheelieFactor = 1 - W.TurnPenalty * math.clamp(pitch / W.BalanceAngle, 0, 1)
	local newHeading = heading - steer * math.rad(Config.Handling.TurnRate) * dt * speedFactor * wheelieFactor

	local lag = math.clamp(wrapAngle(newHeading - yaw), -Config.Handling.MaxHeadingLag, Config.Handling.MaxHeadingLag)
	heading = yaw + lag

	-- Bank into the corner. Roll is still fully controlled, it just follows the
	-- steering now instead of being pinned flat -- and it flattens out as the
	-- front wheel comes up, because you cannot lean on the back wheel alone.
	local leanScale = 1 - (1 - Config.Handling.LeanWheelieScale) * math.clamp(pitch / W.BalanceAngle, 0, 1)
	local targetLean = -steer * math.rad(Config.Handling.MaxLean) * speedFactor * leanScale
	lean += (targetLean - lean) * (1 - math.exp(-Config.Handling.LeanSpeed * dt))

	stab.CFrame = CFrame.Angles(0, heading, 0) * CFrame.Angles(math.rad(pitch), 0, lean)

	local drive = throttle
	if drive < 0 then
		drive *= Config.Drive.ReverseFactor
	end
	local coasting = math.abs(throttle) < 0.05
	rear.MotorMaxTorque = coasting and Config.Drive.BrakeTorque or Config.Drive.MotorTorque
	rear.AngularVelocity = -drive * Config.Drive.MaxWheelSpeed

	steerJoint.TargetAngle = -steer * Config.Handling.MaxSteerAngle

	----------------------------------------------------------------------------
	-- readouts
	----------------------------------------------------------------------------

	local fraction = math.clamp(pitch / W.LoopOutAngle, 0, 1)
	meterFill.Size = UDim2.new(fraction, 0, 1, 0)

	local inPocket = math.abs(pitch - W.BalanceAngle) <= W.SweetSpot
	if pitch > Config.Crash.LandingSafeMax then
		meterFill.BackgroundColor3 = Color3.fromRGB(226, 66, 58)
		meterLabel.Text = "TOO FAR"
	elseif inPocket then
		meterFill.BackgroundColor3 = Color3.fromRGB(72, 214, 132)
		meterLabel.Text = "BALANCED"
	else
		meterFill.BackgroundColor3 = Config.Colors.Frame
		meterLabel.Text = string.format("WHEELIE  %d°", math.floor(pitch + 0.5))
	end

	local trickName = ""
	for _, trick in Config.Tricks do
		if trick.Id == activeTrick then
			trickName = trick.Name
		end
	end
	trickLabel.Text = trickName

	if readout then
		readout.Text = string.format("%d\nKM/H", math.floor(speed * 0.28 * 3.6 + 0.5))
	end
end)
