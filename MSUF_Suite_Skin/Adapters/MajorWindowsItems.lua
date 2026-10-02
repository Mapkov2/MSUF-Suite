local _, NS = ...

-- The Great Vault and the item-service windows of MajorWindows.lua (see its
-- header for the verified sources): Blizzard_WeeklyRewards,
-- Blizzard_ItemSocketingUI, Blizzard_ItemInteractionUI and
-- Blizzard_ItemUpgradeUI. Each skinner joins MajorWindows' groupSkinners.
local Shared = NS.MajorWindowsShared
NS.MajorWindowsShared = nil

local Field = NS.Safety.Field
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade
local FadeFields = Kit.FadeFields
local Attach = Kit.Attach
local SkinControl = Kit.SkinControl
local SurfaceSpec = Kit.SurfaceSpec

local ApplyGeneric = Shared.ApplyGeneric
local FadeNineSlice = Shared.FadeNineSlice
local PANEL, CARD, CARD_ROW, POPUP = Shared.PANEL, Shared.CARD, Shared.CARD_ROW, Shared.POPUP
local BACKGROUND_AND_BORDER = Shared.BACKGROUND_AND_BORDER

local SHELL = SurfaceSpec("shell", 8, 0)
local SMALL_CARD = SurfaceSpec("card", 5, 0)
local SOCKET = SurfaceSpec("card", 5, 0, true)
local SLOT = SurfaceSpec("card", 5, 1, true)
local PREVIEW_POPUP = SurfaceSpec("popup", 6, 0)
local FOOTER = SurfaceSpec("navigation", 5, 0)

local PRIMARY_BUTTON = {
    role = "button", activeRole = "buttonPrimary",
    radius = 5, inset = 1, pillHeight = 24,
}
local VAULT_SELECT_BUTTON = {
    role = "button", activeRole = "buttonPrimary",
    radius = 5, inset = 1, pillHeight = 24,
    regions = { "Left", "Middle", "Right", "Background" },
}
local UPGRADE_DROPDOWN = {
    role = "button", radius = 5, inset = 1, pillHeight = 24,
    regions = { "Background" },
}

local GREAT_VAULT_MODE = {
    role = "shell", maxDepth = 10, maxNodes = 1200,
    allowImplicitProtected = true,
}

local GREAT_VAULT_ART = { "Background", "BorderShadow", "Divider1", "Divider2" }
local GREAT_VAULT_BORDER_ART = { "Border", "TopDecor" }
local GREAT_VAULT_HEADER_ART = { "HeaderDivider" }
local VAULT_WARNING_ART = { "ExtraBG" }
local SOCKET_FILIGREE = { "LeftFiligree", "RightFiligree" }
local ITEM_INTERACTION_FOOTER_ART = { "BlackBorder", "ButtonBorder", "ButtonBottomBorder" }
local VAULT_TYPE_FRAMES = { "RaidFrame", "MythicFrame", "PVPFrame", "WorldFrame" }
local ITEM_SERVICE_SHELL_ART = { "Bg", "TopTileStreaks", "Portrait", "portrait" }
local ITEM_SOCKETING_ART = {
    "ParchmentFrame-Top", "ParchmentFrame-Bottom",
    "ParchmentFrame-Left", "ParchmentFrame-Right",
    "SocketFrame-Left", "SocketFrame-Right",
    "ButtonFrame-Left", "ButtonFrame-Right", "ButtonBorder-Mid",
    "GoldBorder-BottomRight", "GoldBorder-BottomLeft",
    "GoldBorder-TopRight", "GoldBorder-TopLeft",
    "GoldBorder-Left", "GoldBorder-Right",
    "GoldBorder-Top", "GoldBorder-Bottom",
    "BackgroundColor", "BackgroundHighlight",
    "BorderShadow-TopLeftCorner", "BorderShadow-TopRightCorner",
    "BorderShadow-BottomLeftCorner", "BorderShadow-BottomRightCorner",
    "BorderShadow-Top", "BorderShadow-Left",
    "BorderShadow-Bottom", "BorderShadow-Right",
    "BottomLeftNub", "BottomRightNub",
    "MiddleLeftNub", "MiddleRightNub",
    "TopLeftNub", "TopRightNub",
}
local ITEM_UPGRADE_ART = {
    "BottomBG", "BottomBGShadow", "TopBG", "IdleGlow", "MicaFleckSheen",
}
local ITEM_UPGRADE_PREVIEWS = {
    "LeftItemPreviewFrame", "RightItemPreviewFrame", "ItemHoverPreviewFrame",
}

local function SkinGreatVault(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, GREAT_VAULT_MODE)
    if not applied then return false, reason end

    FadeFields(state, root, GREAT_VAULT_ART)
    FadeFields(state, Field(root, "BorderContainer"), GREAT_VAULT_BORDER_ART)
    FadeFields(state, Field(root, "HeaderFrame"), GREAT_VAULT_HEADER_ART)

    for index = 1, #VAULT_TYPE_FRAMES do
        local typeFrame = Field(root, VAULT_TYPE_FRAMES[index])
        if typeFrame then
            Attach(state, typeFrame, PANEL)
            FadeFields(state, typeFrame, BACKGROUND_AND_BORDER)
        end
    end

    -- WeeklyRewardsMixin creates every selectable activity during OnLoad and
    -- exposes the stable list as Activities. Preserve completion icons,
    -- reward effects and item icons; replace only each card's base chrome.
    local activities = Field(root, "Activities")
    if type(activities) == "table" then
        for index = 1, #activities do
            local activity = activities[index]
            if activity then
                Attach(state, activity, CARD_ROW)
                FadeFields(state, activity, BACKGROUND_AND_BORDER)
            end
        end
    end

    SkinControl(state, Field(root, "SelectRewardButton"), VAULT_SELECT_BUTTON)

    local warning = _G.WeeklyRewardExpirationWarningDialog
    if warning then
        Attach(state, warning, POPUP)
        FadeNineSlice(state, warning)
        FadeFields(state, warning, VAULT_WARNING_ART)
    end
    return true, "applied"
end

local function SkinExactItemServiceShell(root, state)
    Attach(state, root, SHELL)
    FadeNineSlice(state, root)
    FadeFields(state, root, ITEM_SERVICE_SHELL_ART)
    Fade(state, Path(root, "PortraitContainer", "portrait"))
    Fade(state, Path(root, "PortraitContainer", "Portrait"))
end

local function SkinItemSocketing(root, state)
    SkinExactItemServiceShell(root, state)

    -- These exact fields are the parchment, gold frame, shadow and rivet
    -- layers around Blizzard's socket data. The socket Background, Icon,
    -- brackets, Shine and interaction textures remain native and visible.
    FadeFields(state, root, ITEM_SOCKETING_ART)

    local description = _G.ItemSocketingDescription
    Attach(state, description, PANEL)
    FadeNineSlice(state, description)

    local container = Field(root, "SocketingContainer")
    local sockets = Field(container, "SocketFrames")
    if type(sockets) == "table" then
        for index = 1, #sockets do
            local socket = sockets[index]
            if socket then
                Attach(state, socket, SOCKET)
                FadeFields(state, socket, SOCKET_FILIGREE)
            end
        end
    end
    SkinControl(state, Field(container, "ApplySocketsButton"), PRIMARY_BUTTON)
    return true, "applied"
end

local function SkinItemInteraction(root, state)
    SkinExactItemServiceShell(root, state)

    -- Background is the Blizzard-selected interaction texture kit. Keep it,
    -- along with conversion borders and celebration layers, as native state.
    local footer = Field(root, "ButtonFrame")
    Attach(state, footer, FOOTER)
    FadeFields(state, footer, ITEM_INTERACTION_FOOTER_ART)
    Kit.FadeNativeTextures(state, Field(footer, "MoneyFrameEdge"))
    SkinControl(state, Field(footer, "ActionButton"), PRIMARY_BUTTON)

    -- The slot surface is cosmetic only. Icon/GlowOverlay and all conversion
    -- input/output borders, arrows, flashes and texture-kit states stay native.
    Attach(state, Field(root, "ItemSlot"), SLOT)
    return true, "applied"
end

local function SkinItemUpgrade(root, state)
    SkinExactItemServiceShell(root, state)

    -- Suppress only the static panel ornament. BottomPanel_Flash, Ring,
    -- tooltip glow pieces, arrows and button glow remain Blizzard-owned so the
    -- complete upgrade-success and interaction feedback is preserved.
    FadeFields(state, root, ITEM_UPGRADE_ART)

    local itemButton = Field(root, "UpgradeItemButton")
    Attach(state, itemButton, SLOT)
    -- ButtonFrame is static slot ornament. IconBorder remains native because
    -- SetItemButtonQuality updates it whenever the selected item/target quality
    -- changes; no addon lifecycle hook is needed to preserve that state.
    Fade(state, Field(itemButton, "ButtonFrame"))

    for index = 1, #ITEM_UPGRADE_PREVIEWS do
        local key = ITEM_UPGRADE_PREVIEWS[index]
        local preview = Field(root, key)
        Attach(state, preview, key == "ItemHoverPreviewFrame" and PREVIEW_POPUP or CARD)
        -- ItemUpgradePreviewTemplate also owns GlowNineSlice; fading only the
        -- inherited NineSlice keeps that success effect intact.
        FadeNineSlice(state, preview)
    end

    local cost = Field(root, "UpgradeCostFrame")
    Attach(state, cost, SMALL_CARD)
    Fade(state, Field(cost, "BGTex"))
    Kit.FadeNativeTextures(state, Field(root, "PlayerCurrenciesBorder"))
    SkinControl(state, Field(root, "UpgradeButton"), PRIMARY_BUTTON)
    SkinControl(state, Path(root, "ItemInfo", "Dropdown"), UPGRADE_DROPDOWN)
    return true, "applied"
end

local groupSkinners = Shared.groupSkinners
groupSkinners["great-vault"] = SkinGreatVault
groupSkinners["item-socketing"] = SkinItemSocketing
groupSkinners["item-interaction"] = SkinItemInteraction
groupSkinners["item-upgrade"] = SkinItemUpgrade
