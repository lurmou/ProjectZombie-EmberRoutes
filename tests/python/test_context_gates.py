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
