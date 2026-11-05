-- Gear skins (Shared/GearSkins, Shared/Gear.Skins), the rotating shop (Shared/ShopRotation),
-- the save fields and the server rules (Systems/GearSkins): buying with Soulstars only while in
-- rotation or in season, Robux sets with refunds, free unlocks once, wearing per slot.
local Classes = require("ReplicatedStorage.Shared.Classes")
local Cosmetics = require("ReplicatedStorage.Shared.Cosmetics")
local Gear = require("ReplicatedStorage.Shared.Gear")
local GearSkins = require("ReplicatedStorage.Shared.GearSkins")
local Items = require("ReplicatedStorage.Shared.Items")
local Monetization = require("ReplicatedStorage.Shared.Monetization")
local Profile = require("ReplicatedStorage.Shared.Profile")
local Rotation = require("ReplicatedStorage.Shared.ShopRotation")
local Seasons = require("ReplicatedStorage.Shared.Seasons")

local RARITIES = { "normal", "magic", "rare", "epic", "unique" }
local LIVE = Seasons.Current.starts + 5 * 86400 -- a time inside the Beta Season

describe("Gear skin catalog", function()
	it("every skin has a look for its slot, roles that show rarity and a source", function()
		for _, s in GearSkins.List do
			local style = Gear.Skins[s.id]
			expect(style).never.toBeNil()
			local normal = Gear.pieces(style, s.slot, "normal")
			local top = Gear.pieces(style, s.slot, Gear.TOP_RARITY)
			expect(#normal >= 2 and s.id).toBe(s.id)
			expect(#top <= Gear.MAX_PIECES and s.id).toBe(s.id)
			expect(#top > #normal and s.id).toBe(s.id) -- trim, gems, glow: the rarity still reads
			expect(Items.SlotName[s.slot]).never.toBeNil()
			expect(s.hint ~= "").toBe(true)
			expect(Gear.style("mage", s.slot, s.id).id).toBe(s.id)
			if s.source.kind == "shop" then
				expect(s.price).toBe(GearSkins.Price[GearSkins.SlotSize[s.slot]])
			else
				expect(s.price).toBeNil()
			end
		end
	end)

	it("keeps every class set within the part budget with any skin swapped in", function()
		for _, c in Classes.List do
			local base = Gear.Styles[c.id]
			for _, s in GearSkins.List do
				local style = Gear.Skins[s.id]
				for _, rarity in RARITIES do
					local n = Gear.count(base, rarity)
						- #Gear.pieces(base, s.slot, rarity)
						+ #Gear.pieces(style, s.slot, rarity)
					expect(n <= Gear.MAX_SET and s.id).toBe(s.id)
				end
			end
		end
	end)

	it("places skin pieces close to the body like the class looks", function()
		for id, style in Gear.Skins do
			for slot, list in style.pieces do
				for _, piece in Gear.pieces(style, slot) do
					expect(Gear.Roles[piece.role] and id).toBe(id)
					expect(Gear.Shapes[piece.shape] and id).toBe(id)
					expect(math.abs(piece.p.X) <= 1 and math.abs(piece.p.Z) <= 1).toBe(true)
					expect(math.abs(piece.p.Y) <= 1.8).toBe(true)
					if piece.part == "UpperTorso" and piece.r == nil then
						expect(piece.p.Y + piece.s.Y / 2 <= 0.6 and id).toBe(id)
					end
					if string.find(piece.part, "Hand", 1, true) then
						expect(math.abs(piece.p.Y) + piece.s.Y / 2 <= 0.65 and id).toBe(id)
						expect(piece.s.X <= 1.3 and piece.s.Z <= 1.3).toBe(true)
					end
				end
				expect(#list > 0).toBe(true)
			end
		end
	end)

	it("class skins fit only their class, class-free ones every class", function()
		expect(GearSkins.fits("helmet", "paladin_helm", "warrior")).toBe(true)
		expect(GearSkins.fits("helmet", "paladin_helm", "mage")).toBe(false)
		expect(GearSkins.fits("helmet", "pumpkin_helm", "mage")).toBe(true)
		expect(GearSkins.fits("armor", "pumpkin_helm", "mage")).toBe(false) -- wrong slot
		expect(GearSkins.fits("helmet", "nope", "mage")).toBe(false)
		expect(GearSkins.fits("helmet", "", "mage")).toBe(false)
	end)

	it("prices sets 20% under their pieces and Robux sets from the pack rates", function()
		local paladin = GearSkins.SetById.paladin
		expect(GearSkins.setPrice(paladin)).toBe(1400) -- 600 + 800 + 300 = 1,700
		expect(GearSkins.robuxFor(1400)).toBe(549)
		-- owned pieces lower the set price, a complete set costs nothing
		expect(GearSkins.setPrice(paladin, function(id)
			return id == "paladin_plate"
		end)).toBe(700)
		expect(GearSkins.setPrice(paladin, function()
			return true
		end)).toBe(0)
		for _, set in GearSkins.Sets do
			local full = GearSkins.setPrice(set)
			local pieces = 0
			for _, id in set.pieces do
				pieces += GearSkins.ById[id].price
			end
			expect(full < pieces).toBe(true)
			if set.product then
				local p = Monetization.ProductByKey[set.product]
				expect(p).never.toBeNil()
				expect(p.robux).toBe(GearSkins.robuxFor(full))
				-- never cheaper than buying the Soulstars at the best pack rate
				expect(p.robux >= full * GearSkins.Price.robuxBest).toBe(true)
				expect(#p.skins).toBe(#set.pieces)
				for i, id in set.pieces do
					expect(p.skins[i]).toBe(id)
				end
			else
				expect(set.season).never.toBeNil() -- season sets: Soulstars only
			end
		end
	end)

	it("cosmetic packs are never cheaper than their pieces at the best Soulstar rate", function()
		for _, p in Monetization.Products do
			if p.cosmetics and not p.once then
				local sum = 0
				for _, id in p.cosmetics do
					sum += Cosmetics.ById[id].soulstars or 0
				end
				expect(p.robux >= sum * GearSkins.Price.robuxBest).toBe(true)
			end
		end
	end)

	it("free skins come from existing milestones, season ones only while live", function()
		local ctx = {
			facts = { depth = 12, guide = 1, bosses = 2 },
			daily = 7,
			build = 999,
			track = { ["3"] = true },
			live = function(id)
				return id == "beta"
			end,
		}
		local got = {}
		for _, id in GearSkins.newlyEarned({}, ctx) do
			got[id] = true
		end
		expect(got.rift_walker_boots).toBe(true)
		expect(got.lumen_circlet).toBe(true)
		expect(got.daily_loyalist_belt).toBe(true)
		expect(got.beacon_dawn_helm).toBe(true)
		expect(got.beta_pioneer_pendant).toBe(true)
		expect(got.conqueror_crown).toBeNil()
		expect(got.journey_gauntlets).toBeNil()
		expect(got.beacon_mantle).toBeNil() -- 999 of 1,000 shards
		expect(got.beacon_dawn_greaves).toBeNil()
		expect(got.pumpkin_helm).toBeNil() -- paid
		-- owned ones are not granted again
		expect(
			#GearSkins.newlyEarned({ rift_walker_boots = true }, ctx)
				< #GearSkins.newlyEarned({}, ctx)
		).toBe(true)
		-- the season is over: no season skin any more, the others still
		ctx.live = function()
			return false
		end
		local late = {}
		for _, id in GearSkins.newlyEarned({}, ctx) do
			late[id] = true
		end
		expect(late.beacon_dawn_helm).toBeNil()
		expect(late.beta_pioneer_pendant).toBeNil()
		expect(late.rift_walker_boots).toBe(true)
	end)

	it("a season is only available while it is live", function()
		local beta = Seasons.Current
		expect(GearSkins.available(nil, 0)).toBe(true)
		expect(GearSkins.available("beta", beta.starts - 10)).toBe(false)
		expect(GearSkins.available("beta", LIVE)).toBe(true)
		expect(GearSkins.available("season_99", LIVE)).toBe(false)
	end)
end)

describe("Rotating shop", function()
	it("never sells season items and has enough for the groups", function()
		for _, e in Rotation.DailyPool do
			if e.kind == "skin" then
				expect(GearSkins.ById[e.id].season).toBeNil()
				expect(GearSkins.ById[e.id].price).never.toBeNil()
			else
				expect(e.kind).toBe("cosmetic")
				expect(Cosmetics.ById[e.id].season).toBeNil()
			end
		end
		for _, e in Rotation.WeeklyPool do
			expect(e.kind).toBe("set")
			expect(GearSkins.SetById[e.id].season).toBeNil()
		end
		expect(#Rotation.DailyPool >= Rotation.DAILY * Rotation.GROUPS).toBe(true)
		expect(#Rotation.WeeklyPool >= Rotation.WEEKLY).toBe(true)
	end)

	it("is the same on every call and gives 4 daily and 2 weekly offers", function()
		for day = 20300, 20340 do
			local a, b = Rotation.daily(day), Rotation.daily(day)
			expect(#a).toBe(Rotation.DAILY)
			for i = 1, #a do
				expect(Rotation.key(a[i])).toBe(Rotation.key(b[i]))
			end
			local seen = {}
			for _, e in a do
				expect(seen[Rotation.key(e)]).toBeNil()
				seen[Rotation.key(e)] = true
			end
		end
		for week = 2890, 2900 do
			local w = Rotation.weekly(week)
			expect(#w).toBe(Rotation.WEEKLY)
			expect(Rotation.key(w[1]) ~= Rotation.key(w[2])).toBe(true)
		end
	end)

	it("does not repeat a daily piece within 3 days and shows every piece", function()
		local lastSeen = {}
		local shown = {}
		for day = 20000, 20400 do
			for _, e in Rotation.daily(day) do
				local k = Rotation.key(e)
				if lastSeen[k] then
					expect(day - lastSeen[k] > 3).toBe(true)
				end
				lastSeen[k] = day
				shown[k] = true
			end
		end
		for _, e in Rotation.DailyPool do
			expect(shown[Rotation.key(e)]).toBe(true)
		end
	end)

	it("refreshes at 00:00 UTC and on Monday 00:00 UTC", function()
		local monday = 1793577600 -- 2026-11-02 00:00 UTC, a Monday
		local d, w = Rotation.leavesIn(monday)
		expect(d).toBe(86400)
		expect(w).toBe(7 * 86400)
		local d2, w2 = Rotation.leavesIn(monday + 86400 * 2 + 3600)
		expect(d2).toBe(86400 - 3600)
		expect(w2).toBe(5 * 86400 - 3600)
		expect(Rotation.weekOf(monday - 1) + 1).toBe(Rotation.weekOf(monday))
		expect(Rotation.weekOf(monday + 7 * 86400 - 1)).toBe(Rotation.weekOf(monday))
		local today = Rotation.daily(Rotation.dayOf(LIVE))[1]
		expect(Rotation.offered(today.kind, today.id, LIVE)).toBe(true)
		local week = Rotation.weekly(Rotation.weekOf(LIVE))[1]
		expect(Rotation.offered(week.kind, week.id, LIVE)).toBe(true)
		expect(Rotation.offered("skin", "beacon_dawn_sash", LIVE)).toBe(false)
	end)
end)

describe("Gear skins in the save", function()
	it("keeps owned skins, wears only owned skins that fit the slot", function()
		local fresh = Profile.freshAccount()
		expect(next(fresh.gearSkins)).toBeNil()
		expect(next(fresh.gearWear)).toBeNil()
		local fixed = Profile.reconcileAccount({
			gearSkins = { pumpkin_helm = true, crystal_plate = true, [4] = true, bad = 1 },
			gearWear = {
				helmet = "pumpkin_helm",
				armor = "paladin_plate", -- not owned
				gloves = "crystal_plate", -- wrong slot
				boots = 5,
			},
		})
		expect(fixed.gearSkins.pumpkin_helm).toBe(true)
		expect(fixed.gearSkins.bad).toBeNil()
		expect(fixed.gearWear.helmet).toBe("pumpkin_helm")
		expect(fixed.gearWear.armor).toBeNil()
		expect(fixed.gearWear.gloves).toBeNil()
		expect(fixed.gearWear.boots).toBeNil()
	end)
end)

-- ------------------------------------------------------------------ In game
local SET_ID = 811

local function liveSet()
	local native = sim:nativeOf(sim:find("ReplicatedStorage.Shared.Monetization"))
	local source = native.Source
	local count
	source, count =
		string.gsub(source, "\n\tskinset_paladin = %d+,", `\n\tskinset_paladin = {SET_ID},`, 1)
	assert(count == 1, "skinset_paladin ID not found")
	for _, key in { "vip", "pet_slot", "magnet" } do
		source = string.gsub(source, "\n\t" .. key .. " = %d+,", `\n\t{key} = 0,`, 1)
	end
	native.Source = source
	sim.modules.server = {}
	sim.modules.client = {}
end

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function account()
	return server(function(req, player)
		return req("ServerScriptService.Server.Systems.Data").account(player)
	end)
end

local function setNow(t)
	server(function(req)
		req("ServerScriptService.Server.Systems.GearSkins").now = function()
			return t
		end
	end)
end

local function send(...)
	local args = table.pack(...)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Skin:FireServer(table.unpack(args, 1, args.n))
	end)
	sim:run(0.5)
end

local function soulstars(n)
	server(function(req, player)
		local a = req("ServerScriptService.Server.Systems.Data").account(player)
		a.soulstars = n
	end)
end

-- A daily skin and a skin that is not on sale on day LIVE
local function todays()
	local inShop, notInShop
	for _, e in Rotation.daily(Rotation.dayOf(LIVE)) do
		if e.kind == "skin" and not inShop then
			inShop = e.id
		end
	end
	for _, e in Rotation.DailyPool do
		if e.kind == "skin" and not Rotation.offered("skin", e.id, LIVE) then
			notInShop = e.id
			break
		end
	end
	return inShop, notInShop
end

describe("Gear skins in game", function()
	it("buys a skin of today's shop for Soulstars, refuses skins out of rotation", function()
		liveSet()
		sim:boot({ seconds = 2 })
		setNow(LIVE)
		local inShop, notInShop = todays()
		expect(inShop).never.toBeNil()
		expect(notInShop).never.toBeNil()
		local price = GearSkins.ById[inShop].price
		soulstars(price - 1)
		send("buy", "skin", inShop)
		expect(account().gearSkins[inShop]).toBeNil() -- too poor
		soulstars(price + 50)
		send("buy", "skin", notInShop)
		expect(account().gearSkins[notInShop]).toBeNil()
		send("buy", "skin", inShop)
		local a = account()
		expect(a.gearSkins[inShop]).toBe(true)
		expect(a.soulstars).toBe(50)
		send("buy", "skin", inShop) -- owned: nothing charged
		expect(account().soulstars).toBe(50)
		-- nonsense never errors
		send("buy", 5, {})
		send("buy", "skin", string.rep("x", 200))
		send("buy", "pet", "x")
	end)

	it("season skins sell only while the season is live", function()
		soulstars(1000)
		setNow(Seasons.Current.starts - 60)
		send("buy", "skin", "beacon_dawn_sash")
		expect(account().gearSkins.beacon_dawn_sash).toBeNil()
		setNow(LIVE)
		send("buy", "skin", "beacon_dawn_sash")
		local a = account()
		expect(a.gearSkins.beacon_dawn_sash).toBe(true)
		expect(a.soulstars).toBe(700)
		-- the season set now costs only the two missing pieces
		local set = GearSkins.SetById.beacon_dawn_shop
		local price = GearSkins.setPrice(set, function(id)
			return a.gearSkins[id] == true
		end)
		expect(price).toBe(500) -- (300 + 300) × 0.8 = 480 → 500
		send("buy", "set", "beacon_dawn_shop")
		local b = account()
		expect(b.gearSkins.beacon_dawn_gauntlets).toBe(true)
		expect(b.gearSkins.beacon_dawn_lantern).toBe(true)
		expect(b.soulstars).toBe(200)
	end)

	it("grants the Beta pendant on join while the Beta is live, only once", function()
		local first, again = server(function(req, player)
			local GS = req("ServerScriptService.Server.Systems.GearSkins")
			GS.now = function()
				return LIVE
			end
			local a = req("ServerScriptService.Server.Systems.Data").account(player)
			a.gearSkins.beta_pioneer_pendant = nil
			local n1 = #GS.check(player)
			local n2 = #GS.check(player)
			return n1, n2
		end)
		expect(first >= 1).toBe(true)
		expect(again).toBe(0)
		expect(account().gearSkins.beta_pioneer_pendant).toBe(true)
	end)

	it(
		"wears owned skins per slot and shows them on the body, class skins only for their class",
		function()
			local inShop = todays()
			local skin = GearSkins.ById[inShop]
			local built = server(function(req, player)
				local Data = req("ServerScriptService.Server.Systems.Data")
				local Stats = req("ServerScriptService.Server.Systems.Stats")
				local profile = Data.get(player)
				profile.equipped[skin.slot] =
					Items.roll(1, Random.new(5), nil, { slot = skin.slot, class = profile.class })
				Stats.refresh(player, false)
				return player.Character:FindFirstChild(Gear.MODEL) ~= nil
			end)
			expect(built).toBe(true)
			send("wear", skin.slot, "")
			expect(account().gearWear[skin.slot]).toBeNil()
			send("wear", skin.slot, inShop)
			expect(account().gearWear[skin.slot]).toBe(inShop)
			send("wear", skin.slot, "paladin_helm") -- not owned
			expect(account().gearWear[skin.slot]).toBe(inShop)
			send("wear", "weapon", inShop) -- not a gear skin slot
			send("wear", skin.slot, "beacon_dawn_sash") -- owned, wrong slot (unless belt)
			local worn = account().gearWear[skin.slot]
			expect(worn == inShop or (skin.slot == "belt" and worn == "beacon_dawn_sash")).toBe(
				true
			)
			send("wear", skin.slot, inShop)
			sim:run(0.5)
			local shown = server(function(_, player)
				local model = player.Character:FindFirstChild(Gear.MODEL)
				return model and model:GetAttribute("skin_" .. skin.slot)
			end)
			expect(shown).toBe(if skin.class == nil then inShop else nil)
		end
	)

	it("a Robux set grants its pieces; owned pieces are refunded up to the set value", function()
		soulstars(0)
		server(function(req, player)
			local a = req("ServerScriptService.Server.Systems.Data").account(player)
			a.gearSkins.paladin_plate = true
		end)
		local decision = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Monetization").processReceipt({
				ProductId = SET_ID,
				PlayerId = player.UserId,
				PurchaseId = "set-1",
			})
		end)
		sim:run(1)
		expect(decision).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		local a = account()
		expect(a.gearSkins.paladin_helm).toBe(true)
		expect(a.gearSkins.paladin_gauntlets).toBe(true)
		-- 1,400 set value minus 700 for the two missing pieces as a set
		expect(a.soulstars).toBe(700)
		-- everything owned: never more than the set's Soulstar value back
		local again = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Monetization").processReceipt({
				ProductId = SET_ID,
				PlayerId = player.UserId,
				PurchaseId = "set-2",
			})
		end)
		sim:run(1)
		expect(again).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(account().soulstars).toBe(700 + 1400)
	end)

	it("the Shop shows the Daily Shop, the season shop and the gear wardrobe", function()
		local result = { ok = false, err = "", daily = 0, season = false, rows = 0, timer = "" }
		sim:runAs("client", function(req)
			local base = "Players." .. sim.player.Name .. ".PlayerScripts.Client."
			local Store = req(base .. "Controllers.StoreController")
			local ok, err = pcall(function()
				Store.open("daily")
				local gui = game:GetService("Players").LocalPlayer.PlayerGui
				local function find(name)
					for _, d in gui:GetDescendants() do
						if d.Name == name then
							return d
						end
					end
					return nil
				end
				for _, d in gui:GetDescendants() do
					if string.sub(d.Name, 1, 5) == "Skin_" then
						result.daily += 1
					end
				end
				result.season = find("Skin_set_beacon_dawn_shop") ~= nil
				for _, d in gui:GetDescendants() do
					if d.Name == "RotationTimer" then
						result.timer ..= d.Text .. "|"
					end
				end
				Store.open("cosmetics")
				for _, d in gui:GetDescendants() do
					if string.sub(d.Name, 1, 5) == "Gear_" then
						result.rows += 1
					end
				end
			end)
			result.ok = ok
			result.err = tostring(err)
		end)
		-- a locked skin: tapping it tries it on in the preview
		local cell, caption
		for _, d in sim.player.PlayerGui:GetDescendants() do
			if d.Name == "Wear_pumpkin_helm" then
				cell = d
			end
		end
		expect(cell).toBeTruthy()
		sim:click(cell)
		sim:run(0.5)
		for _, d in sim.player.PlayerGui:GetDescendants() do
			if d.Name == "Caption" and d:IsA("TextLabel") then
				caption = d.Text
			end
		end
		expect(caption).toBe("Trying on: Pumpkin Helm")
		expect(result.err).toBe("nil")
		expect(result.ok).toBe(true)
		expect(result.daily >= Rotation.DAILY + Rotation.WEEKLY).toBe(true)
		expect(result.rows).toBe(#Gear.Slots)
		expect(string.find(result.timer, "Refreshes in", 1, true)).never.toBeNil()
		expect(string.find(result.timer, "Leaves in", 1, true)).never.toBeNil()
		local _ = result.season -- the season shop shows only while the real clock is in the Beta
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
