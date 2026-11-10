#!/usr/bin/env python3
"""Static Lua module boundaries, not a runtime/alias data-flow proof.

Resolve literal require/pcall(require, ...) against the actual module index.
Skip comments, quoted examples and computed module names. Reject shared->client,
non-UI->UI (Integration is the UI composition boundary), missing local modules,
flat modules, and direct ModData writes/getOrCreate in UI. Dynamic loads and
writes through aliases require source review and targeted runtime tests.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA_ROOT = ROOT / 'Contents/mods/EmberRoutesProbe/42/media/lua'
PREFIX = 'EmberRoutesProbe/'
LONG = re.compile(r'\[(=*)\[')


def tokens(source):
    out = []
    i, line = 0, 1
    while i < len(source):
        c = source[i]
        if c.isspace():
            line += c == '\n'
            i += 1
            continue
        comment = source.startswith('--', i)
        start = i + 2 if comment else i
        long = LONG.match(source, start)
        if long:
            end = source.find(']' + long[1] + ']', long.end())
            end = len(source) if end < 0 else end + len(long[1]) + 2
            if not comment:
                out.append(('string', source[long.end():end-len(long[1])-2], line))
            line += source[i:end].count('\n')
            i = end
            continue
        if comment:
            end = source.find('\n', i)
            i = len(source) if end < 0 else end
            continue
        if c in ("'", '"'):
            end = i + 1
            while end < len(source):
                if source[end] == '\\':
                    end += 2
                elif source[end] == c:
                    end += 1
                    break
                else:
                    end += 1
            out.append(('string', source[i+1:end-1], line))
            line += source[i:end].count('\n')
            i = end
            continue
        match = re.match(r'[A-Za-z_][A-Za-z_0-9]*|\.\.|==|~=|<=|>=', source[i:])
        value = match[0] if match else c
        out.append(('id' if value[0].isalpha() or value[0] == '_' else 'symbol', value, line))
        i += len(value)
    return out


def requires(ts):
    for i, (kind, value, line) in enumerate(ts):
        if kind != 'id' or value != 'require':
            continue
        if i and ts[i-1][1] in ('.', ':'):
            continue
        j = i + 1
        if j < len(ts) and ts[j][1] == '(':
            j += 1
        elif j < len(ts) and ts[j][1] == ',':
            # Only the literal pcall(require, module) form, not arbitrary lists.
            if i < 2 or ts[i-2][1] != 'pcall' or ts[i-1][1] != '(':
                continue
            j += 1
        if j < len(ts) and ts[j][0] == 'string':
            if j + 1 < len(ts) and ts[j+1][1] == '..':
                continue
            yield ts[j][1], line


def inspect(lua_root):
    lua_root = Path(lua_root)
    errors = []
    modules = {}
    sources = []
    for area in ('client', 'shared', 'server'):
        base = lua_root / area
        for path in sorted(base.rglob('*.lua')):
            name = path.relative_to(base).as_posix()[:-4]
            modules.setdefault(name, set()).add(area)
            sources.append((area, path, path.relative_to(base)))
    for area, path, rel in sources:
        entry = rel.as_posix() == 'EmberRoutesProbe.lua'
        if not entry and not rel.as_posix().startswith(PREFIX):
            continue
        parts = rel.parts
        location = path.relative_to(lua_root).as_posix()
        if not entry and len(parts) == 2:
            errors.append(f'{location}: flat module must belong to a domain')
        domain = 'Integration' if entry else parts[1]
        ts = tokens(path.read_text(encoding='utf-8-sig'))
        for target, line in requires(ts):
            if not target.startswith(PREFIX):
                continue  # engine/third-party module resolution belongs to PZ
            resolved = modules.get(target, set())
            if not resolved:
                errors.append(f'{location}:{line}: missing local module {target}')
            elif area == 'shared' and 'shared' not in resolved:
                errors.append(f'{location}:{line}: shared requires non-shared module {target}')
            if area == 'client' and domain not in ('UI', 'Integration') and target.startswith(PREFIX+'UI/'):
                errors.append(f'{location}:{line}: business domain requires UI {target}')
        if area == 'client' and domain == 'UI':
            for i, (kind, value, line) in enumerate(ts):
                if kind == 'id' and value == 'getModData' and i+2 < len(ts) and ts[i+1][1] == '(' and ts[i+2][1] == ')':
                    end = i+3
                    while end < len(ts) and ts[end][2] == line and ts[end][1] not in ('=', ';'):
                        end += 1
                    if end < len(ts) and ts[end][1] == '=':
                        errors.append(f'{location}:{line}: direct character ModData assignment')
                if kind != 'id' or value != 'ModData':
                    continue
                end = i + 1
                while end < len(ts) and ts[end][1] not in ('=', ';') and ts[end][2] == line:
                    end += 1
                if end < len(ts) and ts[end][1] == '=':
                    errors.append(f'{location}:{line}: direct ModData assignment')
                elif i+3 < len(ts) and ts[i+1][1] in ('.', ':') and ts[i+2][1] in ('getOrCreate', 'create', 'add', 'remove', 'transmit') and ts[i+3][1] == '(':
                    errors.append(f'{location}:{line}: direct ModData authority call')
    return errors


# Hardcoded kernel-category names that PublicWork.lua is allowed to reference.
# Adding a new name here is a contract change; the check fails until the baseline is updated.
# P4 left only order creation's cooking/craft split (createOrder, createPrerequisite).
KERNEL_CATEGORY_BASELINE = {'cooking'}
# Exact count of quoted manifest category names in PublicWork.lua code (comments
# excluded). Only-shrink ratchet: more fails; fewer fails until this is lowered.
# Was 10 before P4 (crafting 3, hauling 3, cooking 4).
KERNEL_CATEGORY_LITERAL_COUNT = 2
MANIFEST_REL = 'client/EmberRoutesProbe/Work/LaborManifest.lua'

# PublicWork.lua kernel file (relative to LUA_ROOT)
PUBWORK_REL = 'client/EmberRoutesProbe/Work/PublicWork.lua'
PROVIDERS_REL = 'client/EmberRoutesProbe/Work/PublicWorkProviders.lua'


KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto',
            'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}


def global_writes(ts):
    """Yield (name, line) for every write to a name with no enclosing local.

    Scope-aware over the token stream: locals, local functions, parameters
    (and self for ':' methods) and for-loop names are declared in the block
    that owns them; a bare 'function name()' counts as a write. Table fields
    ({x=1}, a.x=, a[k]=) are not names. shortcut: in a multi-assignment, names
    left of a field/index target (g, t.x = ...) are not seen; upgrade to a
    real Lua parser if such a write ever slips through review.
    """
    scopes = [set()]   # block scopes; scopes[0] is the chunk
    stack = []         # open frames: 'block' or an opening bracket
    pending = set()    # names for the next block (for-loop names)
    i, n = 0, len(ts)

    def is_name(k):
        return 0 <= k < n and ts[k][0] == 'id' and ts[k][1] not in KEYWORDS

    def declared(name):
        return any(name in s for s in scopes)

    def push(names):
        scopes.append(names)
        stack.append('block')

    def pop():
        while stack and stack[-1] != 'block':
            stack.pop()  # unbalanced bracket; the block end still closes it
        if stack:
            stack.pop()
        if len(scopes) > 1:
            scopes.pop()

    def params(k):
        # ts[k] is '(' of a parameter list; returns names and the index after ')'.
        names, k = set(), k + 1
        while k < n and ts[k][1] != ')':
            if is_name(k):
                names.add(ts[k][1])
            k += 1
        return names, k + 1

    while i < n:
        kind, value, line = ts[i]
        if kind == 'string':
            i += 1
            continue
        if value in ('(', '{', '['):
            stack.append(value)
        elif value in (')', '}', ']'):
            if stack and stack[-1] != 'block':
                stack.pop()
        elif kind == 'id' and value == 'local':
            if i + 1 < n and ts[i+1][1] == 'function' and is_name(i + 2):
                scopes[-1].add(ts[i+2][1])
                i += 1  # 'function' handled next round, with the name already local
                continue
            k = i + 1
            while is_name(k):
                scopes[-1].add(ts[k][1])
                if k + 1 < n and ts[k+1][1] == ',':
                    k += 2
                else:
                    break
        elif kind == 'id' and value == 'function':
            k = i + 1
            if is_name(k):  # function a.b:c(...) / function name(...)
                first = ts[k][1]
                bare = not (k + 1 < n and ts[k+1][1] in ('.', ':'))
                method = False
                while k + 1 < n and ts[k+1][1] in ('.', ':') and is_name(k + 2):
                    method = ts[k+1][1] == ':'
                    k += 2
                if bare and not (i > 0 and ts[i-1][1] == 'local') and not declared(first):
                    yield first, line
                k += 1
            else:
                method = False
            names, k = params(k) if k < n and ts[k][1] == '(' else (set(), k)
            if method:
                names.add('self')
            push(names)
            i = k
            continue
        elif kind == 'id' and value == 'for':
            k = i + 1
            while is_name(k):
                pending.add(ts[k][1])
                k += 2 if k + 1 < n and ts[k+1][1] == ',' else 1
                if k < n and ts[k][1] in ('=', 'in'):
                    break
            i = k + 1  # skip the loop names and their '='/'in'
            continue
        elif kind == 'id' and value == 'do':
            push(pending)  # for-loop names belong to the loop body
            pending = set()
        elif kind == 'id' and value in ('then', 'repeat'):
            push(set())
        elif kind == 'id' and value == 'else':
            pop()
            push(set())
        elif kind == 'id' and value in ('elseif', 'end', 'until'):
            pop()
        elif value == '=' and (not stack or stack[-1] == 'block'):
            k = i - 1
            while is_name(k) and not (k > 0 and ts[k-1][1] in ('.', ':')):
                before = ts[k-1][1] if k > 0 else None
                if before == 'local':
                    break
                if not declared(ts[k][1]):
                    yield ts[k][1], ts[k][2]
                if before != ',':
                    break
                k -= 2
        i += 1


# Global writes that existed when the check became general (path relative to
# the Lua root -> names). Only-shrink ratchet: a write not listed fails; a
# listed one that no longer occurs fails until it is removed from this list.
GLOBAL_WRITE_BASELINE = {
    # Public mod API and PZ UI classes (ISPanel:derive) are globals by design.
    'shared/EmberRoutesProbe/Activity/ActivityRegistry.lua': {'EmberRoutes'},
    'client/EmberRoutesProbe/Integration/NpcDebugMenu.lua': {'EmberRoutesNpcStats'},
    'client/EmberRoutesProbe/UI/BatchPaintingSelector.lua': {'EmberRoutesBatchPaintingSelector'},
    'client/EmberRoutesProbe/UI/CraftingBrowser.lua': {'EmberRoutesCraftingBrowser'},
    'client/EmberRoutesProbe/UI/CraftingPage.lua': {'EmberRoutesCraftingPage'},
    'client/EmberRoutesProbe/UI/DefensePage.lua': {'EmberRoutesDefensePage'},
    'client/EmberRoutesProbe/UI/PersonnelPage.lua': {'EmberRoutesPersonnelPage'},
    'client/EmberRoutesProbe/UI/PublicOrderDialog.lua': {'EmberRoutesPublicOrderDialog'},
    'client/EmberRoutesProbe/UI/SettlementDashboard.lua': {'EmberRoutesSettlementDashboard'},
    'client/EmberRoutesProbe/UI/SettlementSelector.lua': {'EmberRoutesSettlementSelector'},
    'client/EmberRoutesProbe/UI/StockRules.lua': {'EmberRoutesStockRules'},
    'client/EmberRoutesProbe/UI/StorageFilterPanel.lua': {'EmberRoutesStorageFilterPanel'},
    'client/EmberRoutesProbe/UI/WarehousePage.lua': {'EmberRoutesWarehousePage'},
    'client/EmberRoutesProbe/UI/WorkPolicyPage.lua': {'EmberRoutesWorkPolicyPage'},
    # Undeclared locals that leak into _G (pre-existing; fixing them changes behavior).
    'client/EmberRoutesProbe/Field/FieldDiscovery.lua': {'seenLimit'},
    'client/EmberRoutesProbe/UI/SettlementOverviewPage.lua': {'isHauling', 'isCrafting'},
}


def check_global_writes(lua_root, errors):
    """Fail on any write to an undeclared (global) name not in the baseline."""
    lua_root = Path(lua_root)
    for area in ('client', 'shared', 'server'):
        for path in sorted((lua_root / area).rglob('*.lua')):
            rel = path.relative_to(lua_root).as_posix()
            allowed = GLOBAL_WRITE_BASELINE.get(rel, set())
            seen = set()
            for name, line in global_writes(tokens(path.read_text(encoding='utf-8-sig'))):
                seen.add(name)
                if name not in allowed:
                    errors.append(f'{rel}:{line}: global write to {name!r}; declare it local or own it in a module table')
            for name in sorted(allowed - seen):
                errors.append(f'{rel}: baseline global write {name!r} is gone; remove it from GLOBAL_WRITE_BASELINE')


def check_kernel_categories(lua_root, errors):
    """Fail if a kernel file hard-codes a category name not in its baseline.

    PublicWork.lua keeps KERNEL_CATEGORY_BASELINE / KERNEL_CATEGORY_LITERAL_COUNT;
    the provider registry PublicWorkProviders.lua must name no category at all.

    The baseline list is KERNEL_CATEGORY_BASELINE above.  Removing a name from
    that list is fine (only-shrink is allowed); adding one to the source without
    updating the baseline is the error this check catches.

    Only looks at strings used in comparison context with 'category', to avoid
    false positives from type names and other short strings.
    """
    for rel, allowed, expected in ((PUBWORK_REL, KERNEL_CATEGORY_BASELINE, KERNEL_CATEGORY_LITERAL_COUNT),
                                   (PROVIDERS_REL, set(), 0)):
        check_kernel_file(lua_root, rel, allowed, expected, errors)


def check_kernel_file(lua_root, rel, allowed, expected, errors):
    import re as _re
    pubwork = Path(lua_root) / rel
    if not pubwork.exists():
        errors.append(f'{rel}: file not found for kernel-category baseline check')
        return
    source = pubwork.read_text(encoding='utf-8-sig')
    # Match patterns like: category=='cooking', category~='crafting', category,'cooking'
    # (category comparisons and explicit category= string assignments)
    cat_pattern = _re.compile(
        r"category\s*[=~!]=\s*['\"]([a-z][a-z0-9_]{1,23})['\"]"
        r"|['\"]([a-z][a-z0-9_]{1,23})['\"]\s*[=~!]=\s*category"
    )
    for ln, text in enumerate(source.splitlines(), 1):
        for m in cat_pattern.finditer(text):
            name = m.group(1) or m.group(2)
            if name not in allowed:
                errors.append(
                    f'{rel}:{ln}: new hardcoded category comparison {name!r} not in '
                    f'its kernel category baseline; update the baseline or remove the reference'
                )
    manifest = Path(lua_root) / MANIFEST_REL
    if not manifest.exists():
        errors.append(f'{MANIFEST_REL}: file not found for kernel-category literal count')
        return
    names = set(_re.findall(r"category\s*=\s*'([A-Za-z][A-Za-z0-9_]*)'",
                            manifest.read_text(encoding='utf-8-sig')))
    literal = _re.compile(r"""['"](""" + '|'.join(sorted(map(_re.escape, names))) + r""")['"]""")
    count = 0
    for text in source.splitlines():
        count += len(literal.findall(text.split('--', 1)[0]))
    if count != expected:
        errors.append(
            f'{rel}: {count} quoted category name(s) in kernel code, baseline {expected}; '
            + ('lower the baseline' if count < expected else 'move the domain check behind a provider hook')
        )


def main():
    if not LUA_ROOT.is_dir():
        raise SystemExit(f'ERROR: missing Lua root: {LUA_ROOT}')
    errors = inspect(LUA_ROOT)
    # Global-write ratchet and kernel-category checks.
    check_global_writes(LUA_ROOT, errors)
    check_kernel_categories(LUA_ROOT, errors)
    for error in errors:
        print('ERROR:', error)
    print(f'Static module boundary checks: {len(errors)} error(s). Dynamic loads/aliased writes NOT proven.')
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
