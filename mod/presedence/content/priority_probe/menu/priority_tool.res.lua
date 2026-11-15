-- Priority Probe: the tool's entry in the game's ROADS > Tools menu (a "construction_tool" resource;
-- menu.script.lua returns the entry). The game finds this file by its place in menu\.
function data()
	return {
		type = "construction_tool",
		data = {
			getDefinitionFn = {
				fileName = resolve("menu.script@getDefinition"),
			}
		}
	}
end
