-- 3D models from code: every showcase model builds without errors, has parts and stays within budget.
describe("Models", function()
	it("showcase builds all models", function()
		local Models = require("ReplicatedStorage.Shared.Models")
		local row = Models.showcase()
		local models = row:GetChildren()
		expect(#models).toBeGreaterThanOrEqual(20)
		for _, m in models do
			local parts = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					expect(d.Size.X * d.Size.Y * d.Size.Z).toBeGreaterThan(0)
				end
			end
			expect(parts).toBeGreaterThan(0)
			expect(parts).toBeLessThanOrEqual(250) -- part budget per model
		end
	end)

	it("replaces the old showcase instead of stacking it", function()
		local Models = require("ReplicatedStorage.Shared.Models")
		Models.showcase()
		Models.showcase()
		local n = 0
		for _, c in workspace:GetChildren() do
			if c.Name == "ModelPreview" then
				n += 1
			end
		end
		expect(n).toBe(1)
	end)
end)

-- Loud drops (criteria audit #3): Rare+ get a bigger box and a light pillar that grows with rarity
describe("Loot drops", function()
	local Loot = require("ReplicatedStorage.Shared.Models.Loot")
	local color = Color3.new(1, 0.8, 0.3)

	local function height(m: Model): number -- vertical extent of the axis-aligned parts
		local top, bottom = -math.huge, math.huge
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Shape ~= Enum.PartType.Cylinder then
				top = math.max(top, d.Position.Y + d.Size.Y / 2)
				bottom = math.min(bottom, d.Position.Y - d.Size.Y / 2)
			end
		end
		return top - bottom
	end

	it("has no pillar below Rare, and a taller one the better the rarity", function()
		expect(Loot.pillar(color, "normal")).toBeNil()
		expect(Loot.pillar(color, "magic")).toBeNil()
		local last = 0
		for _, rarity in { "rare", "epic", "unique" } do
			local p = Loot.pillar(color, rarity) :: Model
			expect(p).never.toBeNil()
			local h = height(p)
			expect(h).toBeGreaterThan(last)
			expect(h).toBeGreaterThanOrEqual(16) -- seen across the clearing
			last = h
			for _, d in p:GetDescendants() do
				if d:IsA("BasePart") then
					expect(d.Anchored).toBe(true)
					expect(d.CanCollide).toBe(false)
					expect(d.CanQuery).toBe(false)
					expect(d.Material).toBe(Enum.Material.Neon)
				end
			end
			expect(p:FindFirstChildWhichIsA("PointLight", true)).never.toBeNil()
			expect(p:FindFirstChild("Ring")).never.toBeNil()
		end
	end)

	it("scales the gift box for Rare and better", function()
		local small = Loot.giftBox(color, true)
		local big = Loot.giftBox(color, true, Loot.Glow.epic.box)
		expect(height(big)).toBeCloseTo(height(small) * Loot.Glow.epic.box, 0.05)
		expect((small.PrimaryPart :: BasePart).Size.X * Loot.Glow.epic.box).toBeCloseTo(
			(big.PrimaryPart :: BasePart).Size.X,
			0.01
		)
	end)
end)
