"""Counterexamples for the static gates; no game or production data mutations."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('architecture_gate', ROOT/'tools/check-architecture.py')
arch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arch)


class ArchitectureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def put(self, area, module, source='return {}'):
        p = self.root/area/('EmberRoutesProbe/'+module+'.lua')
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(source, encoding='utf-8')
        return p

    def errors(self):
        return arch.inspect(self.root)

    def test_all_business_domains_cannot_import_ui(self):
        self.put('client', 'UI/Widget')
        for domain in ('Runtime','Settlement','Leisure','Logistics','Hauling','Crafting','Field','Work','Warehouse','Cooking','Activity','SelfCare'):
            with self.subTest(domain=domain):
                p = self.put('client', domain+'/Service', 'return require "EmberRoutesProbe/UI/Widget"')
                self.assertTrue(any('business domain' in e for e in self.errors()))
                p.unlink()

    def test_shared_resolves_any_client_only_module(self):
        self.put('client','Logistics/Delivery')
        self.put('shared','Kernel/Model','return require( "EmberRoutesProbe/Logistics/Delivery" )')
        self.assertTrue(any('non-shared' in e for e in self.errors()))

    def test_literal_pcall_is_checked(self):
        self.put('client','Warehouse/Service')
        self.put('shared','Warehouse/Model', 'return pcall(require, "EmberRoutesProbe/Warehouse/Service")')
        self.assertTrue(any('non-shared' in e for e in self.errors()))

    def test_valid_shared_and_integration(self):
        self.put('shared','Kernel/Model')
        self.put('client','UI/Widget','return require "EmberRoutesProbe/Kernel/Model"')
        self.put('client','Integration/Entry','return require "EmberRoutesProbe/UI/Widget"')
        self.assertEqual([],self.errors())

    def test_comments_strings_and_computed_names_are_not_literal_edges(self):
        self.put('client','Field/Example', """-- require 'EmberRoutesProbe/UI/Missing'
--[=[ require 'EmberRoutesProbe/UI/Missing' ]=]
local example = \"require 'EmberRoutesProbe/UI/Missing'\"
local long = [=[require 'EmberRoutesProbe/UI/Missing']=]
return require('EmberRoutesProbe/UI/' .. name)
""")
        self.assertEqual([],self.errors())

    def test_missing_literal_and_flat_modules(self):
        self.put('client','Flat', 'return require "EmberRoutesProbe/Kernel/Missing"')
        self.assertTrue(any('flat module' in e for e in self.errors()))
        self.assertTrue(any('missing local' in e for e in self.errors()))

    def test_bootstrap_requires_are_checked(self):
        p=self.root/'client/EmberRoutesProbe.lua'
        p.parent.mkdir(parents=True,exist_ok=True)
        p.write_text('require \"EmberRoutesProbe/Kernel/Missing\"',encoding='utf-8')
        self.assertTrue(any('missing local' in e for e in self.errors()))

    def test_ui_direct_writes_rejected_but_equality_not_write(self):
        for code in ('ModData.x = {}','ModData["x"] = {}','ModData.getOrCreate("x")', 'actor:getModData()[key] = value'):
            with self.subTest(code=code):
                self.put('client','UI/View',code)
                self.assertTrue(self.errors())
        self.put('client','UI/View','if ModData.x == 1 then return end')
        self.assertEqual([],self.errors())

    def test_global_writes_respect_lua_scopes(self):
        cases = {
            'someNewGlobal={}': ['someNewGlobal'],
            'local decisionScans={}\ndecisionScans={}': [],
            'local function f() x=1 end': ['x'],
            'function g() end local function h() h=nil end': ['g'],
            'local M={} function M.f(a) a=1 self=2 end function M:g(b) self=1 b=2 end': ['self'],
            'for i=1,2 do i=3 end for k,v in pairs(t) do k,v=1,2 end': [],
            'local t={a=1,b={c=2}} t.x=1 t[1]=2 if a==1 then end': [],
            'local a if c then local b b=1 else b=2 end': ['b'],
            'local a,b=1,2 a,b=b,a c,a=1,2': ['c'],
            'f(function() y=1 end) while true do q=1 end': ['y', 'q'],
            '-- z=1\nlocal s="w=1" local l=[[v=1]]': [],
            'repeat local r=1 r=2 until r': [],
        }
        for source, expected in cases.items():
            with self.subTest(source=source):
                self.assertEqual(expected, [n for n, _ in arch.global_writes(arch.tokens(source))])

    def test_global_write_ratchet(self):
        self.put('client', 'Work/Kernel', 'local ok=1 newGlobal=ok')
        errors = []
        arch.check_global_writes(self.root, errors)
        self.assertEqual(1, len(errors))
        self.assertIn("'newGlobal'", errors[0])
        key = 'client/EmberRoutesProbe/Work/Kernel.lua'
        saved = dict(arch.GLOBAL_WRITE_BASELINE)
        self.addCleanup(lambda: (arch.GLOBAL_WRITE_BASELINE.clear(), arch.GLOBAL_WRITE_BASELINE.update(saved)))
        arch.GLOBAL_WRITE_BASELINE[key] = {'newGlobal', 'removedGlobal'}
        errors = []
        arch.check_global_writes(self.root, errors)
        self.assertEqual(1, len(errors))
        self.assertIn("'removedGlobal' is gone", errors[0])

    def test_kernel_category_names_cover_the_provider_registry(self):
        self.put('client', 'Work/LaborManifest', "return {{category='cooking'},{category='crafting'}}")
        # Since the opt-split-publicwork split, PublicWork.lua itself names no
        # category; the two order-creation 'cooking' literals live in
        # PublicWorkOrders.lua, checked under the same baseline.
        self.put('client', 'Work/PublicWork', "return {}")
        self.put('client', 'Work/PublicWorkOrders', "local a,b='cooking','cooking'")
        providers = self.put('client', 'Work/PublicWorkProviders', "-- 'crafting' in a comment is fine\nreturn {}")
        errors = []
        arch.check_kernel_categories(self.root, errors)
        self.assertEqual([], errors)
        providers.write_text("local skip='crafting'\nreturn {}", encoding='utf-8')
        arch.check_kernel_categories(self.root, errors)
        self.assertEqual(1, len(errors))
        self.assertIn('PublicWorkProviders.lua: 1 quoted category', errors[0])


class ProviderRetainedTests(unittest.TestCase):
    """Static side of the provider retained contract (P1-8).

    The manifest is the only wiring the check resolves: PublicWork calls
    e.provider() per LaborManifest entry and hands the def to
    Providers.register, which rejects a missing retained at runtime.
    """

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)  # fake LUA_ROOT

    def put(self, area, module, source='return {}'):
        p = self.root/area/('EmberRoutesProbe/'+module+'.lua')
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(source, encoding='utf-8')
        return p

    def manifest(self, entries):
        body = '\n'.join(
            "    {category='%s',provider=function() return require '%s' end}," % (c, m)
            for c, m in entries)
        return self.put('client', 'Work/LaborManifest',
                        'local M={}\nM.categories={\n' + body + '\n}\nreturn M')

    def errors(self):
        errors = []
        arch.check_provider_retained(self.root, errors)
        return errors

    def test_manifest_providers_with_retained_pass(self):
        # The three accepted export shapes on main: method def, inline
        # function field, and a named-function reference.
        self.put('client', 'Cooking/CookingProvider',
                 "local P={category='cooking'}\nfunction P.retained(id) return false end\nreturn P")
        self.put('client', 'Crafting/CraftingProvider',
                 "return {category='crafting',retained=function(npcId) return false end}")
        self.put('client', 'Field/FieldWork', 'return {retained=function(id) return false end}')
        self.put('client', 'Field/CleaningProvider',
                 "local P={category='cleaning',retained=require('EmberRoutesProbe/Field/FieldWork').retained}\nreturn P")
        self.manifest([('cooking', 'EmberRoutesProbe/Cooking/CookingProvider'),
                       ('crafting', 'EmberRoutesProbe/Crafting/CraftingProvider'),
                       ('cleaning', 'EmberRoutesProbe/Field/CleaningProvider')])
        self.assertEqual([], self.errors())

    def test_manifest_provider_without_retained_fails(self):
        self.put('client', 'Hauling/HaulingProvider', 'return {category=\'hauling\'}')
        self.manifest([('hauling', 'EmberRoutesProbe/Hauling/HaulingProvider')])
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn("'hauling'", errors[0])
        self.assertIn('without retained', errors[0])

    def test_manifest_provider_only_calling_retained_fails(self):
        # Using retained is not exporting it: a provider that only reads
        # p.retained must still fail.
        self.put('client', 'Hauling/HaulingProvider',
                 'local p=require "EmberRoutesProbe/Hauling/HaulJobs"\nreturn {category=\'hauling\',check=function(id) return p.retained(id) end}')
        self.manifest([('hauling', 'EmberRoutesProbe/Hauling/HaulingProvider')])
        self.assertTrue(any('without retained' in e for e in self.errors()))

    def test_manifest_provider_retained_nil_fails(self):
        self.put('client', 'Hauling/HaulingProvider', 'return {category=\'hauling\',retained=nil}')
        self.manifest([('hauling', 'EmberRoutesProbe/Hauling/HaulingProvider')])
        self.assertTrue(any('without retained' in e for e in self.errors()))

    def test_manifest_unresolvable_provider_fails(self):
        self.put('client', 'Work/LaborManifest',
                 "local M={}\nM.categories={\n    {category='hauling',provider=someFn},\n}\nreturn M")
        self.assertTrue(any('no literal-require provider thunk' in e for e in self.errors()))

    def test_manifest_missing_provider_module_fails(self):
        self.manifest([('hauling', 'EmberRoutesProbe/Hauling/Missing')])
        self.assertTrue(any('not found' in e for e in self.errors()))

    def test_literal_register_without_retained_fails(self):
        self.put('client', 'Cooking/CookingProvider',
                 "local P={}\nfunction P.retained(id) return false end\nreturn P")
        self.manifest([('cooking', 'EmberRoutesProbe/Cooking/CookingProvider')])
        p = self.put('client', 'Work/Extra',
                     "Providers.register({category='extra',discover=function() end})")
        errors = []
        arch.check_provider_retained(self.root, errors)
        self.assertTrue(any('literal Providers.register' in e for e in errors))
        p.write_text("Providers.register({category='extra',retained=function(id) return false end})",
                     encoding='utf-8')
        self.assertEqual([], self.errors())

    def test_dynamic_register_def_is_runtime_backstop(self):
        # Providers.register(def) with a variable def cannot be resolved
        # statically; the runtime register rejects a missing retained.
        self.put('client', 'Cooking/CookingProvider',
                 "local P={}\nfunction P.retained(id) return false end\nreturn P")
        self.manifest([('cooking', 'EmberRoutesProbe/Cooking/CookingProvider')])
        self.put('client', 'Work/PublicWork', 'Providers.register(def)')
        self.assertEqual([], self.errors())

    def test_non_manifest_retained_is_not_a_provider(self):
        # CraftLegacyRecovery.M.retained(r, j) has a different signature and
        # semantics; it is only examined if wired as a manifest provider.
        self.put('client', 'Crafting/CraftLegacyRecovery',
                 'local M={}\nfunction M.retained(r,j) return false end\nreturn M')
        self.put('client', 'Cooking/CookingProvider',
                 "local P={}\nfunction P.retained(id) return false end\nreturn P")
        self.manifest([('cooking', 'EmberRoutesProbe/Cooking/CookingProvider')])
        self.assertEqual([], self.errors())


class CompatRatchetTests(unittest.TestCase):
    """No-new-compat ratchet (P1-8): marker rules + only-shrink baseline."""

    # (line, java, is_marker, note)
    MARKER_CASES = [
        ("local legacyStockResume", False, True, 'legacy name'),
        ("r.reason='LEGACY_CRAFT_RETIRED'", False, True, 'LEGACY_ code'),
        ("-- Compatibility adapter for optional Debug probes.", False, True, 'compat comment'),
        ("area=firstArea, -- backward compatibility for single area reads", False, True, 'backward compat'),
        ("if value==nil then return true end -- Old saves keep manual recovery.", False, True, 'old saves'),
        ("-- migrate legacy records or authorize resource release.", False, True, 'migrate + legacy'),
        ("local x = fallbackForOldSave()", False, True, 'fallback + old'),
        ("local alias = oldName", False, True, 'alias + old'),
        ("if not Definitions.compatible(event.definition,event.definitionVersion) then return end",
         False, False, 'current definition-version gate call'),
        ("function R.compatible(id,version)", False, False, 'gate definition'),
        ('return result("API_INCOMPATIBLE", error.toString());', True, False, 'incompatible error code'),
        ("-- Rebind only before a unit's native effect; replace atomically migrates bench claims.",
         False, False, 'migrate without old context'),
        ("-- Subscribing never opens/migrates a ledger from a presentation path.",
         False, False, 'migrates without old context'),
        ("local x = value or 2000 -- fallback", False, False, 'plain runtime fallback'),
        ("function EmberRoutesPersonnelPage:syncLayoutAliases()", False, False, 'layout alias'),
        ("local alias=preferences.callsigns[row.id]", False, False, 'call-sign alias'),
        ("public boolean legacyAllowed(String npc) { return !frozen; }", True, False,
         'Java legacyAllowed is a current-behavior gate, not old-save compat'),
        ('probeId = slot.equals("legacy") ? UUID.randomUUID().toString() : slot;', True, False,
         'Java "legacy" carrier slot id is current behavior'),
        ("return migrateRecords(root,legacy,LuaManager.platform);", True, True,
         'Java v1 migration call'),
        ('Object legacy=root.rawget("snapshot")==null ? GlobalModData.instance.getOrCreate(KEY).rawget("record") : null;',
         True, True, 'Java legacy snapshot/record line'),
        ("root.rawset(\"snapshot\", snapshot); // Publish migration once, never consult v1 again.",
         True, True, 'Java migration + v1'),
    ]

    def test_marker_rules(self):
        for line, java, expected, note in self.MARKER_CASES:
            with self.subTest(note=note):
                self.assertEqual(expected, arch.compat_marker(line, java))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)  # fake repo root
        self.lua = self.root/'Contents/mods/EmberRoutesProbe/42/media/lua'
        self.java = self.root/'java/src/main/java'
        (self.lua/'client/EmberRoutesProbe/Work').mkdir(parents=True)
        (self.java/'emberroutes/probe').mkdir(parents=True)
        self.sample = self.lua/'client/EmberRoutesProbe/Work/Sample.lua'
        self.rel = 'Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/Sample.lua'
        saved = dict(arch.COMPAT_BASELINE)
        self.addCleanup(lambda: (arch.COMPAT_BASELINE.clear(), arch.COMPAT_BASELINE.update(saved)))
        arch.COMPAT_BASELINE.clear()
        arch.COMPAT_BASELINE[self.rel] = 2

    def errors(self):
        errors = []
        arch.check_compat(self.lua, self.java, errors, repo_root=self.root)
        return errors

    def test_baselined_count_passes_and_new_line_fails(self):
        self.sample.write_text("-- legacy stock resume\nlocal x = legacyThing\nreturn {}\n", encoding='utf-8')
        self.assertEqual([], self.errors())
        self.sample.write_text("-- legacy stock resume\nlocal x = legacyThing\nlocal y = legacyOther\nreturn {}\n", encoding='utf-8')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('baseline 2', errors[0])

    def test_new_file_with_marker_fails(self):
        self.sample.write_text("-- legacy stock resume\nlocal x = legacyThing\nreturn {}\n", encoding='utf-8')
        other = self.lua/'client/EmberRoutesProbe/Work/Other.lua'
        other.write_text("local legacyThing = 1\n", encoding='utf-8')
        self.assertTrue(any('new compat-marker' in e for e in self.errors()))

    def test_removed_marker_requires_baseline_lowering(self):
        self.sample.write_text("-- legacy stock resume\nreturn {}\n", encoding='utf-8')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('lower the COMPAT_BASELINE', errors[0])

    def test_removed_all_markers_requires_baseline_removal(self):
        self.sample.write_text("return {}\n", encoding='utf-8')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('remove it from COMPAT_BASELINE', errors[0])

    def test_clean_file_passes(self):
        self.sample.write_text("-- legacy stock resume\nlocal x = legacyThing\nreturn {}\n", encoding='utf-8')
        other = self.lua/'client/EmberRoutesProbe/Work/Other.lua'
        other.write_text("local x = value or 2000 -- fallback\nreturn {}\n", encoding='utf-8')
        self.assertEqual([], self.errors())


class DirectCallRatchetTests(unittest.TestCase):
    """Callback-first ratchet (P0 pilot 4): Probe mounts + raw queue adds.

    A new `Probe.<name> =` mount or `ISTimedActionQueue.add(` call fails
    unless annotated with `-- callback-first: <reason>` on the same line or
    a comment-only line directly above. Stock is baselined per file and
    only shrinks, same as the compat ratchet.
    """

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)  # fake LUA_ROOT
        saved = dict(arch.DIRECT_CALL_BASELINE)
        self.addCleanup(lambda: (arch.DIRECT_CALL_BASELINE.clear(), arch.DIRECT_CALL_BASELINE.update(saved)))
        arch.DIRECT_CALL_BASELINE.clear()

    def put(self, area, module, source='return {}'):
        p = self.root/area/('EmberRoutesProbe/'+module+'.lua')
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(source, encoding='utf-8')
        return p

    def errors(self):
        errors = []
        arch.check_direct_calls(self.root, errors)
        return errors

    def test_unannotated_probe_mount_and_queue_add_fail(self):
        self.put('client', 'Work/NewSvc', 'Probe.tickNew=S.tick\nISTimedActionQueue.add(a)\n')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('unannotated Probe mount', errors[0])
        self.assertIn('callback-first', errors[0])

    def test_annotated_same_line_and_line_above_pass(self):
        self.put('client', 'Work/NewSvc',
                 'Probe.tickNew=S.tick -- callback-first: no registry exists for tick hooks yet\n'
                 '-- callback-first: player has no TaskController body\n'
                 'ISTimedActionQueue.add(a)\n')
        self.assertEqual([], self.errors())

    def test_bare_marker_without_reason_fails(self):
        self.put('client', 'Work/NewSvc', 'Probe.tickNew=S.tick -- callback-first:\n')
        self.assertEqual(1, len(self.errors()))

    def test_trailing_comment_does_not_annotate_next_line(self):
        # A trailing comment belongs to its own line: the mount below it is
        # still unannotated even though the marker sits one line above.
        self.put('client', 'Work/NewSvc',
                 'Probe.a=S.a -- callback-first: no registry for this hook yet\nProbe.b=S.b\n')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('1 unannotated Probe mount', errors[0])

    def test_comparisons_strings_and_comments_are_not_mounts(self):
        self.put('client', 'Work/NewSvc',
                 "-- Probe.tickNew=S.tick\n"
                 "local s='Probe.tickNew=S.tick'\n"
                 'if Probe.tickNew==true then return end\n'
                 'if Probe.x then Probe.y() end\n')
        self.assertEqual([], self.errors())

    def test_baselined_stock_passes_and_second_queue_add_fails(self):
        key = 'client/EmberRoutesProbe/Runtime/TaskController.lua'
        arch.DIRECT_CALL_BASELINE[key] = (0, 1)
        self.put('client', 'Runtime/TaskController', 'ISTimedActionQueue.add(a)\n')
        self.assertEqual([], self.errors())
        self.put('client', 'Runtime/TaskController',
                 'ISTimedActionQueue.add(a)\nISTimedActionQueue.add(b)\n')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('baseline 0 / 1', errors[0])

    def test_annotating_baselined_call_requires_baseline_update(self):
        key = 'client/EmberRoutesProbe/Work/Svc.lua'
        arch.DIRECT_CALL_BASELINE[key] = (2, 0)
        self.put('client', 'Work/Svc',
                 'Probe.a=S.a -- callback-first: no registry for this hook yet\nProbe.b=S.b\n')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('lower the DIRECT_CALL_BASELINE', errors[0])

    def test_fully_annotated_baselined_file_requires_baseline_removal(self):
        key = 'client/EmberRoutesProbe/Runtime/TaskController.lua'
        arch.DIRECT_CALL_BASELINE[key] = (0, 1)
        self.put('client', 'Runtime/TaskController',
                 'ISTimedActionQueue.add(a) -- callback-first: the controlled single point\n')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('remove it from DIRECT_CALL_BASELINE', errors[0])


class LongFileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lua = self.root/'Contents/mods/EmberRoutesProbe/42/media/lua'
        self.java = self.root/'java/src/main/java'
        (self.lua/'client/EmberRoutesProbe/Work').mkdir(parents=True)
        (self.java/'emberroutes/probe').mkdir(parents=True)

    def errors(self):
        errors = []
        arch.check_long_files(self.lua, self.java, errors, repo_root=self.root)
        return errors

    def test_over_limit_fails_at_limit_passes(self):
        p = self.lua/'client/EmberRoutesProbe/Work/Big.lua'
        p.write_text('-- x\n' * arch.LUA_LONG_FILE_LIMIT, encoding='utf-8')
        self.assertEqual([], self.errors())
        p.write_text('-- x\n' * (arch.LUA_LONG_FILE_LIMIT + 1), encoding='utf-8')
        errors = self.errors()
        self.assertEqual(1, len(errors))
        self.assertIn('over the', errors[0])


class I18nSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root/'tools').mkdir()
        shutil.copy2(ROOT/'tools/check-i18n.py',self.root/'tools/check-i18n.py')
        self.lua = self.root/'Contents/mods/EmberRoutesProbe/42/media/lua'
        original = ROOT/'Contents/mods/EmberRoutesProbe/42/media/lua'
        shutil.copytree(original/'shared/Translate',self.lua/'shared/Translate')
        for name in ('MembershipMenu.lua','SettlementDashboard.lua'):
            sources = list(original.rglob(name))
            self.assertEqual(1,len(sources))
            target = self.lua/sources[0].relative_to(original)
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(sources[0],target)
        self.menu = list(self.lua.rglob('MembershipMenu.lua'))[0]

    def run_gate(self):
        return subprocess.run([sys.executable,str(self.root/'tools/check-i18n.py')],capture_output=True,text=True)

    def test_migrated_menu_found(self):
        result=self.run_gate()
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    def test_missing_menu_fails_instead_of_skipping(self):
        self.menu.unlink()
        result=self.run_gate()
        self.assertNotEqual(0,result.returncode)
        self.assertIn('Expected exactly one MembershipMenu.lua',result.stdout)

    def test_moved_menu_codes_are_validated(self):
        with self.menu.open('a',encoding='utf-8') as f:
            f.write("\nT.reason('CALIBRATION_MISSING_KEY')\n")
        result=self.run_gate()
        self.assertNotEqual(0,result.returncode)
        self.assertIn('CALIBRATION_MISSING_KEY',result.stdout)

    def test_duplicate_menu_is_not_ambiguous(self):
        other=self.lua/'client/EmberRoutesProbe/Other/MembershipMenu.lua'
        other.parent.mkdir(parents=True)
        shutil.copy2(self.menu,other)
        self.assertNotEqual(0,self.run_gate().returncode)

    def test_missing_dashboard_fails(self):
        list(self.lua.rglob('SettlementDashboard.lua'))[0].unlink()
        self.assertNotEqual(0,self.run_gate().returncode)


if __name__ == '__main__':
    unittest.main()
