--!strict
-- Light at the player's location (Shared/Looks): the base light in the Hub, the light of the arena
-- the player stands in while in a Rift (arena folder under workspace.Arena with attributes Region and Center, Systems/World).
-- Runs locally only, so every player sees their own light - even if others are fighting
-- in other areas at the same time.
-- Changes are briefly cross-faded.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Looks = require(ReplicatedStorage.Shared.Looks)

local LightController = {}

local player = Players.LocalPlayer
local CHECK = 0.25
local FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local defaults: Looks.Light = {}
local mood: ColorCorrectionEffect
local shown = ""

local function cloudsOf(): Clouds?
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	return if terrain then terrain:FindFirstChildOfClass("Clouds") else nil
end

local function remember()
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local clouds = cloudsOf()
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	defaults = {
		clock = Lighting.ClockTime,
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
		fog = if atmo then atmo.Color else nil,
		decay = if atmo then atmo.Decay else nil,
		density = if atmo then atmo.Density else nil,
		haze = if atmo then atmo.Haze else nil,
		tint = Color3.new(1, 1, 1),
		saturation = 0,
		contrast = 0,
		bloom = if bloom then bloom.Intensity else nil,
		clouds = if clouds then clouds.Cover else nil,
	}
end

local function apply(l: Looks.Light, instant: boolean)
	local function pick<V>(v: V?, d: V?): V?
		return if v ~= nil then v else d
	end
	local function set(target: Instance, props: { [string]: any })
		if instant then
			for k, v in props do
				(target :: any)[k] = v
			end
		else
			TweenService:Create(target, FADE, props):Play()
		end
	end
	set(Lighting, {
		ClockTime = pick(l.clock, defaults.clock) or Lighting.ClockTime,
		Brightness = pick(l.brightness, defaults.brightness) or Lighting.Brightness,
		Ambient = pick(l.ambient, defaults.ambient) or Lighting.Ambient,
		OutdoorAmbient = pick(l.outdoor, defaults.outdoor) or Lighting.OutdoorAmbient,
	})
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		set(atmo, {
			Color = pick(l.fog, defaults.fog) or atmo.Color,
			Decay = pick(l.decay, defaults.decay) or atmo.Decay,
			Density = pick(l.density, defaults.density) or atmo.Density,
			Haze = pick(l.haze, defaults.haze) or atmo.Haze,
		})
	end
	set(mood, {
		TintColor = pick(l.tint, defaults.tint) or Color3.new(1, 1, 1),
		Saturation = pick(l.saturation, defaults.saturation) or 0,
		Contrast = pick(l.contrast, defaults.contrast) or 0,
	})
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local glow = pick(l.bloom, defaults.bloom)
	if bloom and glow then
		set(bloom, { Intensity = glow })
	end
	local clouds = cloudsOf()
	local cover = pick(l.clouds, defaults.clouds)
	if clouds and cover then
		set(clouds, { Cover = cover })
	end
end

-- Which place applies right now? "hub" or the Atlas ID of the arena
function LightController.place(): string
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local d = root.Position - Config.HUB_ORIGIN
		if Vector3.new(d.X, 0, d.Z).Magnitude < Looks.HUB_RADIUS then
			return "hub"
		end
		-- nearest arena (slots are Config.ARENA_SPACING apart)
		local arenas = workspace:FindFirstChild("Arena")
		local best, bestD = nil :: string?, Config.ARENA_SPACING / 2
		for _, a in if arenas then arenas:GetChildren() else {} do
			local center, region = a:GetAttribute("Center"), a:GetAttribute("Region")
			if typeof(center) == "Vector3" and typeof(region) == "string" then
				local dist =
					Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
				if dist < bestD then
					best, bestD = region, dist
				end
			end
		end
		if best then
			return best
		end
	end
	return "hub"
end

local function update(instant: boolean)
	if not mood.Parent then
		return
	end
	local place = LightController.place()
	if place == shown then
		return
	end
	shown = place
	apply(if place == "hub" then Looks.Hub else Looks.Regions[place] or Looks.Hub, instant)
end

function LightController.init()
	remember()
	mood = Instance.new("ColorCorrectionEffect")
	mood.Name = "Location"
	mood.Parent = Lighting
end

function LightController.start()
	update(true)
	while mood.Parent do
		task.wait(CHECK)
		update(false)
	end
end

return LightController
