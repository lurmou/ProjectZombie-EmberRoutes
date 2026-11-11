#!/usr/bin/env python3
"""Static gate to catch undeclared module and global accesses in production Lua.

Scans all production Lua files under Contents/mods/EmberRoutesProbe/42/media/lua
for table/module function calls (e.g. `Layout.axis()`, `Theme.enable()`) where
the target is neither:
1. Declared as a `local` variable or local function in scope.
2. A function parameter or loop variable.
3. A known standard Lua library (math, string, table, os, etc.).
4. A known Project Zomboid native global class/function (ISPanel, ISButton, UIFont, getText, etc.).
5. An explicitly exported global class/module for EmberRoutes (e.g. EmberRoutesPersonnelPage).

Any undeclared module access fails with exit code 1 to block PRs and builds.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA_ROOT = ROOT / 'Contents/mods/EmberRoutesProbe/42/media/lua'

STANDARD_GLOBALS = {
    # Standard Lua 5.1 globals
    'assert', 'error', 'ipairs', 'pairs', 'next', 'pcall', 'xpcall', 'select',
    'tonumber', 'tostring', 'type', 'unpack', 'print', '_G', 'setmetatable', 'getmetatable',
    'rawget', 'rawset', 'rawequal', 'require', 'collectgarbage', 'dofile', 'loadfile', 'loadstring',
    'math', 'string', 'table', 'os', 'coroutine', 'debug',
    # Project Zomboid Java & Lua classes & helpers
    'ISPanel', 'ISButton', 'ISCollapsableWindow', 'ISTextEntryBox', 'ISUIElement',
    'ISScrollingListBox', 'ISComboBox', 'ISModalDialog', 'ISContextMenu', 'ISBaseTimedAction',
    'Keyboard', 'Joypad', 'getJoypadData', 'UIFont', 'getText', 'getTextOrNull',
    'getCore', 'getTextManager', 'getTexture', 'getCell', 'getTimestampMs', 'isMouseButtonDown',
    'SandboxVars', 'IsoPlayer', 'Events', 'luautils', 'ISTimedActionQueue', 'ZomboidGlobals',
    'BaseVehicle', 'VehiclePart', 'ItemPickerJava', 'ItemContainer', 'ArrayList', 'Translator',
    'FluidContainer', 'ISFluidUtil', 'HandcraftLogic', 'ISFarmingMenu', 'ISBaseIcon', 'ISSearchManager',
    'AdjacentFreeTileFinder', 'Perks', 'IsoUtils', 'ISHealthPanel', 'ModData', 'DebugLog',
    'CharacterProfessionDefinition', 'CharacterTraitDefinition', 'HaloTextHelper', 'UIManager',
    'IsoRegions', 'IsoWorld', 'MapCollisionData', 'PZArray', 'InventoryItemFactory',
    'PerkFactory', 'ISDebugUtils', 'DebugContextMenu', 'ISFitnessAction', 'FitnessState',
    'RainManager', 'IdleState',
    # EmberRoutes explicitly exported globals
    'EmberRoutesPersonnelPage', 'EmberRoutesWarehousePage', 'EmberRoutesPublicOrderDialog',
    'EmberRoutesLayoutHost', 'PublicWork', 'EmberRoutesSettlementDashboard', 'EmberRoutesProbeJava',
    'EmberRoutesStorageFilterPanel', 'EmberRoutesSquadHUD', 'EmberRoutesSquadUI',
    'EmberRoutesActivityPage', 'EmberRoutesDefensePage', 'EmberRoutesCraftingPage',
    'EmberRoutesSettlementOverviewPage', 'EmberRoutesWorkPolicyPage', 'EmberRoutesDemandPage',
    'EmberRoutesOrderDetailsDialog', 'EmberRoutesBatchPaintingSelector', 'EmberRoutesContainerInspectorDialog',
    'EmberRoutesLifeZoneRules', 'EmberRoutesPersonnelDossierDrawer', 'EmberRoutesDeliveryCartDrawer',
    'EmberRoutesAvatar3DView', 'EmberRoutesSkeletonView', 'EmberRoutesOrderMonitorDetailsDialog',
    'EmberRoutesSettlementSelector', 'EmberRoutesWorkPoliciesDialog', 'EmberRoutesPresetSelectModal',
}

# Sub-methods or local module references within mixin functions (e.g. `Page`, `Host`)
MIXIN_TARGETS = {'Page', 'Host'}


def check_file(path: Path):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    file_locals = set()
    for line in lines:
        clean = re.sub(r'--.*$', '', line)
        for m in re.finditer(r'\blocal\s+([a-zA-Z0-9_,\s]+)(?:=|[;\n]|$)', clean):
            for v in m.group(1).split(','):
                v = v.strip()
                if v and re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', v):
                    file_locals.add(v)
        for m in re.finditer(r'\blocal\s+function\s+([a-zA-Z_][a-zA-Z0-9_]*)', clean):
            file_locals.add(m.group(1))
        for m in re.finditer(r'\bfunction\s+(?:[a-zA-Z0-9_]+[:.])?([a-zA-Z0-9_]+)\s*\(([^)]*)\)', clean):
            for p in m.group(2).split(','):
                p = p.strip()
                if p and re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', p):
                    file_locals.add(p)
        for m in re.finditer(r'\bfor\s+([a-zA-Z0-9_,\s]+)\s+in\b', clean):
            for p in m.group(1).split(','):
                p = p.strip()
                if p and re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', p):
                    file_locals.add(p)

    errors = []
    for i, line in enumerate(lines, 1):
        clean = re.sub(r'--.*$', '', line)
        clean = re.sub(r'".*?"', '""', clean)
        clean = re.sub(r"'.*?'", "''", clean)
        # Match Module.function(...)
        for m in re.finditer(r'(?<![.\w])([A-Z][a-zA-Z0-9_]*)\.([a-zA-Z0-9_]+)\s*\(', clean):
            mod = m.group(1)
            func = m.group(2)
            if mod in MIXIN_TARGETS:
                continue
            if mod not in file_locals and mod not in STANDARD_GLOBALS:
                errors.append((i, f"undeclared module/global `{mod}.{func}()`"))

    return errors


def main():
    total_errors = 0
    scanned_files = 0
    for root_dir, _, filenames in os.walk(LUA_ROOT):
        for fn in filenames:
            if fn.endswith('.lua'):
                path = Path(root_dir) / fn
                scanned_files += 1
                errs = check_file(path)
                if errs:
                    rel = path.relative_to(ROOT)
                    for line_num, desc in errs:
                        print(f"ERROR: {rel}:{line_num}: {desc}")
                        total_errors += 1

    if total_errors > 0:
        print(f"\nFAILED: Found {total_errors} undeclared module/global access(es) across {scanned_files} files.")
        sys.exit(1)
    else:
        print(f"SUCCESS: All {scanned_files} production Lua files passed undeclared module/global checks.")
        sys.exit(0)


if __name__ == '__main__':
    main()
