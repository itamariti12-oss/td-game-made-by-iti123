--!strict
-- Ragdoll
-- Turns a character limp and puts it back together again. Server-side only:
-- the joints it swaps are physical, so they have to be authoritative.
--
-- Every Motor6D is disabled and replaced by a BallSocketConstraint pinned to
-- the same two points, which is what lets the limbs swing. The originals are
-- kept so standing back up is just a matter of switching them back on.

local Ragdoll = {}

local active: { [Model]: { motors: { Motor6D }, holder: Folder, neck: boolean } } = {}

local function limbsOf(character: Model): { Motor6D }
	local motors: { Motor6D } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(motors, d)
		end
	end
	return motors
end

function Ragdoll.IsRagdolled(character: Model): boolean
	return active[character] ~= nil
end

function Ragdoll.Enable(character: Model)
	if active[character] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local motors = limbsOf(character)
	if #motors == 0 then
		return
	end

	local holder = Instance.new("Folder")
	holder.Name = "RagdollJoints"
	holder.Parent = character

	local neckWasRequired = humanoid.RequiresNeck
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	for _, motor in motors do
		local part0, part1 = motor.Part0, motor.Part1
		if part0 and part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = motor.Name .. "RagdollA"
			a0.CFrame = motor.C0
			a0.Parent = part0

			local a1 = Instance.new("Attachment")
			a1.Name = motor.Name .. "RagdollB"
			a1.CFrame = motor.C1
			a1.Parent = part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = motor.Name .. "Socket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 50
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -40
			socket.TwistUpperAngle = 40
			socket.Parent = holder

			motor.Enabled = false
		end
	end

	-- Limbs need to collide with the world or the rider sinks through the road.
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.CanCollide = true
		end
	end

	active[character] = { motors = motors, holder = holder, neck = neckWasRequired }
end

function Ragdoll.Disable(character: Model)
	local state = active[character]
	if not state then
		return
	end
	active[character] = nil

	if state.holder.Parent then
		state.holder:Destroy()
	end

	for _, motor in state.motors do
		if motor.Parent then
			motor.Enabled = true
		end
	end

	for _, d in character:GetDescendants() do
		if d:IsA("Attachment") and d.Name:find("Ragdoll[AB]$") then
			d:Destroy()
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = state.neck
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

return Ragdoll
