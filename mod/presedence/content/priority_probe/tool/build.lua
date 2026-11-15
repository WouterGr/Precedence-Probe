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

-- the proposal that replaces hit.edge by a copy with the wanted precedence at hit["end"]
local function proposalFor(hit, pref)
	local e = hit.edge
	local old = component(e, CT.BASE_EDGE)
	local s = component(e, CT.BASE_EDGE_STREET)
	if old == nil or s == nil then error("the segment is gone") end
	if #old.objects > 0 then error("this segment has stops, signals or signs on it; not changed") end
	local p = api.type.SimpleProposal.new()
	local seg = api.type.SegmentAndEntity.new()
	seg.entity = -1
	seg.type = 0
	seg.comp = old
	if old.laneConfigs ~= nil then seg.comp.laneConfigs = old.laneConfigs end
	if old.roadTemplate ~= nil then seg.comp.roadTemplate = old.roadTemplate end
	if old.roadStyle ~= nil then seg.comp.roadStyle = old.roadStyle end
	if old.roadType ~= nil then seg.comp.roadType = old.roadType end
	if old.edgeDecorations ~= nil then seg.comp.edgeDecorations = old.edgeDecorations end
	if old.roadDevelopmentLocked ~= nil then seg.comp.roadDevelopmentLocked = old.roadDevelopmentLocked end
	-- what the engine hands out is read-only ("cannot write to read only member"): the copy is changed
	-- on the new segment, like the segment's other members
	seg.streetEdge = s
	if hit["end"] == 0 then seg.streetEdge.precedenceNode0 = pref else seg.streetEdge.precedenceNode1 = pref end
	local written = (hit["end"] == 0) and seg.streetEdge.precedenceNode0 or seg.streetEdge.precedenceNode1
	if tostring(written) ~= tostring(pref) then error("the value was not written as asked (" .. tostring(written) .. ")") end
	local owned = component(e, CT.PLAYER_OWNED)
	if owned ~= nil then seg.playerOwned = owned end
	p.streetProposal.edgesToAdd = { seg }
	p.streetProposal.edgesToRemove = { e }

	-- the settings at both ends of the segment: a road end or plain joint gives them up with the build; a
	-- crossing keeps them, handed back with this segment's number renewed
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
						if lc.segment0 == e then lc.segment0 = -1; renewed = renewed + 1 end
						if lc.segment1 == e then lc.segment1 = -1; renewed = renewed + 1 end
						connections[#connections + 1] = lc
					end
					entry.comp.laneConnections = connections
					local walks = {}
					for i = 1, #cfg.crosswalks do
						local w = cfg.crosswalks[i]
						walks[#walks + 1] = (w == e) and -1 or w
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
			say(string.format("VERIFY   edge %d, end %d: precedence=%s; lanes=%d", segs[i], which,
				tostring((which == 0) and s.precedenceNode0 or s.precedenceNode1), #c.laneConfigs))
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
local function send(hit, value, say)
	if BUILD.pending then return end
	local enum = api.type["enum"].PrecedencePreference
	if enum == nil or enum[value] == nil then error("PrecedencePreference." .. value .. " is not available") end
	local pref = enum[value]
	local s = component(hit.edge, CT.BASE_EDGE_STREET)
	if s == nil then error("the segment is gone") end
	local current = (hit["end"] == 0) and s.precedenceNode0 or s.precedenceNode1
	if tostring(current) == tostring(pref) then
		say(string.format("edge %d end %d already %s (%s); nothing to do", hit.edge, hit["end"], value, tostring(current)))
		return
	end
	local before = configText(hit.node)
	local proposal, notes = proposalFor(hit, pref)
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

return { send = send, tick = tick, busy = busy, VALUES = { priority = "YES", giveway = "NO", default = "AUTO" } }
