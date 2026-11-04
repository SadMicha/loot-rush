--!nocheck
-- The Great Build (Shared/GreatBuild, Systems/GreatBuild, Client/GreatBuildController): stage
-- math, the idempotent batch transform, the personal cap and milestones, the save field, and the
-- real server + window: donations only at the chute, never more than owned or the daily cap,
-- batches land in the DataStore, a finished stage builds the monument and starts the buff.
local Balance = require("ReplicatedStorage.Shared.Balance")
local GreatBuild = require("ReplicatedStorage.Shared.GreatBuild")
local Profile = require("ReplicatedStorage.Shared.Profile")

local DAY = 86400
local NOW = 1793750400 + 3 * DAY + 600

describe("Great Build rules", function()
	it("splits the goal into growing stages", function()
		local B = Balance.GreatBuild
		expect(#GreatBuild.Sizes).toBe(B.stages)
		expect(GreatBuild.Sizes[1]).toBe(B.first)
		for i = 2, B.stages do
			expect(GreatBuild.Sizes[i] > GreatBuild.Sizes[i - 1]).toBe(true)
		end
		local done, into, size = GreatBuild.stage(0)
		expect(done).toBe(0)
		expect(into).toBe(0)
		expect(size).toBe(B.first)
		done, into, size = GreatBuild.stage(B.first + 10)
		expect(done).toBe(1)
		expect(into).toBe(10)
		expect(size).toBe(GreatBuild.Sizes[2])
		done, into, size = GreatBuild.stage(GreatBuild.GOAL + 5)
		expect(done).toBe(B.stages)
		expect(size).toBe(0)
		expect(GreatBuild.stage(0 / 0)).toBe(0)
		expect(#GreatBuild.crossed(0, GreatBuild.Ends[3])).toBe(3)
	end)

	it("adds a server's batch once, even when the write is retried", function()
		local rec, finished, applied = GreatBuild.apply(nil, "srv-a", 1, 600, NOW)
		expect(applied).toBe(true)
		expect(rec.total).toBe(600)
		expect(#finished).toBe(0)
		-- the same batch again (timeout after a successful write): not added
		rec, finished, applied = GreatBuild.apply(rec, "srv-a", 1, 600, NOW + 5)
		expect(applied).toBe(false)
		expect(rec.total).toBe(600)
		-- next batch of A and a batch of another server with its own seq 1
		rec = GreatBuild.apply(rec, "srv-a", 2, 300, NOW + 30)
		rec, finished = GreatBuild.apply(rec, "srv-b", 1, 200, NOW + 31)
		expect(rec.total).toBe(1100)
		expect(#finished).toBe(1)
		expect(finished[1]).toBe(1)
		expect(rec.done["1"]).toBe(NOW + 31)
		-- a later batch never moves a stage's finish time
		rec = GreatBuild.apply(rec, "srv-a", 3, 1, NOW + 60)
		expect(rec.done["1"]).toBe(NOW + 31)
		-- servers silent for an hour are forgotten
		rec = GreatBuild.apply(rec, "srv-c", 1, 1, NOW + 60 + GreatBuild.FLUSH_KEEP + 1)
		expect(rec.flushes["srv-a"]).toBeNil()
		expect(rec.flushes["srv-c"]).never.toBeNil()
	end)

	it("cleans a broken record", function()
		local rec = GreatBuild.reconcileRecord({
			total = -5,
			done = { ["1"] = 0 / 0, ["2"] = 1800000000, ["99"] = 5 },
			flushes = { a = { seq = 1, at = 2 }, b = "x", [5] = { seq = 1, at = 1 } },
		})
		expect(rec.total).toBe(0)
		expect(rec.done["1"]).toBeNil()
		expect(rec.done["2"]).toBe(1800000000)
		expect(rec.done["99"]).toBeNil()
		expect(rec.flushes.a.seq).toBe(1)
		expect(rec.flushes.b).toBeNil()
		expect(GreatBuild.reconcileRecord("junk").total).toBe(0)
	end)

	it("caps donations by owned shards and the daily limit, per UTC day", function()
		local data = GreatBuild.fresh()
		expect(GreatBuild.donate(data, 50, 20, NOW)).toBe(20) -- only what the hero has
		expect(GreatBuild.donate(data, 5000, 1e6, NOW)).toBe(GreatBuild.DAILY_CAP - 20)
		expect(GreatBuild.dailyLeft(data, NOW)).toBe(0)
		expect(GreatBuild.donate(data, 10, 1e6, NOW)).toBe(0)
		for _, junk in { 0 / 0, -5, math.huge, "10" } do
			expect(GreatBuild.donate(data, junk, 1e6, NOW + DAY)).toBe(0)
		end
		expect(GreatBuild.donate(data, 10, 1e6, NOW + DAY)).toBe(10) -- next day
		expect(data.total).toBe(GreatBuild.DAILY_CAP + 10)
	end)

	it("pays each personal milestone once", function()
		local data = GreatBuild.fresh()
		data.total = 150
		local first = GreatBuild.collect(data)
		expect(#first).toBe(1)
		expect(first[1].amount).toBe(100)
		expect(#GreatBuild.collect(data)).toBe(0)
		data.total = 20000
		expect(#GreatBuild.collect(data)).toBe(2)
	end)

	it("runs the global buff from the newest finished stage", function()
		local done = { ["1"] = NOW, ["2"] = NOW + 100 }
		local from, untilT = GreatBuild.buffWindow(done)
		expect(from).toBe(NOW + 100)
		expect(untilT).toBe(NOW + 100 + GreatBuild.BUFF_SECONDS)
		expect(GreatBuild.buffActive(done, NOW + 200)).toBe(true)
		expect(GreatBuild.buffActive(done, untilT + 1)).toBe(false)
		expect(GreatBuild.buffActive({}, NOW)).toBe(false)
	end)

	it("lives in the account save; another build starts fresh", function()
		local account = Profile.freshAccount()
		expect(account.greatBuild.id).toBe(GreatBuild.ID)
		local again = Profile.reconcileAccount({
			greatBuild = {
				id = GreatBuild.ID,
				total = 120.7,
				today = 1e9,
				paid = { ["100"] = true, x = true },
			},
		})
		expect(again.greatBuild.total).toBe(120)
		expect(again.greatBuild.today).toBe(GreatBuild.DAILY_CAP)
		expect(again.greatBuild.paid["100"]).toBe(true)
		expect(again.greatBuild.paid.x).toBeNil()
		local other = Profile.reconcileAccount({ greatBuild = { id = "s0", total = 50 } })
		expect(other.greatBuild.total).toBe(0)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function client(fn)
	sim:runAs("client", function(req)
		fn(req("ReplicatedStorage.Shared.Net"))
	end)
	sim:run(0.5)
end

local function mine()
	return server(function(req, player)
		local Data = req("ServerScriptService.Server.Systems.Data")
		return Data.get(player).materials.shards, Data.account(player).greatBuild.total
	end)
end

local function stored()
	local store = sim.datastores[GreatBuild.STORE .. "/global"]
	return store and store[GreatBuild.ID]
end

describe("Great Build server and window", function()
	it("refuses donations away from the chute", function()
		sim:boot({ seconds = 2 })
		client(function(Net)
			Net.Character:FireServer("setup", "Build Hero", "mage")
		end)
		sim:run(1)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Progress").addMaterials(
				player,
				{ shards = 1500 }
			)
			req("ServerScriptService.Server.Systems.Movement").teleported(player)
			player.Character:PivotTo(CFrame.new(req("ReplicatedStorage.Shared.Config").HUB_POS))
		end)
		sim:run(0.5)
		client(function(Net)
			Net.GreatBuild:FireServer("donate", 100)
		end)
		local shards, total = mine()
		expect(shards).toBe(1500)
		expect(total).toBe(0)
	end)

	it("takes shards at the chute, ignores junk and pays the first milestone", function()
		local gold0 = server(function(req, player)
			local station = workspace.Lumenhaven:FindFirstChild(GreatBuild.STATION, true)
			req("ServerScriptService.Server.Systems.Movement").teleported(player)
			player.Character:PivotTo(CFrame.new(station.Position + Vector3.new(-3, 0, 0)))
			return req("ServerScriptService.Server.Systems.Data").get(player).gold
		end)
		sim:run(0.5)
		client(function(Net)
			for _, junk in { 0 / 0, -5, 1.5, 1e9, "100", math.huge } do
				Net.GreatBuild:FireServer("donate", junk)
			end
		end)
		sim:run(2)
		local shards, total = mine()
		expect(shards).toBe(1500)
		expect(total).toBe(0)
		client(function(Net)
			Net.GreatBuild:FireServer("donate", 100)
			Net.GreatBuild:FireServer("donate", 100)
		end)
		shards, total = mine()
		expect(shards).toBe(1300)
		expect(total).toBe(200)
		local gold, attr = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).gold,
				game:GetService("ReplicatedStorage"):GetAttribute("GreatBuildTotal")
		end)
		expect(gold > gold0).toBe(true) -- "Helping Hand" (100)
		expect(attr).toBe(200)
	end)

	it("stops at the daily cap and writes the batch to the DataStore", function()
		sim:run(2)
		client(function(Net)
			Net.GreatBuild:FireServer("donate", GreatBuild.DAILY_CAP)
		end)
		local shards, total = mine()
		expect(total).toBe(GreatBuild.DAILY_CAP)
		expect(shards).toBe(1500 - GreatBuild.DAILY_CAP)
		sim:run(2)
		client(function(Net)
			Net.GreatBuild:FireServer("donate", 10)
		end)
		shards, total = mine()
		expect(total).toBe(GreatBuild.DAILY_CAP)
		server(function(req)
			req("ServerScriptService.Server.Systems.GreatBuild").flush()
		end)
		sim:run(1) -- the DataStore call yields
		local rec = stored()
		expect(rec).never.toBeNil()
		expect(rec.total).toBe(GreatBuild.DAILY_CAP)
		expect(rec.done["1"]).never.toBeNil() -- stage 1 = 1,000
	end)

	it("builds the finished stage on the monument and starts the global buff", function()
		sim:run(3) -- brick animation
		local bricks, solid, bonus, status = server(function(_req, player)
			local model = workspace.Lumenhaven:FindFirstChild(GreatBuild.MODEL)
			local n, s = 0, 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Stage") == 1 then
					n += 1
					if d.Transparency == 0 then
						s += 1
					end
				end
			end
			return n, s, player:GetAttribute("BonusGold"), player:GetAttribute("Status_build")
		end)
		expect(bricks).toBe(4)
		expect(solid).toBe(4)
		expect(bonus >= GreatBuild.BUFF_GOLD).toBe(true)
		expect(status).never.toBeNil()
		server(function(req)
			req("ServerScriptService.Server.Systems.GreatBuild").finishStage()
		end)
		sim:run(1)
		local stage2 = server(function(req)
			return req("ServerScriptService.Server.Systems.GreatBuild").stages()
		end)
		expect(stage2).toBe(2)
		expect(stored().total).toBe(GreatBuild.Ends[2])
	end)

	it("shows the window and fits phone and tablet (touch)", function()
		-- skip the top builders cache (DONOR_READ) instead of simulating a minute: the server loop
		-- wakes on the next frame and reads the list with this donor in it
		sim.sched.now += GreatBuild.DONOR_READ
		sim:run(1)
		sim:runAs("client", function(req)
			req(
				"Players."
					.. sim.player.Name
					.. ".PlayerScripts.Client.Controllers.GreatBuildController"
			).open()
		end)
		sim:run(1)
		local gui = sim.player.PlayerGui.LootRushGreatBuild
		expect(gui.Enabled).toBe(true)
		local stage = gui:FindFirstChild("Stage", true)
		expect(stage.Text).toBe("Stage 3 / " .. GreatBuild.STAGES)
		-- top builders carry the donor's Roblox headshot (placeholder letter underneath)
		local row = gui:FindFirstChild("Row1", true)
		expect(row).toBeTruthy()
		local face = row:FindFirstChild("Headshot")
		expect(face).toBeTruthy()
		expect(face.Initial.Text ~= "").toBe(true)
		local id = sim.player.UserId
		if id > 0 then
			expect(face.Image.Image).toBe(
				`rbxthumb://type=AvatarHeadShot&id={id}&w=150&h=150`
			)
		end
		local strict = {
			offscreen = true,
			["text-small"] = true,
			["touch-target"] = true,
			overlap = true,
			["text-covered"] = true,
			["text-overlap"] = true,
			["text-outside"] = true,
			unlabeled = true,
		}
		for _, size in { Vector2.new(844, 390), Vector2.new(1024, 768) } do
			local found = {}
			for _, f in layoutCheck(size, true) do
				if strict[f.kind] and string.find(f.path or "", "LootRushGreatBuild", 1, true) then
					table.insert(found, f.kind .. " " .. tostring(f.path))
				end
			end
			expect(table.concat(found, "\n")).toBe("")
		end
	end)
end)
