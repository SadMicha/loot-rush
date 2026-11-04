--!nocheck
-- Device profiles, HUD sizes and screens of the layout matrix (tools/lune/matrix.luau and
-- tests/Matrix.spec.luau). One sandbox per screen: `prepare` boots it and opens the screen like a
-- player, `check` resizes it to a device, applies a HUD size and returns the layout findings.

local roblox = require("@lune/roblox")
local Checks = require("./Checks")
local Sandbox = require("./Sandbox")
local Vector2 = roblox.Vector2

local Matrix = {}

-- Safe-area insets are the ones Roblox reports on these devices in landscape (notch / Dynamic
-- Island side, rounded corners, home indicator at the bottom). Sizes in points.
Matrix.DEVICES = {
	{
		name = "iphone-se",
		size = Vector2.new(667, 375),
		touch = true,
		insets = { l = 0, t = 0, r = 0, b = 0 },
	},
	{
		name = "android",
		size = Vector2.new(800, 360),
		touch = true,
		insets = { l = 32, t = 0, r = 0, b = 0 },
	},
	{
		name = "iphone",
		size = Vector2.new(852, 393),
		touch = true,
		insets = { l = 59, t = 0, r = 59, b = 21 },
	},
	{
		name = "iphone-max",
		size = Vector2.new(932, 430),
		touch = true,
		insets = { l = 59, t = 0, r = 59, b = 21 },
	},
	{
		name = "ipad",
		size = Vector2.new(1180, 820),
		touch = true,
		insets = { l = 0, t = 0, r = 0, b = 20 },
	},
	{
		name = "laptop",
		size = Vector2.new(1366, 768),
		touch = false,
		insets = { l = 0, t = 0, r = 0, b = 0 },
	},
	{
		name = "desktop",
		size = Vector2.new(1920, 1080),
		touch = false,
		insets = { l = 0, t = 0, r = 0, b = 0 },
	},
}

-- The "HUD size" choices of the Settings window (Shared/Settings hudScale)
Matrix.SCALES = {
	{ label = "XS", value = 0.8 },
	{ label = "S", value = 0.9 },
	{ label = "M", value = 1 },
	{ label = "L", value = 1.1 },
	{ label = "XL", value = 1.2 },
}

-- Findings that fail the matrix (the rest is reported only)
Matrix.STRICT = {
	offscreen = true,
	["text-small"] = true,
	["touch-target"] = true,
	topbar = true,
	overlap = true,
	["text-covered"] = true,
	["text-overlap"] = true,
	["text-outside"] = true,
	["scroll-cut"] = true,
	unlabeled = true,
	["empty-row"] = true,
	["unsafe-area"] = true,
	["layer-overlap"] = true,
	["autosize-loop"] = true,
}

local function hudButton(sb, name: string)
	for _, d in sb.player.PlayerGui:GetDescendants() do
		if d:IsA("GuiButton") and d.Name == name and d:FindFirstAncestor("LootRushHUD") then
			return d
		end
	end
	return nil
end

local function button(sb, guiName: string, name: string)
	local gui = sb.player.PlayerGui:FindFirstChild(guiName)
	if gui then
		for _, d in gui:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == name then
				return d
			end
		end
	end
	return nil
end

local function click(sb, b)
	assert(b, "button not found")
	sb:click(b)
	sb:run(0.6)
end

-- Fresh player past the hero setup, level 99 (every window unlocked), a full-ish bag, worn gear,
-- materials and stones so every window shows real content
local function stock(sb)
	sb:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", "mage")
	end)
	sb:run(1)
	sb:runAs("server", function(req)
		local player = sb.player
		local Inventory = req("ServerScriptService.Server.Systems.Inventory")
		local Progress = req("ServerScriptService.Server.Systems.Progress")
		local Items = req("ReplicatedStorage.Shared.Items")
		for i = 1, 27 do
			Inventory.add(player, Items.roll(1 + i % 12, Sandbox.Random.new(100 + i)))
		end
		Inventory.addGold(player, 2000)
		Progress.addMaterials(player, { shards = 223 })
		local profile = req("ServerScriptService.Server.Systems.Data").get(player)
		if profile then
			local rng = Sandbox.Random.new(777)
			for _, slot in Items.Slots do
				for _ = 1, 500 do
					local item = Items.roll(8, rng)
					if item.slot == slot then
						profile.equipped[slot] = item
						break
					end
				end
			end
			profile.progress.stones.power = 2
			profile.progress.stones.haste = 1
		end
		Inventory.sync(player)
		Progress.sync(player)
		player:SetAttribute("Level", 99)
		player:SetAttribute("BestDepth", 99)
	end)
	sb:run(1)
	-- onboarding toasts and the daily popup of the first join fly out first
	sb:run(3)
	local daily = sb.player.PlayerGui:FindFirstChild("LootRushDaily")
	if daily and daily.Enabled then
		local close = nil
		for _, d in daily:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == "Close" then
				close = d
			end
		end
		if close then
			click(sb, close)
		else
			daily.Enabled = false
		end
	end
end

-- Enter a Rift (Atlas) and slay enemies like the debug command until the phase is reached
local function riftTo(sb, goal: string)
	if (sb.player:GetAttribute("RiftPhase") or "") == "" then
		sb:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sb:run(1)
	end
	for _ = 1, 60 do
		local phase = sb.player:GetAttribute("RiftPhase") or ""
		if phase == goal then
			break
		end
		sb:runAs("server", function(req)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			for _, e in sb.game:GetService("CollectionService"):GetTagged("Enemy") do
				if goal ~= "boss" or e:GetAttribute("Boss") ~= true then
					Combat.slay(sb.player, e)
				end
			end
		end)
		sb:run(1)
	end
	local now = sb.player:GetAttribute("RiftPhase") or ""
	assert(now == goal, "Rift did not reach " .. goal .. " (phase: " .. tostring(now) .. ")")
	sb:run(1.5)
end

local function window(id: string)
	return function(sb)
		click(sb, hudButton(sb, id))
	end
end

Matrix.SCREENS = {
	{
		name = "setup",
		fresh = true, -- first join: the hero setup screen, nothing else
		open = function() end,
	},
	{ name = "hud", open = function() end },
	{
		name = "hud-combat",
		open = function(sb)
			sb:runAs("server", function()
				sb.player:SetAttribute("InCombat", true)
			end)
			sb:run(1.5)
		end,
	},
	{
		name = "boss", -- a real Rift run: waves slain until the boss stands (boss bar, Break meter)
		open = function(sb)
			riftTo(sb, "boss")
		end,
	},
	{
		name = "rift-clear", -- boss down: Victory banner, then the Deeper / Back to Hub card
		open = function(sb)
			riftTo(sb, "boss")
			riftTo(sb, "clear")
		end,
	},
	{ name = "inventory", open = window("inventory") },
	{
		name = "inventory-compare",
		open = function(sb)
			click(sb, hudButton(sb, "inventory"))
			-- a bag item (a cell inside the grid's scrolling frame) until the comparison shows
			local gui = sb.player.PlayerGui.LootRushInventory
			local compare = gui:FindFirstChild("Compare", true)
			local tries = 0
			for _, d in gui:GetDescendants() do
				if
					d:IsA("GuiButton")
					and d:FindFirstAncestorWhichIsA("ScrollingFrame")
					and sb:hasHandlers(d)
				then
					click(sb, d)
					tries += 1
					local sel = compare and compare:FindFirstChild("Selected")
					if sel and sel:FindFirstChild("Button", true) or tries >= 4 then
						break
					end
				end
			end
		end,
	},
	{
		name = "stash", -- at the hub stash station: a few items stored in tab 1, the bag beside it
		open = function(sb)
			sb:runAs("server", function(req)
				local player = sb.player
				local station =
					sb.game:GetService("Workspace").Lumenhaven:FindFirstChild("Station_Stash", true)
				req("ServerScriptService.Server.Systems.Movement").teleported(player)
				player.Character:PivotTo(station.CFrame + station.CFrame.LookVector * 4)
				local Data = req("ServerScriptService.Server.Systems.Data")
				local Stash = req("ReplicatedStorage.Shared.Stash")
				local profile, account = Data.get(player), Data.account(player)
				for _ = 1, 9 do
					local item = profile.inventory[1]
					if item then
						Stash.deposit(account.stash, profile.inventory, item.id, 1)
					end
				end
				req("ServerScriptService.Server.Systems.Inventory").sync(player)
			end)
			sb:run(0.6)
			sb:runAs("client", function(req)
				req(
					"Players."
						.. sb.player.Name
						.. ".PlayerScripts.Client.Controllers.StashController"
				).open()
			end)
			sb:run(0.6)
		end,
	},
	{ name = "skills", open = window("skills") },
	{
		name = "skills-stones",
		open = function(sb)
			click(sb, hudButton(sb, "skills"))
			click(sb, button(sb, "LootRushAbilities", "Socket1"))
		end,
	},
	{ name = "star-net", open = window("star_net") },
	{ name = "forge", open = window("forge") },
	{ name = "atlas", open = window("atlas") },
	{ name = "pets", open = window("pets") },
	{ name = "shop", open = window("shop") },
	{
		name = "market",
		open = function(sb)
			click(sb, hudButton(sb, "shop"))
			click(sb, button(sb, "LootRushShop", "Market"))
		end,
	},
	{ name = "settings", open = window("Gear") },
	{
		name = "switch-hero",
		open = function(sb)
			click(sb, hudButton(sb, "Gear"))
			click(sb, button(sb, "LootRushSettings", "SwitchHero"))
		end,
	},
	{ name = "daily", open = window("Daily") },
	{ name = "leaderboard", open = window("Leaderboard") },
	{ name = "journey", open = window("Journey") },
	{ name = "season", open = window("Season") },
	{
		name = "great-build", -- at the donation chute in the hub
		open = function(sb)
			sb:runAs("server", function(req)
				local player = sb.player
				local station = sb.game
					:GetService("Workspace").Lumenhaven
					:FindFirstChild("Station_GreatBuild", true)
				req("ServerScriptService.Server.Systems.Movement").teleported(player)
				player.Character:PivotTo(station.CFrame + Vector3.new(-3, 0, 0))
			end)
			sb:run(0.6)
			sb:runAs("client", function(req)
				req(
					"Players."
						.. sb.player.Name
						.. ".PlayerScripts.Client.Controllers.GreatBuildController"
				).open()
			end)
			sb:run(0.6)
		end,
	},
}

function Matrix.prepare(sb, screen)
	sb:boot({ seconds = 2 })
	if not screen.fresh then
		stock(sb)
	end
	screen.open(sb)
	sb:run(0.5)
end

-- Layers that stay while windows come and go
local PERMANENT = {
	LootRushHUD = true,
	LootRushMenuDock = true,
	LootRushDebug = true,
	LootRushToast = true,
	LootRushRift = true,
}

-- Close every open window/popup like a player (its close button), so the next screen starts clean
function Matrix.close(sb)
	for _ = 1, 4 do
		local open = nil
		for _, g in sb.player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled and not PERMANENT[g.Name] then
				for _, d in g:GetDescendants() do
					if d:IsA("GuiButton") and d.Name == "Close" and sb:hasHandlers(d) then
						open = d
					end
				end
			end
		end
		if not open then
			break
		end
		sb:click(open)
		sb:run(0.4)
	end
	-- Rift scenes: back to the Hub, calm again
	if (sb.player:GetAttribute("RiftPhase") or "") ~= "" then
		sb:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sb:run(2)
	end
	sb:runAs("server", function()
		sb.player:SetAttribute("InCombat", false)
	end)
	sb:run(1)
end

-- HUD size like the Settings window (preview = applied at once, not saved)
local function setHudScale(sb, value: number)
	sb:runAs("client", function(req)
		local Prefs = req("Players." .. sb.player.Name .. ".PlayerScripts.Client.Prefs")
		Prefs.preview("hudScale", value)
	end)
end

function Matrix.check(sb, screen, device, scale: number)
	sb:setViewport(device.size, device.touch, device.insets)
	setHudScale(sb, scale)
	sb:run(0.3)
	sb:setViewport(device.size, device.touch, device.insets) -- fresh layout cache
	return Checks.run(sb, { name = device.name, touch = device.touch })
end

function Matrix.strict(findings, screen)
	local out = {}
	local known = screen.known or {}
	for _, f in findings do
		-- a toast sliding in from above the screen edge is motion, not layout
		local flying = f.kind == "offscreen" and string.find(f.path, "^LootRushToast") ~= nil
		if Matrix.STRICT[f.kind] and not known[f.kind] and not flying then
			table.insert(out, f)
		end
	end
	return out
end

local function byName(screenName: string)
	for _, sc in Matrix.SCREENS do
		if sc.name == screenName then
			return sc
		end
	end
	error("unknown screen " .. screenName)
end

-- Screens on the given devices (names) and HUD sizes (values). Screens share one stocked sandbox
-- (each closed again before the next); `fresh` screens get their own. Returns strict findings as
-- text lines per screen name.
function Matrix.run(
	opts,
	screenNames: { string },
	deviceNames: { string }?,
	scaleValues: { number }?,
	onScreen: ((sb: any, screen: any, device: any, scale: any, findings: any) -> ())?
): { [string]: { string } }
	local out = {}
	local shared = nil
	local function sandbox()
		return Sandbox.new({
			placePath = opts.placePath,
			dumpPath = opts.dumpPath,
			sourceFiles = opts.sourceFiles,
			quiet = true,
		})
	end
	for _, name in screenNames do
		local screen = byName(name)
		local lines = {}
		out[name] = lines
		local sb
		local ok, err
		if screen.fresh then
			sb = sandbox()
			ok, err = pcall(Matrix.prepare, sb, screen)
		else
			if not shared then
				shared = sandbox()
				ok, err = pcall(function()
					shared:boot({ seconds = 2 })
					stock(shared)
				end)
				if not ok then
					table.insert(lines, name .. ": could not start: " .. tostring(err))
					shared = nil
					continue
				end
			end
			sb = shared
			ok, err = pcall(function()
				screen.open(sb)
				sb:run(0.5)
			end)
		end
		if not ok then
			table.insert(lines, name .. ": could not open: " .. tostring(err))
			continue
		end
		local errorsBefore = #sb.issues
		for _, device in Matrix.DEVICES do
			if not deviceNames or table.find(deviceNames, device.name) then
				for _, scale in Matrix.SCALES do
					if not scaleValues or table.find(scaleValues, scale.value) then
						local findings = Matrix.check(sb, screen, device, scale.value)
						if onScreen then
							onScreen(sb, screen, device, scale, findings)
						end
						for _, f in Matrix.strict(findings, screen) do
							table.insert(
								lines,
								string.format(
									"%s %s HUD %s: [%s] %s %s",
									name,
									device.name,
									scale.label,
									f.kind,
									f.path,
									f.message
								)
							)
						end
					end
				end
			end
		end
		for i = errorsBefore + 1, #sb.issues do
			local issue = sb.issues[i]
			if issue.level == "error" then
				table.insert(lines, name .. ": runtime error: " .. issue.message)
			end
		end
		if sb == shared then
			-- back to the reference size before closing (buttons are found by layout)
			sb:setViewport(Matrix.DEVICES[#Matrix.DEVICES].size, false)
			Matrix.close(sb)
		end
	end
	return out
end

return Matrix
