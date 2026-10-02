local _, private = ...
local suite = assert(_G.MSUFSuite, 'MSUF_Suite is required')
private.NS, private.Suite = suite, suite.Suite
local S = private.Suite

-- Pure palette lookup for Suite-owned QoL surfaces. Semantic warning/status
-- colors remain with their modules.
function S.QoLStyle(config)
    local looks = suite.QoLVisualStyles
    return looks[config and config.look] or looks[1]
end

-- A shared palette by its index, for modules whose look choices are not
-- numbered like the palettes (a Custom entry before Class Style).
function S.QoLPalette(index)
    local looks = suite.QoLVisualStyles
    return looks[index] or looks[1]
end

function S.QoLColor(region, hex, alpha)
    local r, g, b = S.RGB(hex)
    region:SetColorTexture(r, g, b, alpha or 1)
end

-- Text in a Suite-owned QoL window; text is English source text.
function S.QoLLabel(parent, text, size)
    local label = S.CreateFontString(parent, nil, "ARTWORK")
    S.SetFont(label, nil, size or 12, "")
    label:SetText(S.Text(text))
    return label
end

-- A movable Suite-owned window with a title, a drag strip and a close button.
function S.QoLWindow(width, height, title, titleSize)
    local panel = S.CreateFrame("Frame", nil, UIParent)
    panel:SetSize(width, height)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    local background = S.CreateTexture(panel, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.065, .075, .085, .97)
    local accent = S.CreateTexture(panel, nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(.8, .68, .42, 1)
    local drag = S.CreateFrame("Button", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", -32, 0)
    drag:SetHeight(38)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    local close = S.CreateFrame("Button", nil, panel)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -7, -7)
    S.QoLLabel(close, "X", 13):SetPoint("CENTER")
    close:SetScript("OnClick", function() panel:Hide() end)
    S.QoLLabel(panel, title, titleSize or 14):SetPoint("TOPLEFT", 14, -12)
    return panel
end

-- A movable window with one edit box for text the player copies with Ctrl+C:
-- C_OS.CopyToClipboard is restricted, so the text is only selected.
function S.QoLCopyDialog(title, hint, width)
    local panel = S.QoLWindow(width, 104, title)
    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetSize(width - 54, 25)
    edit:SetPoint("TOP", panel, "TOP", 0, -45)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() panel:Hide() end)
    panel.edit = edit
    S.QoLLabel(panel, hint, 11):SetPoint("BOTTOM", 0, 9)
    panel:Hide()
    return panel
end

function S.QoLShowCopy(panel, text)
    panel.edit:SetText(text)
    panel:Show()
    panel.edit:SetFocus()
    panel.edit:HighlightText()
end

function S.QoLClearCopy(panel)
    panel:Hide()
    panel.edit:ClearFocus()
    panel.edit:SetText("")
end

-- A restricted client action (using a bag item, cancelling an aura). The
-- client refuses one with ADDON_ACTION_BLOCKED or ADDON_ACTION_FORBIDDEN
-- instead of a Lua error; both events fire while the call runs. True when the
-- call returned without a refusal; a call that raises is reported.
-- Blizzard answers a refusal with its own notice (the interface-action
-- message or the ADDON_ACTION_FORBIDDEN popup), so callers check the known
-- restriction states first and stop after one refusal.
-- Calls nest (an action may run another restricted call): every level sees
-- the refusals made while it ran, inner ones included, and the watch stays
-- registered until the outermost call returns.
local refusalWatch, depth, refused = nil, 0, false
local function Refused()
    if depth > 0 then refused = true end
end

function S.QoLRestrictedCall(action, ...)
    if not refusalWatch then
        refusalWatch = S.CreateFrame("Frame")
        refusalWatch:SetScript("OnEvent", Refused)
    end
    if depth == 0 then
        refusalWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
        refusalWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    end
    local outer = refused
    depth, refused = depth + 1, false
    local ok = S.Dispatch(suite.Finish, action, ...)
    local mine = refused
    depth, refused = depth - 1, outer or mine
    if depth == 0 then
        refused = false
        refusalWatch:UnregisterEvent("ADDON_ACTION_BLOCKED")
        refusalWatch:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
    end
    return ok == true and not mine
end

-- Windows that give C_Container.UseContainerItem another meaning (sell,
-- deposit, attach, trade, post, socket, upgrade, scrap, insert): Blizzard's
-- own list in ContainerFrameItemButton_OnClick (ContainerFrame.lua) plus the
-- scrapper, item interaction and socket windows. Load-on-demand windows exist
-- only once Blizzard loaded them.
local ITEM_USE_WINDOWS = {
    "MerchantFrame", "BankFrame", "GuildBankFrame", "MailFrame", "TradeFrame", "AuctionHouseFrame",
    "ItemUpgradeFrame", "ObliterumForgeFrame", "ChallengesKeystoneFrame", "AzeriteRespecFrame",
    "RuneforgeFrame", "ScrappingMachineFrame", "ItemInteractionFrame", "ItemSocketingFrame",
}

-- The name of the first such window that is open, leaving out except.
function S.QoLItemUseWindow(except)
    for i = 1, #ITEM_USE_WINDOWS do
        local name = ITEM_USE_WINDOWS[i]
        local frame = name ~= except and _G[name]
        if frame and frame:IsShown() then return name end
    end
end

-- The content a per-zone switch refers to: "world", "party" (dungeons,
-- scenarios and delves), "raid" or "pvp" (battlegrounds and arenas); nil
-- while the instance state is unreadable or of another kind.
local INSTANCE_KINDS = { party = "party", scenario = "party", raid = "raid", pvp = "pvp", arena = "pvp" }
function S.InstanceKind()
    local inside, kind = IsInInstance()
    if not S.Public(inside) or not S.Public(kind) then return nil end
    if inside ~= true then return "world" end
    return INSTANCE_KINDS[kind]
end
