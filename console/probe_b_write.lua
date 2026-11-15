-- PROBE B (write test, UNTESTED). Run probe A first, pick one edge id, set EDGE and VALUE, paste in console.
-- Replaces the edge by an identical copy whose streetEdge.precedenceNode0 is changed. Test on a bare road first.
local EDGE = 0           -- edge entity id from probe A
local VALUE = "NO"       -- "YES" | "NO" | "AUTO"
local CT = api.type.ComponentType
local s = api.engine.getComponent(EDGE, CT.BASE_EDGE_STREET)
local b = api.engine.getComponent(EDGE, CT.BASE_EDGE)
local enum = api.type["enum"] or api.type
local pref = (enum.PrecedencePreference or api.type.PrecedencePreference)[VALUE]
print("PP before", tostring(s.precedenceNode0), "setting", VALUE, tostring(pref))
s.precedenceNode0 = pref
local seg = api.type.SegmentAndEntity.new()
seg.entity = -1
seg.type = 0
seg.comp = b
seg.streetEdge = s
local prop = api.type.SimpleProposal.new()
prop.streetProposal.edgesToRemove[1] = EDGE
prop.streetProposal.edgesToAdd[1] = seg
local cmd = api.cmd.makeWorldBuildProposalCmd(prop, api.type.Context.new(), false, true)
api.cmd.sendCommand(cmd, function(res) print("PP write result", tostring(res)) end)
