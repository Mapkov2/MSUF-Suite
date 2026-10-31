local F = {}
function F.DisabledProtection(root, NS, S)
    local install = S.Install
    S.Install = function(id, module) assert(id == "inventoryProtection"); module.active = false end
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/InventoryProtection.lua"))("Test", { NS = NS, Suite = S })
    S.Install = install
end
function F.New(root, forever)
    local E = { combat = false, now = 1000, guid = "player-a", name = "Alpha", region = "EU", bags = {},
        bankType = 1, free = 8, writes = {}, attachments = {}, sets = {}, frames = {}, timers = {}, events = {},
        calls = { scan = 0 }, cursor = nil, recipes = {}, schematics = {}, hardware = false }
    E.secret = setmetatable({}, { __tostring = function() error("secret formatted") end })
    local S = { instances = {}, Text = function(v) assert(type(v) == "string"); return v end }
    S.Public = function(v) return v ~= E.secret end
    S.Finite = function(v) return v ~= E.secret and type(v) == "number" and v == v and v > -math.huge and v < math.huge end
    S.PublicText = function(v) return v ~= E.secret and type(v) == "string" and v ~= "" and v or nil end
    local NS = { Suite = S, RootDB = {}, DB = {}, Client = { isForever = forever } }
    NS.InCombat = function() return E.combat end
    NS.IsCombatLocked = NS.InCombat
    NS.Print = function(text) E.message = text end
    E.NS, E.S = NS, S
    local methods = {}
    local function Frame(kind, _, parent, template)
        local f = setmetatable({ scripts = {}, shown = true, parent = parent, kind = kind, events = {} }, { __index = methods })
        E.frames[#E.frames + 1] = f
        if template == "InputBoxInstructionsTemplate" then f.Instructions = Frame("FontString") end
        return f
    end
    for _, key in ipairs({ "SetPoint", "SetAllPoints", "SetJustifyH", "SetWordWrap", "SetTextColor", "SetAutoFocus", "SetMaxBytes",
        "RegisterForClicks", "ClearFocus", "SetFocus", "HighlightText", "SetMultiLine", "SetColorTexture",
        "SetFrameStrata" }) do methods[key] = function() end end
    function methods:SetSize(w, h) self.width, self.height = w, h end
    function methods:SetWidth(w) self.width = w end
    function methods:SetHeight(h) self.height = h end
    function methods:GetHeight() return self.height end
    function methods:GetStringHeight() return math.ceil(#(self.text or "") / 90) * 14 end
    function methods:SetText(text) self.text = text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function methods:GetText() return self.text or "" end
    function methods:GetFontString()
        if not self.fontString then self.fontString = Frame("FontString", nil, self) end
        return self.fontString
    end
    function methods:SetTexture(value) self.texture = value end
    function methods:SetScrollChild(value) assert(value.kind == "Frame" or value.kind == "EditBox"); self.child = value end
    function methods:SetScript(event, fn) self.scripts[event] = fn end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:SetEnabled(value) self.enabled = value end
    function methods:Show() self.shown = true end
    function methods:Hide()
        local shown = self.shown
        self.shown = false
        if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:SetShown(value) if value then self:Show() else self:Hide() end end
    function methods:IsShown() return self.shown end
    function methods:Click(button)
        E.hardware = true
        if self.enabled ~= false then self.scripts.OnClick(self, button or "LeftButton") end
        E.hardware = false
    end
    S.CreateFrame, S.CreateTexture, S.CreateFontString = Frame, Frame, Frame
    S.QoLLabel = function(parent, text) local f = Frame("FontString", nil, parent); f:SetText(text); return f end
    S.QoLWindow = function(w, h)
        local f = Frame("Frame"); f:SetSize(w, h)
        f.close = { caption = Frame("FontString", nil, f) }
        return f
    end
    S.SetFont = function() end
    S.TooltipLines = { Add = function(_, _, callback) E.tooltip = callback end,
        Line = function(tooltip, label, value) tooltip[#tooltip + 1] = { label, value } end }
    S.ContextMenu = function(_, callback)
        E.menu = {}
        local menu = { CreateTitle = function() end, CreateButton = function(_, label, fn) E.menu[#E.menu + 1] = { label, fn } end }
        callback(nil, menu)
    end
    S.Install = function(id, module) S.instances[id] = module; module.id = id end
    S.Set = function(id, key, value)
        if E.combat or value == nil then return false end
        local module = S.instances[id]; module.config[key] = value; module:Refresh(); return true
    end
    S.QoLItemUseWindow = function() return E.conflict end
    S.QoLRestrictedCall = function(fn, ...) assert(E.hardware, "native item write without user click"); if E.blocked then return false end; fn(...); return true end
    _G.UnitGUID = function() return E.guid end
    _G.UnitFullName = function() return E.name, "Realm" end
    _G.GetNormalizedRealmName = function() return "Realm" end
    _G.GetCurrentRegionName = function() return E.region end
    _G.GetServerTime = function() return E.now end
    _G.date = os.date
    _G.Enum = { BankType = { Character = 1, Account = 2 }, CraftingReagentType = { Basic = 1, Modifying = 2 } }
    _G.GetCursorInfo = function() if E.cursor then return E.cursor.kind, E.cursor.id end end
    _G.CursorHasItem = function() return E.cursor ~= nil end
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_Item = {
        GetItemNameByID = function(id) return "Item " .. id end,
        GetItemGUID = function(location) local item = E.bags[location.bag] and E.bags[location.bag][location.slot]; return item and item.guid end,
        CanBeRefunded = function() return E.refundable or false end,
        IsEquippableItem = function(id) return id == 99 end,
    }
    _G.C_Container = {
        GetContainerNumSlots = function(bag) E.calls.scan = E.calls.scan + 1; return E.bags[bag] and 8 or 0 end,
        GetContainerItemInfo = function(bag, slot) return E.bags[bag] and E.bags[bag][slot] end,
        GetContainerItemQuestInfo = function() return { isQuestItem = false } end,
        GetContainerNumFreeSlots = function() return E.free end,
        UseContainerItem = function(...) E.writes[#E.writes + 1] = { "use", ... } end,
        PickupContainerItem = function(bag, slot)
            local item = E.bags[bag][slot]; E.cursor = { kind = "item", id = item.itemID, count = item.stackCount }
            E.bags[bag][slot] = nil
        end,
        SplitContainerItem = function(bag, slot, count)
            local item = E.bags[bag][slot]; item.stackCount = item.stackCount - count
            E.cursor = { kind = "item", id = item.itemID, count = count }
        end,
    }
    _G.C_Bank = { CanUseBank = function() return E.canBank ~= false end,
        FetchPurchasedBankTabData = function(kind) return { { ID = kind == 1 and 6 or 13 } } end,
        IsItemAllowedInBankType = function() return E.allowed ~= false end }
    _G.BankFrame, _G.MailFrame, _G.SendMailFrame = Frame("Frame"), Frame("Frame"), Frame("Frame")
    BankFrame:Hide(); MailFrame:Hide(); SendMailFrame:Hide()
    BankFrame.GetActiveBankType = function() return E.bankType end
    _G.SendMailNameEditBox, _G.SendMailSubjectEditBox = Frame("EditBox"), Frame("EditBox")
    _G.GetSendMailItem = function(i)
        local item = E.attachments[i]
        if item then return "Item", item.id, nil, item.count end
    end
    _G.ClickSendMailItemButton = function()
        assert(E.hardware and E.cursor, "attachment needs clicked prepared cursor")
        E.attachments[#E.attachments + 1] = E.cursor; E.cursor = nil
        E.writes[#E.writes + 1] = { "attach" }
    end
    _G.SendMail = function() error("must never send") end
    _G.C_EquipmentSet = { GetEquipmentSetIDs = function() return E.sets == E.secret and E.secret or next(E.sets) and { 1 } or {} end }
    _G.EquipmentManager_GetLocationData = function(location) return { isBags = true, bag = 0, slot = location } end
    _G.C_TradeSkillUI = { GetRecipesTracked = function(recraft) return recraft and E.recrafts or E.recipes end,
        GetRecipeSchematic = function(id, recraft) return E.schematics[recraft and -id or id] end }
    local P = { NS = NS, Suite = S }
    function E:Load(path, core) return assert(loadfile(root .. "/" .. path))("Test", core and NS or P) end
    function E:Start(id, config)
        local module = assert(S.instances[id]); module.config, module.active = config, true
        module.context = { events = {} }
        function module.context:Event(event, fn) self.events[event] = fn end
        function module.context:RemoveEvent(event) self.events[event] = nil end
        function module.context:After(_, fn) E.timers[fn] = module end
        function module.context:Cancel(fn) E.timers[fn] = nil end
        function module.context:Coalesce(_, fn)
            local job = { Request = function() E.timers[fn] = module end, Cancel = function() E.timers[fn] = nil end }
            return job
        end
        module:Enable()
        return module
    end
    function E:Flush()
        local due = E.timers; E.timers = {}
        for fn, module in pairs(due) do fn(module) end
    end
    function E:Emit(module, event, ...)
        local fn = module.context.events[event]
        if fn then fn(module, event, ...) end
    end
    function E:Click(module, fn, ...)
        self.hardware = true; local result = fn(module, ...); self.hardware = false; return result
    end
    function E:Item(bag, slot, id, count, quality)
        self.bags[bag] = self.bags[bag] or {}
        self.bags[bag][slot] = { itemID = id, stackCount = count or 1, quality = quality or 1, isLocked = false,
            isBound = false, hasNoValue = false, hasLoot = false, hyperlink = "item:" .. id, guid = bag .. ":" .. slot .. ":" .. id }
    end
    E:Load("MSUF_Suite/Core/InventoryRules.lua", true)
    E:Load("MSUF_Suite/Core/InventoryLists.lua", true)
    E:Load("MSUF_Suite_Modules/ToolListWindow.lua")
    E:Load("MSUF_Suite_QualityOfLife/SharedItems.lua")
    for _, name in ipairs({ "InventoryData", "InventoryToolsUI", "InventoryProtection", "InventoryArchive", "RestockPlanner",
        "CraftShopping", "InventoryTransfers", "MailTemplates" }) do E:Load("MSUF_Suite_QualityOfLife/" .. name .. ".lua") end
    return E
end
return F
