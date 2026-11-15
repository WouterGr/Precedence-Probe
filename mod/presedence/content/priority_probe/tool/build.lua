-- Priority Probe: stage 3. Sets the precedence of one road end by replacing the segment with a copy
-- of itself whose streetEdge carries the new value. Pattern taken from how a custom road tool replaces
-- segments: the segment's end points stay; a crossing's settings (lane connections, crosswalks, lights)
-- refer to the segment by number, so they are handed back with the replaced segment's number renewed.

local CT = api.type.ComponentType
local COOLDOWN = 0.6          -- s after a build before anything is looked up again
local PENDING_MAX = 15.0      -- s after which a build that never answered is given up
local VERIFY_AFTER = 0.8      -- s after a successful build: look at what the junction holds now

local BUILD = { pending = false, since = 0, quietUntil = 0 }
local verifyJob = nil         -- { at, node, before = "text" }

-- never ask the engine for a component of an entity it does not know (fatal, not caught by pcall)
local function component(e, kind)
	if type(e) ~= "number" or e < 0 then return nil end
	if not api.engine.entityExists(e) then return nil end
	return api.engine.getComponent(e, kind)
end

-- things read out of a fresh holder may point into it: keep the holders for a while
local ALIVE, aliveAt = {}, 0
local function keepAlive(holder)
	aliveAt = aliveAt % 4096 + 1
	ALIVE[aliveAt] = holder
end

-- a crossing: three or more segments meet (what cannot be read counts as one)
local function segmentCount(node)
	local street, all = nil, 0
	local ok = pcall(function()
		street = api.engine.system.streetSystem.getNodeStreetSegments(node)
		all = #street
	end)
	if not ok then return nil end
	pcall(function()
		local n = #api.engine.system.streetSystem.getNodeSegments(node)
		if n > all then all = n end
	end)
	return all
end
local function isCrossing(node)
	local n = segmentCount(node)
	return n == nil or n > 2
end

local function configText(node)
	local cfg = component(node, CT.BASE_NODE_CONFIG)
	if cfg == nil then return "no node config" end
	local text = "node config"
	pcall(function()
		text = string.format("%d lane connections, %d crosswalks, %d light phases",
			#cfg.laneConnections, #cfg.crosswalks, #cfg.trafficLightConfig.states)
	end)
	return text
end

-- Slow approach (prototype): the give-way arm gets a short piece next to the junction whose car lanes have a
-- very low speed limit, so vehicles roll up to the junction slowly instead of entering at speed.
local SLOW_SPEED = 1.5        -- m/s (about 5 km/h) on the car lanes running into the junction
local SLOW_LEN = 20.0         -- m from the junction's point: the length of the slow piece
local FAR_MIN = 10.0          -- m: the piece left on the far side may not be shorter than this
local SAMPLES = 64            -- pieces a segment's length is measured over

local function allows(lc, name)
	local yes = false
	pcall(function() yes = lc.transportModes[api.type["enum"].TransportMode[name]] == true end)
	return yes
end
local function isCarLane(lc) return allows(lc, "CAR") or allows(lc, "BUS") or allows(lc, "TRUCK") end

-- the lowest speed of a segment's car lanes (nil: none)
local function carSpeed(c, forward)
	local low = nil
	pcall(function()
		for i = 1, #c.laneConfigs do
			local lc = c.laneConfigs[i]
			if isCarLane(lc) and (forward == nil or lc.forward == forward) and (low == nil or lc.speed < low) then low = lc.speed end
		end
	end)
	return low
end

-- a segment's line (cubic Hermite): a point and its direction at parameter t
local function onLine(c, t)
	local t2, t3 = t * t, t * t * t
	local h00, h10, h01, h11 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t, -2 * t3 + 3 * t2, t3 - t2
	local d00, d10, d01, d11 = 6 * t2 - 6 * t, 3 * t2 - 4 * t + 1, -6 * t2 + 6 * t, 3 * t2 - 2 * t
	local p0, p1, a, b = c.position0, c.position1, c.tangent0, c.tangent1
	local function mix(k0, k1, k2, k3, f) return k0 * p0[f] + k1 * a[f] + k2 * p1[f] + k3 * b[f] end
	return { x = mix(h00, h10, h01, h11, "x"), y = mix(h00, h10, h01, h11, "y"), z = mix(h00, h10, h01, h11, "z") },
		{ x = mix(d00, d10, d01, d11, "x"), y = mix(d00, d10, d01, d11, "y"), z = mix(d00, d10, d01, d11, "z") }
end

-- the metres at each of SAMPLES + 1 places along the line, and the whole length
local function measure(c)
	local at, sum, last = { 0 }, 0, nil
	for i = 0, SAMPLES do
		local p = onLine(c, i / SAMPLES)
		if last ~= nil then
			sum = sum + math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2)
			at[i + 1] = sum
		end
		last = p
	end
	return at, sum
end

local function paramAt(at, m)
	for i = 1, SAMPLES do
		if m <= at[i + 1] then
			local span = at[i + 1] - at[i]
			return ((i - 1) + ((span > 1e-9) and (m - at[i]) / span or 0)) / SAMPLES
		end
	end
	return 1
end

-- the piece of the line between two parameters
local function piece(c, ta, tb)
	local k = tb - ta
	local pa, da = onLine(c, ta)
	local pb, db = onLine(c, tb)
	local function sc(d) return { x = d.x * k, y = d.y * k, z = d.z * k } end
	return { position0 = pa, position1 = pb, tangent0 = sc(da), tangent1 = sc(db) }
end

local function vec(p) return api.type.Vec3f.new(p.x, p.y, p.z) end

-- a copy of the old segment as a new one (number id) between two points; line = nil keeps its line
local function copyOf(e, _old, _s, id, node0, node1, line, slowForward)
	-- each piece from a reading of its own, so that two pieces cannot share anything
	local old = component(e, CT.BASE_EDGE)
	local s = component(e, CT.BASE_EDGE_STREET)
	if old == nil or s == nil then error("the segment is gone") end
	local seg = api.type.SegmentAndEntity.new()
	seg.entity = id
	seg.type = 0
	seg.comp = old
	if old.laneConfigs ~= nil then seg.comp.laneConfigs = old.laneConfigs end
	if old.roadTemplate ~= nil then seg.comp.roadTemplate = old.roadTemplate end
	if old.roadStyle ~= nil then seg.comp.roadStyle = old.roadStyle end
	if old.roadType ~= nil then seg.comp.roadType = old.roadType end
	if old.edgeDecorations ~= nil then seg.comp.edgeDecorations = old.edgeDecorations end
	if old.roadDevelopmentLocked ~= nil then seg.comp.roadDevelopmentLocked = old.roadDevelopmentLocked end
	seg.comp.node0 = node0
	seg.comp.node1 = node1
	if line ~= nil then
		seg.comp.position0 = vec(line.position0)
		seg.comp.position1 = vec(line.position1)
		seg.comp.tangent0 = vec(line.tangent0)
		seg.comp.tangent1 = vec(line.tangent1)
	end
	if slowForward ~= nil then
		-- only the lanes that run into the junction (their direction = slowForward) are slowed
		-- a lane is changed on a holder of its own (kept alive), then the list of such lanes is handed to the
		-- segment; every write is read back
		local lanes, changed = {}, 0
		for i = 1, #old.laneConfigs do
			local tmp = api.type.SegmentAndEntity.new()
			tmp.comp.laneConfigs = { old.laneConfigs[i] }
			keepAlive(tmp)
			local own = tmp.comp.laneConfigs[1]
			if isCarLane(own) and own.forward == slowForward and own.speed > SLOW_SPEED then
				own.speed = SLOW_SPEED
				if math.abs(own.speed - SLOW_SPEED) > 0.01 then error("a lane's speed was not written as asked") end
				changed = changed + 1
			end
			lanes[i] = own
		end
		seg.comp.laneConfigs = lanes
		local low = carSpeed(seg.comp, slowForward)
		if changed > 0 and (low == nil or low > SLOW_SPEED + 0.01) then error("the slow lanes were not taken by the segment (" .. tostring(low) .. ")") end
	end
	-- what the engine hands out is read-only ("cannot write to read only member"): the copy is changed
	-- on the new segment, like the segment's other members
	seg.streetEdge = s
	local owned = component(e, CT.PLAYER_OWNED)
	if owned ~= nil then seg.playerOwned = owned end
	return seg
end

-- the settings at both ends of the old segment: a road end or plain joint gives them up with the build; a
-- crossing keeps them, handed back with this segment's number renewed (idAt[node] = the new segment there)
local function settingsFor(p, e, old, idAt)
	local configAdds, toRemove, notes, done = {}, {}, {}, {}
	for _, node in ipairs({ old.node0, old.node1 }) do
		if not done[node] then
			done[node] = true
			local cfg = component(node, CT.BASE_NODE_CONFIG)
			if cfg ~= nil then
				if isCrossing(node) then
					keepAlive(cfg)
					local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
					entry.entity = node
					entry.comp = cfg
					local connections, renewed = {}, 0
					for i = 1, #cfg.laneConnections do
						local lc = cfg.laneConnections[i]
						if lc.segment0 == e then lc.segment0 = idAt[node]; renewed = renewed + 1 end
						if lc.segment1 == e then lc.segment1 = idAt[node]; renewed = renewed + 1 end
						connections[#connections + 1] = lc
					end
					entry.comp.laneConnections = connections
					local walks = {}
					for i = 1, #cfg.crosswalks do
						local w = cfg.crosswalks[i]
						walks[#walks + 1] = (w == e) and idAt[node] or w
					end
					entry.comp.crosswalks = walks
					keepAlive(entry)
					configAdds[#configAdds + 1] = entry
					notes[#notes + 1] = string.format("node %d is a crossing: settings handed back, %d segment number(s) renewed (%s)",
						node, renewed, configText(node))
				else
					notes[#notes + 1] = string.format("node %d is a road end or joint: settings given up (%s)", node, configText(node))
				end
				toRemove[#toRemove + 1] = node
			else
				notes[#notes + 1] = string.format("node %d: no settings", node)
			end
		end
	end
	if #configAdds > 0 then p.streetProposal.nodeConfigsToAdd = configAdds end
	if #toRemove > 0 then p.streetProposal.nodeConfigsToRemove = toRemove end
	return notes
end

local function setPrecedence(seg, whichEnd, pref)
	if whichEnd == 0 then seg.streetEdge.precedenceNode0 = pref else seg.streetEdge.precedenceNode1 = pref end
	local written = (whichEnd == 0) and seg.streetEdge.precedenceNode0 or seg.streetEdge.precedenceNode1
	if tostring(written) ~= tostring(pref) then error("the value was not written as asked (" .. tostring(written) .. ")") end
end

-- the proposal that replaces hit.edge by a copy with the wanted precedence at hit["end"]; slow = the copy next
-- to the junction gets a low speed limit (the segment is cut for it when it is long enough)
local function proposalFor(hit, pref, slow)
	local e = hit.edge
	local old = component(e, CT.BASE_EDGE)
	local s = component(e, CT.BASE_EDGE_STREET)
	if old == nil or s == nil then error("the segment is gone") end
	if #old.objects > 0 then error("this segment has stops, signals or signs on it; not changed") end
	local p = api.type.SimpleProposal.new()
	local notes = {}
	local idAt = {}
	local whichEnd = hit["end"]
	local junction = (whichEnd == 0) and old.node0 or old.node1
	-- lanes that run into the junction: against the segment's direction at its start, with it at its end
	local inward = (whichEnd == 1)
	-- (a plain "x and inward or nil" would lose inward = false)
	local function ifSlow(flag) if flag then return inward end return nil end
	local at, length = measure(old)
	if slow and length >= SLOW_LEN + FAR_MIN then
		-- cut: the point -1, the pieces -2 (node0 side) and -3 (node1 side)
		local tc = (whichEnd == 0) and paramAt(at, SLOW_LEN) or paramAt(at, length - SLOW_LEN)
		local line1, line2 = piece(old, 0, tc), piece(old, tc, 1)
		local point = api.type.NodeAndEntity.new()
		point.entity = -1
		point.comp.position = vec(line1.position1)
		local seg1 = copyOf(e, old, s, -2, old.node0, -1, line1, ifSlow(whichEnd == 0))
		local seg2 = copyOf(e, old, s, -3, -1, old.node1, line2, ifSlow(whichEnd == 1))
		if whichEnd == 0 then setPrecedence(seg1, 0, pref) else setPrecedence(seg2, 1, pref) end
		p.streetProposal.edgesToAdd = { seg1, seg2 }
		p.streetProposal.nodesToAdd = { point }
		idAt[old.node0] = -2
		idAt[old.node1] = -3
		notes[#notes + 1] = string.format("CUT at %.1f m from node %d (segment %.1f m): slow piece %d, car lanes %.1f m/s",
			SLOW_LEN, junction, length, whichEnd == 0 and -2 or -3, SLOW_SPEED)
	else
		local seg = copyOf(e, old, s, -1, old.node0, old.node1, nil, ifSlow(slow))
		setPrecedence(seg, whichEnd, pref)
		p.streetProposal.edgesToAdd = { seg }
		idAt[old.node0] = -1
		idAt[old.node1] = -1
		if slow then notes[#notes + 1] = string.format("segment is %.1f m, too short to cut: all of it slow (%.1f m/s)", length, SLOW_SPEED) end
	end
	p.streetProposal.edgesToRemove = { e }
	for _, line in ipairs(settingsFor(p, e, old, idAt)) do notes[#notes + 1] = line end
	return p, notes
end

-- what the junction holds after a build: every street segment at the node and its value at that node
local function verify(node, before, say)
	if not api.engine.entityExists(node) then say("VERIFY node " .. node .. " is gone") return end
	say("VERIFY node " .. node .. ": " .. configText(node) .. " (before: " .. before .. ")")
	local segs = api.engine.system.streetSystem.getNodeStreetSegments(node)
	for i = 1, #segs do
		local c = component(segs[i], CT.BASE_EDGE)
		local s = component(segs[i], CT.BASE_EDGE_STREET)
		if c ~= nil and s ~= nil then
			local which = (c.node0 == node) and 0 or 1
			say(string.format("VERIFY   edge %d, end %d: precedence=%s; lanes=%d; car speed in/out=%s/%s", segs[i], which,
				tostring((which == 0) and s.precedenceNode0 or s.precedenceNode1), #c.laneConfigs, tostring(carSpeed(c, which == 1)), tostring(carSpeed(c, which == 0))))
		end
	end
end

-- true while the engine must not be asked about entities (a build is on its way or has just landed)
local function busy(time) return BUILD.pending or time < BUILD.quietUntil end

-- call every frame: gives up a build that never answered, runs the check after a build
local function tick(time, say)
	if BUILD.pending and time - BUILD.since > PENDING_MAX then
		BUILD.pending = false
		BUILD.quietUntil = time + COOLDOWN
		say("a build got no answer from the game for " .. PENDING_MAX .. " s, given up")
	end
	if verifyJob ~= nil and not BUILD.pending and time >= verifyJob.at and time >= BUILD.quietUntil then
		local job = verifyJob
		verifyJob = nil
		local ok, err = pcall(verify, job.node, job.before, say)
		if not ok then say("verify failed: " .. tostring(err):match("^[^\r\n]*")) end
	end
end

-- start the build: value is "YES" | "NO" | "AUTO"
local function send(hit, value, say, slow)
	if BUILD.pending then return end
	local enum = api.type["enum"].PrecedencePreference
	if enum == nil or enum[value] == nil then error("PrecedencePreference." .. value .. " is not available") end
	local pref = enum[value]
	local s = component(hit.edge, CT.BASE_EDGE_STREET)
	if s == nil then error("the segment is gone") end
	local current = (hit["end"] == 0) and s.precedenceNode0 or s.precedenceNode1
	local edgeNow = component(hit.edge, CT.BASE_EDGE)
	local lowNow = edgeNow ~= nil and carSpeed(edgeNow, hit["end"] == 1) or nil
	local alreadySlow = (not slow) or (lowNow ~= nil and lowNow <= SLOW_SPEED + 0.1)
	if tostring(current) == tostring(pref) and alreadySlow then
		say(string.format("edge %d end %d already %s (%s); nothing to do", hit.edge, hit["end"], value, tostring(current)))
		return
	end
	local before = configText(hit.node)
	local proposal, notes = proposalFor(hit, pref, slow)
	say(string.format("SENDING edge %d end %d: %s -> %s (%s)", hit.edge, hit["end"], tostring(current), value, tostring(pref)))
	for _, line in ipairs(notes) do say("   " .. line) end
	local now = api.util.getApplicationTime()
	BUILD.pending = true
	BUILD.since = now
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, true), function(res, success)
		local t = api.util.getApplicationTime()
		BUILD.pending = false
		BUILD.quietUntil = t + COOLDOWN
		if success then
			say("BUILT edge " .. hit.edge .. " end " .. hit["end"] .. " -> " .. value)
			verifyJob = { at = t + VERIFY_AFTER, node = hit.node, before = before }
		else
			local msg = ""
			pcall(function()
				local es = res.resultProposalData.errorState
				for i = 1, #es.messages do msg = msg .. tostring(es.messages[i]) .. " | " end
				msg = msg .. "critical = " .. tostring(es.critical)
			end)
			say("REFUSED by the game: " .. msg)
		end
	end)
end

return { send = send, tick = tick, busy = busy, VALUES = { priority = "YES", giveway = "NO", slow = "NO", default = "AUTO" } }
