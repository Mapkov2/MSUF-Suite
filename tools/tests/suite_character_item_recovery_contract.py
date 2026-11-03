"""Occupied dossier slots recover their initially unavailable inventory links."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
source = (root / "tools/tests/suite_character_stats_dr_contract.lua").read_text(encoding="utf-8-sig")
checks = r'''
do (function()
    local secret = {}
    local identities = { player = { [1] = 501 }, target = { [1] = 601 } }
    local guids = { player = "Player-Self", target = "Player-Other" }
    local loaded, requests, idReads = {}, {}, 0
    local function Identity(unit, slot) return (identities[unit] or {})[slot] end
    GetInventoryItemID = function(unit, slot) idReads = idReads + 1 return Identity(unit, slot) end
    GetInventoryItemTexture = function(unit, slot) return Identity(unit, slot) and 1234 or nil end
    GetInventoryItemQuality = function() return nil end
    GetInventoryItemLink = function(unit, slot)
        local id = Identity(unit, slot)
        return id and id ~= secret and loaded[id] and ("item:" .. id .. ":0:") or nil
    end
    UnitGUID = function(unit) return guids[unit] end
    C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    C_Item = {
        GetItemInfo = function(link)
            return "Recovered " .. link, nil, 4, nil, nil, nil, nil, nil, "INVTYPE_HEAD", 1234, nil, 4, 2, nil, 11
        end,
        GetItemGemID = function() return nil end,
        GetItemGem = function() return nil end,
        GetItemIconByID = function() return 99 end,
        GetItemUpgradeInfo = function() return nil end,
        GetDetailedItemLevelInfo = function() return 639 end,
        GetItemNumSockets = function() return 0 end,
        GetItemStats = function() return {} end,
        RequestLoadItemDataByID = function(id)
            assert(type(id) == "number" and id > 0, "invalid or restricted item identity requested")
            requests[id] = (requests[id] or 0) + 1
        end,
    }
    C_TooltipInfo = { GetInventoryItem = function() return { lines = {} } end }
    Enum = { TooltipDataLineType = { GemSocket = 3, ItemEnchantmentPermanent = 15 } }
    ITEM_QUALITY_COLORS = { [4] = { r = 1, g = 1, b = 1 } }
    NS.EquipmentInfo = Fresh("EquipmentInfo.lua").EquipmentInfo
    local function Flush()
        local count = 0
        while #timers > 0 do
            count = count + 1
            assert(count < 20, "item completion created a refresh loop")
            table.remove(timers, 1)()
        end
    end
    local function Event(view, name, ...)
        if view.host.events[name] then view.host.scripts.OnEvent(view.host, name, ...) end
    end
    local function Create(kind)
        PaperDollFrame, InspectPaperDollFrame = Object(), Object()
        local frame = Object({ unit = "target" })
        local api = Fresh("CharacterDetails.lua").CharacterDetails
        api.Apply(frame, kind, "recovery")
        return api, assert(api.views[frame]), frame
    end
    local function Loaded(view, id, event)
        loaded[id] = true
        Event(view, event or "ITEM_DATA_LOAD_RESULT", id, true)
        Flush()
    end
    for _, kind in ipairs({ "character", "inspect" }) do
        local unit = kind == "character" and "player" or "target"
        local id = identities[unit][1]
        local beforeIDs = idReads
        local api, view, frame = Create(kind)
        local row = view.bySlot[1]
        assert(row.name.text == NS.L.DOSSIER_LOADING and view.pending[id] and requests[id] == 1,
            kind .. ": occupied linkless slot did not retain/request its item identity")
        assert(idReads == beforeIDs + 1, kind .. ": empty slots caused unnecessary identity reads")
        beforeIDs = idReads
        Event(view, "GET_ITEM_INFO_RECEIVED", 9999, true)
        Event(view, "GET_ITEM_INFO_RECEIVED", secret, true)
        Event(view, "ITEM_DATA_LOAD_RESULT", 9999, true)
        Event(view, "ITEM_DATA_LOAD_RESULT", secret, true)
        Flush()
        assert(idReads == beforeIDs and #timers == 0, kind .. ": unrelated completion refreshed equipment")
        for _ = 1, 4 do Event(view, "GET_ITEM_INFO_RECEIVED", id, false) end
        assert(#timers == 1, kind .. ": a failure burst was not coalesced")
        Flush()
        assert(requests[id] == 1 and view.pending[id], kind .. ": failed completion retried in a loop or lost interest")
        Loaded(view, id, kind == "character" and "ITEM_DATA_LOAD_RESULT" or "GET_ITEM_INFO_RECEIVED")
        assert(row.name.text == "Recovered item:" .. id .. ":0:" and row.audit.itemLevel == 639
            and not view.pending[id] and row.pendingItemID == nil, kind .. ": successful completion did not recover the row")
        beforeIDs = idReads
        for _ = 1, 3 do api.Refresh(view) end
        Event(view, "GET_ITEM_INFO_RECEIVED", id, true)
        Flush()
        assert(idReads == beforeIDs and requests[id] == 1, kind .. ": resolved warm paints repeated identity/loading work")

        local nextID = id + 10
        identities[unit][1], loaded[id] = nextID, nil
        Event(view, "UNIT_INVENTORY_CHANGED", unit)
        Flush()
        assert(view.pending[nextID] and not view.pending[id] and requests[nextID] == 1,
            kind .. ": identity change retained the old waiter")
        beforeIDs = idReads
        Event(view, "GET_ITEM_INFO_RECEIVED", id, true)
        Flush()
        assert(idReads == beforeIDs and row.name.text == NS.L.DOSSIER_LOADING,
            kind .. ": old completion affected replacement equipment")
        view.host:Hide()
        assert(next(view.pending) == nil and row.pendingItemID == nil, kind .. ": hiding retained an item waiter")
        view.host:Show()
        assert(requests[nextID] == 2 and view.pending[nextID], kind .. ": reopening did not retry the unresolved identity")
        api.Disable(frame, "recovery")
        beforeIDs = idReads
        Event(view, "GET_ITEM_INFO_RECEIVED", nextID, true)
        Flush()
        assert(next(view.pending) == nil and row.pendingItemID == nil and idReads == beforeIDs,
            kind .. ": disabled view retained pending work")
        api.Apply(frame, kind, "recovery")
        assert(requests[nextID] == 3, kind .. ": re-enabling did not rebuild pending identity")
        Loaded(view, nextID)
        assert(row.audit.itemLevel == 639 and row.name.text == "Recovered item:" .. nextID .. ":0:",
            kind .. ": re-enabled row did not recover")
        api.Disable(frame, "recovery")
    end
    -- Native parents may protect owned frames during combat. Releasing a
    -- waiter is bookkeeping and must still happen without touching that UI.
    for _, kind in ipairs({ "character", "inspect" }) do
        local unit = kind == "character" and "player" or "target"
        local id = kind == "character" and 801 or 901
        identities[unit][1], loaded[id] = id, nil
        local api, view, frame = Create(kind)
        local row = view.bySlot[1]
        assert(requests[id] == 1 and view.pending[id])
        local panelHide, toggleHide, iconTexture = view.panel.Hide, view.toggle.Hide, row.icon.SetTexture
        local function UnsafeWrite() error("protected item recovery wrote native-inherited UI") end
        view.panel.Hide, view.toggle.Hide, row.icon.SetTexture = UnsafeWrite, UnsafeWrite, UnsafeWrite
        combatLocked, view.host.protected = true, true
        view.host:Hide() -- native parent hide; only the post-hook is addon work
        assert(next(view.pending) == nil and row.pendingItemID == nil,
            kind .. ": protected combat hide retained item waiters")
        combatLocked, view.host.protected = false, false
        view.panel.Hide, view.toggle.Hide, row.icon.SetTexture = panelHide, toggleHide, iconTexture
        view.host:Show()
        assert(requests[id] == 2 and view.pending[id], kind .. ": protected close lost reopen retry")
        combatLocked, view.host.protected = true, true
        view.panel.Hide, view.toggle.Hide, row.icon.SetTexture = UnsafeWrite, UnsafeWrite, UnsafeWrite
        api.Disable(frame, "recovery")
        assert(next(view.pending) == nil and row.pendingItemID == nil and not view.registered,
            kind .. ": protected combat disable retained item waiters")
        combatLocked, view.host.protected = false, false
        view.panel.Hide, view.toggle.Hide, row.icon.SetTexture = panelHide, toggleHide, iconTexture
        api.Apply(frame, kind, "recovery")
        assert(requests[id] == 3 and view.pending[id], kind .. ": protected disable lost re-enable retry")
        combatLocked, view.host.protected, NS.DB.enabled = true, true, false
        view.panel.Hide, view.toggle.Hide, row.icon.SetTexture = UnsafeWrite, UnsafeWrite, UnsafeWrite
        api.Refresh(view)
        assert(next(view.pending) == nil and row.pendingItemID == nil and not view.registered,
            kind .. ": disabled protected refresh retained item waiters")
        combatLocked, view.host.protected, NS.DB.enabled = false, false, true
        view.panel.Hide, view.toggle.Hide, row.icon.SetTexture = panelHide, toggleHide, iconTexture
        api.Apply(frame, kind, "recovery")
        assert(requests[id] == 4 and view.pending[id], kind .. ": disabled refresh lost re-enable retry")
        api.Disable(frame, "recovery")
    end
    -- A reused inspect window must wait for the new matching ready GUID.
    identities.target[1], guids.target = 701, "Player-First"
    local api, view, frame = Create("inspect")
    assert(requests[701] == 1 and view.pending[701])
    guids.target, identities.target[1] = "Player-Second", 702
    Event(view, "UNIT_INVENTORY_CHANGED", "target")
    Flush()
    assert(next(view.pending) == nil and not requests[702], "new inspect identity read before its ready GUID")
    Event(view, "GET_ITEM_INFO_RECEIVED", 701, true)
    Event(view, "INSPECT_READY", "Player-First")
    Flush()
    assert(not requests[702], "old inspect readiness/completion affected the new target")
    Event(view, "INSPECT_READY", "Player-Second")
    Flush()
    assert(requests[702] == 1 and view.pending[702] and not view.pending[701], "new inspect GUID did not acquire its own waiter")
    Loaded(view, 702)
    assert(view.bySlot[1].name.text == "Recovered item:702:0:", "new inspect item did not recover")
    api.Disable(frame, "recovery")

    local oldSecret = issecretvalue
    issecretvalue = function(value) return value == secret end
    identities.player[1] = secret
    api, view, frame = Create("character")
    assert(next(view.pending) == nil and not requests[secret], "restricted item identity entered pending state")
    api.Disable(frame, "recovery")
    issecretvalue = oldSecret
    print("dossier recovery: character/inspect cold link, filtered/coalesced events, warm cache, reopen/disable and GUID safety passed")
end)() end
'''
result = subprocess.run([lua, "-", str(root)], input=source + checks, text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(result.stdout, end="")
raise SystemExit(result.returncode)
