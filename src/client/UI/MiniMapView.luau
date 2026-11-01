--!strict
-- Terrain view for the minimap: a top-down ViewportFrame that follows the player and shows a light
-- copy of the ground and props within Theme.MiniMap.Range. Purely client-side, nothing is replicated.
-- Only the real map containers (workspace.Arena, workspace.Lumenhaven) are scanned, never pets, loot, fx.
-- Cost control: part set refreshed at PartHz, camera at ViewHz, at most PartCap parts (applied after the
-- filters, ground first), a few new copies per refresh, nothing runs while the view is hidden or there
-- is no character (the last copies are kept meanwhile, so a respawn never shows a half-empty map). Only streamed-in parts
-- are visible (StreamingEnabled-safe: a query simply returns what exists on this client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local MiniMapView = {}

-- Containers of the walkable world (see World.luau / Hub.luau); everything else in workspace is ignored
local CONTAINERS = { "Arena", "Lumenhaven" }
local BACKDROP = "Backdrop" -- far scenery folder inside the containers, not part of the map

export type View = {
	root: CanvasGroup, -- circular clip around the terrain viewport and its tint
	-- Call every frame; throttles itself. rootPart = the player's root (nil = no character), yaw = camera yaw
	update: (dt: number, rootPart: BasePart?, yaw: number) -> boolean,
}

-- Copy of a world part without scripts, lights, emitters, decals (keeps the mesh / special mesh)
local function copyOf(src: BasePart): BasePart?
	local cloned = src:Clone()
	if not cloned or not cloned:IsA("BasePart") then
		return nil
	end
	for _, child in cloned:GetChildren() do
		if not child:IsA("SpecialMesh") then
			child:Destroy()
		end
	end
	cloned.Anchored = true
	cloned.CanCollide = false
	cloned.CanQuery = false
	cloned.CanTouch = false
	cloned.CastShadow = false
	if cloned.Material ~= Enum.Material.Neon and cloned.Material ~= Enum.Material.Glass then
		cloned.Material = Enum.Material.SmoothPlastic -- flat look, no texture cost
	end
	return cloned
end

-- True for characters / creatures (they are shown as dots instead)
local function isCreature(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Ground tiles live in a folder named "Ground"; the hub spawn pad counts as ground too
local function isGround(part: BasePart): boolean
	local folder = part:FindFirstAncestor("Ground")
	return folder ~= nil and folder:IsA("Folder")
end

function MiniMapView.new(): View
	local M = Theme.MiniMap
	local group = Instance.new("CanvasGroup") -- clips the viewport render to a circle (UICorner)
	group.Name = "Terrain"
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Size = UDim2.fromScale(1, 1)
	local groupCorner = Instance.new("UICorner")
	groupCorner.CornerRadius = UDim.new(0.5, 0)
	groupCorner.Parent = group

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Ambient = M.Ambient
	viewport.LightColor = M.Light
	viewport.LightDirection = Vector3.new(-0.35, -1, -0.25)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Parent = group
	local camera = Instance.new("Camera")
	camera.FieldOfView = M.Fov
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Dark tint above the terrain, so the bright ground sits in the dark UI palette
	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Theme.Color.Bg0
	tint.BackgroundTransparency = M.Tint
	tint.BorderSizePixel = 0
	tint.ZIndex = 2
	tint.Parent = group
	local tintCorner = Instance.new("UICorner")
	tintCorner.CornerRadius = UDim.new(0.5, 0)
	tintCorner.Parent = tint

	local height = M.Range / math.tan(math.rad(M.Fov) / 2)
	local copies: { [BasePart]: BasePart } = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.MaxParts = 0 -- the Include list already limits the query to the map; the cap comes after filtering
	local include: { Instance } = {}
	local sincePart, sinceView = math.huge, math.huge
	local hadRoot = false

	local function refreshParts(origin: Vector3)
		table.clear(include)
		for _, name in CONTAINERS do
			local c = workspace:FindFirstChild(name)
			if c then
				table.insert(include, c)
			end
		end
		if #include == 0 then
			return
		end
		params.FilterDescendantsInstances = include

		local found = workspace:GetPartBoundsInRadius(origin, M.Range * 1.15, params)
		local ground: { BasePart } = {}
		local props: { BasePart } = {}
		for _, part in found do
			local dy = part.Position.Y - origin.Y
			if
				part.Transparency < 0.9
				and part.Size.Magnitude >= M.MinPartSize
				and dy < M.MaxAbove
				and dy > -M.MaxBelow
				and not part:IsA("Terrain")
				and not isCreature(part)
				and not part:FindFirstAncestor(BACKDROP)
			then
				table.insert(if isGround(part) then ground else props, part)
			end
		end
		local function bySize(a: BasePart, b: BasePart)
			return a.Size.Magnitude > b.Size.Magnitude
		end
		table.sort(ground, bySize)
		table.sort(props, bySize)
		-- The cap comes after the filters: the largest ground parts first (never more than 3/4 of the
		-- cap, so props still show), then the largest props
		local wanted: { BasePart } = {}
		local groundMax = math.floor(M.PartCap * 0.75)
		for i = 1, math.min(#ground, groundMax) do
			table.insert(wanted, ground[i])
		end
		for i = 1, #props do
			if #wanted >= M.PartCap then
				break
			end
			table.insert(wanted, props[i])
		end
		local keep: { [BasePart]: boolean } = {}
		for _, part in wanted do
			keep[part] = true
		end
		for src, copy in copies do
			if not keep[src] then
				copy:Destroy()
				copies[src] = nil
			end
		end
		local budget = M.ClonesPerRefresh
		for _, src in wanted do
			local copy = copies[src]
			if copy then
				if copy.CFrame ~= src.CFrame then
					copy.CFrame = src.CFrame -- moving platforms
				end
			elseif budget > 0 then
				budget -= 1
				local made = copyOf(src)
				if made then
					made.Parent = viewport
					copies[src] = made
				end
			end
		end
	end

	local function update(dt: number, rootPart: BasePart?, yaw: number): boolean
		if not rootPart then
			-- Respawn: keep the last copies until the new character exists (no half-empty map)
			hadRoot = false
			return false
		end
		if not group.Visible or group.AbsoluteSize.X <= 0 then
			return false
		end
		if not hadRoot then
			hadRoot = true
			sincePart = math.huge -- refresh right away for the new character
		end
		sincePart += dt
		sinceView += dt
		if sinceView < 1 / M.ViewHz then
			return false
		end
		sinceView = 0
		local pos = rootPart.Position
		-- Up on screen = viewing direction (same rotation as the enemy dots in HudController)
		camera.CFrame = CFrame.lookAt(
			pos + Vector3.new(0, height, 0),
			pos,
			Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		)
		if sincePart >= 1 / M.PartHz then
			sincePart = 0
			refreshParts(pos)
		end
		return true
	end

	return { root = group, update = update }
end

return MiniMapView
