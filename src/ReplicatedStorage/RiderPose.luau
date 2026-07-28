--!strict
-- RiderPose
-- Every rider animation in the game, built the same way the bike is: in code,
-- at runtime. No uploaded animation assets.
--
-- Roblox animations are just Motor6D.Transform values written every frame, so
-- that is exactly what this does. Every client runs it for every rider, which
-- is how a normal animation would replicate anyway.
--
-- Poses are absolute, not additive. Whatever is currently on screen is eased
-- toward the active pose each frame, so switching between any two tricks --
-- or dropping back to seated -- blends smoothly with no bookkeeping.

local Config = require(script.Parent.BikeConfig)

local RiderPose = {}

local R = Config.Rider

-- Every R15 joint's C0/C1 is rotation-free in the rest pose, so a Transform
-- rotation acts in character space:
--   +X swings a downward-pointing limb FORWARD, -X swings it back
--   -X on the waist leans the chest forward
--   +Z on a shoulder/hip swings that limb toward the rider's right
local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

type Pose = { [string]: CFrame }
type Offset = { Lift: number, Forward: number, Pitch: number }

-- Sat down and riding: knees up on the pegs, leaning into the bars.
local SEATED: Pose = {
	Waist = ang(-26, 0, 0),
	Neck = ang(16, 0, 0),
	LeftHip = ang(70, 0, 9),
	RightHip = ang(70, 0, -9),
	LeftKnee = ang(-84, 0, 0),
	RightKnee = ang(-84, 0, 0),
	LeftAnkle = ang(18, 0, 0),
	RightAnkle = ang(18, 0, 0),
	LeftShoulder = ang(56, 0, 13),
	RightShoulder = ang(56, 0, -13),
	LeftElbow = ang(-24, 0, 0),
	RightElbow = ang(-24, 0, 0),
	LeftWrist = ang(6, 0, 0),
	RightWrist = ang(6, 0, 0),
}

-- Up off the seat, on the pegs, chest over the bars.
local STAND: Pose = {
	Waist = ang(-40, 0, 0),
	Neck = ang(28, 0, 0),
	LeftHip = ang(14, 0, 7),
	RightHip = ang(14, 0, -7),
	LeftKnee = ang(-24, 0, 0),
	RightKnee = ang(-24, 0, 0),
	LeftAnkle = ang(12, 0, 0),
	RightAnkle = ang(12, 0, 0),
	LeftShoulder = ang(70, 0, 9),
	RightShoulder = ang(70, 0, -9),
	LeftElbow = ang(-12, 0, 0),
	RightElbow = ang(-12, 0, 0),
	LeftWrist = ang(0, 0, 0),
	RightWrist = ang(0, 0, 0),
}

-- Hands off the bars, arms thrown out wide.
local NO_HANDER: Pose = {
	Waist = ang(-14, 0, 0),
	Neck = ang(6, 0, 0),
	LeftHip = ang(26, 0, 8),
	RightHip = ang(26, 0, -8),
	LeftKnee = ang(-38, 0, 0),
	RightKnee = ang(-38, 0, 0),
	LeftAnkle = ang(14, 0, 0),
	RightAnkle = ang(14, 0, 0),
	LeftShoulder = ang(12, 0, -78),
	RightShoulder = ang(12, 0, 78),
	LeftElbow = ang(-8, 0, 0),
	RightElbow = ang(-8, 0, 0),
	LeftWrist = ang(0, 0, 0),
	RightWrist = ang(0, 0, 0),
}

-- Legs kicked straight out behind, flat over the bike.
local SUPERMAN: Pose = {
	Waist = ang(-56, 0, 0),
	Neck = ang(46, 0, 0),
	LeftHip = ang(-74, 0, 10),
	RightHip = ang(-74, 0, -10),
	LeftKnee = ang(-6, 0, 0),
	RightKnee = ang(-6, 0, 0),
	LeftAnkle = ang(-16, 0, 0),
	RightAnkle = ang(-16, 0, 0),
	LeftShoulder = ang(78, 0, 6),
	RightShoulder = ang(78, 0, -6),
	LeftElbow = ang(-4, 0, 0),
	RightElbow = ang(-4, 0, 0),
	LeftWrist = ang(0, 0, 0),
	RightWrist = ang(0, 0, 0),
}

-- Right leg swung across the bike, hands still on the bars.
local CAN_CAN: Pose = {
	Waist = ang(-22, 0, 0),
	Neck = ang(14, 0, 0),
	LeftHip = ang(64, 0, 8),
	RightHip = ang(46, 0, -66),
	LeftKnee = ang(-78, 0, 0),
	RightKnee = ang(-52, 0, 0),
	LeftAnkle = ang(16, 0, 0),
	RightAnkle = ang(6, 0, 0),
	LeftShoulder = ang(60, 0, 11),
	RightShoulder = ang(60, 0, -11),
	LeftElbow = ang(-20, 0, 0),
	RightElbow = ang(-20, 0, 0),
	LeftWrist = ang(4, 0, 0),
	RightWrist = ang(4, 0, 0),
}

local POSES: { [string]: Pose } = {
	Seated = SEATED,
	Stand = STAND,
	NoHander = NO_HANDER,
	Superman = SUPERMAN,
	CanCan = CAN_CAN,
}

-- How far the rider rises off the seat and leans forward for each pose.
local OFFSETS: { [string]: Offset } = {
	Seated = { Lift = 0, Forward = 0, Pitch = 0 },
	Stand = { Lift = R.StandLift, Forward = R.StandForward, Pitch = R.StandPitch },
	NoHander = { Lift = R.StandLift * 0.8, Forward = R.StandForward * 0.5, Pitch = -4 },
	Superman = { Lift = R.StandLift * 1.3, Forward = R.StandForward * 1.7, Pitch = -16 },
	CanCan = { Lift = R.StandLift * 0.9, Forward = R.StandForward * 0.6, Pitch = -5 },
}

-- R6 has one joint per limb with pre-rotated C0s, so it only gets the torso
-- lean; combined with the seat lift that still reads as coming up off the bike.
local R6_LEAN: { [string]: number } = {
	Seated = 0,
	Stand = -18,
	NoHander = -10,
	Superman = -34,
	CanCan = -14,
}

type State = {
	joints: { [string]: Motor6D },
	rendered: { [string]: CFrame },
	lift: number,
	forward: number,
	pitch: number,
	seatWeld: Weld?,
	baseC0: CFrame?,
	animate: LocalScript?,
}

local states: { [Model]: State } = {}

local function collect(character: Model): { [string]: Motor6D }
	local joints: { [string]: Motor6D } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			joints[d.Name] = d
		end
	end
	return joints
end

local function stopAnimator(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end
end

--------------------------------------------------------------------------------

-- Call every frame while the character is riding. `trick` is a key of POSES,
-- or nil for the ordinary seated riding pose.
function RiderPose.Update(character: Model, trick: string?, dt: number)
	local state = states[character]
	if not state then
		-- Take the rig over: the default sit animation would fight us for the
		-- same Motor6D.Transform values every frame.
		local animate = character:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") and animate.Enabled then
			animate.Enabled = false
		else
			animate = nil
		end
		stopAnimator(character)

		state = {
			joints = collect(character),
			rendered = {},
			lift = 0,
			forward = 0,
			pitch = 0,
			seatWeld = nil,
			baseC0 = nil,
			animate = animate :: LocalScript?,
		}
		states[character] = state
	end

	local key = (trick ~= nil and POSES[trick] ~= nil) and trick or "Seated"
	local pose = POSES[key]
	local offset = OFFSETS[key]
	local blend = 1 - math.exp(-R.BlendSpeed * dt)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15

	if isR15 then
		for name, targetCF in pose do
			local joint = state.joints[name]
			if joint and joint.Parent then
				local current = state.rendered[name] or CFrame.identity
				local nextCF = current:Lerp(targetCF, blend)
				state.rendered[name] = nextCF
				joint.Transform = nextCF
			end
		end
	else
		local rootJoint = state.joints["RootJoint"]
		if rootJoint and rootJoint.Parent then
			local target = ang(R6_LEAN[key] or 0, 0, 0)
			local current = state.rendered["RootJoint"] or CFrame.identity
			local nextCF = current:Lerp(target, blend)
			state.rendered["RootJoint"] = nextCF
			rootJoint.Transform = nextCF
		end
	end

	-- Lift the rider off the seat. The seat weld's C0 is axis-aligned with the
	-- seat, so this offset is in bike space and tips with the bike.
	state.lift += (offset.Lift - state.lift) * blend
	state.forward += (offset.Forward - state.forward) * blend
	state.pitch += (offset.Pitch - state.pitch) * blend

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local seatWeld = root:FindFirstChild("SeatWeld")
		if seatWeld and seatWeld:IsA("Weld") then
			if state.seatWeld ~= seatWeld then
				state.seatWeld = seatWeld
				state.baseC0 = seatWeld.C0
			end
			local base = state.baseC0
			if base then
				seatWeld.C0 = base
					* CFrame.new(0, state.lift, -state.forward)
					* CFrame.Angles(math.rad(state.pitch), 0, 0)
			end
		end
	end
end

-- Hand the rig back to the normal animation system.
function RiderPose.Release(character: Model)
	local state = states[character]
	if not state then
		return
	end
	states[character] = nil

	for _, joint in state.joints do
		if joint.Parent then
			joint.Transform = CFrame.identity
		end
	end

	local seatWeld = state.seatWeld
	if seatWeld and seatWeld.Parent and state.baseC0 then
		seatWeld.C0 = state.baseC0
	end

	if state.animate and state.animate.Parent then
		state.animate.Enabled = true
	end
end

return RiderPose
