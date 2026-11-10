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
        self.put('client', 'Work/PublicWork', "local a,b='cooking','cooking'")
        providers = self.put('client', 'Work/PublicWorkProviders', "-- 'crafting' in a comment is fine\nreturn {}")
        errors = []
        arch.check_kernel_categories(self.root, errors)
        self.assertEqual([], errors)
        providers.write_text("local skip='crafting'\nreturn {}", encoding='utf-8')
        arch.check_kernel_categories(self.root, errors)
        self.assertEqual(1, len(errors))
        self.assertIn('PublicWorkProviders.lua: 1 quoted category', errors[0])


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
