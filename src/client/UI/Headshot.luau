--!strict
-- Player headshot for every ranking (leaderboard window and hub board, Great Build top builders):
-- the Roblox profile headshot in a round gold ring. The image comes from the rbxthumb:// content
-- URL, so nothing yields and the engine caches and loads it per userId (works for players on
-- other servers or offline). A placeholder with the name's initial is drawn over it until the image
-- has loaded, so it shows while loading, on failure, and for ids without a profile (Studio test
-- players are ≤ 0). "Loaded" comes from ContentProvider:PreloadAsync (once per userId, also
-- answers at once for a cached image) and ImageLabel.IsLoaded, whichever is first: the
-- IsLoaded change signal alone does not fire reliably, which left the letter on the photo.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Kit)

local C = Theme.Color
local F = Theme.Flat
local H = Theme.Headshot

local Headshot = {}

local urls: { [number]: string } = {}
local ready: { [number]: boolean } = {} -- userId → image fetched
local fetching: { [number]: boolean } = {} -- userId → a PreloadAsync is running
-- userId → hide callbacks of placeholders still showing; kept across failed fetches, so a later
-- successful fetch (asked by the next row of that user) hides the older rows too
local waiting: { [number]: { () -> () } } = {}

local function markReady(userId: number)
	ready[userId] = true
	local list = waiting[userId]
	waiting[userId] = nil
	if list then
		for _, hide in list do
			hide()
		end
	end
end

-- Fetch once per userId; every placeholder of that user hides when it arrives
local function fetch(userId: number, url: string, hide: () -> ())
	if ready[userId] then
		hide()
		return
	end
	local list = waiting[userId]
	if list then
		table.insert(list, hide)
	else
		waiting[userId] = { hide }
	end
	if fetching[userId] then
		return
	end
	fetching[userId] = true
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ url }, function(_: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Success then
					markReady(userId)
				end
			end)
		end)
		fetching[userId] = nil -- failed: placeholders stay listed; the next row asks again
	end)
end

-- Content URL of a user's headshot, or nil for ids that have no Roblox profile
function Headshot.url(userId: number): string?
	if typeof(userId) ~= "number" or userId ~= userId or userId < 1 or userId % 1 ~= 0 then
		return nil
	end
	local cached = urls[userId]
	if cached then
		return cached
	end
	local url = `rbxthumb://type=AvatarHeadShot&id={userId}&w={H.Res}&h={H.Res}`
	urls[userId] = url
	return url
end

local function initial(name: string): string
	local first = string.match(name, "^[%w]") -- first letter or digit (names are ASCII)
	return if first then string.upper(first) else "?"
end

export type Options = {
	userId: number,
	name: string?, -- for the placeholder letter
	size: number, -- design px (Theme.Headshot.Row/Small/Hub)
	top: boolean?, -- ranks 1-3: brighter, thicker ring
	mine: boolean?, -- the local player: cyan ring
}

-- Round headshot frame `size` × `size`; position it like any GuiObject
function Headshot.new(o: Options): Frame
	local f = Instance.new("Frame")
	f.Name = "Headshot"
	f.Size = UDim2.fromOffset(o.size, o.size)
	f.BackgroundColor3 = F.Surface3
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local ring = Instance.new("UIStroke")
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Color = if o.mine then C.Cyan elseif o.top then C.GoldHi else C.Gold
	ring.Thickness = if o.top then H.StrokeTop else H.Stroke
	ring.Parent = f

	local url = Headshot.url(o.userId)
	local img: ImageLabel? = nil
	if url then
		local i = Instance.new("ImageLabel")
		i.Name = "Image"
		i.BackgroundTransparency = 1
		i.Size = UDim2.fromScale(1, 1)
		i.Image = url
		i.ScaleType = Enum.ScaleType.Crop
		local c2 = Instance.new("UICorner")
		c2.CornerRadius = UDim.new(0.5, 0)
		c2.Parent = i
		i.Parent = f
		img = i
	end

	local letter = Instance.new("TextLabel")
	letter.Name = "Initial"
	letter.BackgroundTransparency = 1
	letter.Size = UDim2.fromScale(1, 1)
	letter.Text = initial(o.name or "")
	letter.TextColor3 = F.Faint
	letter.TextSize = Kit.fontSize(math.max(9.5, o.size * H.InitialScale))
	letter.FontFace = Theme.Font.UI
	letter.ZIndex = 2 -- above the image until it has loaded
	letter.Parent = f
	if img and url then
		local function hide()
			letter.Visible = false
			f.BackgroundTransparency = 1 -- no placeholder tint around the photo
		end
		local function check()
			if img.IsLoaded then
				hide()
			end
		end
		img:GetPropertyChangedSignal("IsLoaded"):Connect(check)
		check()
		fetch(o.userId, url, hide)
	end
	return f
end

return Headshot
