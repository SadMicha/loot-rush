--!strict
-- Builds the visible gear of a hero (looks: Shared/Gear) from studded parts into the model
-- "WornGear", welded to the R15 body parts. Used by the server (Systems/Gear, replicates to
-- everyone) and by the shop preview on the client (UI/CosmeticPreview, to try gear skins on).
-- The model carries what it shows as attributes (slot = item rarity, "skin_<slot>" = skin id),
-- so a copy of the character can be rebuilt with other skins without the item data.

local Gear = require(script.Parent.Parent.Gear)
local Kit = require(script.Parent.Kit)
local Studs = require(script.Parent.Studs)

local GearBuild = {}

export type Worn = { [string]: any } -- slot → item (only its rarity is read)

-- Every piece goes through the stud rule (Studs.applyAllFaces: 1-stud tiles on all shapes and
-- faces like the world); glowing pieces (runes, rarity edges, gems) keep their Neon/Glass look.
local function makePart(
	model: Model,
	piece: Gear.Piece,
	size: Vector3,
	color: Color3,
	finish: Gear.Finish
): BasePart
	local material = if finish == "neon"
		then Enum.Material.Neon
		elseif finish == "glass" then Enum.Material.Glass
		else nil
	local p: BasePart
	if piece.shape == "wedge" then
		p = Kit.wedge(model, size, CFrame.new(), color, material)
	elseif piece.shape == "ball" then
		p = Kit.ball(model, size.X, Vector3.zero, color, material)
	elseif piece.shape == "disc" then
		p = Kit.cylinder(model, size, CFrame.new(), color, material)
	else
		p = Kit.block(model, size, CFrame.new(), color, material)
	end
	Studs.applyAllFaces(p)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	return p
end

-- Replaces the WornGear model of `character`. skins: slot → skin id the hero may wear
-- (checked by the caller); anchored = true for a still copy (preview) instead of welds.
function GearBuild.build(
	character: Model,
	class: string,
	items: Worn,
	skins: { [string]: string },
	anchored: boolean?
): Model
	local old = character:FindFirstChild(Gear.MODEL)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = Gear.MODEL
	model:SetAttribute("Class", class)
	for _, slot in Gear.Slots do
		local item = items[slot]
		local style = item and Gear.style(class, slot, skins[slot])
		if not item or not style then
			continue
		end
		model:SetAttribute(slot, item.rarity)
		if style.id ~= class then
			model:SetAttribute("skin_" .. slot, style.id)
		end
		for _, piece in Gear.pieces(style, slot, item.rarity) do
			local body = character:FindFirstChild(piece.part)
			if not body or not body:IsA("BasePart") then
				continue -- R6 or a custom rig without this part: skip the piece
			end
			local size, offset = Gear.place(piece, body.Size)
			local color = Gear.color(style, piece.role, item.rarity)
			local p = makePart(model, piece, size, color, Gear.finish(piece.role, item.rarity))
			p.Name = slot
			p.CFrame = body.CFrame * offset
			if anchored then
				p.Anchored = true
			else
				local weld = Instance.new("Weld")
				weld.Part0 = body
				weld.Part1 = p
				weld.C0 = offset
				weld.Parent = p
			end
		end
	end
	model.Parent = character
	return model
end

-- What a built WornGear model shows: class, slot → { rarity }, slot → skin id
function GearBuild.read(model: Instance?): (string?, Worn, { [string]: string })
	local items: Worn, skins: { [string]: string } = {}, {}
	if not model then
		return nil, items, skins
	end
	for _, slot in Gear.Slots do
		local rarity = model:GetAttribute(slot)
		if typeof(rarity) == "string" then
			items[slot] = { rarity = rarity }
		end
		local skin = model:GetAttribute("skin_" .. slot)
		if typeof(skin) == "string" then
			skins[slot] = skin
		end
	end
	local class = model:GetAttribute("Class")
	return if typeof(class) == "string" then class else nil, items, skins
end

return table.freeze(GearBuild)
