"""Extract bounded review samples from installed vanilla scripts, not recipe effects.

Generates source-derived IO fixtures for the Kahlua contract test. Item/tag resolution,
native crafting and game state remain mocked there; this is not a game acceptance test.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).absolute().parent.parent
SCRIPTS = Path('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/scripts/generated/recipes')
SAMPLES = {
    'CarveWoodenFork': ('recipes_carving.txt', 1, 1, [1]),
    'CarveWoodenSpoon': ('recipes_carving.txt', 1, 1, [1]),
    'CraftSheetRope': ('recipes.txt', 1, 0, [1]),
    'SawLogs': ('recipes_carpentry.txt', 1, 1, [3]),
    'ChopLog': ('recipes_carpentry.txt', 1, 1, [6, 1]),
    'MakeTentKit': ('recipes_camping.txt', 8, 0, [1]),
    'MakeWoodenToolbox': ('recipes_carpentry.txt', 4, 3, [1]),
}


def block(text, pattern):
    match = re.search(pattern + r'\s*\{', text)
    assert match, pattern
    start = match.end()
    depth, end = 1, start
    while depth:
        assert end < len(text), 'unclosed source block'
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end - 1]


def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join('[' + json.dumps(k) + ']=' + lua(v) for k, v in value.items()) + '}'
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    return json.dumps(value, ensure_ascii=True)


rows = []
for name, (file, material_count, tool_count, yields) in SAMPLES.items():
    raw = (SCRIPTS / file).read_bytes()
    source = raw.decode('utf-8-sig')
    body = block(source, r'\bcraftRecipe\s+' + name + r'\b')
    assert not re.search(r'On(?:Create|Start|Update|Test|Failed)\s*=|mapper:', body), name
    inputs = []
    for line in block(body, r'\binputs').splitlines():
        line = line.strip().rstrip(',')
        if not line:
            continue
        match = re.fullmatch(r'item\s+(\d+)\s+(\[[^\]]+\]|tags\[[^\]]+\])(.*)', line)
        assert match, (name, line)
        selector = match[2]
        inputs.append(dict(count=int(match[1]), keep='mode:keep' in match[3],
                           choices=selector[selector.index('[')+1:-1].split(';'),
                           tag=selector.startswith('tags'), line=line))
    outputs = []
    for line in block(body, r'\boutputs').splitlines():
        line = line.strip().rstrip(',')
        if not line:
            continue
        match = re.fullmatch(r'item\s+(\d+)\s+(Base\.\w+)', line)
        assert match, (name, line)
        outputs.append(dict(count=int(match[1]), kind=match[2], line=line))
    assert sum(i['count'] for i in inputs if not i['keep']) == material_count, name
    assert sum(i['count'] for i in inputs if i['keep']) == tool_count, name
    assert [o['count'] for o in outputs] == yields, name
    skills = re.search(r'SkillRequired\s*=\s*([^,]+)', body)
    rows.append(dict(id='Base.' + name, file=file, sha256=hashlib.sha256(raw).hexdigest(),
                     hand='InHandCraft' in body, inputs=inputs, outputs=outputs,
                     skills=skills[1].strip().split(';') if skills else []))

# Negative controls use actual source, not fabricated special-mechanism recipes.
carpentry = (SCRIPTS / 'recipes_carpentry.txt').read_text(encoding='utf-8-sig')
assert 'OnCreate = RecipeCodeOnCreate.createLogStack' in block(carpentry, r'craftRecipe MakeTwoLogStack\b')
assert 'item 2 mapper:StickMapper' in block(carpentry, r'craftRecipe SawLongStick\b')
output = ROOT / 'build/qa'
output.mkdir(parents=True, exist_ok=True)
(output / 'recipe-coverage.lua').write_text('return ' + lua(rows) + '\n', encoding='utf-8')
(output / 'recipe-coverage.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
print('PASS 7 installed vanilla source profiles + callback/mapping negative controls; native resolution/effects NOT RUN')
