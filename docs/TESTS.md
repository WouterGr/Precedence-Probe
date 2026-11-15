# Behaviour tests (stage 4)

Setup: mod `presedence` enabled, `Road_test.sav`, tool ROADS > Tools > Priority Probe. Set modes: Priority = `YES`, Give way = `NO`, Default = `AUTO`. A setting applies to the road end nearest the click, i.e. one arm of one junction. The log (`crash_dump\stdout.txt`, lines `[presedence]`) shows what was written.

| # | Test | Result |
|---|------|--------|
| 0 | Write `NO` to one end, read it back (Read mode) | PASS: reads 1, lane connections unchanged |
| 1 | T-junction: side arm `NO`, both main arms `YES`. Do side-road vehicles wait for the main road? | Set up at nodes 33148 and 31562 (log, 09:46Z). In-game: PARTIAL. Side-road cars do yield, but they roll in without stopping, take the gap early and accelerate slowly, so main-road cars still brake. Fine in heavy traffic, weak in light traffic. |
| 2 | Same junction, main road `YES` only: any difference from default? | |
| 3 | All arms `YES`: deadlock? | |
| 4 | Junction with traffic lights: does priority change anything? | |
| 5 | 4-way junction, one road `YES` | |
| 6 | Save, reload: do the values survive? | |
| 7 | Town rebuilds or upgrades the road: is the value reset? | |
| 8 | `Default` restores 2 | |
| 9 | `YES` writes 0 and reads back | PASS (4 arms, 2 junctions; lane connections 6 -> 6) |

Notes on how to watch: use the traffic layer, or follow a vehicle on the side road arriving at the junction while the main road is busy.

## Slow approach prototype (2026-11-15)

- Give way + slow at node 27175 (edge 28743): built, cut 20 m from the junction, junction config unchanged (6/0/0), slow piece reads back 3 m/s, other arms 22.2 m/s.
- In game: side-road cars slow down, no longer enter at speed. Problem: the limit also applied to cars leaving the junction onto the side road (both directions slowed).
- Change: only car lanes running into the junction are slowed now. Result: pending.
