local _, P = ...
local NS, S = P.NS, P.Suite

-- Blizzard dialogs (StaticPopup1-4) and loot toasts: an optional Suite look,
-- font, minimum height and screen position for dialogs, colored frames (and
-- a sound) around a resurrection offer and its accept button, the item
-- quality written on loot toasts and a gold frame around money toasts.
local M = { looks = {}, cues = {}, buttonCues = {}, heights = {},
    qualityLabels = setmetatable({}, { __mode = "k" }), moneyFrames = setmetatable({}, { __mode = "k" }) }
local DIALOG_COUNT = 4
local ART_KEYS = { "BG", "NineSlice", "Border" }
local CUE_FRAME, CUE_SOUND = 2, 3
local CUE_R, CUE_G, CUE_B = .35, .9, .55
local GOLD_R, GOLD_G, GOLD_B = 1, .8, .25
local CUE_EDGES = {
    { "TOPLEFT", "TOPRIGHT", "SetHeight" },
    { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
    { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
}

local dialogs = {}
local function Dialog(index)
    local dialog = dialogs[index]
    if not dialog then
        dialog = _G["StaticPopup" .. index]
        dialogs[index] = dialog
    end
    return dialog
end

------------------------------------------------------------------ dialog look
local function LookState(dialog)
    local state = M.looks[dialog]
    if state then return state end
    local panel = S.CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    panel:SetAllPoints()
    panel:SetFrameLevel(dialog:GetFrameLevel())
    panel:EnableMouse(false)
    panel:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(.04, .07, .1, .98)
    panel:SetBackdropBorderColor(.25, .65, .8, 1)
    panel:Hide()
    state = { panel = panel, art = {} }
    M.looks[dialog] = state
    return state
end

local function ClearPanel(state)
    if not state.panelOn then return end
    state.panel:Hide()
    for art, alpha in pairs(state.art) do art:SetAlpha(alpha) end
    state.panelOn = nil
end

local function ClearFont(dialog, state)
    if not state.font then return end
    dialog.Text:SetFont(unpack(state.font))
    state.font = nil
end

local function ClearLook(dialog)
    local state = M.looks[dialog]
    if not state then return end
    ClearPanel(state)
    ClearFont(dialog, state)
end

-- The dark panel (skin) and the Suite font (dialogFont) apply on show,
-- before Blizzard sizes the dialog to its text; either works alone.
local function ApplyLook(dialog)
    local c = M.config
    if not c.skin and not c.dialogFont then return ClearLook(dialog) end
    local state = LookState(dialog)
    if c.skin and not state.panelOn then
        for _, key in ipairs(ART_KEYS) do
            local art = dialog[key]
            if art then state.art[art] = art:GetAlpha() end
        end
        state.panelOn = true
    elseif not c.skin then
        ClearPanel(state)
    end
    if state.panelOn then
        state.panel:Show()
        for art in pairs(state.art) do art:SetAlpha(0) end
    end
    if c.dialogFont then
        state.font = state.font or { dialog.Text:GetFont() }
        S.SetFont(dialog.Text, nil, c.fontSize, "OUTLINE")
    else
        ClearFont(dialog, state)
    end
end

------------------------------------------------------------------ height
-- Blizzard's Resize (GameDialogMixin, through StaticPopup_Show and every
-- frame of a countdown) sets the dialog's height from its content; a taller
-- minimum is applied right after it, and the height Blizzard chose is kept
-- to hand back.
local function Sized(dialog)
    local wanted = M.active and M.config.minHeight or 0
    if wanted <= 0 then return end
    local height = dialog:GetHeight()
    if not S.Finite(height) or height >= wanted then return end
    if NS.IsCombatLocked() and dialog:IsProtected() then return end
    M.heights[dialog] = height
    dialog:SetHeight(wanted)
end

-- Hands back the height Blizzard chose for a dialog this helper made taller.
local function Unsize(dialog)
    local native = M.heights[dialog]
    if not native or NS.IsCombatLocked() and dialog:IsProtected() then return end
    dialog:SetHeight(native)
    M.heights[dialog] = nil
end

------------------------------------------------------------------ position
local function IsDialog(frame)
    for index = 1, DIALOG_COUNT do
        if Dialog(index) == frame then return true end
    end
    return false
end

-- StaticPopup_SetUpPosition chains the shown dialogs, each TOP to the BOTTOM
-- of the one before; moving the first dialog moves the chain. Dialogs with a
-- fixed position of their own are left alone.
local function ChainHead()
    for index = 1, DIALOG_COUNT do
        local dialog = Dialog(index)
        if dialog:IsShown() and not dialog.hasFixedPosition then
            local _, relative = dialog:GetPoint(1)
            if not IsDialog(relative) then return dialog end
        end
    end
end

-- Whether a dialog sits at the custom position already.
local function Placed(dialog)
    if dialog:GetNumPoints() ~= 1 then return false end
    local c = M.config
    local point, relative, _, x, y = dialog:GetPoint(1)
    return point == "CENTER" and relative == UIParent and x == c.x and y == c.y
end

-- Hooked on every dialog's Resize, which Blizzard's StaticPopup_OnUpdate
-- calls every frame while a dialog counts down (resurrection, summon, quit):
-- a head already in place is never scanned for or moved again.
local function Place(dialog)
    if not M.active or not M.config.move then return end
    if dialog and dialog == M.placedHead and Placed(dialog) then return end
    local head = ChainHead()
    if not head or head == M.placedHead and Placed(head) then return end
    if NS.IsCombatLocked() and head:IsProtected() then return end
    head:ClearAllPoints()
    head:SetPoint("CENTER", UIParent, "CENTER", M.config.x, M.config.y)
    M.placedHead = head
end

-- Hands a dialog this helper placed back to Blizzard's own spot.
local function Unplace()
    local head = M.placedHead
    M.placedHead = nil
    if not head or not head:IsShown() or head.hasFixedPosition then return end
    local point, relative = head:GetPoint(1)
    if point ~= "CENTER" or relative ~= UIParent or NS.IsCombatLocked() and head:IsProtected() then return end
    head:ClearAllPoints()
    head:SetPoint("TOP", GetAppropriateTopLevelParent(), "TOP", 0, head.topOffset or -135)
end

------------------------------------------------------------------ resurrection
-- A thin colored frame around parent, offset outward (or inward when
-- negative), drawn by Suite textures only.
local function Outline(parent, offset, thickness, r, g, b)
    local frame = S.CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", -offset, offset)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", offset, -offset)
    for _, edge in ipairs(CUE_EDGES) do
        local line = S.CreateTexture(frame, nil, "OVERLAY")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        line[edge[3]](line, thickness)
        line:SetColorTexture(r, g, b, 1)
    end
    return frame
end

local function Cue(list, owner, offset)
    local cue = list[owner]
    if not cue then
        cue = Outline(owner, offset, 2, CUE_R, CUE_G, CUE_B)
        list[owner] = cue
    end
    return cue
end

-- RESURRECT, RESURRECT_NO_SICKNESS and RESURRECT_NO_TIMER offers: a frame
-- around the dialog (optionally with a sound) and one around its accept
-- button (GameDialogMixin:GetButton1).
local function MarkRevive(dialog)
    local which = S.PublicText(dialog.which)
    local revive = which ~= nil and which:find("^RESURRECT") ~= nil
    local wanted = M.config.reviveCue
    if revive and wanted >= CUE_FRAME then
        Cue(M.cues, dialog, 3):Show()
        if wanted == CUE_SOUND then PlaySound(SOUNDKIT.READY_CHECK) end
    elseif M.cues[dialog] then
        M.cues[dialog]:Hide()
    end
    local button = dialog:GetButton1()
    if revive and M.config.reviveButton then
        Cue(M.buttonCues, button, 2):Show()
    elseif M.buttonCues[button] then
        M.buttonCues[button]:Hide()
    end
end

------------------------------------------------------------------ loot toasts
-- LootWonAlertFrame_SetUp(frame, link, quantity, rollType, roll, specID,
-- isCurrency, ...): the toast names the quality in words as well as color.
local function QualityName(frame, link, _, _, _, _, isCurrency)
    local label = M.qualityLabels[frame]
    local quality = M.active and M.config.lootQualityName and not isCurrency and S.PublicText(link)
        and select(3, C_Item.GetItemInfo(link))
    local name = S.Finite(quality) and _G["ITEM_QUALITY" .. quality .. "_DESC"]
    local color = S.PublicText(name) and ITEM_QUALITY_COLORS[quality]
    if not color then
        if label then label:Hide() end
        return
    end
    if not label then
        label = S.CreateFontString(frame, nil, "OVERLAY")
        S.SetFont(label, nil, 10, "OUTLINE")
        label:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 14)
        M.qualityLabels[frame] = label
    end
    label:SetText(name)
    label:SetTextColor(color.r, color.g, color.b)
    label:Show()
end

-- MoneyWonAlertFrame_SetUp(frame, amount): a gold frame inside the toast.
local function MoneyFrame(frame)
    local mark = M.moneyFrames[frame]
    if not M.active or not M.config.moneyToastFrame then
        if mark then mark:Hide() end
        return
    end
    if not mark then
        mark = Outline(frame, -6, 1, GOLD_R, GOLD_G, GOLD_B)
        M.moneyFrames[frame] = mark
    end
    mark:Show()
end

------------------------------------------------------------------ hooks
local function DialogShown(dialog)
    if not M.active then return end
    ApplyLook(dialog)
    MarkRevive(dialog)
end

local function DialogHidden(dialog)
    ClearLook(dialog)
    if M.cues[dialog] then M.cues[dialog]:Hide() end
    local button = dialog:GetButton1()
    if M.buttonCues[button] then M.buttonCues[button]:Hide() end
    Unsize(dialog)
    if M.placedHead == dialog then M.placedHead = nil end
end

local function Resized(dialog)
    Sized(dialog)
    Place(dialog)
end

-- StaticPopup_Show shows a dialog and then sizes it (dialog:Resize()); the
-- height and the chain are set once the size is final. AlertFrameSystems.lua
-- handed LootWonAlertFrame_SetUp and MoneyWonAlertFrame_SetUp to their queued
-- systems at load, which call their own references (AlertFrames.lua
-- setUpFunction); bonus rolls call the globals by name (GroupLootFrame.lua).
-- Hooks cannot be removed.
local function Install(self)
    if self.hooked then return end
    for index = 1, DIALOG_COUNT do
        local dialog = Dialog(index)
        dialog:HookScript("OnShow", DialogShown)
        dialog:HookScript("OnHide", DialogHidden)
        hooksecurefunc(dialog, "Resize", Resized)
    end
    hooksecurefunc(LootAlertSystem, "setUpFunction", QualityName)
    hooksecurefunc("LootWonAlertFrame_SetUp", QualityName)
    hooksecurefunc(MoneyWonAlertSystem, "setUpFunction", MoneyFrame)
    hooksecurefunc("MoneyWonAlertFrame_SetUp", MoneyFrame)
    self.hooked = true
end

------------------------------------------------------------------ edit mode
local function Preview(self)
    if not S.editMode then
        if self.preview then self.preview:Hide() end
        return
    end
    local frame = self.preview
    if not frame then
        frame = S.CreateFrame("Frame", nil, UIParent)
        frame:EnableMouse(false)
        local background = S.CreateTexture(frame, nil, "BACKGROUND")
        background:SetAllPoints(frame)
        background:SetColorTexture(.12, .12, .14, .96)
        local text = S.CreateFontString(frame, nil, "OVERLAY")
        text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        S.SetFont(text, nil, 14, "OUTLINE")
        text:SetText(S.Text("Dialog position"))
        self.preview = frame
    end
    -- The sample shows the saved destination even before the custom position
    -- is on, at the minimum height.
    frame:SetSize(320, math.max(72, self.config.minHeight))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", self.config.x, self.config.y)
    frame:Show()
end

function M:HideEditPreview()
    if self.preview then self.preview:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover("popupAttention", "popup", { label = "Dialog position", order = 656,
        getFrame = function() return self.preview end, xKey = "x", yKey = "y", point = "CENTER",
        moveValues = { move = true }, historyKeys = { "move" }, sizeKeys = { "minHeight" } })
end

------------------------------------------------------------------ lifecycle
local function Repaint(self)
    local placing = self.active and self.config.move
    if not placing then Unplace() end
    for index = 1, DIALOG_COUNT do
        local dialog = Dialog(index)
        if dialog:IsShown() then
            if self.active then DialogShown(dialog) else DialogHidden(dialog) end
        end
    end
    if placing then Place() end
    for index = 1, DIALOG_COUNT do
        local dialog = Dialog(index)
        Unsize(dialog)
        if dialog:IsShown() then Sized(dialog) end
    end
    for frame, label in pairs(self.qualityLabels) do
        if not self.active or not self.config.lootQualityName or not frame:IsShown() then label:Hide() end
    end
    for frame, mark in pairs(self.moneyFrames) do
        if not self.active or not self.config.moneyToastFrame or not frame:IsShown() then mark:Hide() end
    end
end

function M:Enable()
    Install(self)
    self:Refresh()
    self:RegisterMovers()
end

function M:Refresh()
    Repaint(self)
    Preview(self)
end

function M:Disable()
    if self.preview then self.preview:Hide() end
    Repaint(self)
end

S.Install("popupAttention", M)
