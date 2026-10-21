--[[
	BoneWriter

	Shared Bone.Transform bookkeeping for every procedural layer on a creature
	(BodyArticulation, LegIK, HeadLook). One writer per character; the driver
	owns it, brackets the frame with BeginFrame/EndFrame, and hands the same
	writer to each layer.

	Why this is shared rather than per-layer
	  * The Animator only rewrites Transform on bones the playing clip actually
	    keyframes, and skips distant rigs when it throttles. Blindly composing
	    onto whatever the bone holds would compound forever on the bones it
	    never touches, so a writer remembers exactly what it wrote and the pose
	    it built that write on: if a bone still holds our value the Animator did
	    not touch it, and the remembered base is reused verbatim. There is no
	    per-frame inverse to accumulate error, which is also why nothing here
	    needs to care about Animator.EvaluationThrottled.
	  * More than one layer legitimately wants the same bone — the neck both
	    leads into a turn (BodyArticulation) and aims at what the creature is
	    looking at (HeadLook). With one writer per layer each would read the
	    other's write as the animation pose and strip it. Here the offsets
	    simply compose in call order on a single remembered base.

	Writes land immediately, not at EndFrame, because layers read
	Bone.TransformedWorldCFrame to convert a world axis into a bone's local
	frame — a child must see its parent's new pose, and LegIK re-reads a joint
	between its own two rotations.

	Frame shape:
		writer:BeginFrame()
		layer:Update(...)   -- Prepare() then Add() the bones it owns
		...
		writer:EndFrame()   -- releases bones no layer touched this frame

	Animated() reads a bone's pose from the clip alone — under whatever the
	layers have added so far — without taking the bone over. LegIK uses it to
	tell a paw the clip lifted from one a bent spine or a banked chest moved.
]]

local BoneWriter = {}
BoneWriter.__index = BoneWriter

-- Write-detection tolerance: must sit above float noise on a CFrame
-- round-trip and below any real Animator delta. Raising it risks treating a
-- genuine animation change as our own write.
local EQ_EPS = 1e-5

type State = {
	base: CFrame, -- the animation pose our offsets are composed onto
	acc: CFrame, -- everything the layers added this frame
	written: CFrame, -- what we last put in Bone.Transform
	frame: number,
}

export type BoneWriter = typeof(setmetatable({} :: { state: { [Bone]: State }, frame: number }, BoneWriter))

local function cframeFuzzyEq(a: CFrame, b: CFrame): boolean
	return a.Position:FuzzyEq(b.Position, EQ_EPS)
		and a.XVector:FuzzyEq(b.XVector, EQ_EPS)
		and a.YVector:FuzzyEq(b.YVector, EQ_EPS)
		and a.ZVector:FuzzyEq(b.ZVector, EQ_EPS)
end

-- ===== rig lookup (shared by every layer) ====================================

-- Every Bone in the character by name, with a count so a configured name that
-- is ambiguous fails loud instead of silently picking one.
function BoneWriter.Index(character: Model): ({ [string]: Bone }, { [string]: number })
	local byName, count = {}, {}
	for _, d in character:GetDescendants() do
		if d:IsA("Bone") then
			byName[d.Name] = byName[d.Name] or d
			count[d.Name] = (count[d.Name] or 0) + 1
		end
	end
	return byName, count
end

-- Which of `names` are not (yet) on the character. Empty = ready to build.
-- The drivers use this to wait out a rig that is still replicating.
function BoneWriter.Missing(character: Model, names: { string }): { string }
	local byName = BoneWriter.Index(character)
	local missing = {}
	for _, n in names do
		if not byName[n] then
			missing[#missing + 1] = n
		end
	end
	return missing
end

-- A resolver that turns a configured bone name into the Bone, and refuses a
-- name that is absent, ambiguous, or already claimed by another part of the
-- SAME layer (two chains sharing a bone is a config bug — two *layers*
-- sharing one is fine and is the point of this module).
function BoneWriter.Claimer(character: Model, layer: string): (string, string) -> Bone
	local byName, count = BoneWriter.Index(character)
	local claimed: { [Bone]: string } = {}
	return function(name: string, where: string): Bone
		local bone = byName[name]
		assert(bone, `{layer}: {where} names bone "{name}" which does not exist on the rig`)
		assert(count[name] == 1, `{layer}: {where} names bone "{name}" which is ambiguous ({count[name]} found)`)
		assert(not claimed[bone], `{layer}: bone "{name}" is written by both {claimed[bone]} and {where}`)
		claimed[bone] = where
		return bone
	end
end

-- ===== per-frame =============================================================

function BoneWriter.new(): BoneWriter
	return setmetatable({ state = {}, frame = 0 }, BoneWriter)
end

function BoneWriter:BeginFrame()
	self.frame += 1
end

-- Track `bone` for this frame and return the animation pose underneath our
-- offsets. On the first touch of a frame the bone is stripped back to that
-- pose; on a later touch by a second layer the bone keeps the offsets already
-- added, so that layer reads (and composes onto) the pose so far.
function BoneWriter:Prepare(bone: Bone): CFrame
	local st = self.state[bone]
	if st and st.frame == self.frame then
		return st.base
	end
	local current = bone.Transform
	local base = if st and cframeFuzzyEq(current, st.written) then st.base else current
	bone.Transform = base
	if st then
		st.base, st.acc, st.written, st.frame = base, CFrame.identity, base, self.frame
	else
		self.state[bone] = { base = base, acc = CFrame.identity, written = base, frame = self.frame }
	end
	return base
end

-- Compose one layer's offset onto the bone and write it out now.
function BoneWriter:Add(bone: Bone, offset: CFrame)
	local st = self.state[bone]
	if not st or st.frame ~= self.frame then
		self:Prepare(bone)
		st = self.state[bone]
	end
	st.acc *= offset
	local t = st.base * st.acc
	bone.Transform = t
	st.written = t
end

-- The pose the animation alone gives `bone` this frame — what Prepare would
-- strip it back to — read without tracking or touching the bone.
function BoneWriter:Animated(bone: Bone): CFrame
	local st = self.state[bone]
	if st and (st.frame == self.frame or cframeFuzzyEq(bone.Transform, st.written)) then
		return st.base
	end
	return bone.Transform
end

-- Give back every bone no layer touched this frame, so a layer that eases out
-- (or stops running) leaves the plain animation pose behind with no
-- per-layer release bookkeeping.
function BoneWriter:EndFrame()
	for bone, st in pairs(self.state) do
		if st.frame ~= self.frame then
			if bone.Parent and cframeFuzzyEq(bone.Transform, st.written) then
				bone.Transform = st.base
			end
			self.state[bone] = nil
		end
	end
end

-- Take every offset back off. Called when the character goes away.
function BoneWriter:Release()
	for bone, st in pairs(self.state) do
		if bone.Parent and cframeFuzzyEq(bone.Transform, st.written) then
			bone.Transform = st.base
		end
	end
	table.clear(self.state)
end

BoneWriter.Destroy = BoneWriter.Release

return BoneWriter
