local _, NS = ...
local Window = {}
NS.QuestWindow = Window

local Safety, Kit, Cosmetics = NS.Safety, NS.AdapterKit, NS.Cosmetics
local OWNER = "blizzardWindows:quest-presentation"
local ROOT_SPEC = Kit.SurfaceSpec("shell", 7, 0, false, true)
local BUTTON_SPEC = { role = "button", allowImplicitProtected = true, regions = { "Left", "Center", "Middle", "Right" } }
local footerButtonSlices = { "Left", "Middle", "Right" }
local pages = {
    QuestFrameRewardPanel = { "QuestRewardScrollFrame", "QuestFrameCompleteQuestButton" },
    QuestFrameDetailPanel = { "QuestDetailScrollFrame", "QuestFrameAcceptButton", "QuestFrameDeclineButton" },
    QuestFrameProgressPanel = { "QuestProgressScrollFrame", "QuestFrameCompleteButton", "QuestFrameGoodbyeButton" },
    QuestFrameGreetingPanel = { "QuestGreetingScrollFrame", "QuestFrameGreetingGoodbyeButton" },
}
local material = { "TopTileStreaks", "PortraitOverlay", "MaterialTopLeft", "MaterialTopRight", "MaterialBotLeft", "MaterialBotRight", "SealMaterialBG" }
local pieces = { "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner",
    "BottomLeftCorner", "BottomRightCorner", "Center" }
local owners, bands = {}, {}
local art = Kit.WeakSet()
local enabled, hooked, status, paints = false, false, "inactive", 0
local Release

local function Enabled()
    local db = NS.DB
    return enabled and db and db.enabled ~= false and db.blizzardWindowsEnabled ~= false
        and (not db.skins or db.skins.blizzardWindows ~= false) and NS.GenericWindows.IsCategoryEnabled("quest")
end

local function Visible()
    return Enabled() and Safety.Read(QuestFrame, "IsVisible") == true
end

local function OurOwner(owner)
    return owner == OWNER or owner == "blizzardWindows" or owners[owner] == true
end

local function Fade(region)
    if not Safety.Public(region) or not region then return end
    local current = Cosmetics.GetOwner(region)
    if current and not OurOwner(current) then return end
    local owner = current or "blizzardWindows"
    if Cosmetics.FadeDecoration(region, owner, OWNER) then art[region] = owner end
end

local function Dress(frame)
    local bg = Safety.Field(frame, "Bg")
    if bg and Kit.ParentIs(bg, frame) then Fade(bg) end
    for _, key in ipairs(material) do Fade(Safety.Field(frame, key)) end
    local nine = Safety.Field(frame, "NineSlice")
    if nine then for _, key in ipairs(pieces) do Fade(Safety.Field(nine, key)) end end
end

-- Texture bands have no hit rectangle. The title and portrait live in their
-- native higher-level holders. The bottom band stays behind the real buttons.
local function Band(key, point, offset, height, token)
    local texture = bands[key]
    if not texture then
        texture = QuestFrame:CreateTexture(nil, "ARTWORK", nil, -5)
        local left = point == "TOP" and "TOPLEFT" or "BOTTOMLEFT"
        local right = point == "TOP" and "TOPRIGHT" or "BOTTOMRIGHT"
        texture:SetPoint(left, QuestFrame, left, 2, offset)
        texture:SetPoint(right, QuestFrame, right, -2, offset)
        texture:SetHeight(height)
        bands[key] = texture
    end
    local r, g, b = NS.Theme.GetColor(token)
    texture:SetColorTexture(r, g, b, 1)
    texture:Show()
end

local function PaintShell()
    local surface = NS.Registry.GetSurface(QuestFrame)
    local spec = surface and surface.spec or ROOT_SPEC
    if not NS.Surface.Attach(QuestFrame, spec) then return false end
    Dress(QuestFrame)
    local inset = Safety.Field(QuestFrame, "Inset")
    if Kit.ParentIs(inset, QuestFrame) and Safety.CanDecorate(inset, true) then Dress(inset) end
    Band("title", "TOP", -2, 20, "ink")
    Band("topLine", "TOP", -22, 1, "borderSoft")
    Band("footer", "BOTTOM", 2, 29, "ink")
    Band("bottomLine", "BOTTOM", 31, 1, "borderSoft")
    return true
end

local function PaintFooterButton(page, button)
    if not Kit.ParentIs(button, page) or not Safety.CanDecorate(button, true) then return end
    local owner = NS.ControlSkin.GetOwner(button)
    local painted
    if not owner then painted = NS.ControlSkin.ApplyButton(button, OWNER, BUTTON_SPEC)
    elseif OurOwner(owner) or owner == "uipanel-buttons" then painted = NS.ControlSkin.Refresh(button) end
    if not painted then return end
    for _, key in ipairs(footerButtonSlices) do
        local region = Safety.Field(button, key)
        if Safety.Public(region) and Kit.ParentIs(region, button) and Cosmetics.HideDecoration(region, OWNER) then
            art[region] = OWNER
        end
    end
end

local function PaintPage(page, controls)
    Dress(page)
    -- The native page is wider than the visible NPC window, so constrain its
    -- backing to the shell. Its scroll frame and footer buttons render above it.
    local backing = bands[page]
    if not backing and Safety.CanCreateRegions(page, true) then
        backing = page:CreateTexture(nil, "ARTWORK", nil, -5)
        backing:SetPoint("TOPLEFT", QuestFrame, "TOPLEFT", 3, -24)
        backing:SetPoint("BOTTOMRIGHT", QuestFrame, "BOTTOMRIGHT", -3, 33)
        bands[page] = backing
    end
    if backing then
        local r, g, b = NS.Theme.GetColor("background")
        backing:SetColorTexture(r, g, b, NS.Theme.GetMaterialOpacity(NS.Theme.GetMaterial("panel")))
        backing:Show()
    end
    local scroll = Safety.Field(_G, controls[1])
    local bar = scroll and Safety.Field(scroll, "ScrollBar")
    if Kit.ParentIs(scroll, page) and Kit.ParentIs(bar, scroll) then
        local state = NS.ScrollBarSkin.GetState(bar)
        if not state then NS.ScrollBarSkin.Apply(bar, OWNER)
        elseif OurOwner(state.owner) then NS.ScrollBarSkin.Refresh(bar) end
    end
    for i = 2, #controls do
        PaintFooterButton(page, Safety.Field(_G, controls[i]))
    end
end

local function Paint()
    if not Visible() then return end
    if NS.IsCombatLocked() then return NS.CombatGate.RunOrDefer(OWNER, Paint) end
    if not Safety.CanCreateRegions(QuestFrame, true) then status = "protected" return end
    if not PaintShell() then status = "surface" return end
    for name, controls in pairs(pages) do
        local page = Safety.Field(_G, name)
        if Kit.ParentIs(page, QuestFrame) and Safety.Read(page, "IsVisible") == true then
            if Safety.CanDecorate(page, true) then PaintPage(page, controls) end
        end
    end
    NS.QuestText.Refresh()
    NS.QuestRewardCards.Paint()
    status, paints = "painted", paints + 1
end

function Window.Refresh()
    if Visible() then NS.Registry.QueueJob(Paint)
    elseif enabled and not Enabled() and status == "painted" then NS.Registry.QueueJob(Release) end
end

local function HookWindow()
    if hooked then return end
    QuestFrame:HookScript("OnShow", Window.Refresh)
    for name in pairs(pages) do
        local page = Safety.Field(_G, name)
        if Kit.ParentIs(page, QuestFrame) then page:HookScript("OnShow", Window.Refresh) end
    end
    hooksecurefunc("QuestFrame_SetMaterial", Window.Refresh)
    NS.Registry.AddListener(Window, function(_, domain)
        if domain == "theme" or domain == "color" or domain == "profile" then Window.Refresh() end
    end)
    hooked = true
end

function Window.Activate(root, owner)
    if root ~= QuestFrame or not owner then return end
    owners[owner] = true
    if not enabled then
        enabled, status = true, "waiting"
        HookWindow()
        NS.QuestRewardCards.Enable()
    end
    Window.Refresh()
end

Release = function()
    if Enabled() then return end
    if NS.IsCombatLocked() then return NS.CombatGate.RunOrDefer(OWNER, Release) end
    for region, owner in pairs(art) do
        Cosmetics.ReleaseDecoration(region, owner, OWNER)
        art[region] = nil
    end
    for _, band in pairs(bands) do band:Hide() end
    local surface = NS.Registry.GetSurface(QuestFrame)
    if surface and surface.spec == ROOT_SPEC then NS.Surface.SetVisible(QuestFrame, false) end
    NS.ControlSkin.DisableOwner(OWNER)
    NS.ScrollBarSkin.DisableOwner(OWNER)
    if enabled then status = "disabled" end
end

function Window.Deactivate(root, owner)
    if root ~= QuestFrame or not owner then return end
    owners[owner] = nil
    if not enabled or next(owners) then return end
    enabled, status = false, "inactive"
    NS.QuestRewardCards.Disable()
    Release()
end

function Window.GetStatus() return status, paints end
