# Health Gate C / B.5 acceptance

Baseline: `e8c982f`, `phase-3a-consolidation`. Gate C uses domain manifests and tool custody; DEC-003/DEC-004 are DEFERRED. No old-save migration, multiplayer, off-screen simulation or P4 domain acceptance.

## One new-save continuous script

Status: **UNVERIFIED (in-game)**. Linux host tests cannot establish native pathing, TimedActions, station effects, UI or disk save/reload correctness.

1. Create one new world with the matching Lua/Java build. Settle exactly one NPC using [Gate A](membership-runtime-acceptance.md); record stable NPC/settlement IDs, membership, bed and posting. Confirm ordinary work eligibility without changing Gate A policy.
2. Register named source boxes S1/S2 and destination boxes D1/D2 using [Gate B](single-player-health-gate-b.md). Use STORAGE roles accepted by production, matching filters and accessible positions. Record endpoint IDs. Put real inputs across S1/S2; place the real required tool in S1. Record every ItemID and initial container. Arrange destination capacity so all six planks fit across D1/D2 but neither holds the full output.
3. Submit one known saw-logs production intent, requested **4**, actual rounded batch target **6**, following [generic production](single-player-generic-production.md). Record order/job IDs. Repeating the same intent or changing demand alone must not create another order. Do not infer completion from a UI counter.
4. Observe the NPC walk to each source, take the original inputs, use the native craft action (and required station if the selected recipe requires one), and deliver each real output to D1/D2. Record Asset → Target Allocation List and per-ItemID actual/allocated/transferred/remaining/state. Requested 4 and target 6 stay fixed. Fill destinations before remaining delivery: the chain must pause with a visible capacity reason and remaining quantity, retain cargo, then resume after capacity is restored, without crafting again.
5. Observe the original tool returned, then borrowed by a field job, used, returned, and re-borrowed by the next job. Record tool ID, holder, custody and unfinished return job. Save normally while held; exit/reload. Repeat while return is unfinished. Each reload must find the same tool and obligation, resume or visibly pause, never create a replacement or permit another claimant.
6. Independently trigger farming, existing cooking and crafting demand/restock conditions. For each, record domain/intent/cycle, one order, settlement evidence and no duplicate from demand-only changes. Check both creation orders against an overlapping public delivery intent: first-created-wins, with visible suppression. No new cooking/P4 feature is part of this check.
7. Run production, field work and delivery sequentially under the same NPC controller. At each boundary reconcile real inputs consumed once, outputs transferred once, exclusive tool ownership and NPC-carried stock excluded from source stock. Monitor requested/actual/allocated/settled/remaining must agree with physical counts; settled is a transfer fact, not additional stock.
8. Normally save, exit and reload after partial delivery and after completion. Record save/build/world IDs and logs. Confirm one resumable chain or a clean pause with a visible reason; no repeated native crafting, duplicate ItemID, lost original, stuck owner or duplicate order. Repeat resume commands to check idempotence.

## Count sheet and outcome

For each checkpoint record: ItemID, fullType, S1/S2 count, NPC count, D1/D2 count, consumed evidence, target allocation, transferred/settled fact, remaining, holder/job and reason. One physical original occupies exactly one location; settled history is never added to physical inventory. Retain logs and save files for failures.

| Scope | Result | Evidence / limitation |
|---|---|---|
| Host syntax / directed tests | PASS within the scopes below; harness gaps remain | 16 Lua syntax checks; 22 runnable directed suites passed; one stale API failure and four blocked suites |
| New-save native production / split delivery | UNVERIFIED | Game unavailable in Linux environment |
| Native field/tool return and held/unfinished-return reload | UNVERIFIED | Host persistence checks cannot prove disk/native behavior |
| Independent domains / combined B.5 / monitor UI | UNVERIFIED | Requires the continuous in-game run above |
| Normal exit / disk reload / no loss or duplication | UNVERIFIED | No in-game acceptance run |
| Performance | UNVERIFIED | No measurements; no performance claim |

## Implementation / closure evidence

Phase 0 created the script above before any logic change. Frozen judgment is the user-provided `health-gateC-design-judgment.md`; implementation follows the approved stage scope, without claiming that the online requirements were resynchronized.

- **Phase 1:** `shared/EmberRoutesProbe/ProductionAllocation.lua` stores `outputAllocation={format=1,assets={...}}` on the production Job payload. Each indivisible native ItemID has actual=1, allocated=0/1, transferred=0/1, remaining=1−transferred, state and a target list. Different ItemIDs may target different boxes; no ItemID is divided or recreated. Completed earlier native batches retain their transfer rows until that production node ends. Requested and rounded target remain the existing separate fields; produced counts real native effects, allocated counts assigned originals, settled counts destination transfer facts, remaining is target−settled. Counts are not inventory.
- **Creation/claim:** existing `Production.lua:354` preparation / `ProductionJobs.create` and `replace` retain the unique Job/Labor claims; `ProductionActions.lua:174` captures native output ItemIDs. `ProductionRouting.lua:6–47` calls unchanged CraftSupply routing for each unallocated original with batch-local capacity accounting. Its transient weight map is neither stock nor another claims authority. `ProductionSupply` was unchanged; the cross-target test uses its actual multi-source matching and rejects unrelated NPC-carried materials as fresh source stock.
- **Normal release:** `Production.lua:340` settles the selected ItemID only from the existing native transfer adapter's verified destination callback (`ProductionActions.lua:47–56`). Repeated native perform is fenced by `attempted`. `CraftRecord` rejects contradictions between output flags, ItemID manifest and delivered count. Destination selection persists before dispatch; full or invalid destinations pause using existing reasons rather than shrinking the target, rerouting assigned originals silently or repeating craft effects. Monitor service exports totals and the ItemID allocation snapshot; cards prepare cached bilingual totals and up to 64 ItemID destination/remaining lines outside rendering.
- **Interruption/reload:** `Production.pause` at `Production.lua:125` retains originals and UNKNOWN results; `ProductionJobs.prepareRecovery` retains the Job, pauses with LOAD_RECOVERY and does not replay an unknown craft. Allocation rows survive the same JobStore payload copy/save path. New host tests deep-copy scalar manifests and reconcile pending originals, not disk files.
- **Phase 2:** existing PublicWork stock cycles independently observe crafting inventory and cooking stock. Changed minimum/batch retains the active intent/cycle. Missing active Order now reports TASK_RECORD_MISSING without clearing the cycle or generating another. Existing field farming demand remains a plant condition in the same public directory, rather than a second product-order type: `FieldDiscovery.lua:118` replaces stale observed tile conditions and `:215` revalidates water/harvest/clear before claim. The test covers changing water demand while the offer is claimed and later harvest. No duplicate public-order entry in FieldWork was established, so no ownership extraction, FieldWork rewrite or new scheduler was performed.
- **Minimal Gate B wiring:** `PublicWork.lua:174–220` replaces the single-destination inference with membership in actual output destinations / persisted target allocation lists. This is needed for first-created-wins to recognize D2 in a split batch. No intent identity, warehouse or box-delivery executor was changed; Gate A membership/beds/posting files were untouched.
- **Phase 3:** `ToolReturnService.lua:138` persists the exact return intent; `:183` resumes a pending held original under that same job ID, while UNKNOWN or already-arrived returns remain observation-only. `:223` preserves the unfinished intent on SAVE. `:220` completes custody only after arrival and actual stop. Missing destination rejects recovery with an explicit reason and preserves the intent. `FieldSupplies.releaseUncollected` observes all originals before cleanup: verified warehouse reservations release, held tools retain HELD custody, unknown originals retain responsibility and enter diagnostic reconciliation through `FieldSession.lua:96`. The PREPARE resume path reconciles already-picked tools to HELD. Existing Field retirement clears only the settled Job association; subsequent jobs re-borrow the same original.
- **Concrete fixes, not convergence:** the stale farming targets, absent-cycle false settlement, unconditional partial-pickup custody release, and unfinished-return SAVE cancellation / recovery-only cancellation were fixed in their own domain paths. No double-submit/consume/settle was observed in runnable directed Lua checks. **Java commit-path guardrail remains UNVERIFIED** because Java/JDK is unavailable; Lua host results cannot establish Java parity. DEC-003/DEC-004 remain DEFERRED.
- **Phase 4:** reviewed common ownership boundaries: production/field/delivery share TaskRuntime and LaborStore; carried assets remain claimed; delivery overlap uses actual selected destinations. Directed production allocation, field/tool, public overlap and save suites pass individually. A full combined executing production→field→delivery host run is **NOT RUN**, because baseline native-production fixtures are missing. No claim that separate suites establish a continuous native chain.
- **Phase 5 / B.5 outcome:** **OPEN / UNVERIFIED**. The new-save run, native crafting/transfer/pathing, all domain settlement effects together, monitor interaction and normal disk exit/reload must still be run in-game. No performance measurements, packaging, migration or multiplayer checks were performed.

## Directed verification results

Commands use repo-only paths and Lua 5.4 compatibility for the existing fixtures:

```sh
export LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;'
lua5.4 -e 'unpack=table.unpack' tests/lua/<name>-test.lua
luac -p <each changed or new Lua file>
git diff --check
```

| tests/lua/ suite | Final result | Scope / reason |
|---|---|---|
| gate-c-cross-target | PASS 14 | Real ProductionSupply, CraftSupply/ranking, allocation, record contract and transfer adapter; physical native effect mocked; partial capacity, exact ItemIDs, duplicate notification, scalar reload |
| gate-c-demand-restock | PASS 18 (+ reused public-work 85) | Actual stock cycle entry and farming discovery/directory, independent triggers, demand changes, both creation orders, D2 overlap, absent Order; domain effects mocked |
| gate-c-tool-reload | PASS 20 | Actual custody/return/stop adapter; held, unfinished return, arrived-before-settlement reload; mixed pickup stop; native/body/disk mocked |
| production-chain | PASS 18 | Pure production dependency planning |
| production-carry | PASS 26 | Batch carry rules; native attributes mocked |
| crafting-provider | PASS | Provider boundary assertions; fixture prints no count |
| public-work | PASS 85 | Existing dispatch, priority, claim, recovery, bidirectional overlap |
| stock-rules | PASS 44 | Existing stock evaluation |
| stock-service | PASS 18 | Existing stock service, early settlement and overlap |
| field-demand | PASS 15 | Existing independent cleaning observations |
| field-work | PASS 36 | Existing lifecycle and resource boundaries |
| field-workflow | PASS 20 | Field progression and settlement |
| field-tool-supply | PASS 30 | Existing real supply/custody seam; native effects mocked |
| field-continuous-batch | PASS 55 | Tool retention / cross-job reuse |
| field-cargo-phase | PASS 4 | Cargo route/projection boundary |
| tool-custody | PASS 23 | Claims and reload authorization |
| tool-return | PASS 102 | Return lifecycle/recovery/stop and directory release |
| task-save-runtime | PASS 71 | Unified save barrier; disk/native save mocked |
| health-gate-b-boxtobox | PASS 37 | Existing Gate B regression for minimal PublicWork wiring |
| order-monitor-service | PASS 36 | Projection / command seam |
| order-monitor-view | PASS 19 | Presentation facts; native UI not run |
| labor-capacity-commit | PASS 16 (Lua only) | Actual authority rollback, CAS/post-CAS isolation; no Java execution |
| craft-record | FAIL (stale test API) | Baseline suite calls removed Record.valid / legacy formats at line 27. ProductionAllocation's new full format-4 contract checks pass in cross-target suite. Production guard not relaxed; legacy suite not rewritten. |
| production-three-batch | NOT RUN, attempted | Missing baseline tests/lua/craft-probe-test.lua; stops before assertions |
| task-production-runtime | NOT RUN, attempted | Same missing craft-probe-test.lua; full production body/craft chain not established |
| crafting-chain-width | NOT RUN, attempted | Baseline settlement-tabs dependency hardcodes unavailable Windows ISTickBox.lua |
| cooking-public | NOT RUN, attempted | Transitive baseline dependency tests/lua/work-test.lua missing; full native cooking settlement not established |
| Java commit/Kahlua | NOT RUN | java/javac unavailable; no Java path pass inferred |

Initial tool-return harness failed on removed reset / markNpcCustodiesDead APIs. The test now uses reconcile (no destructive reset) and the existing settleNpcDeath contract, whose production implementation already releases claims without moving originals. This is test call/expectation adaptation to the baseline contract, not a new death behavior or removal of failure cases. After adaptation all 102 assertions, including the later reload cases, ran. New-test fixture mistakes were corrected to supply full storage filter format / actor / settled domain records; production guards were not weakened.

Static results: **all 16 changed/new Lua files pass luac -p**; **git diff --check PASS**; both translation JSON files parse, **1810 matching keys**. Official doclink tool is unavailable in this checkout; local links added by this change are checked separately. Original test outputs are temporary `/tmp/gate-c-host-initial.log`, `/tmp/gate-c-host-final.log`, `/tmp/gate-c-host-changed.log`; this table records the durable outcomes. Working tree intentionally remains uncommitted; no push or reset.
