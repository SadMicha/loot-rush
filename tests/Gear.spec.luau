-- Visible gear on the hero (Shared/Gear looks, Systems/Gear builder).
local Classes = require("ReplicatedStorage.Shared.Classes")
local Gear = require("ReplicatedStorage.Shared.Gear")
local Items = require("ReplicatedStorage.Shared.Items")

local RARITIES = { "normal", "magic", "rare", "epic", "unique" }

local function finite(vec, limit)
	if vec == nil then
		return true
	end
	for _, n in { vec.X, vec.Y, vec.Z } do
		if n ~= n or math.abs(n) > (limit or 10) then
			return false
		end
	end
	return true
end

describe("Gear looks", function()
	it("has a look for every class and visible slot, within the part budget", function()
		for _, c in Classes.List do
			local style = Gear.style(c.id, "helmet")
			expect(style).never.toBeNil()
			for _, slot in Gear.Slots do
				expect(Items.SlotName[slot]).never.toBeNil()
				local all = Gear.pieces(style, slot)
				local top = Gear.pieces(style, slot, Gear.TOP_RARITY)
				expect(#all).toBe(#top) -- every piece shows at the top rarity
				expect(#top >= 3).toBe(true)
				expect(#top <= Gear.MAX_PIECES).toBe(true)
				expect(#Gear.pieces(style, slot, "normal") >= 2).toBe(true)
			end
		end
	end)

	it("uses only valid roles, shapes, rarities and finite numbers", function()
		for id, style in Gear.Styles do
			for _, key in { "main", "dark", "metal", "accent" } do
				expect(typeof(style.palette[key])).toBe("Color3")
			end
			for slot, list in style.pieces do
				for i, piece in list do
					local where = `{id}.{slot}[{i}]`
					expect(Gear.Roles[piece.role] and where).toBe(where)
					expect(Gear.Shapes[piece.shape] and where).toBe(where)
					if piece.min then
						expect(Items.rank(piece.min) > 0 and where).toBe(where)
					end
					expect(
						finite(piece.s)
							and finite(piece.p)
							and finite(piece.r, 360)
							and finite(piece.pad)
					).toBe(true)
					expect(piece.s.X > 0).toBe(true)
					if piece.shape ~= "ball" then
						expect(piece.s.Y > 0).toBe(true)
					end
					if piece.shape == "block" or piece.shape == "wedge" then
						expect(piece.s.Z > 0).toBe(true)
					end
					-- part-relative and close to the body: nothing floats far away
					expect(math.abs(piece.p.X) <= 1 and math.abs(piece.p.Z) <= 1).toBe(true)
					expect(math.abs(piece.p.Y) <= 1.8).toBe(true)
				end
			end
		end
	end)

	it("keeps chest pieces out of the head and gloves around the grip", function()
		for id, style in Gear.Styles do
			for _, slot in { "armor", "amulet" } do
				for _, piece in Gear.pieces(style, slot) do
					if piece.part == "UpperTorso" and piece.r == nil then
						local top = piece.p.Y + piece.s.Y / 2
						expect(top <= 0.6 and id).toBe(id) -- head starts at the torso top (0.5)
					end
				end
			end
			for _, piece in Gear.pieces(style, "gloves") do
				if string.find(piece.part, "Hand", 1, true) then
					-- the weapon grip sits in the hand: the glove hugs it, no long fingers
					expect(math.abs(piece.p.Y) + piece.s.Y / 2 <= 0.65).toBe(true)
					expect(piece.s.X <= 1.3 and piece.s.Z <= 1.3).toBe(true)
				end
			end
		end
	end)

	it("shows trim from magic, gems from rare and glow edges from epic", function()
		local floor = { trim = 2, gem = 3, glow = 4 }
		for _, c in Classes.List do
			local style = Gear.Styles[c.id]
			local last = 0
			for rank, rarity in RARITIES do
				local n = Gear.count(style, rarity)
				local seen = {}
				for _, slot in Gear.Slots do
					for _, piece in Gear.pieces(style, slot, rarity) do
						seen[piece.role] = true
						expect(rank >= (floor[piece.role] or 1)).toBe(true)
						expect(Gear.shows(piece, rarity)).toBe(true)
					end
				end
				-- every step up adds pieces (unique may equal epic)
				if rank <= 4 then
					expect(n > last).toBe(true)
				else
					expect(n >= last).toBe(true)
				end
				last = n
				expect(seen.trim == true).toBe(rank >= 2)
				expect(seen.gem == true).toBe(rank >= 3)
				expect(seen.glow == true).toBe(rank >= 4)
			end
		end
		-- unknown rarity = the plain base look
		local plain = Gear.count(Gear.Styles.warrior, "normal")
		expect(Gear.count(Gear.Styles.warrior, "nope")).toBe(plain)
	end)

	it("keeps a full set within the part budget", function()
		expect(Gear.MAX_SET <= 60).toBe(true)
		for _, c in Classes.List do
			local style = Gear.Styles[c.id]
			for _, rarity in RARITIES do
				expect(Gear.count(style, rarity) <= Gear.MAX_SET).toBe(true)
			end
		end
	end)

	it("glows runes, rarity edges and rare gems, studs on everything else", function()
		expect(Gear.finish("main", "unique")).toBe("studs")
		expect(Gear.finish("trim", "epic")).toBe("studs")
		expect(Gear.finish("rune", "normal")).toBe("neon")
		expect(Gear.finish("glow", "epic")).toBe("neon")
		expect(Gear.finish("gem", "rare")).toBe("neon")
		expect(Gear.finish("gem", "magic")).toBe("glass")
		local style = Gear.Styles.mage
		expect(Gear.color(style, "rune", "normal")).toBe(style.palette.accent)
		expect(Gear.color(style, "metal", "rare")).toBe(style.palette.metal)
	end)

	it("mirrors two-sided pieces onto left and right", function()
		local pieces = Gear.pieces(Gear.Styles.warrior, "gloves")
		local left, right
		for _, p in pieces do
			expect(string.find(p.part, "{S}", 1, true)).toBeNil()
			if p.part == "LeftHand" then
				left = p
			elseif p.part == "RightHand" then
				right = p
			end
		end
		expect(left).never.toBeNil()
		expect(right).never.toBeNil()
		expect(left.p.X).toBe(-right.p.X)
		-- `mirror` pieces: two copies on the same part
		local cheeks = {}
		for _, p in Gear.pieces(Gear.Styles.warrior, "helmet") do
			if p.part == "Head" and math.abs(p.s.Y - 0.62) < 1e-4 then
				table.insert(cheeks, p.p.X)
			end
		end
		expect(#cheeks).toBe(2)
		expect(cheeks[1]).toBe(-cheeks[2])
	end)

	it("scales pieces with the body part", function()
		local piece = Gear.Styles.mage.pieces.armor[1]
		local small = Gear.place(piece, Vector3.new(2, 1.6, 1))
		local big = Gear.place(piece, Vector3.new(4, 3.2, 2))
		expect(math.abs(big.X - small.X * 2) < 1e-6).toBe(true)
		local gem
		for _, p in Gear.Styles.mage.pieces.amulet do
			if p.shape == "ball" then
				gem = p
			end
		end
		local ball = Gear.place(gem, Vector3.new(2, 1.6, 1))
		expect(ball.X).toBe(ball.Y)
	end)

	it("falls back to the class look for unknown skins", function()
		expect(Gear.style("ranger", "helmet", "nope").id).toBe("ranger")
		expect(Gear.style("pirate", "helmet")).toBeNil()
	end)

	it("changes the signature only when the worn look changes", function()
		local a = Gear.signature("mage", { helmet = { rarity = "rare" } })
		expect(Gear.signature("mage", { helmet = { rarity = "rare", id = "x" } })).toBe(a)
		expect(Gear.signature("mage", { helmet = { rarity = "epic" } }) ~= a).toBe(true)
		expect(Gear.signature("warrior", { helmet = { rarity = "rare" } }) ~= a).toBe(true)
		expect(Gear.signature("mage", {}) ~= a).toBe(true)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("Visible gear in game", function()
	it("builds worn gear on the body and removes it on unequip", function()
		sim:boot({ seconds = 2 })
		local empty, full, slots, welded, after, studded = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			local Stats = req("ServerScriptService.Server.Systems.Stats")
			local profile = Data.get(player)
			local function count()
				local model = player.Character:FindFirstChild(Gear.MODEL)
				return if model then #model:GetChildren() else 0
			end
			local n0 = count()
			-- the sandbox rig has only Head and UpperTorso: add the other R15 parts
			for _, name in
				{
					"LowerTorso",
					"LeftUpperArm",
					"RightUpperArm",
					"LeftLowerArm",
					"RightLowerArm",
					"LeftUpperLeg",
					"RightUpperLeg",
				}
			do
				local part = Instance.new("Part")
				part.Name = name
				part.Size = Vector3.new(1, 1, 1)
				part.Parent = player.Character
			end
			for _, name in
				{
					"LeftHand",
					"RightHand",
					"LeftLowerLeg",
					"RightLowerLeg",
					"LeftFoot",
					"RightFoot",
				}
			do
				local part = Instance.new("Part")
				part.Name = name
				part.Size = Vector3.new(1, 0.4, 1)
				part.Parent = player.Character
			end
			local rng = Random.new(7)
			for _, slot in Gear.Slots do
				local item = Items.roll(1, rng, nil, { slot = slot, class = profile.class })
				item.rarity = "epic" -- the richest look: trim, gems and Neon edges
				profile.equipped[slot] = item
			end
			Stats.refresh(player, false)
			local model = player.Character:FindFirstChild(Gear.MODEL)
			local names, welds = {}, 0
			for _, p in model:GetChildren() do
				names[p.Name] = true
				local w = p:FindFirstChildOfClass("Weld")
				if w and w.Part0 and w.Part0.Parent == player.Character and w.Part1 == p then
					welds += 1
				end
			end
			local n1 = count()
			-- every piece follows the stud rule: studded Plastic, or a kept glow/glass gem; and
			-- it never touches physics
			local Studs = req("ReplicatedStorage.Shared.Models.Studs")
			local studded = n1 == Gear.count(Gear.Styles[profile.class], "epic")
			for _, p in model:GetChildren() do
				if not Studs.styled(p) then
					studded = false
				elseif not Studs.keeps(p) and p.Material ~= Enum.Material.Plastic then
					studded = false
				end
				if p.CanCollide or p.CanQuery or p.CanTouch or not p.Massless or p.Anchored then
					studded = false
				end
			end
			profile.equipped.helmet = nil
			Stats.refresh(player, false)
			local helmets = 0
			for _, p in player.Character[Gear.MODEL]:GetChildren() do
				if p.Name == "helmet" then
					helmets += 1
				end
			end
			return n0, n1, names, welds == n1, helmets, studded
		end)
		expect(studded).toBe(true)
		expect(empty).toBe(0)
		expect(full > 0).toBe(true)
		for _, slot in Gear.Slots do
			expect(slots[slot]).toBe(true)
		end
		expect(welded).toBe(true)
		expect(after).toBe(0)
	end)

	it("leaves the helmet off with the setting Hide helmet", function()
		local shown, hidden = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			local Settings = req("ServerScriptService.Server.Systems.Settings")
			local Stats = req("ServerScriptService.Server.Systems.Stats")
			local profile = Data.get(player)
			profile.equipped.helmet =
				Items.roll(1, Random.new(3), nil, { slot = "helmet", class = profile.class })
			Stats.refresh(player, false)
			local function helmets()
				local n = 0
				for _, p in player.Character[Gear.MODEL]:GetChildren() do
					if p.Name == "helmet" then
						n += 1
					end
				end
				return n
			end
			local before = helmets()
			Settings.set(player, "hideHelmet", true)
			req("ServerScriptService.Server.Systems.Gear").apply(player) -- Settings.set defers it
			return before, helmets()
		end)
		expect(shown > 0).toBe(true)
		expect(hidden).toBe(0)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
