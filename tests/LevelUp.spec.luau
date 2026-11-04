-- Level-up card (audit #11): stats line rules and the card in the client after a level-up.
local Balance = require("ReplicatedStorage.Shared.Balance")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function card()
	local gui = sim.player.PlayerGui:FindFirstChild("LootRushLevelUp")
	return gui and gui:FindFirstChild("LevelUp", true)
end

local function levelTo(from: number, to: number)
	server(function(req, player)
		req("ServerScriptService.Server.Systems.Combat").setLevel(player, from, 0)
	end)
	sim:run(1)
	server(function(req, player)
		player:SetAttribute("Level", to)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		req("ReplicatedStorage.Shared.Net").Fx:FireAllClients(
			"levelup",
			{ pos = if root then root.Position else Vector3.zero, level = to, who = player.UserId }
		)
	end)
	sim:run(0.3)
end

describe("Level-up card", function()
	it("names life, damage and Star Web points only once the Star Web is open", function()
		sim:boot({ seconds = 2 })
		local line
		sim:runAs("client", function(req)
			line =
				req("StarterPlayer.StarterPlayerScripts.Client.Controllers.LevelUpController").statsLine
		end)
		local life = Balance.life(3) - Balance.life(2)
		expect(line(2, 3)).toBe(string.format("+%d Life  ·  +2%% Damage", life))
		expect(string.find(line(4, 5), "+1 Star Web point", 1, true)).toBeTruthy()
		expect(string.find(line(5, 8), "+3 Star Web points", 1, true)).toBeTruthy()
	end)

	it("pops a card for the own level-up and names the skill unlocked at level 8", function()
		levelTo(6, 7)
		local c = card()
		expect(c).toBeTruthy()
		expect(c.Visible).toBe(true)
		expect(c:FindFirstChild("NewSkill", true).Visible).toBe(false)
		sim:run(5)
		expect(c.Visible).toBe(false)
		levelTo(7, 8)
		expect(c.Visible).toBe(true)
		local row = c:FindFirstChild("NewSkill", true)
		expect(row.Visible).toBe(true)
		local text = ""
		for _, d in row:GetDescendants() do
			if d:IsA("TextLabel") then
				text ..= d.Text
			end
		end
		expect(string.find(text, "New skill: ", 1, true)).toBeTruthy()
	end)
end)
