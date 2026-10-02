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

------------------------------------------------------------------ cards
-- The palette alpha of each module card's fill and frame lines, as each
-- module has always drawn them. Stripes and accent lines are opaque.
local CARD_ALPHA = {
    battleRes = { fill = .92, lines = .95 },
    durabilityAlert = { fill = .92, lines = .9 },
    groupBloodlust = { fill = .92, lines = .95 },
    innervateCue = { fill = .94 },
    combatMovementCue = { fill = .92 },
    combatPetStatus = { fill = .91 },
    loadoutReminder = { fill = .94 },
    mapLandingShortcuts = { fill = .95 },
}

-- A card of a QoL module: a frame on UIParent (spec.kind, else a Frame)
-- above the game world, without the mouse unless spec.mouse, of spec.width
-- by spec.height when given. Its BACKGROUND fill covers it; its BORDER lines
-- are four, a frame spec.edge pixels wide, or one down its left side,
-- spec.stripe pixels wide. spec.fill and spec.line ({ r, g, b, a }) color
-- them until the module paints its palette (S.PaintQoLCard). Returns the
-- host, the fill and the lines (the four, or the stripe).
local function FrameLines(host, spec)
    local lines = {}
    for i = 1, 4 do lines[i] = S.CreateTexture(host, nil, "BORDER") end
    local line = spec.line
    S.PlaceEdges(lines, host, spec.edge, line[1], line[2], line[3], line[4])
    return lines
end

local function Stripe(host, spec)
    local stripe = S.CreateTexture(host, nil, "BORDER")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(spec.stripe)
    if spec.line then stripe:SetColorTexture(unpack(spec.line)) end
    return stripe
end

function S.QoLCard(spec)
    local host = S.CreateFrame(spec.kind or "Frame", nil, UIParent)
    if spec.width then host:SetSize(spec.width, spec.height) end
    host:SetFrameStrata("HIGH")
    host:EnableMouse(spec.mouse == true)
    local fill = S.CreateTexture(host, nil, "BACKGROUND")
    fill:SetAllPoints(host)
    fill:SetColorTexture(unpack(spec.fill))
    local lines = spec.edge and FrameLines(host, spec) or Stripe(host, spec)
    return host, fill, lines
end

-- Paints the fill and, where the module's alphas name them, the four frame
-- lines in the module's palette; returns the palette for the rest.
function S.PaintQoLCard(id, config, fill, lines)
    local style, alpha = S.QoLStyle(config), CARD_ALPHA[id]
    S.QoLColor(fill, style.background, alpha.fill)
    if alpha.lines then
        for i = 1, #lines do S.QoLColor(lines[i], style.border, alpha.lines) end
    end
    return style
end

-- Places a Suite-owned surface on UIParent from its settings: the same
-- anchor point of both (config.point, an index into the Suite's anchor
-- points, else fallback or CENTER) at config.x and config.y, at
-- config.scale percent. Returns that point.
function S.PlaceHost(host, config, fallback)
    local point = suite.AnchorPoints[config.point] or fallback or "CENTER"
    host:ClearAllPoints()
    host:SetPoint(point, UIParent, point, config.x, config.y)
    host:SetScale(config.scale / 100)
    return point
end

-- S.QoLLabel, S.QoLWindow and the copy dialog live in the shared runtime
-- (MSUF_Suite_Modules/Dialogs.lua): the Chat addon uses them too.

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
