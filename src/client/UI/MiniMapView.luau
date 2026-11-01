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
local KEY_STEP = 0.05 -- studs; ground parts with the same XZ centre (to this precision) are stacked (top slab over base)

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

-- Ground tiles live in a folder named "Ground"; the hub spawn pad (a SpawnLocation parented directly
-- to Lumenhaven) counts as ground too
local function isGround(part: BasePart): boolean
	if part:IsA("SpawnLocation") then
		return true
	end
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
		-- Top surfaces only: per exact XZ centre keep the ground part with the highest top, so the bases
		-- below the coloured top slabs are skipped. Parts that merely overlap a cell (stair steps) have
		-- their own centre and are never merged away.
		local tops: { [string]: BasePart } = {}
		for _, part in ground do
			local p = part.Position
			local key = string.format(
				"%d_%d",
				math.floor(p.X / KEY_STEP + 0.5),
				math.floor(p.Z / KEY_STEP + 0.5)
			)
			local other = tops[key]
			if not other or other.Position.Y + other.Size.Y / 2 < p.Y + part.Size.Y / 2 then
				tops[key] = part
			end
		end
		table.clear(ground)
		local dist: { [BasePart]: number } = {}
		for _, part in tops do
			-- Distance to the nearest edge of the footprint (not the centre), so big tiles at the rim count
			local p, s = part.Position, part.Size
			local dx = math.max(math.abs(p.X - origin.X) - s.X / 2, 0)
			local dz = math.max(math.abs(p.Z - origin.Z) - s.Z / 2, 0)
			dist[part] = dx * dx + dz * dz
			table.insert(ground, part)
		end
		table.sort(ground, function(a: BasePart, b: BasePart)
			return dist[a] < dist[b]
		end)
		table.sort(props, function(a: BasePart, b: BasePart)
			return a.Size.Magnitude > b.Size.Magnitude
		end)
		-- The cap comes after the filters: the nearest top slabs first (never more than GroundShare of
		-- the cap, so props still show), then the largest props
		local wanted: { BasePart } = {}
		local groundMax = math.floor(M.PartCap * M.GroundShare)
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
		-- Mostly empty (first load, teleport): fill in quickly; otherwise spread the cost
		local have = 0
		for _ in copies do
			have += 1
		end
		local budget = if have < #wanted * 0.5 then M.ClonesBurst else M.ClonesPerRefresh
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
