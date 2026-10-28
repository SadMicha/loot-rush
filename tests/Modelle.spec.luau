-- 3D-Modelle aus Code: jedes Modell der Vorschau baut ohne Fehler, hat Teile und bleibt im Budget.
describe("Modelle", function()
	it("showcase baut alle Modelle", function()
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
			expect(parts).toBeLessThanOrEqual(250) -- Teile-Budget je Modell
		end
	end)

	it("ersetzt die alte Vorschau statt sie zu stapeln", function()
		local Models = require("ReplicatedStorage.Shared.Models")
		Models.showcase()
		Models.showcase()
		local n = 0
		for _, c in workspace:GetChildren() do
			if c.Name == "ModellVorschau" then
				n += 1
			end
		end
		expect(n).toBe(1)
	end)
end)
