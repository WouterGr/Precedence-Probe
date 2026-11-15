--- Priority Probe: stage 1 skeleton. Only proves the mod loads and logs to stdout.txt.

local LOG <const> = "[presedence] "

local record State
	started : boolean
end

local mod = {}

mod.update = function(_userParams : table, state : GameScriptState<State>, _dt : number)
	local current = state:get()
	if current ~= nil and current.started then
		return
	end
	log.message(LOG .. "skeleton loaded, build " .. getBuildVersion())
	state:set({ started = true })
end

return mod
