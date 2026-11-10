#!/usr/bin/env python3
"""Static Lua module boundaries, not a runtime/alias data-flow proof.

Resolve literal require/pcall(require, ...) against the actual module index.
Skip comments, quoted examples and computed module names. Reject shared->client,
non-UI->UI (Integration is the UI composition boundary), missing local modules,
flat modules, and direct ModData writes/getOrCreate in UI. Dynamic loads and
writes through aliases require source review and targeted runtime tests.

Also enforced here (P1-8 architecture-gate extension):
- Provider retained contract: every provider wired through
  LaborManifest.categories must export a `retained` function, and any literal
  table passed to Providers.register(...) must carry `retained`. This is the
  static side of PublicWorkProviders.Registry.register, which rejects a
  missing/non-function retained at runtime.
- No-new-compat ratchet: production Lua/Java lines matching old-save compat
  markers (compat/legacy/old-save/migration-with-old-context, and
  fallback/alias only when combined with old/legacy wording) are counted per
  file against COMPAT_BASELINE. Only-shrink: a new marker line fails, a
  removed one fails until the baseline is lowered. Runtime fallbacks and
  layout/call-sign aliases are NOT markers; see check_compat for the exact
  rules and the known over-matches.
- Long-file tripwire: a production Lua file over LUA_LONG_FILE_LIMIT lines or
  a Java file over JAVA_LONG_FILE_LIMIT lines fails; split the file first.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA_ROOT = ROOT / 'Contents/mods/EmberRoutesProbe/42/media/lua'
JAVA_ROOT = ROOT / 'java/src/main/java'
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


def _retained_export(ts):
    """True if a token stream exports `retained` as a function value.

    Accepts `function P.retained(...)`, `retained = function (...)`, and
    `retained = <name>` (a named function or dotted reference, e.g.
    `retained = FieldWork.retained`). A call expression (`retained =
    makeRetained()`), `nil`/`false`/`true`, a string or a number do NOT
    count: the runtime register rejects non-functions anyway, and the static
    check must not bless a value it cannot see is a function. Mere uses
    (`p.retained(npcId)`, `if x.retained then`) do not count either.
    """
    for i, (kind, value, _line) in enumerate(ts):
        if kind != 'id':
            continue
        if (value == 'function' and i + 4 < len(ts) and ts[i + 1][0] == 'id'
                and ts[i + 2][1] == '.' and ts[i + 3][1] == 'retained'
                and ts[i + 4][1] == '('):
            return True
        if value == 'retained' and i + 1 < len(ts) and ts[i + 1][1] == '=':
            if i + 2 < len(ts):
                vkind, vval = ts[i + 2][0], ts[i + 2][1]
                if vval == 'function':
                    return True
                if vkind == 'id' and vval not in KEYWORDS:
                    return True
    return False


def _manifest_provider_entries(source):
    """Yield (category, provider-module) for each LaborManifest category entry.

    Entries are `{category='...', ..., provider=function() return require
    'EmberRoutesProbe/...' end}` blocks. A block whose provider thunk is not
    a literal require yields (category, None): the static check cannot resolve
    it, and that is an error, not a skip.
    """
    for block in re.findall(r'\{([^{}]*category\s*=[^{}]*)\}', source):
        category = re.search(r"""category\s*=\s*['"]([^'"]+)['"]""", block)
        provider = re.search(
            r"""provider\s*=\s*function\s*\(\s*\)\s*return\s+require\s*['"]([^'"]+)['"]""",
            block)
        yield (category.group(1) if category else None,
               provider.group(1) if provider else None)


def _resolve_module(lua_root, target):
    for area in ('client', 'shared', 'server'):
        path = Path(lua_root) / area / (target + '.lua')
        if path.is_file():
            return path
    return None


def check_provider_retained(lua_root, errors):
    """Fail if a registered provider cannot statically show a `retained`.

    Two sources, matching how registration actually happens:
    1. LaborManifest.categories: PublicWork calls `e.provider()` for each
       entry and passes the returned def to Providers.register. The provider
       module file must export `retained` (see _retained_export).
    2. Literal defs: `Providers.register({...})` with a table literal must
       carry `retained` in that literal.
    Boundaries (documented, not silently skipped): defs passed as variables
    (`Providers.register(def)`, `Service.registerProvider(def)`) cannot be
    resolved statically -- the runtime register rejects a missing retained,
    and tests/provider-retained-test.lua covers the runtime side. Other
    registries (PageRegistry, JobPolicyRegistry, ActivityRegistry, ...) have
    their own contracts and are not checked here. A `retained` with a
    different signature/semantics (e.g. CraftLegacyRecovery.M.retained(r, j))
    is not a provider export and is not counted: only manifest-wired provider
    modules and literal provider defs are examined.
    """
    manifest = Path(lua_root) / MANIFEST_REL
    if not manifest.exists():
        errors.append(f'{MANIFEST_REL}: file not found for provider-retained check')
    else:
        entries = list(_manifest_provider_entries(
            manifest.read_text(encoding='utf-8-sig')))
        if not entries:
            errors.append(f'{MANIFEST_REL}: no provider categories found; '
                          'the manifest format changed and this check is blind')
        for category, target in entries:
            if not category:
                errors.append(f'{MANIFEST_REL}: category entry without a category name')
                continue
            if not target:
                errors.append(
                    f'{MANIFEST_REL}: provider {category!r} has no literal-require '
                    'provider thunk; use provider=function() return require '
                    "'EmberRoutesProbe/...' end so the retained check can resolve it")
                continue
            path = _resolve_module(lua_root, target)
            if path is None:
                errors.append(f'{MANIFEST_REL}: provider {category!r} module {target!r} not found')
                continue
            if not _retained_export(tokens(path.read_text(encoding='utf-8-sig'))):
                errors.append(
                    f'{path.relative_to(lua_root).as_posix()}: provider {category!r} '
                    'registers without retained; add a retained(npcId) function '
                    '(PublicWorkProviders.register rejects one without it at runtime)')
    for area in ('client', 'shared', 'server'):
        for path in sorted((Path(lua_root) / area).rglob('*.lua')):
            ts = tokens(path.read_text(encoding='utf-8-sig'))
            for i, (kind, value, line) in enumerate(ts):
                if (kind != 'id' or value != 'register' or i < 2
                        or ts[i - 1][1] != '.' or ts[i - 2][1] != 'Providers'
                        or i + 1 >= len(ts) or ts[i + 1][1] != '('):
                    continue
                if i + 2 >= len(ts) or ts[i + 2][1] != '{':
                    continue  # dynamic def: runtime register is the backstop
                depth, j = 0, i + 2
                while j < len(ts):
                    if ts[j][1] in ('{', '(', '['):
                        depth += 1
                    elif ts[j][1] in ('}', ')', ']'):
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                if not _retained_export(ts[i + 2:j + 1]):
                    errors.append(
                        f'{path.relative_to(lua_root).as_posix()}:{line}: literal '
                        'Providers.register({...}) without retained; add '
                        'retained = <function>')


# Compat-marker ratchet: per-file counts of production lines matching an
# old-save compat marker, measured on main 673da20. Only-shrink: a higher
# count fails (new compat code), a lower count fails until the baseline is
# lowered, a file not listed here with any marker fails. Keys are repo-root
# relative paths. These are historical leftovers slated for P1-10 deletion,
# not permission to add more: each deletion lowers its file's count here.
# Lua total 53 lines / 26 files; Java total 5 lines / 1 file.
COMPAT_BASELINE = {
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Crafting/CraftLegacyRecovery.lua': 3,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Crafting/CraftProbe.lua': 1,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Crafting/ProductionRecipe.lua': 3,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Field/ToolReturnProvider.lua': 1,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/Persistence.lua': 8,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/InlineCardDrawer.lua': 2,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Warehouse/ContainerRegistry.lua': 3,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Warehouse/OrderMonitorService.lua': 1,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/LaborStore.lua': 7,
    'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/PublicWork.lua': 1,
    'Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/Boot.lua': 2,
    'Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/JobStore.lua': 2,
    'Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Warehouse/StorageFilter.lua': 1,
    'java/src/main/java/emberroutes/probe/ProbePersistence.java': 5,
}
def _line_words(line):
    """Lowercase words on a line, splitting camelCase/underscores/digits.

    `fallbackForOldSave` -> {fallback, for, old, save}; `cold` stays {cold}
    (never `old`); `holdSelection` stays {hold, selection}. Context rules
    below match whole words, so `cold`, `gold` and `hold` cannot smuggle in
    an `old`.
    """
    words = set()
    for token in re.findall(r'[A-Za-z]+', line):
        for part in re.split(r'(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])', token):
            words.add(part.lower())
    return words


_COMPAT_MIGRAT_CTX = {'legacy', 'old', 'v1', 'format', 'record', 'records',
                      'save', 'saved', 'saves'}
_COMPAT_FALLBACK_CTX = {'old', 'legacy', 'former', 'previous'}
_COMPAT_ALIAS_CTX = {'old', 'legacy', 'deprecated', 'former', 'previous'}
# Java only: `legacy` is overloaded there (the "legacy" carrier slot id and
# BodyAuthority.legacyAllowed are current-behavior gates, not old-save
# compat), so a Java `legacy` counts only with old-save context on the line.
_COMPAT_JAVA_LEGACY_CTX = {'migrat', 'migrate', 'migrates', 'migration',
                           'old', 'snapshot', 'record', 'records'}
_COMPAT_VERSION = re.compile(r'\bv\d+\b', re.I)


def compat_marker(line, java=False):
    """True if one production line is an old-save compat marker.

    Rules, in order (a line counts once however many rules hit):
    - `compat` anywhere, except the current definition-version gate
      `compatible(` (calls and the `function R.compatible` definition) and
      `incompatib*` (e.g. the API_INCOMPATIBLE error code). So "Compatibility
      adapter", "backward compatibility", "compatible with primary slot 0"
      count, while `Definitions.compatible(...)` does not.
    - `legacy` anywhere (Lua). In Java only with old-save context, see above.
    - `old` + `save`/`saved`/`saves` as one phrase (covers `oldSave`,
      "Old saves", `old_save`); a bare `old` variable next to an unrelated
      `saved` table on the same line (e.g. `local old = saved.byId[id]`)
      is NOT a marker.
    - `migrat*` only with old-save context on the same line (legacy/old/v1/
      format/record/save): "migrate legacy records" counts, "migrates bench
      claims" and "never opens/migrates a ledger" do not.
    - `fallback` / `alias` only with old/legacy/former/previous/vN wording
      on the same line: plain runtime fallbacks (`or 2000`, `fallbackInitials`,
      `intVal(x, fallback)`, doorway/A* fallbacks) and layout/call-sign
      aliases (`syncLayoutAliases`, callsign `alias`) are NOT markers.
      Context is matched on whole words (camelCase split), so `cold`,
      `gold` and `hold` never count as `old`.
    Known over-matches (all currently baselined, none on a new line is
    acceptable without a baseline update + reason): SocialActions "emote/turn
    compatibility" (pose compatibility, not save compat); MembershipService
    "old world is NOT a migration grant" (a line *refusing* migration still
    counts); `deprecated` is NOT a marker at all (---@deprecated tags and
    ---@diagnostic disable-next-line: deprecated suppressions for engine APIs
    are out of scope). A silent rename with none of these words
    (e.g. `api.transferCooking = api.transferOwner` with no compat comment)
    is NOT caught: that needs review, not this scan. Tests, docs and
    Translate files are out of scope: only production Lua + Java main.
    """
    text = re.sub(r'incompatib\w*', ' ', line, flags=re.I)
    text = re.sub(r'compatible\s*\(', ' ', text, flags=re.I)
    if re.search(r'compat', text, re.I):
        return True
    words = _line_words(text)
    if 'legacy' in words:
        if not java or words & _COMPAT_JAVA_LEGACY_CTX or _COMPAT_VERSION.search(text):
            return True
    if re.search(r'(?<![A-Za-z])old[-_ ]?(?:saves?|saved)(?![A-Za-z])', text, re.I):
        return True
    if re.search(r'migrat\w*', text, re.I) and (words & _COMPAT_MIGRAT_CTX
                                                or _COMPAT_VERSION.search(text)):
        return True
    if 'fallback' in words and (words & _COMPAT_FALLBACK_CTX or _COMPAT_VERSION.search(text)):
        return True
    if 'alias' in words and (words & _COMPAT_ALIAS_CTX or _COMPAT_VERSION.search(text)):
        return True
    return False


def check_compat(lua_root, java_root, errors, repo_root=None):
    """Only-shrink ratchet over compat-marker lines (see COMPAT_BASELINE)."""
    repo_root = Path(repo_root) if repo_root is not None else ROOT
    counts = {}
    for base, pattern, java in ((lua_root, '*.lua', False),
                                (java_root, '*.java', True)):
        base = Path(base)
        if not base.is_dir():
            errors.append(f'{base.relative_to(repo_root).as_posix()}: directory not found for compat check')
            continue
        for path in sorted(base.rglob(pattern)):
            rel = path.relative_to(repo_root).as_posix()
            count = sum(1 for line in path.read_text(
                encoding='utf-8-sig', errors='replace').splitlines()
                if compat_marker(line, java))
            if count:
                counts[rel] = count
    for rel, count in sorted(counts.items()):
        baseline = COMPAT_BASELINE.get(rel)
        if baseline is None:
            errors.append(
                f'{rel}: {count} new compat-marker line(s); development must not '
                'add compat/legacy/old-save code -- delete the old code instead '
                '(see COMPAT_BASELINE / check_compat for the exact rules)')
        elif count > baseline:
            errors.append(
                f'{rel}: {count} compat-marker line(s), baseline {baseline}; '
                'new compat/legacy/old-save code is not allowed in development')
        elif count < baseline:
            errors.append(
                f'{rel}: {count} compat-marker line(s), baseline {baseline}; '
                'lower the COMPAT_BASELINE entry (old compat code was deleted)')
    for rel in sorted(set(COMPAT_BASELINE) - set(counts)):
        errors.append(
            f'{rel}: compat-marker lines are gone; remove it from COMPAT_BASELINE')


# Long-file tripwire. Current maxima on main 673da20 are 1699 Lua lines
# (UI/SettlementOverviewPage.lua, already slated for a P1-9 split) and 1146
# Java lines (ProbeNpc.java); the limits sit just above them so any further
# growth fails instead of silently adding a second SettlementOverviewPage.
LUA_LONG_FILE_LIMIT = 1800
JAVA_LONG_FILE_LIMIT = 1200


def check_long_files(lua_root, java_root, errors, repo_root=None):
    """Fail on a production file over the long-file limit (see above)."""
    repo_root = Path(repo_root) if repo_root is not None else ROOT
    for base, pattern, limit in ((lua_root, '*.lua', LUA_LONG_FILE_LIMIT),
                                 (java_root, '*.java', JAVA_LONG_FILE_LIMIT)):
        for path in sorted(Path(base).rglob(pattern)):
            lines = len(path.read_text(encoding='utf-8-sig', errors='replace').splitlines())
            if lines > limit:
                errors.append(
                    f'{path.relative_to(repo_root).as_posix()}: {lines} lines, over the '
                    f'{limit}-line limit; split the file before adding more')


def main():
    if not LUA_ROOT.is_dir():
        raise SystemExit(f'ERROR: missing Lua root: {LUA_ROOT}')
    errors = inspect(LUA_ROOT)
    # Global-write ratchet and kernel-category checks.
    check_global_writes(LUA_ROOT, errors)
    check_kernel_categories(LUA_ROOT, errors)
    # P1-8 gate extension: provider retained contract, no-new-compat ratchet,
    # long-file tripwire.
    check_provider_retained(LUA_ROOT, errors)
    check_compat(LUA_ROOT, JAVA_ROOT, errors)
    check_long_files(LUA_ROOT, JAVA_ROOT, errors)
    for error in errors:
        print('ERROR:', error)
    print(f'Static module boundary checks: {len(errors)} error(s). Dynamic loads/aliased writes NOT proven.')
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
