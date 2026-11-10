"""Enqueue-path inventory for the TaskController single point (P0 pilot 14/15).

The callback-first ratchet in tools/check-architecture.py counts only
UNANNOTATED direct calls, so an annotated new ISTimedActionQueue.add would
pass it. This test pins the full inventory -- annotated sites included --
and fails on any new raw enqueue path. It also pins the admission single
point (controller:request has exactly one production caller) and asserts no
code waits for a TimedAction interrupt callback (PZ has none: stop
completion is polled via observeStop, once per TaskController step).
"""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
LUA_ROOT = ROOT / 'Contents/mods/EmberRoutesProbe/42/media/lua'
JAVA_ROOT = ROOT / 'java/src/main/java'

spec = importlib.util.spec_from_file_location(
    'architecture_gate', ROOT / 'tools/check-architecture.py')
arch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arch)

# Lua-root relative path -> one identifying substring per raw
# ISTimedActionQueue.add site, in file order. Line numbers are deliberately
# NOT pinned, so unrelated edits above a site do not fail this test; a new
# site fails it because the file's site list no longer matches.
ENQUEUE_PATHS = {
    # Controlled single point: body.add funnel; every managed-NPC action
    # (14 body.add call sites) lands here and nowhere else.
    'client/EmberRoutesProbe/Runtime/TaskController.lua': [
        'ISTimedActionQueue.add(action) return true',
    ],
    # Legacy fallback: only when no TaskController body exists (uncontrolled
    # probe path); managed-NPC actions take body.add on the same line.
    'client/EmberRoutesProbe/Runtime/Actions.lua': [
        "else ISTimedActionQueue.add(action) end",
    ],
    # Player doctor walks to the NPC to open the health panel; the character
    # is the player, not a managed NPC, so no ticket/body exists.
    'client/EmberRoutesProbe/SelfCare/NpcMedical.lua': [
        'ISTimedActionQueue.add(ISOpenNpcMedicalAction:new(doctor, npc))',
    ],
    # Real-player stash routine: walk + transfer for the player character.
    'shared/EmberRoutesProbe/Warehouse/PlayerStashRoutine.lua': [
        'ISTimedActionQueue.add(ISWalkToTimedAction:new(player, freeSquare))',
        'ISTimedActionQueue.add(ISInventoryTransferAction:new(player, item, sourceContainer, targetContainer))',
    ],
}
# The one site that IS the funnel; every other site must carry a
# `-- callback-first:` reason (it has no TaskController body to go through).
SINGLE_POINT = 'client/EmberRoutesProbe/Runtime/TaskController.lua'

# Patterns that would mean code is waiting on a TimedAction interrupt
# callback. PZ has no such callback: ISBaseTimedAction.stop/perform are
# engine-invoked overrides, and stop completion is polled via observeStop.
# `interruptWaitToStart` (LeisurePosture) is a vanilla engine call that
# interrupts a wait, not a callback wait, so it is not listed here.
INTERRUPT_CALLBACK_PATTERNS = (
    'onInterrupt', 'interruptCallback', 'waitForInterrupt', 'awaitInterrupt',
)


def production_lua_files():
    for area in ('client', 'shared', 'server'):
        base = LUA_ROOT / area
        if base.is_dir():
            yield from sorted(base.rglob('*.lua'))


def raw_add_sites():
    """{relpath: [(line, line_text)]} for every raw queue add in production Lua.

    Token-based (arch.direct_calls), so adds inside comments or strings do
    not count; test doubles under tests/ are out of scope (production root
    only).
    """
    sites = {}
    for path in production_lua_files():
        source = path.read_text(encoding='utf-8-sig')
        lines = source.splitlines()
        found = [(line, lines[line - 1].strip())
                 for kind, line in arch.direct_calls(arch.tokens(source))
                 if kind == 'queue']
        if found:
            sites[path.relative_to(LUA_ROOT).as_posix()] = found
    return sites


class TaskControllerSinglePointTests(unittest.TestCase):
    def test_raw_add_inventory_is_exact(self):
        sites = raw_add_sites()
        self.assertEqual(
            set(sites), set(ENQUEUE_PATHS),
            'raw ISTimedActionQueue.add sites changed: a new enqueue path '
            'must go through TaskController body.add, or be added to this '
            'inventory with a callback-first reason')
        for rel, expected in ENQUEUE_PATHS.items():
            actual = sites[rel]
            self.assertEqual(
                len(actual), len(expected),
                f'{rel}: {len(actual)} raw add(s), inventory lists {len(expected)}')
            for (line, text), marker in zip(actual, expected):
                self.assertIn(marker, text,
                              f'{rel}:{line}: site no longer matches its '
                              f'inventoried role ({marker!r} not in {text!r})')

    def test_non_single_point_sites_are_annotated(self):
        sites = raw_add_sites()
        for rel, found in sites.items():
            path = LUA_ROOT / rel
            source = path.read_text(encoding='utf-8-sig')
            comments = list(arch.line_comments(source))
            lines = source.splitlines()
            for line, _text in found:
                if rel == SINGLE_POINT:
                    self.assertFalse(
                        arch._annotated(comments, lines, line),
                        f'{rel}:{line}: the controlled single point is the '
                        'funnel, not an exception -- it stays unannotated in '
                        'DIRECT_CALL_BASELINE as (0, 1)')
                else:
                    self.assertTrue(
                        arch._annotated(comments, lines, line),
                        f'{rel}:{line}: exception enqueue path without a '
                        '`-- callback-first: <reason>` annotation')

    def test_ratchet_sees_only_the_single_point(self):
        counts = arch.count_direct_calls(LUA_ROOT)
        queue = {rel: q for rel, (_p, q) in counts.items() if q}
        self.assertEqual(queue, {SINGLE_POINT: 1},
                         'unannotated queue adds outside the single point; '
                         'lower DIRECT_CALL_BASELINE or annotate, and update '
                         'the inventory above')

    def test_admission_single_point(self):
        callers = []
        for path in production_lua_files():
            source = path.read_text(encoding='utf-8-sig')
            for i, text in enumerate(source.splitlines(), 1):
                if 'controller:request(' in text:
                    callers.append(
                        f'{path.relative_to(LUA_ROOT).as_posix()}:{i}')
        self.assertEqual(len(callers), 1,
                         'controller:request must have exactly one production '
                         'caller (TaskRuntime advance); all business admission '
                         'goes through Runtime:submit')
        self.assertTrue(callers[0].startswith(
            'client/EmberRoutesProbe/Runtime/TaskRuntime.lua:'),
            f'unexpected controller:request caller: {callers[0]}')
        definitions = []
        for path in production_lua_files():
            source = path.read_text(encoding='utf-8-sig')
            for i, text in enumerate(source.splitlines(), 1):
                if 'function body.add(action)' in text:
                    definitions.append(
                        f'{path.relative_to(LUA_ROOT).as_posix()}:{i}')
        self.assertEqual(len(definitions), 1)
        self.assertTrue(definitions[0].startswith(
            'client/EmberRoutesProbe/Runtime/TaskController.lua:'))

    def test_no_code_waits_for_an_interrupt_callback(self):
        hits = []
        for base in (LUA_ROOT, JAVA_ROOT):
            for path in sorted(base.rglob('*.lua' if base == LUA_ROOT else '*.java')):
                text = path.read_text(encoding='utf-8-sig', errors='replace')
                for pattern in INTERRUPT_CALLBACK_PATTERNS:
                    if pattern in text:
                        hits.append(f'{path.relative_to(ROOT).as_posix()}: {pattern}')
        self.assertEqual(hits, [],
                         'code references a TimedAction interrupt callback; '
                         'PZ has none -- poll observeStop / hasAction per '
                         'tick instead of waiting')

    def test_walk_adj_is_player_only(self):
        # luautils.walkAdj enqueues a vanilla walk via the engine; its only
        # production use is the player doctor in NpcMedical (same player
        # path as the raw add inventoried above, not a managed-NPC path).
        hits = []
        for path in production_lua_files():
            if 'luautils.walkAdj' in path.read_text(encoding='utf-8-sig'):
                hits.append(path.relative_to(LUA_ROOT).as_posix())
        self.assertEqual(
            hits, ['client/EmberRoutesProbe/SelfCare/NpcMedical.lua'],
            'luautils.walkAdj appeared outside the player-doctor path; a '
            'managed-NPC walk must go through TaskController body.add')


if __name__ == '__main__':
    unittest.main()
