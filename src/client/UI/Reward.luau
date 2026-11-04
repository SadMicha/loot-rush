--!strict
-- Reward chips (docs/ROADMAP-1.0.md U5 "one shared reward card component"): a row of icon +
-- amount for a Shared/Journey reward table, used by the Journey and Season windows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Journey = require(ReplicatedStorage.Shared.Journey)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Flat = require(script.Parent.Flat)
local Kit = require(script.Parent.Kit)

local Reward = {}

local C = Theme.Color

export type Line = { icon: string, text: string, color: Color3 }

-- Display lines of a reward (already scaled), most valuable first
function Reward.lines(r: Journey.Reward): { Line }
	local out: { Line } = {}
	local function add(icon: string, n: number?, color: Color3)
		if n and n > 0 then
			table.insert(out, { icon = icon, text = Format.int(n), color = color })
		end
	end
	if r.cosmetic then
		local c = Cosmetics.ById[r.cosmetic]
		if c then
			table.insert(
				out,
				{ icon = c.icon, text = c.name, color = Theme.Rarity[c.rarity] or C.GoldHi }
			)
		end
	end
	add("soulstar", r.soulstars, Theme.Rarity.epic)
	add("gold", r.gold, C.Gold)
	add("skills", r.stones, C.Cyan)
	add("crystal", r.shards, C.Cyan)
	add("candy", r.candy, C.Text)
	add("glitter_dust", r.dust, C.Text)
	return out
end

-- Horizontal row of chips; `size` = icon size in design pixels
function Reward.row(r: Journey.Reward, size: number, maxLines: number?): Frame
	local f = Flat.frame(UDim2.fromOffset(0, size))
	f.Name = "Reward"
	f.AutomaticSize = Enum.AutomaticSize.X
	local layout = Kit.list(f, Enum.FillDirection.Horizontal, 14)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for i, line in Reward.lines(r) do
		if maxLines and i > maxLines then
			break
		end
		local chip = Flat.frame(UDim2.fromOffset(0, size))
		chip.Name = "Chip_" .. line.icon
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.LayoutOrder = i
		Kit.list(chip, Enum.FillDirection.Horizontal, 6)
		local ic = Kit.icon(line.icon, size)
		ic.LayoutOrder = 1
		ic.Parent = chip
		local t = Flat.text(line.text, math.max(14, size * 0.5), line.color, Theme.Font.UI)
		t.LayoutOrder = 2
		t.Parent = chip
		chip.Parent = f
	end
	return f
end

return table.freeze(Reward)
