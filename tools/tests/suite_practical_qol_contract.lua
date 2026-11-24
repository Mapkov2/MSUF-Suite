local root = assert(arg[1])
local inventory = dofile(root .. "/tools/tests/suite_inventory_tools_fixture.lua")
local function Field(owner, key) return owner and owner[key] end

local function Restock(forever)
    local env = inventory.New(root, forever)
    env.NS.Safety = { Field = Field }
    local supply, price, money, merchant = 50, 100, 10000, "vendor"
    local purchased = {}
    MerchantFrame = env.S.CreateFrame("Frame")
    MerchantFrame.selectedTab = 1
    UnitGUID = function(unit) return unit == "npc" and merchant or "player" end
    canaccesstable = function() return true end
    GetMoney = function() return money end
    GetMerchantItemID = function(index) if index == 1 then return 12 end end
    GetMerchantItemMaxStack = function() return 20 end
    C_MerchantFrame = { GetItemInfo = function()
        return { stackCount = 10, price = price, numAvailable = supply, isPurchasable = true, hasExtendedCost = false }
    end }
    C_Item.GetItemCount = function() return env.bags[0][1].stackCount end
    C_Item.GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, 20 end
    C_Item.GetItemFamily = function() return 0 end
    C_Container.GetContainerNumFreeSlots = function() return env.free, 0 end
    BuyMerchantItem = function(index, quantity) purchased[#purchased + 1] = { index, quantity } end
    env.S.MoneyText = tostring
    env.S.Confirm = function(_, data) env.confirm = data end
    local modules = { NS = env.NS, Suite = env.S }
    env.S.InventoryData = { Bags = function() return {}, {}, true end }
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/RestockPurchase.lua"))("Test", modules)
    local purchase = modules.RestockPurchase
    local owner = { active = true, config = {}, context = {
        After = function() end, Cancel = function() end,
        Event = function(_, event, callback) assert(event == "PLAYER_MONEY"); env.debit = callback end,
        RemoveEvent = function() env.debit = nil end,
    } }
    local row = { key = 1, itemID = 12, name = "Arrows", missing = 31, goldOffer = true }
    env:Item(0, 1, 12, 9)

    purchase.Confirm(owner, row)
    assert(#purchased == 0 and env.confirm.text_arg1 == "Buy 40 × Arrows for 400?", "confirm the rounded quantity and full cost")
    env.confirm.callback()
    assert(#purchased == 1 and purchased[1][2] == 20, "one capped purchase at a time")
    purchase.Delivered(owner)
    assert(#purchased == 1, "unrelated bags update is not acceptance")
    env:Item(0, 1, 12, 29)
    purchase.Delivered(owner)
    assert(#purchased == 1, "a matching quantity without a debit must not queue another buy")
    money = money - 200
    env.debit(owner)
    assert(#purchased == 2 and purchased[2][2] == 20, "matching items and debit unlock the next purchase")
    money = money - 200
    env.debit(owner)
    assert(owner.purchase, "a debit before item delivery must wait")
    env:Item(0, 1, 12, 49)
    purchase.Delivered(owner)
    assert(#purchased == 2 and not owner.purchase, "no more requests after the confirmed order")

    purchase.Confirm(owner, row)
    merchant = "different vendor"
    env.confirm.callback()
    assert(#purchased == 2 and not owner.purchase, "different vendor cannot inherit a confirmation")
    purchase.Confirm(owner, row)
    price = 150
    env.confirm.callback()
    assert(#purchased == 2 and not owner.purchase, "different price requires a new confirmation")
    purchase.Confirm(owner, row)
    env.combat = true
    env.confirm.callback()
    assert(#purchased == 2 and not owner.purchase, "combat cannot spend")
    env.combat, env.confirm, env.free = false, nil, 0
    purchase.Confirm(owner, row)
    assert(not env.confirm and #purchased == 2, "insufficient bag space avoids a partial purchase")
end

local function Receipts(forever)
    local env = inventory.New(root, forever)
    env.NS.Safety = { IsForbidden = function() return false end }
    local capture
    hooksecurefunc = function(name, callback)
        assert(name == "SendMail" and not capture, "hook mail sends once across enable calls")
        capture = callback
    end
    GetSendMailMoney = function() return 14 end
    GetSendMailCOD = function() return 0 end
    local mailbox = MailFrame
    MailFrame = nil
    env:Load("MSUF_Suite_QualityOfLife/MailReceipts.lua")
    local module = env:Start("mailReceipts", {})
    assert(not module.mailOpen and not module.button, "activation works before the mailbox exists")

    MailFrame = mailbox
    MailFrame:Show()
    env:Emit(module, "MAIL_SHOW")
    local button = assert(module.button)
    assert(module.mailOpen and button:IsShown() and button.parent == mailbox, "opening the mailbox shows its receipts button")
    module:Disable()
    assert(not module.mailOpen and not button:IsShown(), "disabling hides the receipts button")
    env:Start("mailReceipts", {})
    assert(module.mailOpen and module.button == button and button:IsShown(), "re-enable while the mailbox is already open")

    env.attachments[1] = { id = 12, count = 4 }
    capture("Beta")
    env:Emit(module, "MAIL_FAILED")
    env:Emit(module, "MAIL_SEND_SUCCESS")
    assert(not env.NS.RootDB.suiteSentMail, "failed send must never become a receipt")
    capture("Beta")
    env:Emit(module, "MAIL_SEND_SUCCESS")
    env:Emit(module, "MAIL_SEND_SUCCESS")
    local entries = env.NS.RootDB.suiteSentMail[env.guid]
    assert(#entries == 1 and entries[1].recipient == "Beta" and entries[1].gold == 14)
    assert(entries[1].items[1] == "4 × Item", "attach the original quantity to a single receipt")
    capture(env.secret)
    env:Emit(module, "MAIL_SEND_SUCCESS")
    assert(#entries == 1, "do not display or persist restricted recipient data")
    capture("Stale recipient")
    env.combat = true
    capture("Different recipient")
    env.combat = false
    env:Emit(module, "MAIL_SEND_SUCCESS")
    assert(#entries == 1, "an unreadable send must discard the preceding capture")
    for index = 1, 40 do
        capture("Alt " .. index)
        env:Emit(module, "MAIL_SEND_SUCCESS")
    end
    assert(#entries == 30 and entries[1].recipient == "Alt 40", "keep a bounded newest-first history")
end


local function DialogKeys()
    local env = inventory.New(root, false)
    local bindings, attrs = {}, {}
    local create = env.S.CreateFrame
    local function Frame(kind, name, parent)
        local frame = create(kind, name, parent)
        frame.name = name
        frame.GetName = function(self) return self.name end
        frame.SetAttribute = function(self, key, value)
            if name then attrs[name] = attrs[name] or {}; attrs[name][key] = value end
        end
        frame.IsVisible = function(self) return self.shown end
        frame.IsEnabled = function() return true end
        frame.IsObjectType = function(self, expected) return self.kind == expected end
        frame.GetTop = function(self) return self.y or 100 end
        frame.GetLeft = function() return 0 end
        frame.ClearAllPoints = function() end
        frame.HookScript = frame.SetScript
        return frame
    end
    env.S.CreateFrame, env.S.CreateFontString = Frame, Frame
    env.S.GamepadUI = function() return false end
    env.NS.Safety = { Field = Field, IsForbidden = function() return false end }
    UIParent = Frame("Frame")
    QuestFrame, GossipFrame = Frame("Frame"), Frame("Frame")
    QuestFrame:Hide()
    local first, second = Frame("Button"), Frame("Button")
    first.y, second.y = 100, 80
    local scroll = {
        ForEachFrame = function(_, visit)
            visit(second, { index = 2, buttonType = "Option", info = {} })
            visit(first, { index = 1, buttonType = "Option", info = {} })
        end,
        RegisterCallback = function() end,
        UnregisterCallback = function() end,
    }
    GossipFrame.GreetingPanel = { ScrollBox = scroll }
    ScrollBoxListMixin = { Event = { OnUpdate = "update" } }
    local hooks = {}
    hooksecurefunc = function(name, callback) hooks[name] = callback end
    SecureHandlerWrapScript = function() end
    SecureHandlerSetFrameRef = function() end
    RegisterStateDriver = function() end
    ClearOverrideBindings = function() bindings = {} end
    SetOverrideBindingClick = function(_, _, key, target) bindings[key] = target end
    GetBindingKey = function() end
    local focus
    GetCurrentKeyBoardFocus = function() return focus end

    env:Load("MSUF_Suite_QualityOfLife/DialogKeys.lua")
    local keys = env:Start("dialogKeys", { useSpace = true, numberChoices = true })
    assert(attrs[bindings.SPACE].clickbutton1 == first, "advance delegates to the visible first native row")
    assert(attrs[bindings["1"]].clickbutton1 == first and attrs[bindings["2"]].clickbutton1 == second,
        "number keys follow the rendered row order")
    focus = Frame("EditBox")
    env:Emit(keys, "UPDATE_BINDINGS")
    assert(not bindings.SPACE and not bindings["1"], "input focus releases quest bindings")
    focus = nil
    env:Emit(keys, "GOSSIP_SHOW")
    assert(bindings.SPACE, "reopening grants the keys")
    GossipFrame:Hide()
    env:Emit(keys, "GOSSIP_CLOSED")
    assert(not bindings.SPACE and not attrs.MSUFSuiteQuestContinue.clickbutton1, "hide clears delegates")

    QuestFrame:Show()
    QuestFrameRewardPanel, QuestFrameCompleteQuestButton = Frame("Frame"), Frame("Button")
    QuestInfoFrame, QuestInfoRewardsFrame = { itemChoice = 0 }, { RewardButtons = { first, second } }
    first.type, second.type = "choice", "choice"
    GetNumQuestChoices = function() return 2 end
    env:Emit(keys, "QUEST_COMPLETE")
    assert(not bindings.SPACE and bindings["1"], "choose a reward before offering to complete the quest")
    QuestInfoFrame.itemChoice = 1
    hooks.QuestInfoItem_OnClick()
    assert(attrs[bindings.SPACE].clickbutton1 == QuestFrameCompleteQuestButton,
        "choosing the reward immediately enables keyboard completion")
end


local function BagDetails(forever)
    local env = inventory.New(root, forever)
    local create = env.S.CreateTexture
    env.S.CreateTexture = function(...)
        local texture = create(...)
        texture.SetAtlas = function(self, atlas) self.atlas = atlas end
        return texture
    end
    env.NS.Safety = { Field = Field }
    env.NS.BagsSort, env.NS.BagsView, env.NS.BagsBankView = { ITEM_LEVEL = 1 }, {}, {}
    local post
    Enum.TooltipDataType = { Item = 1 }
    TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) post = fn end }
    C_PetInfo = { CanPetEatItem = function(id) return id == 601 end }
    C_Item.GetItemUpgradeInfo = function()
        return { currentLevel = 2, maxLevel = 6, maxItemLevel = 255, trackString = "Champion" }
    end
    local config = { showPetFood = forever, showUpgradeTrack = not forever, upgradeTextSize = 9 }
    local private = { NS = env.NS, Suite = env.S, BagsModule = { active = true, config = config },
        SlotCache = { KEY = 200 } }
    assert(loadfile(root .. "/MSUF_Suite_Bags/InventoryDetails.lua"))("Test", private)
    local details = private.InventoryDetails
    local item = { itemID = 601, bag = 0, slot = 1, equipLoc = not forever and "INVTYPE_HEAD" or nil, link = "link" }
    details.Index({ items = { item } }, "")
    assert(item.petFood == (forever and true or nil))
    assert(item.upgradeCap == (not forever and 255 or nil))
    local button = env.S.CreateFrame("Button")
    details.Paint(button, item, "font")
    local lines = {}
    GameTooltip = { GetOwner = function() return button end, AddLine = function(_, line) lines[#lines + 1] = line end }
    post(GameTooltip)
    if forever then
        assert(lines[1] == "Your pet can eat this", "food marker should explain its meaning")
        assert(details.overlays[button].petFood.atlas == "UI-PetHappiness")
    else
        assert(lines[2] == "Maximum item level: 255", "bag tooltip exposes Blizzard's upgrade cap")
    end
end


local function BonusRoll()
    local env = inventory.New(root, false)
    env.NS.Safety = { Field = Field }
    local create = env.S.CreateFrame
    local function Frame(...)
        local frame = create(...)
        frame.attrs = {}
        frame.SetAttribute = function(self, key, value) self.attrs[key] = value end
        frame.SetFrameLevel = function() end
        frame.GetFrameLevel = function() return 5 end
        frame.GetFrameStrata = function() return "DIALOG" end
        frame.EnableMouse = function() end
        frame.IsVisible = function(self) return self.shown end
        frame.IsEnabled = function(self) return self.enabled ~= false end
        frame.HookScript = frame.SetScript
        frame.UnregisterEvent = function(self, event) self.events[event] = nil end
        return frame
    end
    env.S.CreateFrame = Frame
    local prompt = Frame("Frame")
    prompt.RollButton, prompt.PassButton = Frame("Button"), Frame("Button")
    BonusRollFrame = { PromptFrame = prompt }
    RegisterStateDriver = function(_, state, driver)
        assert(state == "visibility" and driver:find("[combat]", 1, true), "the overlay drops out during combat")
    end
    GameTooltip = { IsOwned = function() return false end }
    hooksecurefunc = function() end
    env:Load("MSUF_Suite_QualityOfLife/BonusRollConfirm.lua")
    local guard = env:Start("bonusRollConfirm", {})
    assert(guard.rollOverlay.attrs["shift-clickbutton1"] == prompt.RollButton)
    assert(guard.passOverlay.attrs["shift-clickbutton1"] == prompt.PassButton)
    assert(not guard.rollOverlay.attrs.type1 and not guard.passOverlay.attrs.type1,
        "an ordinary click cannot dispatch Roll or Pass")
    prompt:Hide()
    assert(not guard.container.shown, "closing the native prompt removes its overlays")
    prompt:Show()
    guard:Refresh()
    env.combat, guard.active = true, false
    guard:Disable()
    assert(guard.cleanup and guard.cleanup.events.PLAYER_REGEN_ENABLED, "protected cleanup survives module disable")
    env.combat = false
    guard.cleanup.scripts.OnEvent(guard.cleanup, "PLAYER_REGEN_ENABLED")
    assert(not guard.container.shown, "disabled overlays cannot return after combat")
end


local function SelfBuffKey()
    local env = inventory.New(root, false)
    local create = env.S.CreateFrame
    env.S.CreateFrame = function(...)
        local frame = create(...)
        frame.attrs = {}
        frame.SetAttribute = function(self, key, value) self.attrs[key] = value end
        frame.GetAttribute = function(self, key) return self.attrs[key] end
        return frame
    end
    RegisterStateDriver = function() end
    local api = { SyncCursor = function() end }
    local private = { NS = env.NS, Suite = env.S, BuffReminders = api }
    assert(loadfile(root .. "/MSUF_Suite_BuffReminders/Special.lua"))("Test", private)
    api.StyleNotices = function() end
    local entries = {
        { id = 10, kind = "spell", present = false, ally = true },
        { id = 11, kind = "spell", present = false, group = true },
        { id = 12, kind = "spell", present = nil },
        { id = 13, kind = "spell", present = false },
        { id = 14, kind = "spell", present = false },
    }
    local owner = { config = { selfBuffKey = true }, view = { allowed = true }, list = { entries = entries } }
    api.RefreshSpecialControls(owner)
    owner.view.afterUpdate(owner)
    local attrs = owner.view.selfBuffButton.attrs
    assert(attrs.spell1 == 13 and attrs.unit == "player" and attrs.type1 == "spell",
        "choose the first definitely missing self spell and omit allies and unreadable buffs")
    entries[4].present = true
    owner.view.afterUpdate(owner)
    assert(attrs.spell1 == 14, "after the first buff is cast, select the next")
    local handle = owner.view.selfBuffButton
    setfenv(assert(loadstring(attrs["_onstate-msufbuff"])), { self = handle, newstate = "blocked" })()
    assert(not attrs.type1, "combat clears the secure action")
    entries[5].present = true
    owner.view.afterUpdate(owner)
    assert(not attrs.spell1 and not attrs.type1, "all present leaves the binding inert")
end

Restock(false)
Restock(true)
Receipts(false)
Receipts(true)
DialogKeys()
BagDetails(false)
BagDetails(true)
BonusRoll()
SelfBuffKey()
print("practical QoL: restock, sent mail, dialogue keys, bags, bonus roll and self-buff key passed")
