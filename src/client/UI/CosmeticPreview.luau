--!strict
-- Shop preview of cosmetics: a turning copy of the own hero on a studded pedestal inside a
-- ViewportFrame, wearing the 3D aura (Client/Fx/CosmeticRig, parts only: particles and beams do
-- not render in a ViewportFrame) and a comet that shows the trail colors.
--   local p = CosmeticPreview.new(size)   p.frame → parent it anywhere
--   p.show(auraId, trailId)               "" = nothing in that slot; rebuilds only what changed
--   p.refresh()                           new copy of the hero (after respawn / gear change)
--   p.destroy()
-- Animates only while the frame is on screen; one BulkMoveTo per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Fx = require(ReplicatedStorage.Shared.CosmeticFx)
local Models = require(ReplicatedStorage.Shared.Models.Kit)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Rig = require(script.Parent.Parent.Fx.CosmeticRig)
local Flat = require(script.Parent.Flat)

local CosmeticPreview = {}

local S = Theme.Store
local PEDESTAL = 6 -- studs across

export type Preview = {
	frame: Frame,
	show: (aura: string, trail: string) -> (),
	refresh: () -> (),
	destroy: () -> (),
}

function CosmeticPreview.new(size: Vector2): Preview
	local player = Players.LocalPlayer
	local frame = Flat.card(UDim2.fromOffset(size.X, size.Y))
	frame.Name = "Preview"
	frame.ClipsDescendants = true

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Stage"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = S.PreviewAmbient
	viewport.LightColor = S.PreviewLight
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.ZIndex = 2
	viewport.Parent = frame

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 5.2, -17), Vector3.new(0, 2.6, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Studded pedestal: the hero stands on y = 0
	local base = Models.cylinder(
		world,
		Vector3.new(0.6, PEDESTAL, PEDESTAL),
		CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
		S.PreviewPedestal
	)
	base.Name = "Pedestal"
	local rim = Models.cylinder(
		world,
		Vector3.new(0.3, PEDESTAL + 0.6, PEDESTAL + 0.6),
		CFrame.new(0, -0.75, 0) * CFrame.Angles(0, 0, math.pi / 2),
		S.PreviewRim
	)
	rim.Name = "Rim"

	local hero: Model? = nil
	local heroDrop = 3 -- root center above the feet
	local auraId, trailId = "", ""
	local aura: Rig.Rig? = nil
	local trail: Rig.Rig? = nil
	local t0 = os.clock()
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}

	local function copyHero()
		if hero then
			hero:Destroy()
			hero = nil
		end
		local character = player.Character
		if not character then
			return
		end
		local was = character.Archivable
		character.Archivable = true
		local clone = character:Clone()
		character.Archivable = was
		if not clone then
			return
		end
		for _, d in clone:GetDescendants() do
			if
				d:IsA("Script")
				or d:IsA("LocalScript")
				or d:IsA("ParticleEmitter")
				or d:IsA("Trail")
			then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local root = clone:FindFirstChild("HumanoidRootPart")
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			local r15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
			heroDrop = Fx.feetDrop(r15, if humanoid then humanoid.HipHeight else 2, root.Size.Y)
			clone.PrimaryPart = root
		end
		clone.Parent = world
		hero = clone
	end

	local function build()
		if aura then
			Rig.destroy(aura)
			aura = nil
		end
		if trail then
			Rig.destroy(trail)
			trail = nil
		end
		local a = Cosmetics.ById[auraId]
		if a and a.slot == "aura" then
			aura = Rig.aura(a, Fx.plan(a, "full"), world, { world = false })
		end
		local tr = Cosmetics.ById[trailId]
		if tr and tr.slot == "trail" then
			trail = Rig.trailGhost(tr, world)
		end
	end

	local function step()
		if not frame.Parent or not frame.Visible then
			return
		end
		local gui = frame:FindFirstAncestorWhichIsA("LayerCollector")
		if gui and not gui.Enabled then
			return
		end
		local t = os.clock() - t0
		local yaw = CFrame.Angles(0, t * S.PreviewSpin, 0)
		local h = hero
		if h and h.PrimaryPart then
			h:PivotTo(yaw * CFrame.new(0, heroDrop, 0))
		end
		table.clear(parts)
		table.clear(cfs)
		local origin = CFrame.identity
		if aura then
			Rig.step(aura, origin, t, parts, cfs)
		end
		if trail then
			Rig.step(trail, origin, t, parts, cfs)
		end
		if #parts > 0 then
			world:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	local conn = RunService.Heartbeat:Connect(step)
	copyHero()

	local preview: Preview
	preview = {
		frame = frame,
		show = function(newAura: string, newTrail: string)
			if
				newAura == auraId
				and newTrail == trailId
				and (aura ~= nil or trail ~= nil or (newAura == "" and newTrail == ""))
			then
				return
			end
			auraId, trailId = newAura, newTrail
			build()
			-- a short shock ring on the pedestal: the change is felt
			local c = Cosmetics.ById[if newAura ~= "" then newAura else newTrail]
			if c then
				Rig.burst(
					world,
					CFrame.new(0, 0.05, 0),
					Fx.style(c).core,
					PEDESTAL * 0.7,
					c.slot == "aura"
				)
			end
		end,
		refresh = function()
			copyHero()
		end,
		destroy = function()
			conn:Disconnect()
			if aura then
				Rig.destroy(aura)
			end
			if trail then
				Rig.destroy(trail)
			end
			frame:Destroy()
		end,
	}
	frame.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return preview
end

return CosmeticPreview
