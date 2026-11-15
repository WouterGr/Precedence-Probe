-- PROBE A (read only). Point the mouse at a road, then run this in the TF3 Lua console.
-- Output lines start with "PP" and also go to crash_dump\stdout.txt.
local CT = api.type.ComponentType
local p = api.gui.mouse.getTerrainPosition()
print("PP mouse", p.x, p.y, p.z)
local es = api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(p.x, p.y), 40, CT.BASE_EDGE_STREET)
print("PP edges found", #es)
for _, e in ipairs(es) do
  local s = api.engine.getComponent(e, CT.BASE_EDGE_STREET)
  local b = api.engine.getComponent(e, CT.BASE_EDGE)
  print("PP edge", e, "prec0", tostring(s.precedenceNode0), "prec1", tostring(s.precedenceNode1),
        "node0", b.node0, "node1", b.node1, "objects", #b.objects, "locked", tostring(b.roadDevelopmentLocked))
  for _, n in ipairs({ b.node0, b.node1 }) do
    local cfg = api.engine.getComponent(n, CT.BASE_NODE_CONFIG)
    print("PP   node", n, "config", tostring(cfg ~= nil), "light", tostring(api.engine.getComponent(n, CT.BASE_NODE_TRAFFIC_LIGHT) ~= nil))
  end
end
