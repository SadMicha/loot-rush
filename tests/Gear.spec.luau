-- Visible gear on the hero (Shared/Gear looks, Systems/Gear builder).
local Classes = require("ReplicatedStorage.Shared.Classes")
local Gear = require("ReplicatedStorage.Shared.Gear")
local Items = require("ReplicatedStorage.Shared.Items")

describe("Gear looks", function()
	it("has a look for every class and visible slot, within the part budget", function()
		for _, c in Classes.List do
			local style = Gear.style(c.id, "helmet")
			expect(style).never.toBeNil()
			for _, slot in Gear.Slots do
				expect(Items.SlotName[slot]).never.toBeNil()
				local pieces = Gear.pieces(style, slot)
				expect(#pieces > 0).toBe(true)
				expect(#pieces <= Gear.MAX_PIECES).toBe(true)
			end
		end
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
	end)

	it("scales pieces with the body part", function()
		local piece = Gear.Styles.mage.pieces.armor[1]
		local small = Gear.place(piece, Vector3.new(2, 1.6, 1))
		local big = Gear.place(piece, Vector3.new(4, 3.2, 2))
		expect(math.abs(big.X - small.X * 2) < 1e-6).toBe(true)
		local ball = Gear.place(Gear.Styles.mage.pieces.amulet[2], Vector3.new(2, 1.6, 1))
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
		local empty, full, slots, welded, after = server(function(req, player)
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
				{ "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }
			do
				local part = Instance.new("Part")
				part.Name = name
				part.Size = Vector3.new(1, 1, 1)
				part.Parent = player.Character
			end
			for _, name in
				{ "LeftHand", "RightHand", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot" }
			do
				local part = Instance.new("Part")
				part.Name = name
				part.Size = Vector3.new(1, 0.4, 1)
				part.Parent = player.Character
			end
			local rng = Random.new(7)
			for _, slot in Gear.Slots do
				local item = Items.roll(1, rng, nil, { slot = slot, class = profile.class })
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
			profile.equipped.helmet = nil
			Stats.refresh(player, false)
			local helmets = 0
			for _, p in player.Character[Gear.MODEL]:GetChildren() do
				if p.Name == "helmet" then
					helmets += 1
				end
			end
			return n0, n1, names, welds == n1, helmets
		end)
		expect(empty).toBe(0)
		expect(full > 0).toBe(true)
		for _, slot in Gear.Slots do
			expect(slots[slot]).toBe(true)
		end
		expect(welded).toBe(true)
		expect(after).toBe(0)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
