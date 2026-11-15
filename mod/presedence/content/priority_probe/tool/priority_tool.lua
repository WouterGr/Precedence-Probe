-- Priority Probe: the tool while it is in hand. Stage 2 (read mode): the road end nearest the cursor
-- is described in a tooltip and, on a click, in the game log (crash_dump\stdout.txt, lines "[presedence]").
-- Stage 3: Priority / Give way / Default set the precedence (YES / NO / AUTO) of that road end (build.lua).

local builtin = ug_require "::/gui/main/builtin.lua"
local react = ug_require "::/gui/main/react.lua"
local Build = require "presedence::/priority_probe/tool/build.lua"

local CT = api.type.ComponentType
local MODES = {
	{ id = "read", label = "Read" },
	{ id = "priority", label = "Priority" },
	{ id = "giveway", label = "Give way" },
	{ id = "slow", label = "Give way + slow" },
	{ id = "default", label = "Default" },
}
local REFRESH = 0.1          -- s between two looks under the cursor
local RADIUS = 60.0          -- m around the cursor in which roads are looked at
local MAX_DIST = 12.0        -- m: farther from a road than this, nothing is picked

local function say(msg)
	local t = "[presedence] " .. tostring(msg)
	if pcall(function() log.message(t) end) then return end
	pcall(print, t)
end

-- never ask the engine for a component of an entity it does not know (fatal, not caught by pcall)
local function component(e, kind)
	if type(e) ~= "number" or e < 0 then return nil end
	if not api.engine.entityExists(e) then return nil end
	return api.engine.getComponent(e, kind)
end

-- distance from (x, y) to the straight line between a segment's two ends, and which end is nearer: 0 | 1
local function measure(c, x, y)
	local ax, ay, bx, by = c.position0.x, c.position0.y, c.position1.x, c.position1.y
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	local t = len2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / len2)) or 0
	local px, py = ax + t * dx, ay + t * dy
	return math.sqrt((x - px) ^ 2 + (y - py) ^ 2), (t < 0.5) and 0 or 1
end

-- the street segment nearest the cursor: -> { edge, end (0|1), node, dist } or nil
local function pick()
	if not api.gui.mouse.hasTerrainPosition() then return nil end
	local p = api.gui.mouse.getTerrainPosition()
	local edges = api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(p.x, p.y), RADIUS, CT.BASE_EDGE)
	local best
	for _, e in ipairs(edges) do
		local c = component(e, CT.BASE_EDGE)
		if c ~= nil and component(e, CT.BASE_EDGE_STREET) ~= nil then
			local d, which = measure(c, p.x, p.y)
			if d <= MAX_DIST and (best == nil or d < best.dist) then
				best = { edge = e, ["end"] = which, node = (which == 0) and c.node0 or c.node1, dist = d }
			end
		end
	end
	return best
end

local function describe(hit)
	local s = component(hit.edge, CT.BASE_EDGE_STREET)
	local b = component(hit.edge, CT.BASE_EDGE)
	if s == nil or b == nil then return nil end
	local cfg = component(hit.node, CT.BASE_NODE_CONFIG)
	return string.format("edge %d, end %d (node %d): precedence node0=%s node1=%s; objects=%d; node config=%s; light=%s",
		hit.edge, hit["end"], hit.node, tostring(s.precedenceNode0), tostring(s.precedenceNode1), #b.objects,
		tostring(cfg ~= nil), tostring(component(hit.node, CT.BASE_NODE_TRAFFIC_LIGHT) ~= nil))
end

local recipe = react.RegisterRecipe("PresedencePriorityTool", function(params)
	if not params.isActive then return end
	local action = function()
		local hit = react.useRef(nil)
		local text = react.useState("")
		local refreshAt = react.useRef(0)

		react.onStep(function()
			local time = api.util.getApplicationTime()
			Build.tick(time, say)
			-- nothing is looked up while a build is on its way or has just landed (a fresh entity is fatal to ask about)
			if Build.busy(time) then hit:set(nil); return end
			if time < refreshAt:get() then return end
			refreshAt:set(time + REFRESH)
			local ok, err = pcall(function()
				local h = pick()
				hit:set(h)
				local want = ""
				if h ~= nil then
					local s = component(h.edge, CT.BASE_EDGE_STREET)
					if s ~= nil then
						want = string.format("edge %d  end %d:  %s", h.edge, h["end"],
							tostring((h["end"] == 0) and s.precedenceNode0 or s.precedenceNode1))
					end
				end
				if want ~= text:old() then text:set(want) end
			end)
			if not ok then
				hit:set(nil)
				refreshAt:set(time + 1.0)
				say("look failed: " .. tostring(err):match("^[^\r\n]*"))
			end
		end)

		local children = {
			builtin.Selector{
				filter = function() return false end,
				onProcessMouseEvent = function(event)
					if event.type == api.gui.mouse.Event.Type.Pressed and event.button == 0 then
						local h = hit:get()
						if h ~= nil and not Build.busy(api.util.getApplicationTime()) then
							local mode = MODES[tonumber((params.getCurrentParams() or {}).pp_mode) or 1] or MODES[1]
							local ok, err = pcall(function()
								if mode.id == "read" then
									say("READ " .. tostring(describe(h)))
								else
									say(mode.id .. ": " .. tostring(describe(h)))
									Build.send(h, Build.VALUES[mode.id], say, mode.id == "slow")
									hit:set(nil)
								end
							end)
							if not ok then say("click failed: " .. tostring(err):match("^[^\r\n]*")) end
						end
						return true
					end
					return false
				end,
				onSelect = function() return true end,
				lineViewerSupport = false,
				stopOnMenuBack = false,
			},
		}
		local t = text:old()
		if type(t) == "string" and t ~= "" then
			children[#children + 1] = builtin.ActionTooltip{ recipe = builtin.TextView, param = { text = t } }
		end
		return builtin.ActionDescriptor{
			tool = "presedence-priority-tool",
			crosshair = true,
			children = children,
			onBack = function() params.abort() end,
		}
	end
	params.setActionFn(action, "presedence-priority-tool")
end)

return { MODES = MODES, recipe = recipe }
