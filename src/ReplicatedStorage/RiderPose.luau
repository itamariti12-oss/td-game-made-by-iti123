--!strict
-- RiderPose
-- The stand-up-on-the-pegs animation, built the same way the bike is: in code,
-- at runtime. No uploaded animation assets.
--
-- Roblox animations are just Motor6D.Transform values written every frame, so
-- that is exactly what this does. Every client runs it for every rider, which
-- is how a normal animation would replicate anyway.
--
-- Two poses, crossfaded by `alpha`:
--   SEATED   -- sat down, knees up on the pegs, leaning into the bars
--   STANDING -- up off the seat, legs almost straight, chest over the bars,
--               the pose in the wheelie reference photo

local Config = require(script.Parent.BikeConfig)

local RiderPose = {}

local R = Config.Rider

-- Every R15 joint's C0/C1 is rotation-free in the rest pose, so a Transform
-- rotation acts in character space: +X rotation swings a downward-pointing
-- limb forwards, and rotating about Z swings it out to the side.
local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- side is -1 for left, +1 for right, so one table describes both limbs.
local function poseR15(standing: boolean): { [string]: CFrame }
	if standing then
		return {
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
	end
	return {
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
end

-- R6 has one joint per limb with pre-rotated C0s, so it gets a simpler
-- treatment: lean the whole body and let the seat lift do the talking.
local function poseR6(standing: boolean): { [string]: CFrame }
	if standing then
		return { RootJoint = ang(0, 0, 0), Neck = ang(0, 0, 0) }
	end
	return { RootJoint = ang(0, 0, 0), Neck = ang(0, 0, 0) }
end

local SEATED_R15 = poseR15(false)
local STANDING_R15 = poseR15(true)

-- Per-character blend state, so a rider who leaves mid-blend cleans up.
local states: { [Model]: { alpha: number, joints: { [string]: Motor6D }, seatWeld: Weld?, baseC0: CFrame?, animate: LocalScript? } } = {}

local function collect(character: Model)
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

-- Call every frame while the character is riding.
function RiderPose.Update(character: Model, standing: boolean, dt: number)
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
			alpha = 0,
			joints = collect(character),
			seatWeld = nil,
			baseC0 = nil,
			animate = animate :: LocalScript?,
		}
		states[character] = state
	end

	local target = standing and 1 or 0
	state.alpha += math.clamp(target - state.alpha, -R.BlendSpeed * dt, R.BlendSpeed * dt)
	local alpha = state.alpha

	-- Lift the rider off the seat. The seat weld's C0 is axis-aligned with the
	-- seat, so this offset is in bike space and tips with the bike.
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
					* CFrame.new(0, R.StandLift * alpha, -R.StandForward * alpha)
					* CFrame.Angles(math.rad(R.StandPitch) * alpha, 0, 0)
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15

	if isR15 then
		for name, seatedCF in SEATED_R15 do
			local joint = state.joints[name]
			if joint and joint.Parent then
				joint.Transform = seatedCF:Lerp(STANDING_R15[name], alpha)
			end
		end
	else
		-- R6: lean the torso, which with the seat lift still reads as standing.
		local rootJoint = state.joints["RootJoint"]
		if rootJoint and rootJoint.Parent then
			rootJoint.Transform = ang(0, 0, 0):Lerp(ang(-18, 0, 0), alpha)
		end
		local _ = poseR6
	end
end

-- Hand the rig back to the normal animation system.
function RiderPose.Release(character: Model)
	local state = states[character]
	if not state then
		return
	end

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

	states[character] = nil
end

return RiderPose
