-- Priority Probe: the tool's menu entry and its mode setting.
-- Pattern taken from how a custom road tool is declared (action ACTION_CUSTOM + a react recipe).

local react = ug_require "::/gui/main/react.lua"
local Tool = require "presedence::/priority_probe/tool/priority_tool.lua"

local IMAGES = "presedence::/priority_probe/tool_images/"
local MODES = Tool.MODES   -- the setting's values, in this order

local function label(s) return (_ and _(s)) or s end

function data()
	return {
		getDefinition = function(resName, _repository, _params)
			local e = api.type["enum"]
			local values = {}
			for i, m in ipairs(MODES) do values[i] = label(m.label) end
			return {
				resName = resName,
				action = "ACTION_CUSTOM",
				name = label("Priority Probe"),
				description = label("Show or set which road has priority at an intersection. Experimental."),
				icon = { icon = IMAGES .. "priority_tool.tga" },
				previewIcon = { icon = IMAGES .. "priority_tool_preview.tga" },
				availability = { yearFrom = 0, yearTo = 0 },
				menuCategory = { categories = { { category = "roads_tools", order = 1600 } } },
				params = {
					{
						key = "pp_mode", name = label("Mode"), tooltip = label("Read shows the setting of the road end nearest the cursor."),
						values = values, defaultIndex = 1,
						uiType = e.ScriptParamType.Button, location = e.ScriptParamLocation.Default,
						displayMode = e.ScriptParamDisplayMode.Horizontal,
						yearFrom = 0, yearTo = 0, group = "pp_mode", constructionParam = true,
						onChangeFn = function()
							react.fireEvent(nil, "constructionSetSuppressCallout", true)
						end,
					},
				},
				customAction = { recipe = Tool.recipe, customParam = {} },
				builderAudioRes = { "::/gui/construction/sound/tool_bus_lane.builder_audio" },
			}
		end,
	}
end
