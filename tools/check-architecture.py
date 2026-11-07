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


def main():
    if not LUA_ROOT.is_dir():
        raise SystemExit(f'ERROR: missing Lua root: {LUA_ROOT}')
    errors = inspect(LUA_ROOT)
    for error in errors:
        print('ERROR:', error)
    print(f'Static module boundary checks: {len(errors)} error(s). Dynamic loads/aliased writes NOT proven.')
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
