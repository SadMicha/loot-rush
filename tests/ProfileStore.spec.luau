-- N9.1 spike: the real ProfileStore package (ServerPackages) runs unmodified against the sandbox
-- DataStore/MessagingService. Two ProfileStore copies with different JobIds act as two servers.
-- The tests build on each other (one sandbox per spec file).
local STORE_NAME = "LootRush_Profile_v3"
local STORE = STORE_NAME .. "/global"
local PACKAGE = "ServerScriptService.ServerPackages.ProfileStore"

local Profile = require("ReplicatedStorage.Shared.Profile")

local function template()
	return { v = Profile.VERSION, data = Profile.freshAccount() }
end

local function waitUntil(cond: () -> boolean, timeout: number): boolean
	local start = os.clock()
	while not cond() do
		if os.clock() - start > timeout then
			return false
		end
		task.wait()
	end
	return true
end

local function raw(key: string)
	return sim.datastores[STORE] and sim.datastores[STORE][key]
end

local A, B -- ProfileStore module copies ("server-a", "server-b")
local storeA, storeB
local profileA, profileB

describe("ProfileStore in the sandbox", function()
	it("starts a session on server A and creates the raw record", function()
		A = sim:requireFresh(PACKAGE, { jobId = "server-a" })
		B = sim:requireFresh(PACKAGE, { jobId = "server-b" })
		expect(A ~= B).toBe(true)
		storeA = A.New(STORE_NAME, template())
		storeB = B.New(STORE_NAME, template())

		profileA = storeA:StartSessionAsync("p_1", {})
		expect(profileA).never.toBeNil()
		expect(A.DataStoreState).toBe("Access")
		expect(profileA:IsActive()).toBe(true)
		expect(profileA.Data.v).toBe(Profile.VERSION)
		expect(#profileA.Data.data.characters).toBe(1)

		local rec = raw("p_1")
		expect(rec).never.toBeNil()
		expect(type(rec.Data)).toBe("table")
		expect(rec.MetaData.ActiveSession[2]).toBe("server-a")
		expect(rec.MetaData.SessionLoadCount).toBe(1)
		expect(type(rec.GlobalUpdates)).toBe("table")
	end)

	it("saves changes and user IDs; the store holds a copy, not the live table", function()
		profileA.Data.data.gold = 42
		profileA:AddUserId(1)
		local saved = false
		local conn = profileA.OnAfterSave:Connect(function()
			saved = true
		end)
		profileA:Save()
		expect(waitUntil(function()
			return saved
		end, 10)).toBe(true)
		conn:Disconnect()

		local rec = raw("p_1")
		expect(rec.Data.data.gold).toBe(42)
		expect(rec.UserIds[1]).toBe(1)
		expect(sim.datastoreInfo[STORE].p_1.userIds[1]).toBe(1)
		expect(profileA.KeyInfo:GetUserIds()[1]).toBe(1)
		expect(type(profileA.KeyInfo.Version)).toBe("string")

		profileA.Data.data.gold = 43 -- not saved
		expect(raw("p_1").Data.data.gold).toBe(42)
		profileA.Data.data.gold = 42
	end)

	it("loads and reconciles an existing record", function()
		sim.datastores[STORE].p_2 = {
			Data = { v = Profile.VERSION, data = { gold = 5 } },
			MetaData = { ProfileCreateTime = 0, SessionLoadCount = 3, MetaTags = {} },
			RobloxMetaData = {},
			UserIds = { 2 },
			GlobalUpdates = { 0, {} },
		}
		local p = storeA:StartSessionAsync("p_2", {})
		expect(p).never.toBeNil()
		expect(p.Data.data.gold).toBe(5)
		expect(p.Data.data.soulstars).toBeNil()
		p:Reconcile()
		expect(p.Data.data.soulstars).toBe(Profile.freshAccount().soulstars)
		expect(p.SessionLoadCount).toBe(4)
		expect(p.UserIds[1]).toBe(2)
		p:EndSession()
		expect(waitUntil(function()
			return raw("p_2").MetaData.ActiveSession == nil
		end, 10)).toBe(true)
	end)

	it("hands the session over to server B without two active profiles", function()
		-- ProfileStore ignores session messages within 6 s of os.clock() 0 (real servers are older)
		waitUntil(function()
			return os.clock() > 7
		end, 10)
		local endedOnA = false
		profileA.OnSessionEnd:Connect(function()
			endedOnA = true
		end)
		-- Unsaved change right before the hand-off: only A's final save on release can carry it
		profileA.Data.data.gold = 77
		expect(raw("p_1").Data.data.gold).toBe(42)
		local start = os.clock()
		local done = false
		local both = false
		task.spawn(function()
			profileB = storeB:StartSessionAsync("p_1", {})
			done = true
		end)
		expect(waitUntil(function()
			if profileA:IsActive() and profileB and profileB:IsActive() then
				both = true
			end
			return done
		end, 30)).toBe(true)
		local handOff = os.clock() - start

		expect(both).toBe(false)
		expect(endedOnA).toBe(true)
		expect(profileA:IsActive()).toBe(false)
		expect(profileB).never.toBeNil()
		expect(profileB:IsActive()).toBe(true)
		expect(profileB.Data.data.gold).toBe(77)
		expect(raw("p_1").MetaData.ActiveSession[2]).toBe("server-b")
		expect(raw("p_1").MetaData.ForceLoadSession).toBeNil()
		-- A asked to end its session over MessagingService
		local asked = false
		for _, m in sim.messages do
			if m.topic:sub(1, 3) == "PS_" and m.data.EndSession == true then
				asked = true
			end
		end
		expect(asked).toBe(true)
		-- Measured: FIRST_LOAD_REPEAT (5 s) plus a few DataStore calls
		expect(handOff < 10).toBe(true)
	end)

	it("releases the session with EndSession", function()
		local ended = false
		profileB.OnSessionEnd:Connect(function()
			ended = true
		end)
		profileB:EndSession()
		expect(waitUntil(function()
			return raw("p_1").MetaData.ActiveSession == nil
		end, 10)).toBe(true)
		expect(ended).toBe(true)
		expect(profileB:IsActive()).toBe(false)
		expect(raw("p_1").Data.data.gold).toBe(77)
	end)

	it("steals the session after SESSION_STEAL when the owner does not answer", function()
		local pa = storeA:StartSessionAsync("p_6", {})
		expect(pa).never.toBeNil()
		pa.Data.data.gold = 6
		local saved = false
		local conn = pa.OnAfterSave:Connect(function()
			saved = true
		end)
		pa:Save()
		expect(waitUntil(function()
			return saved
		end, 10)).toBe(true)
		conn:Disconnect()
		-- A no longer hears its session topic (e.g. MessagingService down); unsaved change
		sim.subscriptions["PS_" .. raw("p_6").MetaData.ActiveSession[3]] = nil
		pa.Data.data.gold = 99

		local start = os.clock()
		local pb
		local done = false
		task.spawn(function()
			pb = storeB:StartSessionAsync("p_6", {})
			done = true
		end)
		expect(waitUntil(function()
			return done
		end, 90)).toBe(true)
		local took = os.clock() - start
		expect(pb).never.toBeNil()
		expect(pb:IsActive()).toBe(true)
		-- Stolen: A never saved again, so its unsaved change is lost
		expect(pb.Data.data.gold).toBe(6)
		expect(raw("p_6").MetaData.ActiveSession[2]).toBe("server-b")
		-- FIRST_LOAD_REPEAT (5 s) + SESSION_STEAL (40 s) in LOAD_REPEAT_PERIOD steps
		expect(took >= 40).toBe(true)
		expect(took < 70).toBe(true)

		-- A finds out on its next save and ends the session without overwriting B
		local endedOnA = false
		pa.OnSessionEnd:Connect(function()
			endedOnA = true
		end)
		pa:Save()
		expect(waitUntil(function()
			return endedOnA
		end, 10)).toBe(true)
		expect(pa:IsActive()).toBe(false)
		expect(raw("p_6").Data.data.gold).toBe(6)
		expect(raw("p_6").MetaData.ActiveSession[2]).toBe("server-b")
		pb:EndSession()
		expect(waitUntil(function()
			return raw("p_6").MetaData.ActiveSession == nil
		end, 10)).toBe(true)
	end)

	it("releases all sessions on BindToClose and refuses new ones", function()
		local pa = storeA:StartSessionAsync("p_3", {})
		local pb = storeB:StartSessionAsync("p_4", {})
		expect(pa).never.toBeNil()
		expect(pb).never.toBeNil()
		pa.Data.data.gold = 3
		pb.Data.data.gold = 4

		local pending = #sim.onClose
		expect(pending).toBe(2) -- one per ProfileStore copy
		for _, fn in sim.onClose do
			task.spawn(function()
				fn()
				pending -= 1
			end)
		end
		expect(waitUntil(function()
			return pending == 0
		end, 20)).toBe(true)

		expect(A.IsClosing).toBe(true)
		expect(B.IsClosing).toBe(true)
		for key, gold in { p_3 = 3, p_4 = 4 } do
			expect(raw(key).MetaData.ActiveSession).toBeNil()
			expect(raw(key).Data.data.gold).toBe(gold)
		end
		expect(storeA:StartSessionAsync("p_5", {})).toBeNil()
	end)
end)
