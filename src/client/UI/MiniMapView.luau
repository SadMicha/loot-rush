--!strict
-- Terrain view for the minimap: a top-down ViewportFrame that follows the player and shows a light
-- copy of the ground and props within Theme.MiniMap.Range. Purely client-side, nothing is replicated.
-- Cost control: part set refreshed at PartHz, camera at ViewHz, at most PartCap parts, a few new copies
-- per refresh, nothing runs while the view is hidden or there is no character. Only streamed-in parts
-- are visible (StreamingEnabled-safe: a query simply returns what exists on this client).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local MiniMapView = {}

export type View = {
	root: ViewportFrame,
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

function MiniMapView.new(): View
	local M = Theme.MiniMap
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Terrain"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Ambient = M.Ambient
	viewport.LightColor = M.Light
	viewport.LightDirection = Vector3.new(-0.35, -1, -0.25)
	viewport.Size = UDim2.fromScale(1, 1)
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
	tint.Parent = viewport

	local height = M.Range / math.tan(math.rad(M.Fov) / 2)
	local copies: { [BasePart]: BasePart } = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.MaxParts = M.PartCap * 2
	local exclude: { Instance } = {}
	local sincePart, sinceView = math.huge, math.huge

	local function refreshParts(origin: Vector3)
		table.clear(exclude)
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(exclude, p.Character)
			end
		end
		for _, e in CollectionService:GetTagged("Enemy") do
			table.insert(exclude, e)
		end
		params.FilterDescendantsInstances = exclude

		local found = workspace:GetPartBoundsInRadius(origin, M.Range * 1.15, params)
		local wanted: { BasePart } = {}
		for _, part in found do
			local dy = part.Position.Y - origin.Y
			if
				part.Transparency < 0.9
				and part.Size.Magnitude >= M.MinPartSize
				and dy < M.MaxAbove
				and dy > -M.MaxBelow
				and not part:IsA("Terrain")
				and not isCreature(part)
			then
				table.insert(wanted, part)
			end
		end
		-- Big parts (ground) first so the cap never drops the floor
		table.sort(wanted, function(a: BasePart, b: BasePart)
			return a.Size.Magnitude > b.Size.Magnitude
		end)
		local keep: { [BasePart]: boolean } = {}
		for i = 1, math.min(#wanted, M.PartCap) do
			keep[wanted[i]] = true
		end
		for src, copy in copies do
			if not keep[src] then
				copy:Destroy()
				copies[src] = nil
			end
		end
		local budget = M.ClonesPerRefresh
		for i = 1, math.min(#wanted, M.PartCap) do
			local src = wanted[i]
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

	local function clear()
		for src, copy in copies do
			copy:Destroy()
			copies[src] = nil
		end
	end

	local function update(dt: number, rootPart: BasePart?, yaw: number): boolean
		if not rootPart or not viewport.Visible or viewport.AbsoluteSize.X <= 0 then
			if next(copies) ~= nil and not rootPart then
				clear()
			end
			return false
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

	return { root = viewport, update = update }
end

return MiniMapView
