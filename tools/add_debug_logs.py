# Python script to inject diagnostic logs into WarehouseIndex.lua and SettlementOverviewPage.lua
import re
from pathlib import Path

def patch_warehouse_index():
    path = Path("Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Warehouse/WarehouseIndex.lua")
    content = path.read_text(encoding="utf-8")
    
    target = """local function fastScanJava(ctx)
    if not (EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseFastScan) then return false end
    local ledger=Ledger.data()
    local entry=ledger.entries[ctx.id]
    if not entry then return false end"""
    
    replacement = """local function fastScanJava(ctx)
    if not (EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseFastScan) then return false end
    local ledger=Ledger.data()
    local entry=ledger.entries[ctx.id]
    if not entry then
        Log.write("ER_DEBUG", "fastScanJava: entry NOT FOUND for id=" .. tostring(ctx.id))
        return false
    end
    Log.write("ER_DEBUG", "fastScanJava ctx=" .. tostring(ctx.id) .. " areas=" .. tostring(entry and entry.areas and #entry.areas or 0))
    if entry and entry.areas then
        for i, a in ipairs(entry.areas) do
            Log.write("ER_DEBUG", "  settlement area[" .. i .. "]: x=" .. a.x .. " y=" .. a.y .. " w=" .. a.w .. " h=" .. a.h)
        end
    end
    for cid, cpos in pairs(Registry.data().containers or {}) do
        local inside = entry and Geometry.inside(entry, cpos.x, cpos.y)
        local ep, epReason = Registry.resolve(cid, "take", "local-world")
        local epCont = ep and ep.container
        local epType = epCont and epCont:getType() or "nil"
        local epItems = epCont and epCont:getItems() and epCont:getItems():size() or 0
        Log.write("ER_DEBUG", "  regCont: id=" .. cid .. " pos=" .. cpos.x .. "," .. cpos.y .. "," .. cpos.z .. " type=" .. tostring(epType) .. " inside=" .. tostring(inside) .. " resolve=" .. tostring(ep ~= nil) .. " reason=" .. tostring(epReason) .. " items=" .. tostring(epItems))
    end"""

    assert target in content, "Target not found in WarehouseIndex.lua"
    content = content.replace(target, replacement, 1)

    # Also log snapshot result
    snap_target = """    local snapshot=EmberRoutesProbeJava.warehouseFastScan(ctx.id,containerList,ctx.viewReset or false)
    if not snapshot or snapshot.state~="READY" then return false end"""

    snap_replacement = """    local snapshot=EmberRoutesProbeJava.warehouseFastScan(ctx.id,containerList,ctx.viewReset or false)
    Log.write("ER_DEBUG", "warehouseFastScan snapshot state=" .. tostring(snapshot and snapshot.state) .. " rows=" .. tostring(snapshot and snapshot.rows and #snapshot.rows or 0))
    if snapshot and snapshot.rows then
        for idx, r in ipairs(snapshot.rows) do
            Log.write("ER_DEBUG", "    row[" .. idx .. "]: " .. tostring(r.fullType) .. " node=" .. tostring(r.node) .. " count=" .. tostring(r.count))
        end
    end
    if not snapshot or snapshot.state~="READY" then return false end"""

    assert snap_target in content, "snap_target not found in WarehouseIndex.lua"
    content = content.replace(snap_target, snap_replacement, 1)

    path.write_text(content, encoding="utf-8")
    print("WarehouseIndex.lua patched successfully.")

def patch_settlement_overview():
    path = Path("Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/SettlementOverviewPage.lua")
    content = path.read_text(encoding="utf-8")

    # Add Log require
    req_target = "local ItemPresentation = require 'EmberRoutesProbe/UI/ItemPresentation'"
    req_replacement = "local ItemPresentation = require 'EmberRoutesProbe/UI/ItemPresentation'\nlocal Log = require 'EmberRoutesProbe/Kernel/Log'"
    if "local Log = require 'EmberRoutesProbe/Kernel/Log'" not in content:
        assert req_target in content, "req_target not found"
        content = content.replace(req_target, req_replacement, 1)

    stock_target = """function EmberRoutesSettlementOverviewPage:refreshStockpile(snapshot)
    if not self.active or self.disposed then return end"""

    stock_replacement = """function EmberRoutesSettlementOverviewPage:refreshStockpile(snapshot)
    if not self.active or self.disposed then return end
    Log.write("ER_DEBUG", "Overview:refreshStockpile active=" .. tostring(self.active)
        .. " snapState=" .. tostring(snapshot and snapshot.state or "nil")
        .. " snapRows=" .. tostring(snapshot and snapshot.rows and #snapshot.rows or "nil"))"""

    assert stock_target in content, "stock_target not found"
    content = content.replace(stock_target, stock_replacement, 1)

    calc_target = """    local pop = (self.store and self.store.value and self.store.value.vitals and self.store.value.vitals.population) or 0
    local stock = SupplyEstimate.calculate(currentSnapshot.rows, pop)"""

    calc_replacement = """    local pop = (self.store and self.store.value and self.store.value.vitals and self.store.value.vitals.population) or 0
    local stock = SupplyEstimate.calculate(currentSnapshot.rows, pop)
    Log.write("ER_DEBUG", "Overview:calculated stock: totalFood=" .. tostring(stock.totalFoodCount) .. " meals=" .. tostring(stock.mealsCount) .. " crops=" .. tostring(stock.cropsCount) .. " water=" .. tostring(stock.waterCount))"""

    assert calc_target in content, "calc_target not found"
    content = content.replace(calc_target, calc_replacement, 1)

    path.write_text(content, encoding="utf-8")
    print("SettlementOverviewPage.lua patched successfully.")

patch_warehouse_index()
patch_settlement_overview()
