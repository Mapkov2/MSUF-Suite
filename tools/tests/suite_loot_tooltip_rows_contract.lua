local rootPath = assert(arg[1])
local function Noop() end
local function Widget()
    local widget = { shown = true }
    function widget:IsShown() return self.shown end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:GetFrameLevel() return 1 end
    widget.SetPoint, widget.SetFrameLevel, widget.SetAllPoints = Noop, Noop, Noop
    return widget
end

Enum = { LootSlotType = { Item = 1, Currency = 2, Money = 3 } }
ScrollBoxListMixin = { Event = { OnInitializedFrame = "Init", OnReleasedFrame = "Release" } }
local function Row(slot, kind)
    local row = { slot = slot, kind = kind, Item = {}, Text = { name = "Silk Cloth" }, QualityText = {},
        QualityStripe = {}, BorderFrame = {}, NameFrame = {} }
    row.NameFrame.parent = row
    function row.NameFrame:GetAlpha() return 1 end
    row.Item.GetCount = function() return 2 end
    row.Item.Click = function() return slot end
    row.Item.parent, row.Text.parent, row.QualityText.parent = row, row, row
    function row.Text:GetText() return self.name end
    function row:GetItemSlotType() return self.kind end
    function row:GetSlotIndex() return self.slot end
    function row:GetHeight() return 46 end
    function row:GetQuality() return 1 end
    row.GetFrameLevel = Widget().GetFrameLevel
    return row
end

local item, money = Row(1, Enum.LootSlotType.Item), Row(2, Enum.LootSlotType.Money)
local callbacks, hooks, art, faded = {}, {}, {}, {}
local box = {}
function box:RegisterCallback(event, callback, owner) callbacks[event] = function(row) callback(owner, row) end end
function box:UnregisterCallback(event) callbacks[event] = nil end
function box:FindFrameByPredicate(predicate)
    if predicate(item) then return item end
    if predicate(money) then return money end
end
local window = Widget()
window.ScrollBox = box
function window:HookScript(event, callback) hooks[event] = callback end
local style, listener, border, reads = "suite", nil, true, 0
local surfaceMode, backings = "auto", {}
function GetLootSlotLink(slot)
    assert(slot == 1, "the adapter queried a non-item loot slot")
    reads = reads + 1
    return "item:4306"
end
local function Public(value) return type(value) ~= "table" or not value.secret end
local ns = {
    DB = { enabled = true },
    Safety = {
        Field = function(frame, key) return frame[key] end, Public = Public,
        CanCreateRegions = function(row) return row ~= nil end,
        HasMethod = function(frame, key) return type(frame[key]) == "function" end,
        Read = function(frame, key)
            if not frame or not frame[key] then return end
            local result = frame[key](frame)
            if Public(result) then return result end
        end,
        ReadColor = function() return 1, 1, 1 end,
        Dispatch = function(fn, ...) return fn(...) end,
    },
    AdapterKit = {
        WeakSet = function() return {} end,
        ParentIs = function(frame, parent) return frame and frame.parent == parent end,
        ForEachRow = function(_, paint) paint(item) paint(money) end,
    },
    Cosmetics = {
        Fade = function(region, owner) faded[region] = owner return true end,
        Restore = function(region) if region then faded[region] = nil end end,
        RestoreOwner = function(owner)
            for region, saved in pairs(faded) do if saved == owner then faded[region] = nil end end
        end,
    },
    ItemTooltipCard = {
        TypeStyle = function(kind) assert(kind == "loot") return style end,
        MatchesLootSurface = function() return surfaceMode == "match" or surfaceMode == "auto" and style == "custom" end,
        CreateBacking = function(row)
            assert(not backings[row], "recycled row recreated its fill")
            backings[row] = Widget()
            return backings[row]
        end,
        SetUnifiedHeader = function(card, enabled) card.unified = enabled end,
        Create = function(row, detached)
            assert(detached, "Forever loot frame construction entered native gamepad discovery")
            art[row] = { frame = Widget() }
            return art[row]
        end,
        ReadItem = function() return 132905, "Cloth", "Item level 30" end,
        Draw = function(card, name, icon, kind, level, _, height)
            assert(icon == nil and height == 42, "the card replaced the native item widget or overflowed its row")
            card.name, card.kind, card.level = name, kind, level
        end,
        CreateOutline = function() return { frame = Widget() } end,
        PaintOutline = function(outline) outline.frame.shown = border end,
    },
    Registry = { AddListener = function(_, callback) listener = callback end },
}
assert(loadfile(rootPath .. "/MSUF_Suite_Skin/Adapters/LootTooltipRows.lua"))("MSUF_Suite_Skin", ns)
local adapter = ns.LootTooltipRows
adapter.Apply(window, "test")
assert(not next(callbacks) and not next(art), "stock loot allocated or painted a card")
style = "custom"
listener(nil, "tooltipStyle")
assert(art[item].frame:IsShown() and art[item].kind == "Cloth" and art[item].level == "Item level 30")
assert(item.Item.Click() == 1 and item.Item.GetCount() == 2 and not art[money] and faded[item.Text] and faded[item.BorderFrame])
assert(backings[item] and backings[item]:IsShown() and art[item].unified and faded[item.NameFrame] and not backings[money],
    "matched Loot must draw one fill behind the entire item row")
item.Text.name = "Fresh Cloth"
hooks.OnEvent(window, "LOOT_SLOT_CHANGED", 1)
assert(art[item].name == "Fresh Cloth" and reads == 2, "native slot updates did not repaint the changed row")
border = false
listener(nil, "tooltipStyle")
assert(not faded[item.BorderFrame] and faded[item.Text], "native border option did not restore the native stroke")
callbacks.Release(item)
assert(not art[item].frame:IsShown() and not next(faded))
item.kind = Enum.LootSlotType.Currency
callbacks.Init(item)
assert(not art[item].frame:IsShown(), "a recycled currency row displayed the prior item")
item.kind = Enum.LootSlotType.Item
callbacks.Init(item)
assert(art[item].frame:IsShown() and faded[item.Text])
style, surfaceMode = "suite", "match"
local readCount = reads
listener(nil, "tooltipStyle")
assert(backings[item]:IsShown() and not art[item].frame:IsShown() and faded[item.NameFrame] and not faded[item.Text]
    and not faded[item.QualityText] and reads == readCount, "stock layout cannot use the shared fill without activating the extension")
surfaceMode = "native"
listener(nil, "tooltipStyle")
assert(not backings[item]:IsShown() and not faded[item.NameFrame] and not next(callbacks), "native surface was not restored")
style = "custom"
listener(nil, "tooltipStyle")
assert(art[item].frame:IsShown() and not art[item].unified and not faded[item.NameFrame], "custom layout could not keep its own look")
adapter.Disable("test")
assert(not next(faded) and not next(callbacks) and not art[item].frame:IsShown())
print("loot tooltip rows: native controls, built-in style, custom layout, live updates, recycle and restore passed")
