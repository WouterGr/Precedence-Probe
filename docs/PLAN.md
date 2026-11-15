# Precedence Probe — plan

Status (2026-11-15): skeleton mod and console probes written, not yet run in game.

## Goal

Find out whether intersection priority (right of way) can be forced on Transport Fever 3 road junctions through the modding API, using a small, separate test mod. If it works, decide whether to build a proper feature.

## Dev setup (2026-11-15)

- modId `presedence`, display name "Priority Probe", author WouterGr. Source of truth: `mod/presedence/` in this repo; copy to `<steam>\userdata\<id>\3493540\local\mods\presedence`.
- TF3 has a Lua console. Game log: `<steam>\userdata\<id>\3493540\local\crash_dump\stdout.txt`.
- Script mods are Teal (`.tl`), compiled by the game. Typings: `<game>\api\tealdef`, `<game>\base\tealdef`. Template layout: `mod.json`, `_content.json`, `_metadata/modinfo.json`, `content/<name>.gs.lua` + `content/<name>.script.tl`.

## Findings from the game files (2026-11-15)

1. **ROADS > Tools entries are `construction_tool` resources bound to a fixed set of native `ACTION_*` names** (e.g. `ACTION_LANE_MODIFIER_TOOL`, `ACTION_TRAFFIC_LIGHT_TOOL`, `ACTION_CROSSWALK_MODIFIER_TOOL`). No custom action is visible, so a mod cannot add a new native world tool the same way. React tools (`ToolReactUtil.registerToolWithWindow`) exist but the base game only uses them for windows (pause menu, statistics, music player, map editor).
   - Revised UI plan: bare-bones UI is a mod button (`MainModButtonAreaExtension`) plus mouse picking in a GUI script (`api.gui.mouse.getTerrainPosition()`, mouse click events, `api.engine.util.findEntitiesInCircle(..., BASE_EDGE_STREET)`). The console probe tells us first whether the engine side works at all.
2. **Write command in TF3 is `api.cmd.makeWorldBuildProposalCmd(proposal, context, ignoreErrors, playerInitiated)`** sent with `api.cmd.sendCommand`, not the TF2-style `make.buildProposal`.
3. `BaseEdgeStreet.precedenceNode0/1` doc strings: "Precedence preference at first/second node". `Edge.precedence : boolean` is a field of the `Edge` record.

## Stage 0 gate (console)

- `console/probe_a_read.lua`: read-only. Mouse over a road, run in the console; logs `PP ...` lines with precedence values and node config presence.
- `console/probe_b_write.lua`: replaces one edge with a copy that has a changed `precedenceNode0`. Untested; run after probe A, on a bare road.

## What we know

- TF3 has no priority or stop-sign UI. Players report every junction behaves like a yield. The only player controls are lane connections and traffic light phases.
- The engine stores priority per street segment end: `Engine.Component.BaseEdgeStreet.precedenceNode0` / `precedenceNode1`, type `PrecedencePreference` with values `YES`, `NO`, `AUTO`. The docs do not say what each value does.
  - Working guess (unverified): `YES` = priority at that end, `NO` = give way, `AUTO` = game decides.
- `api.engine` is read-only. Read with `api.engine.getComponent(edge, api.type.ComponentType.BASE_EDGE_STREET)`.
- Write path is confirmed in the type docs: `SimpleProposal.streetProposal` (`SimpleStreetProposal`) has `edgesToAdd : { Proposal.SegmentAndEntity }` and `edgesToRemove : { Engine.Entity }`. `SegmentAndEntity` has a `streetEdge : BaseEdgeStreet` field. So: remove the segment, add an identical copy with a modified `streetEdge`.

### New since the first plan

1. **`Edge.precedence : boolean`** exists in `api.type`, undocumented. It may be a second (street-type or per-edge) switch. Read mode logs it too.
2. **Node config can be lost.** `SimpleStreetProposal` also carries `nodeConfigsToAdd` / `nodeConfigsToRemove`, and `BaseNodeConfig` holds `trafficLightPreference`, `trafficLightConfig` and `userModifiedTrafficLightStates`. Replacing a segment may reset custom lane connections and light phases at that node. Read mode dumps the node config so write mode can re-add it if needed.
3. **Replaced segments get a new entity ID.** Anything that refers to the old edge (bus/tram stops via `edgeObjectsToAdd`, signals, line routes) may break. Stage 3 tests on bare road first; edge objects come later.

## Stages

| # | Stage | Est. | Done when |
|---|-------|------|-----------|
| 0 | Console probe (gate; console exists) | 30 min | Precedence values read from an in-game Lua console on one junction. Skipped if TF3 has no console |
| 1 | Skeleton | 30 min | Mod loads (template pattern), a startup line appears in the game log. UI entry point per finding 1 |
| 2 | Read mode | 1 h | Clicking a road end writes `precedenceNode0/1`, `Edge.precedence`, node + segment IDs, node config and traffic-light presence to the game log |
| 3 | Write mode | 2 h | Clicking sets `YES`/`NO`/`AUTO` on that end; road, lanes and lights unchanged afterwards |
| 4 | Behaviour tests | 1 h | Matrix below filled in `docs/TESTS.md` (in-game testing) |
| 5 | Go / no-go | 15 min | Decision on a real feature (main-road mode, optional give-way paint, EN/RU/DE/NL strings) |

Stage 0 is the gate: the console exists, so we learn whether the idea works before any UI is written.

## Platform

- Developed and tested on Steam for Windows.
- The mod must work on every launcher (Steam, GOG, Epic) and through the Mod Hub. So: no hard-coded install or user paths, no launcher-specific APIs, only the documented mod folder structure and the scripting API.
- All diagnostic output goes through `print()` to the game log file, which is the main feedback channel during testing.

## Mod design

- Own `modId`, written from the public API docs only; no code copied from other mods.
- Modes: **Read / Priority / Give way / Default**, behind a mod button (see finding 1; a native ROADS > Tools entry is not possible with the known actions).
- Commands go through `api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(...))`. Check in stage 1 which script context (GUI vs game script) the TF3 API requires.

## Test matrix (stage 4)

1. T-junction, side road `NO`: do side-road vehicles wait for the main road?
2. Same junction, main road `YES`: any difference from default?
3. Both roads `YES`: what happens, any deadlock?
4. Junction with traffic lights: does priority change anything, or do lights override it?
5. 4-way junction, one road `YES`: priority over both crossing arms?
6. **Save and reload:** do the values survive?
7. **Town road upgrade:** does a town rebuilding the road reset the value? (Compare with `BaseEdge.roadDevelopmentLocked = true`.)

## Open questions

- What each `PrecedencePreference` value does in play.
- What `Edge.precedence` controls.
- Whether segment replacement resets lane connections or light phases.
- Whether a lighter setter than a full proposal exists in `api.cmd`.

## Sources

- https://wiki.transportfever3.com/script-doc/api/engine.html
- https://wiki.transportfever3.com/script-doc/api/type.html
- https://steamcommunity.com/app/3493540/discussions/0/588439600673976114/
- https://wiki.transportfever3.com/doku.php?id=modding%3Ageneral%3Aguidelines
