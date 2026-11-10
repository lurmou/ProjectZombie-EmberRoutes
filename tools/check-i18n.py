#!/usr/bin/env python3
"""
EmberRoutes Translation (I18N) Integrity Validator.
Enforces:
1. Exact key symmetry between CN and EN translation files (IG_UI.json, Sandbox.json).
2. All literal getText('IGUI_EmberRoutesProbe_...') calls exist in both dictionaries.
3. All localized helper calls (e.g. text('key')) resolve to existing keys.
4. All dynamically assembled keys from registered domains exist in both dictionaries:
   - PublicWork categories: IGUI_EmberRoutesProbe_Public_<cat>
   - Personnel column categories: IGUI_EmberRoutesProbe_Personnel_<cat>
   - Settlement dashboard tabs: IGUI_EmberRoutesProbe_Settlement_tab_<tab>
   - WorkPolicy titleKeys
   - Membership reason/action codes: IGUI_EmberRoutesProbe_Membership_<code>
5. No bare % in any translation value (PZ 42.20.2: a literal % must be written
   %%; a bare % is only kept by a temporary engine workaround that will be
   removed). %% and %1..%9 placeholders are fine. Lua string.format verbs
   (%d/%s/%.1f) are only allowed for the keys in FORMAT_VERB_ALLOWLIST below:
   those values are fetched with getTextOrNull (no args) and formatted in Lua.
"""

import sys
import os
import json
import re
from pathlib import Path

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

# Keys whose translation values intentionally contain Lua string.format verbs
# (%d/%s/%.1f). Each is fetched with getText/getTextOrNull (no args) and
# formatted in Lua -- the engine returns the raw string untouched on that path
# (verified against the installed Translator: getText with no args returns the
# format string verbatim for Lua string.format). Do NOT add a key here to
# silence the gate: prefer getText %1..%9 args for new strings, and migrate
# these keys to %1..%9 args instead (see TranslatorFormatTest, which already
# forbids %d/%s for the Public/Monitor/Stock/Crafting scopes).
# Value: the Lua call site doing the string.format.
FORMAT_VERB_ALLOWLIST = {
    'IGUI_EmberRoutesProbe_NpcDebug_allPerksFive': 'Integration/NpcDebugMenu.lua:299',
    'IGUI_EmberRoutesProbe_NpcDebug_allPerksMax': 'Integration/NpcDebugMenu.lua:298',
    'IGUI_EmberRoutesProbe_NpcDebug_allPerksZero': 'Integration/NpcDebugMenu.lua:300',
    'IGUI_EmberRoutesProbe_Order_cancelConfirm': 'no Lua call site (dead key, kept for parity)',
    'IGUI_EmberRoutesProbe_Public_conversionFull': 'UI/PublicOrderDialog.lua:405',
    'IGUI_EmberRoutesProbe_Public_conversionLine1': 'UI/PublicOrderDialog.lua:407',
    'IGUI_EmberRoutesProbe_Public_conversionLine2': 'UI/PublicOrderDialog.lua:409',
    'IGUI_EmberRoutesProbe_Settlement_containerInspectorTotal': 'UI/ContainerInspectorDialog.lua:60',
    'IGUI_EmberRoutesProbe_Settlement_summaryDetailFormat': 'no Lua call site (dead key, kept for parity)',
    'IGUI_EmberRoutesProbe_Stock_btn_create_confirm_with_target': 'UI/StockRules.lua:539',
}

# A Lua string.format verb: % + optional flags/width/precision + conversion.
# Evaluated only when the char after % is not '%' and not a PZ placeholder
# digit, so "%2x%3" (zoneOption/dragAdd dimensions) tokenizes as placeholder
# %2 + literal "x" + placeholder %3, not as a verb. Width-qualified verbs
# starting with a placeholder digit (%5d) are likewise read as placeholder +
# literal -- rewrite those as %d / %.nf or a %N argument instead.
FORMAT_VERB_RE = re.compile(r'%[#0\- +]*\d*(?:\.\d+)?[diouxXeEfgGcsq]')

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, '..'))
    mod_root = os.path.join(project_root, 'Contents', 'mods', 'EmberRoutesProbe', '42', 'media')
    trans_root = os.path.join(mod_root, 'lua', 'shared', 'Translate')

    errors = []

    # 1. Symmetry check for all translation files
    for filename in ['IG_UI.json', 'Sandbox.json', 'UI.json']:
        cn_file = os.path.join(trans_root, 'CN', filename)
        en_file = os.path.join(trans_root, 'EN', filename)

        if not os.path.exists(cn_file):
            errors.append(f"Missing CN translation file: {cn_file}")
            continue
        if not os.path.exists(en_file):
            errors.append(f"Missing EN translation file: {en_file}")
            continue

        cn_data = load_json(cn_file)
        en_data = load_json(en_file)

        missing_in_en = sorted(set(cn_data.keys()) - set(en_data.keys()))
        missing_in_cn = sorted(set(en_data.keys()) - set(cn_data.keys()))

        if missing_in_en:
            errors.append(f"[{filename}] Keys present in CN but missing in EN ({len(missing_in_en)}): {missing_in_en[:10]}")
        if missing_in_cn:
            errors.append(f"[{filename}] Keys present in EN but missing in CN ({len(missing_in_cn)}): {missing_in_cn[:10]}")

    # Use IG_UI.json for mod UI keys
    ig_ui_cn = load_json(os.path.join(trans_root, 'CN', 'IG_UI.json'))
    lua_root = os.path.join(mod_root, 'lua')

    # 2. Check all literal getText calls in Lua (strictly static string literals)
    # Ignore anything followed by '..' on the same line
    call_regex = re.compile(r'getText(?:OrNull)?\s*\(\s*[\'"]([^\'"]+)[\'"]\s*(?:,|\))')
    missing_literals = set()

    for dirpath, _, filenames in os.walk(lua_root):
        for fn in filenames:
            if fn.endswith('.lua'):
                file_path = os.path.join(dirpath, fn)
                rel_path = os.path.relpath(file_path, project_root)
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    for line_no, line in enumerate(f, 1):
                        for m in call_regex.finditer(line):
                            key = m.group(1).strip()
                            if key.startswith('IGUI_EmberRoutesProbe_') or key.startswith('UI_EmberRoutesProbe_'):
                                if key not in ig_ui_cn:
                                    missing_literals.add((key, f"{rel_path}:{line_no}"))

    if missing_literals:
        for key, loc in sorted(missing_literals):
            errors.append(f"Literal translation key '{key}' referenced at {loc} is missing from IG_UI.json")

    # 3. Local helper functions with prefix: e.g. local function text(key) return getText('PREFIX' .. key) end
    helper_fn_regex = re.compile(
        r'local\s+function\s+([a-zA-Z0-9_]+)\s*\(\s*([a-zA-Z0-9_]+)[^\)]*\)\s*(?:return\s+)?getText(?:OrNull)?\s*\(\s*[\'"]([^\'"]+)[\'"]\s*\.\.\s*\2',
        re.MULTILINE
    )

    missing_helper_keys = set()
    for dirpath, _, filenames in os.walk(lua_root):
        for fn in filenames:
            if fn.endswith('.lua'):
                file_path = os.path.join(dirpath, fn)
                rel_path = os.path.relpath(file_path, project_root)
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                for m in helper_fn_regex.finditer(content):
                    fn_name, arg_name, prefix = m.groups()
                    # Find calls: fn_name('literal') where literal is followed by comma or close paren
                    for cm in re.finditer(rf'\b{fn_name}\s*\(\s*[\'"]([a-zA-Z0-9_]+)[\'"]\s*(?:,|\))', content):
                        key_suffix = cm.group(1)
                        full_key = prefix + key_suffix
                        if full_key not in ig_ui_cn:
                            missing_helper_keys.add((full_key, fn_name, rel_path))

    if missing_helper_keys:
        for key, fn_name, loc in sorted(missing_helper_keys):
            errors.append(f"Helper call {fn_name}('{key}') at {loc} resolves to missing key '{key}' in IG_UI.json")

    # 4. Dynamic domain: PublicWork categories
    categories = set()
    for dirpath, _, filenames in os.walk(lua_root):
        for fn in filenames:
            if fn.endswith('Provider.lua') or fn == 'PublicWorkProviders.lua':
                with open(os.path.join(dirpath, fn), 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    for m in re.finditer(r'category\s*=\s*[\'"]([^\'"]+)[\'"]', content):
                        cat = m.group(1).strip()
                        if cat and not cat.startswith('IGUI_') and len(cat) <= 32:
                            categories.add((cat, fn))

    for cat, fn in sorted(categories):
        pub_key = f"IGUI_EmberRoutesProbe_Public_{cat}"
        per_key = f"IGUI_EmberRoutesProbe_Personnel_{cat}"
        if pub_key not in ig_ui_cn:
            errors.append(f"PublicWork category '{cat}' (in {fn}) is missing required key '{pub_key}' in IG_UI.json")
        if per_key not in ig_ui_cn:
            errors.append(f"PublicWork category '{cat}' (in {fn}) is missing required key '{per_key}' in IG_UI.json")

    # 5. Dynamic domain: Settlement dashboard tabs
    dashboard_sources = list(Path(lua_root).rglob('SettlementDashboard.lua'))
    dashboard_path = str(dashboard_sources[0]) if len(dashboard_sources)==1 else None
    if dashboard_path is None:
        errors.append(f'Expected exactly one SettlementDashboard.lua, found {len(dashboard_sources)}')
    else:
        with open(dashboard_path, 'r', encoding='utf-8', errors='ignore') as f:
            dash_content = f.read()
            tab_block_m = re.search(r'local\s+tabs\s*=\s*\{([^}]+)\}', dash_content)
            if tab_block_m:
                tab_ids = re.findall(r'id\s*=\s*[\'"]([^\'"]+)[\'"]', tab_block_m.group(1))
                for tid in tab_ids:
                    tab_key = f"IGUI_EmberRoutesProbe_Settlement_tab_{tid}"
                    if tab_key not in ig_ui_cn:
                        errors.append(f"Dashboard tab '{tid}' is missing required key '{tab_key}' in IG_UI.json")

    # 6. Dynamic domain: WorkPolicy titleKey
    for dirpath, _, filenames in os.walk(lua_root):
        for fn in filenames:
            if fn.endswith('PolicyDef.lua') or fn == 'WorkPolicies.lua':
                with open(os.path.join(dirpath, fn), 'r', encoding='utf-8', errors='ignore') as f:
                    for m in re.finditer(r'titleKey\s*=\s*[\'"]([^\'"]+)[\'"]', f.read()):
                        tk = m.group(1).strip()
                        if tk and tk not in ig_ui_cn:
                            errors.append(f"Policy definition titleKey '{tk}' in {fn} is missing from IG_UI.json")

    # 7. Dynamic domain: Membership codes
    membership_sources = list(Path(lua_root).rglob('MembershipMenu.lua'))
    membership_menu = str(membership_sources[0]) if len(membership_sources)==1 else None
    if membership_menu is None:
        errors.append(f'Expected exactly one MembershipMenu.lua, found {len(membership_sources)}')
    else:
        with open(membership_menu, 'r', encoding='utf-8', errors='ignore') as f:
            for m in re.finditer(r'T\.reason\(\s*[\'"]([a-zA-Z0-9_]+)[\'"]\s*\)', f.read()):
                code = m.group(1)
                mkey = f"IGUI_EmberRoutesProbe_Membership_{code}"
                if mkey not in ig_ui_cn:
                    errors.append(f"Membership code '{code}' in MembershipMenu.lua is missing '{mkey}' in IG_UI.json")

    # Squad motion labels and conditional receipt labels are an explicit finite domain.
    squad_keys = ['title', 'empty', 'selectionHint', 'all', 'commands', 'show', 'following', 'inPosition', 'queued', 'yielding', 'traversal', 'vehicleWait', 'blocked', 'unavailable', 'stopping', 'selfCare', 'starting', 'returning', 'working', 'idle', 'superseded', 'applied', 'health', 'healthUnknown', 'command', 'actual', 'pending', 'settings', 'scale', 'buttonScale', 'resetLayout', 'callsign', 'clearCallsign', 'callsignPrompt', 'bleeding', 'sick', 'pain', 'exhausted', 'panic', 'heavyLoad', 'tired', 'hungry', 'thirsty']
    for suffix in squad_keys:
        key = 'IGUI_EmberRoutesProbe_Squad_' + suffix
        if key not in ig_ui_cn:
            errors.append(f"Squad presentation label is missing: {key}")
    binding_key = 'UI_optionscreen_binding_EmberRoutesSquadWheel'
    if binding_key not in load_json(os.path.join(trans_root, 'CN', 'UI.json')):
        errors.append(f"Missing native key binding label: {binding_key}")

    # 8. Percent-escape check (PZ 42.20.2: literal % must be %%)
    # Tokenize every value left to right: %% (escaped), %1..%9 (PZ
    # placeholder), Lua format verb (allowlisted keys only), anything else
    # is a bare % and fails the gate. Covers all 6 translation files.
    seen_format_verbs = set()
    for filename in ['IG_UI.json', 'Sandbox.json', 'UI.json']:
        for lang in ['CN', 'EN']:
            data = load_json(os.path.join(trans_root, lang, filename))
            for key, value in data.items():
                i = 0
                while i < len(value):
                    if value[i] != '%':
                        i += 1
                        continue
                    nxt = value[i + 1] if i + 1 < len(value) else ''
                    if nxt == '%':
                        i += 2
                        continue
                    if nxt and nxt in '123456789':  # '' (trailing %) is NOT a placeholder: '' in '123456789' is True in Python, so guard it
                        i += 2
                        continue
                    m = FORMAT_VERB_RE.match(value, i)
                    if m:
                        seen_format_verbs.add(key)
                        if key not in FORMAT_VERB_ALLOWLIST:
                            errors.append(
                                f"[{filename}:{lang}] Lua format verb '{m.group(0)}' in '{key}' "
                                f"is not in FORMAT_VERB_ALLOWLIST: use getText %1..%9 args for "
                                f"new strings, or add the key to the allowlist with its "
                                f"string.format call site"
                            )
                        i += len(m.group(0))
                        continue
                    errors.append(
                        f"[{filename}:{lang}] Bare % in '{key}': {value!r} -- "
                        f"write %% for a literal percent (PZ 42.20.2)"
                    )
                    i += 1
    for key in sorted(FORMAT_VERB_ALLOWLIST):
        if key not in seen_format_verbs:
            errors.append(
                f"Stale FORMAT_VERB_ALLOWLIST entry '{key}': no translation value "
                f"still uses a Lua format verb -- remove it from the allowlist"
            )

    # Summary report
    if errors:
        print(f"FAILED: Found {len(errors)} translation integrity error(s):\n")
        for err in errors:
            print(f"  [X] {err}")
        print("\nAll UI strings, provider categories, tabs, policies, and helper calls must have paired CN/EN translations!")
        sys.exit(1)
    else:
        print(f"SUCCESS: All {len(ig_ui_cn)} translation keys verified. CN/EN symmetry, literals, helpers, and dynamic domain registries are 100% intact.")
        sys.exit(0)

if __name__ == '__main__':
    main()
