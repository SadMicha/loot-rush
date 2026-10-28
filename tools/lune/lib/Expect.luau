--!nocheck
-- Kleine expect()-Bibliothek im Jest-Stil für tests/*.spec.luau.

local function show(v, depth: number?): string
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "table" and type(getmetatable(v)) == "string" then
		return "Instance " .. tostring(v) -- Sandbox-Proxy
	elseif type(v) == "table" and (depth or 0) > 2 then
		return "{…}"
	elseif type(v) == "table" then
		local parts, n = {}, 0
		for k, x in v do
			n += 1
			if n > 8 then
				table.insert(parts, "…")
				break
			end
			table.insert(parts, tostring(k) .. "=" .. show(x, (depth or 0) + 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function deepEqual(a, b): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function expect(actual)
	local self = { never = {} }
	local function check(ok: boolean, negated: boolean, message: string)
		if ok == negated then
			error((if negated then "erwartet NICHT: " else "erwartet: ") .. message, 4)
		end
	end
	local matchers = {
		toBe = function(neg, expected)
			check(actual == expected, neg, string.format("%s == %s", show(actual), show(expected)))
		end,
		toEqual = function(neg, expected)
			check(
				deepEqual(actual, expected),
				neg,
				string.format("%s gleich %s", show(actual), show(expected))
			)
		end,
		toBeCloseTo = function(neg, expected, eps)
			check(
				math.abs(actual - expected) <= (eps or 1e-6),
				neg,
				string.format("%s ≈ %s", show(actual), show(expected))
			)
		end,
		toBeTruthy = function(neg)
			check(not not actual, neg, show(actual) .. " ist wahr")
		end,
		toBeFalsy = function(neg)
			check(not actual, neg, show(actual) .. " ist falsch")
		end,
		toBeNil = function(neg)
			check(actual == nil, neg, show(actual) .. " ist nil")
		end,
		toBeGreaterThan = function(neg, n)
			check(actual > n, neg, string.format("%s > %s", show(actual), show(n)))
		end,
		toBeGreaterThanOrEqual = function(neg, n)
			check(actual >= n, neg, string.format("%s >= %s", show(actual), show(n)))
		end,
		toBeLessThan = function(neg, n)
			check(actual < n, neg, string.format("%s < %s", show(actual), show(n)))
		end,
		toBeLessThanOrEqual = function(neg, n)
			check(actual <= n, neg, string.format("%s <= %s", show(actual), show(n)))
		end,
		toHaveLength = function(neg, n)
			check(#actual == n, neg, string.format("Länge %d == %d", #actual, n))
		end,
		toMatch = function(neg, pattern)
			check(
				type(actual) == "string" and actual:match(pattern) ~= nil,
				neg,
				string.format("%s passt zu %q", show(actual), pattern)
			)
		end,
		toContain = function(neg, item)
			local found = false
			if type(actual) == "string" then
				found = actual:find(item, 1, true) ~= nil
			else
				for _, v in actual do
					if v == item then
						found = true
					end
				end
			end
			check(found, neg, string.format("%s enthält %s", show(actual), show(item)))
		end,
		toThrow = function(neg, pattern)
			local ok, err = pcall(actual)
			local matches = not ok
				and (pattern == nil or tostring(err):find(pattern, 1, true) ~= nil)
			check(
				matches,
				neg,
				"Funktion wirft Fehler"
					.. (if pattern then " mit „" .. pattern .. "“" else "")
					.. (if ok then "" else " (war: " .. tostring(err) .. ")")
			)
		end,
		toBeA = function(neg, typeName)
			check(
				typeof(actual) == typeName,
				neg,
				string.format("typeof %s == %s", typeof(actual), typeName)
			)
		end,
	}
	for name, fn in matchers do
		self[name] = function(...)
			fn(false, ...)
		end
		self.never[name] = function(...)
			fn(true, ...)
		end
	end
	return self
end

return expect
