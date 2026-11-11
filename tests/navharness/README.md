# Nav harness — Ember Routes 寻路测试工具（迷你僵毁测试版）

Headless test rig for the Ember Routes pathfinder / movement / haul
loop: real production Java classes (`EmberPathfinder`, `EmberNavGrid`,
`NavCost`, `ProbeMovement`) against a synthetic vanilla world, plus the
real `HaulAgent.lua` under lua5.4. No game client, no map files, no
sprite loading. Production code is untouched; everything here lives
under `tests/`.

## Run (one click)

```sh
tests/navharness/run.sh
```

Exit 0 = every section passes. Any FAIL (or a failed compile / missing
prerequisite) exits non-zero. Run one section only:

```sh
tests/navharness/run.sh motion        # world | pathfinder | motion | haul
```

### Prerequisites

- **JDK 25**: `$JDK_BIN/java`, or `$JAVA_HOME/bin/java`, or
  `~/workspace/jdk-25/bin/java` by default. `run.sh` refuses to run on
  any other major version.
- **Game jars, classpath-only**: `$GAME_ROOT/projectzomboid.jar` +
  `ZombieBuddy.jar` (default `~/workspace/game-root`). The jars are
  never copied into the repo.
- **lua5.4** on PATH (haul-loop section only).

### What `run.sh` does

1. Preflight: JDK 25, both jars, lua5.4.
2. Generates a `BuildInfo` stub into a scratch directory under `/tmp`
   (default `/tmp/navharness-build`, override with
   `$NAVHARNESS_BUILD_DIR`). The production tree references
   `emberroutes.probe.BuildInfo`, which `tools/build-probe.ps1`
   normally generates; the stub uses the **same template fields**:
   `VERSION` from `version.txt`, `PREFIX` derived from it,
   `GAME_SHA256` = sha256 of `projectzomboid.jar`. It is regenerated
   on every run, never written into `java/src` or `Contents/`, and
   never committed.
3. Compiles the **full production tree** (`java/src/main/java`) +
   generated stub + harness sources together with `javac`.
4. Runs `NavHarness` (`tests/java/emberroutes/probe/navharness/NavHarness.java`),
   which runs each section in its own subprocess (each builds its own
   headless world, so the global `IsoWorld.instance` stays clean
   between sections) and prints a `NAVHARNESS SUMMARY` table.

## Sections and acceptance

| section | runner | acceptance (measured) |
|---|---|---|
| `world` | `SyntheticWorldTest` | PASS: 8x8 room + gapped wall + doors + window + fences + glass + upper floor, getSquare round-trip + isWalkable all green |
| `pathfinder` | `PathfinderScenarios` | 6 PASS, 3 SKIP: open-room, wall-gap, sealed-wall, flag-wall, broken-glass-control, stairs-negative pass; broken-glass detour/cost, door-key, stairs traversal skip (unbuildable headless, see below) |
| `motion` | `MotionDriver` | A clean walk REACHED 1.93s; B root-motion-clip model PATH_ENDED 1.88s; C doorway-WAIT model REACHED 4.43s; D sealed wall BLOCKED |
| `haul` | `run-haul-loop.sh` (lua5.4) | `HAUL-LOOP PASS: 27 checks, 4 scenarios` (S1–S4) |

Each section is also runnable standalone once compiled (see the
javadoc header of each runner). The Java sections exit non-zero on any
missed expectation; the haul loop exits non-zero on any failed
assertion.

## Files

- `run.sh` — one-click entry (compile + run all, summary, exit code).
- `NavHarness.java` — entry main (in
  `tests/java/emberroutes/probe/navharness/`): section orchestration
  and summary. Not a scenario itself.
- `SyntheticWorld.java` / `SyntheticWorldTest.java` — the **one shared
  world builder** (item 1) and its acceptance test. Every scenario
  builds its world through it; the vendored Spike1c copies that used
  to live in `PathfinderScenarios` / `MotionDriver` were converged
  onto it in the harness-entry item.
- `PathfinderScenarios.java` — 6 PASS / 3 SKIP pathfinder scenarios.
- `MotionDriver.java` — 60fps motion driver, four model scenarios.
- `haul-loop-driver.lua` / `haul-loop-scenarios.lua` /
  `haul-loop-stubs.lua` / `run-haul-loop.sh` — haul-loop harness
  (item 4): real `HaulAgent.lua` under lua5.4, bridge motion model
  from the real Java measurement (`motion-trace-spike4.txt`).
- `haul-loop-trace-s<N>.txt` — full event traces from the last haul run.
- `motion-trace-spike4.txt` — the Java motion measurement the Lua
  bridge reproduces (scenario B: MOVING 1.9s, then PATH_ENDED).
- `VANILLA-REFERENCE-NOTES.md` — the vanilla-reference attempt log
  (item 6). Full detail lives there; the summary is below.

## Haul-loop verdict (S3/S4, measured)

- **PUT leg: multi-endpoint rotation CONFIRMED.** Walks go
  destA -> destB -> destC ~2s apart, then ~11s of 500ms
  STARTED/PAUSED flicker with no walking, repeating when the first
  15s backoff expires. This IS the "moves a bit every few seconds"
  rhythm. It works because `api.resume` gates only on
  `r.pathBackoff[r.source]` — PUT destination backoffs are invisible
  to it — while `nextStep` skips backed-off destinations and picks
  the next held line's destination.
- **TAKE leg: rotation FALSIFIED.** The job pins on `nextSource()`,
  the first UNCOLLECTED line's source, and the resume gate keys on
  that same `r.source`. sourceB/sourceC are never attempted while
  line 1 is uncollected; cadence stays 2s walk / 15s stop.

So the in-game "every few seconds moves a bit" is explained **if**
the NPC was carrying cargo with per-line destinations, and is **not**
explained if it was still collecting. **Which leg Kevin's NPC was on
is still open — it needs the in-game log to confirm** (the
`REPORT … FAILED movement=XXX` line and whether the NPC stalled near
a door). The harness cannot settle that; the game log can.

## Adding a new scenario

**Java (world / pathfinder / motion):**

1. Build the world with `SyntheticWorld.create()` — never copy the
   world-bootstrap code again. `room(8, 8)`, `wallSegment(...)`,
   `wall(...)`, `door(...)`, `window(...)`, `fence(...)`,
   `brokenGlass(...)`, `staircase(...)`, `upperFloor(...)` cover the
   geometry; `getSquare(x, y, z)` / `isWalkable(x, y, z)` read it back.
   Single chunk only: coordinates must stay in 0..7 (x, y); z = 1
   round-trips, higher z is untested.
2. Drive the real production classes (`EmberPathfinder.findPath`,
   `ProbeMovement`, `EmberNavGrid`, `NavCost`). Do not reimplement
   their logic in the test.
3. If a scenario cannot run headless, record it with an explicit
   skip + the verified cause (as `PathfinderScenarios` does) instead
   of faking it. A scenario that models engine behaviour it cannot
   get from the engine (e.g. MotionDriver B/C) must be labelled
   MODEL in its name and docs.
4. Add the runner to `NavHarness` (new section or extend an existing
   one) and record its expected numbers in the acceptance table above.

**Lua (haul loop):**

1. Add the scenario to `haul-loop-scenarios.lua` (assertions via the
   `check()` helper) and, if it needs new stubs, to
   `haul-loop-stubs.lua`. The bridge motion model stays scenario B
   (MOVING 1.9s, then PATH_ENDED) unless the Java measurement changes.
2. Re-run `run-haul-loop.sh`; it rewrites the
   `haul-loop-trace-s<N>.txt` files — commit the updated traces with
   the scenario.

## Known limits

### Vanilla reference: NOT connected (item 6, delivered)

There is **no vanilla reference runner**: the original `PolygonalMap2`
pathfinder has never returned one `SUCCEEDED` headless. The attempt
log is `VANILLA-REFERENCE-NOTES.md` (§ references below are to that
file). Summary, as delivered:

- **Route (a) — other `allocChunkIfNeeded` coords: disproved in 1
  attempt.** A fresh `IsoMetaGrid` is `minX=minY=1e7, width=height=0`,
  so `cells` is an empty array and `allocChunkIfNeeded` returns null
  at all 12 probed coords. This is a mathematical impossibility
  (the `cellX >= width` check fails for every coordinate), not a
  wrong-coordinate problem — no further coords can work.
- **Route (b) — configured `IsoMetaGrid`: 3 attempts, NPE bypassed,
  requests still FAILED.**
  - **B1**: public min/max fields set to 0 + reflection on the
    private `width`/`height` (= 1) makes `alloc(0,0)` non-null;
    `addChunkToWorld` + `updateThread` run past the original
    `Chunk.setData` NPE — but the request returns `FAILED`.
  - **B2**: dropped the manual `updateThread()` (the `PMThread`
    already runs it; real games only call `updateMain()`), added
    diagnostics: `squareToNode.size=0` — no path nodes generated.
    Both the trivial open-ground request and the wall-crossing
    request return `FAILED`. (`minLevel=32` / `levelData(0)=null`
    looked like missing data but is the normal +32 PM level offset.)
  - **B3**: verified the PM chunk data is correct (level 32, 8x8,
    `SOLID`/`SOLID_FLOOR` bits match the fake map) and found the real
    gap: **ground squares lack `IsoFlagType.canPathW` / `canPathN`**,
    so `SquareUpdateTask.getBits` never sets `BIT_CAN_PATH_W/N`,
    `addCanPathNodes` finds nothing to connect — and with no
    vehicles, `createVehicleClusters` returns early, so `graphs` is
    empty and `squareToNode` stays 0.
- **Next step (from the notes §5, not yet run):** give every ground
  square `canPathW`/`canPathN` flags when building the fake map and
  re-run the B3 flow. If the open-ground request turns `SUCCEEDED`,
  the vanilla reference is usable on open ground; if the
  wall-crossing request still `FAILED`, the missing piece is the
  no-vehicle visibility graph / A* node generation. Until then, all
  harness conclusions are **Ember-vs-Ember** (our pathfinder against
  our own synthetic world), not Ember-vs-vanilla.

### Doors / windows / broken glass: flag-level only

Real `IsoDoor` / `IsoWindow` objects cannot be built headless:
sprite lookup returns null (no tilesets loaded) and the constructors
throw `NullPointerException` / `ExceptionInInitializerError`
(`SandboxOptions` needs game init). Doors and windows here are
flag-level: a closed door is a `solid` square with a
`DoorWallN`/`DoorWallW` flag (verified to block `canStep`); an open
door is a plain walkable floor square recorded in `doors()`. A window
is a floor square with a `WindowN`/`WindowW` flag. `NavCost`
door/window edge costs return `CLEAR` for these, because they read
real objects via `getDoorTo` / `getWindowTo`.

Real broken glass (`IsoGridSquare.addBrokenGlass()`) cannot be built
headless either: `IsoBrokenGlass`'s constructor calls `Rand.Next`
and the game randomizer is null without game init.
`SyntheticWorld.brokenGlass` records the hazard in its own registry
(and still attempts the real call, so a fuller harness that
initialises `Rand` gets the real object for free).

### Stairs: flag-level only

Real stairs (`IsoGridSquare.AddStairs`) also fail headless
(`SandboxOptions` init). `SyntheticWorld.staircase` places both
floors and records the link; `EmberNavGrid` stair linkage reads real
stair objects, so it returns null for these. Positive stair
traversal is therefore SKIPped; only the negative assertions (no
stairs → no route between z=0 and z=1, all stair lookups null) run.

### Single chunk: world 0..7 only

One registered chunk covers exactly 8x8 tiles (world 0..7 in x and
y). Coordinate 8+ does not round-trip. Registering neighbour chunks
is a future extension.

### Kahlua in-JVM is blocked

The Lua half does **not** run under Kahlua in the JVM:
`KahluaLaborTest` reads `stdlib.lua` from a hardcoded Windows path
(`D:/Software/GameApp/steam/.../ProjectZomboid/stdlib.lua`) that does
not exist on this machine, so the Lua half runs only under lua5.4.
(The stale `tests/lua/haul-source-backoff-test.lua` was fixed
separately in item 5; it is not part of this entry.)

### Animation / per-frame following: out of scope

By Kevin's decision, animation and per-frame follower behaviour are
**not** in scope for this harness. Only overall logic and
functionality matter; the acceptance test is reproducing the
walk-stop / haul pause-resume bug.

## Open issues (do not silently fix in production code)

- **Diagonal crossing of a flagged column pays no fence cost
  (item 2 finding, pending re-check).** `EmberNavGrid.fenceEdgeKind`
  returns `NONE` for diagonal steps, so an A* route that crosses a
  `WallW`/`WallN`-flagged column diagonally does not pay
  `NavCost.TALL_FENCE_CLIMB` (120) and its waypoint is not mandatory
  — while an orthogonal crossing of the same column is `TALL` and
  pays 120. This is asserted explicitly in `PathfinderScenarios`
  (flag-wall) as real production behaviour, not assumed. Whether the
  diagonal should also pay (or be blocked) is a **待复核问题**:
  it needs a decision and a production-code change of its own.
  **Do not change production code from this harness.**
- **Vanilla reference gap** (above): ground squares need
  `canPathW`/`canPathN` before the next reference attempt.
- **In-game leg question** (above): which leg Kevin's NPC was on
  when it stuttered — needs the in-game log, not more harness work.
