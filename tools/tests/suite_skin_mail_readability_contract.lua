-- The dark mail panels theme the native text in place. The receiving body
-- is SimpleHTML, the composer is an EditBox and invoices have FontStrings.
local root = assert(arg[1], "Suite root required") .. "/MSUF_Suite_Skin/"
local original = { 0.27, 0.16, 0.04, 1 }
local theme = { 0.94, 0.95, 0.97, 1 }
local faded, surfaced = {}, {}
local secretBody = {}
issecretvalue = function(value) return value == secretBody end
local NS = {
    DB = { skinCategories = { social = true, economy = false } },
    IsCombatLocked = function() return false end,
    L = { ["No message text."] = "Localized empty message." },
    Theme = { GetColor = function(role)
        if role == "muted" then return 0.7, 0.7, 0.7, 1 end
        assert(role == "text", "mail text should use the theme's text role")
        return unpack(theme)
    end },
    Cosmetics = {
        Fade = function(region)
            faded[region] = true
            return true
        end,
        RestoreOwner = function() end,
    },
    Surface = {
        SetVisible = function() end,
        Attach = function(frame, spec)
            surfaced[frame] = spec
            return {}
        end,
    },
    ControlSkin = { DisableOwner = function() end },
}

securecallfunction = function(callback, ...) return callback(...) end
hooksecurefunc = function(target, method, hook)
    if type(target) == "string" then
        target, method, hook = _G, target, method
    end
    local originalMethod = assert(target[method])
    target[method] = function(...)
        originalMethod(...)
        hook(...)
    end
end
for _, file in ipairs({ "Core/Safety.lua", "Adapters/AdapterKit.lua", "Adapters/Commerce.lua" }) do
    assert(loadfile(root .. file))("MSUF_Suite_Skin", NS)
end

local function FontString()
    local text = { color = original }
    function text:GetObjectType() return "FontString" end
    function text:GetTextColor() return unpack(self.color) end
    function text:SetTextColor(...) self.color = { ... } end
    return text
end

local function LabelFrame()
    local label = FontString()
    local texture = { GetObjectType = function() return "Texture" end }
    local frame = { shown = false, GetRegions = function() return label, texture end }
    function frame:IsShown() return self.shown end
    return frame, label
end

local function CheckColor(text, expected, message, selector)
    local r, g, b, a = text:GetTextColor(selector)
    assert(r == expected[1] and g == expected[2] and b == expected[3] and a == expected[4], message)
end

local mailBody = { color = original, text = "A letter with an |Hitem:2589|h[item]|h." }
OpenMailBodyText = mailBody
function mailBody:GetTextColor(selector)
    assert(selector == "P", "SimpleHTML needs its paragraph selector")
    return unpack(self.color)
end
function mailBody:SetTextColor(selector, ...)
    assert(selector == "P", "SimpleHTML needs its paragraph selector")
    self.color = { ... }
end
function mailBody:SetText(text)
    self.text = text
end

SendMailBodyEditBox = FontString()
SendStationeryBackgroundLeft = {}
OpenStationeryBackgroundLeft = {}
SendMailScrollFrame = {}
OpenMailScrollFrame = {}

local invoice, invoiceLabel = LabelFrame()
local deposit, depositSign = LabelFrame()
local cut, cutSign = LabelFrame()
local sale, saleCount = LabelFrame()
local consortium, consortiumLabel = LabelFrame()
local commission, commissionLabel = LabelFrame()
local commissionMoney, commissionSign = LabelFrame()
local semanticAmount = FontString()
semanticAmount:SetTextColor(1, 0.1, 0.1, 1)
cut.GetChildren = function() return semanticAmount end
consortium.CommissionPaidDisplay = commission
commission.MoneyDisplayFrame = commissionMoney
OpenMailInvoiceFrame = invoice
OpenMailDepositMoneyFrame = deposit
OpenMailHouseCutMoneyFrame = cut
OpenMailSalePriceMoneyFrame = sale
ConsortiumMailFrame = consortium

local hint = { writes = 0 }
function hint:SetPoint() end
function hint:SetAlpha(alpha)
    self.alpha = alpha
    self.writes = self.writes + 1
end
function hint:SetText(text) self.text = text end
function hint:SetTextColor() end
OpenMailScrollChildFrame = { CreateFontString = function() return hint end }

local body, isInvoice, isConsortium
local function NativeUpdate()
    mailBody:SetText(body, true)
    invoice.shown = isInvoice
    consortium.shown = isConsortium
end
local forever = arg[2] == "forever"
if forever then
    OpenMailFrame = { Update = NativeUpdate }
else
    OpenMail_Update = NativeUpdate
end
local function OpenMail(text, invoiceShown, consortiumShown)
    body, isInvoice, isConsortium = text, invoiceShown == true, consortiumShown == true
    if forever then OpenMailFrame:Update() else OpenMail_Update() end
end

local colors = { SendMailBodyEditBox, invoiceLabel, depositSign, cutSign, saleCount,
    consortiumLabel, commissionLabel, commissionSign }
local bodyText = mailBody.text
local function CheckMailColors(expected)
    CheckColor(mailBody, expected, "received mail has the wrong text color", "P")
    for _, label in ipairs(colors) do
        CheckColor(label, expected, "mail label or composer has the wrong text color")
    end
    CheckColor(semanticAmount, { 1, 0.1, 0.1, 1 }, "mail skin recolored a semantic amount")
    assert(mailBody.text == bodyText, "mail skin changed the message text")
end

assert(NS.Commerce.Apply(), "mail skin was not applied")
CheckMailColors(theme)
assert(faded[SendStationeryBackgroundLeft] and faded[OpenStationeryBackgroundLeft]
    and surfaced[SendMailScrollFrame] and surfaced[OpenMailScrollFrame],
    "mail skin did not retain the themed mail surfaces")
assert(surfaced[SendMailScrollFrame].opaqueFill and surfaced[OpenMailScrollFrame].opaqueFill
    and surfaced[OpenMailScrollFrame].keepGlassFill,
    "mail text panes do not request an opaque reading background")

theme = { 0.90, 0.92, 0.86, 1 }
NS.Commerce.Apply()
CheckMailColors(theme)

NS.DB.skinCategories.social = false
NS.Commerce.Apply()
CheckMailColors(original)
NS.DB.skinCategories.social = true
NS.Commerce.Apply()
CheckMailColors(theme)

assert(hint.text == "Localized empty message.", "the empty state did not use the localized label")
OpenMail(nil)
assert(hint.alpha == 1 and mailBody.text == nil, "attachment-only mail does not show an empty state")
local writes = hint.writes
OpenMail("")
assert(hint.writes == writes, "unchanged empty state repainted its alpha")
OpenMail(nil, true)
assert(hint.alpha == 0, "empty-state text covers an auction invoice")
OpenMail("   ")
assert(hint.alpha == 1, "switching from an invoice to empty mail kept the hint hidden")
OpenMail(nil, false, true)
assert(hint.alpha == 0, "empty-state text covers a crafting order")
OpenMail("Hello!")
assert(hint.alpha == 0 and mailBody.text == "Hello!", "normal mail is obscured or rewritten")
OpenMail(secretBody)
assert(hint.alpha == 0, "a secret body was treated as empty")
OpenMail(nil)
NS.DB.skinCategories.social = false
NS.Commerce.Apply()
writes = hint.writes
OpenMail(nil)
assert(hint.alpha == 0 and hint.writes == writes, "a disabled mail skin keeps updating the empty state")
print("Suite mail readability contract passed (" .. (forever and "Forever" or "Retail") .. ")")
