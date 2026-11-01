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
