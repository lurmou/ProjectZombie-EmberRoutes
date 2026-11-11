# Haul-loop harness (navharness, item 4)

Headless reproduction of the in-game NPC walk-stop / haul pause-resume
loop, using the **real** `HaulAgent.lua` under lua5.4 plus a scripted
bridge whose motion model comes from a **real Java measurement**.

## Bridge: Java motion trace -> Lua

`motion-trace-spike4.txt` is the output of Spike4: the real
`EmberPathfinder` + `ProbeMovement` on the synthetic world, headless.
Measured on this machine (JDK 25, game jars on the classpath):

| scenario | result |
|---|---|
| A clean walk through doorway gap | REACHED after 1.93s |
| B path ends 0.5 short (root-motion clip model) | **PATH_ENDED after 1.88s** |
| C doorway WAIT 2.5s mid-path (model) then clear | REACHED after 4.43s |
| D sealed wall | moveTo refuses (BLOCKED) |

The Lua bridge in `haul-loop-stubs.lua` reproduces **scenario B**:
`command("move")` -> MOVING for 19 ticks of 100ms (1.9s), then
PATH_ENDED, on every attempt. The 100ms tick quantisation adds ~0.1s
of detection lag versus the 1.88s Java measurement; walks are
therefore reported as ~2.0s.

Kahlua-in-JVM is deliberately NOT used: `KahluaLaborTest` reads
`stdlib.lua` from a hardcoded Windows path that does not exist on
this machine, so the Lua half runs only under lua5.4.

## Files

- `haul-loop-stubs.lua` — complete stub set (Store incl.
  `settleHaulLines`, `routeRevision=0`, `Manifest.line`,
  `Routing.new` -> nil, per-id items). Self-contained; does not reuse
  the stale stubs from `tests/lua/haul-source-backoff-test.lua`.
- `haul-loop-driver.lua` — reusable driver: tick every 100ms, resume
  attempt every 500ms while idle, full event trace + per-walk table.
- `haul-loop-scenarios.lua` — the four scenarios + assertions.
- `run-haul-loop.sh` — runs all scenarios under lua5.4.
- `motion-trace-spike4.txt` — the Java measurement above.
- `haul-loop-trace-s<N>.txt` — full event traces from the last run.

## Scenarios

| id | leg | manifest | expected |
|---|---|---|---|
| S1 take-single | TAKE | 1 UNCOLLECTED line | walk ~2s, stop 15s (baseline) |
| S2 put-single | PUT | 1 CARRIED line | STARTED/PAUSED flicker every 500ms, walk once per ~15s (baseline) |
| S3 put-multi (**key**) | PUT | 3 CARRIED lines, destA/destB/destC | rotation burst, see verdict |
| S4 take-multi (control) | TAKE | 3 UNCOLLECTED lines, sourceA/B/C | pins on sourceA, no rotation |

## Verdict (S3/S4, measured)

- **PUT leg: rotation CONFIRMED.** Walks go destA -> destB -> destC
  ~2s apart, then ~11s of 500ms STARTED/PAUSED flicker with no
  walking, repeating when the first 15s backoff expires. This IS the
  "moves a bit every few seconds" rhythm. It works because
  `api.resume` gates only on `r.pathBackoff[r.source]` -- PUT
  destination backoffs are invisible to it -- while `nextStep`
  skips backed-off destinations and picks the next held line's
  destination.
- **TAKE leg: rotation FALSIFIED.** The job pins on `nextSource()`,
  the first UNCOLLECTED line's source, and the resume gate keys on
  that same `r.source`. sourceB/sourceC are never attempted while
  line 1 is uncollected; cadence stays 2s walk / 15s stop.

So the in-game "every few seconds moves a bit" is explained **if**
the NPC was carrying cargo with per-line destinations, and is **not**
explained if it was still collecting. Which leg Kevin's NPC was on
is the remaining open question for the in-game report, not for this
harness.

## Run

```sh
tests/navharness/run-haul-loop.sh
```

Exit 0 = all scenarios pass. Production code is untouched; only
`tests/navharness/` files are added by this item.
