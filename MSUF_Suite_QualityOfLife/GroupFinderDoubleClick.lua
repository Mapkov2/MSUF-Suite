local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}
local ID = "groupFinderDoubleClick"
local CLICK_WINDOW = .4
-- The saved note rule allows 63 bytes; EditBox byte limits count the
-- terminator, so non-ASCII text can never exceed what the setting accepts.
local NOTE_BYTES = 64

-- Group Finder loads with the Retail UI at startup; this module is Retail-only.
-- Blizzard's sign-up code is Lua: an error inside it is reported
-- (S.Dispatch) and the click stays an ordinary selection.
local function QuickApply(resultID)
    local c = M.config or {}
    local shift = IsShiftKeyDown()
    local application = LFGListApplicationDialog
    local signUp = application.SignUpButton
    if not c.quickApply or not S.Public(shift) or shift then return end
    local visible, ready = application:IsShown(), signUp:IsEnabled()
    local id = application.resultID
    if S.Public(visible) and visible == true and S.Public(ready) and ready == true
        and S.Finite(id) and id == resultID
        and not S.Dispatch(NS.Finish, LFGListApplicationDialogSignUpButton_OnClick, signUp) then
        S.Print(S.Text("Application could not be submitted by the client."))
    end
end

local function OnEntryClick(entry, button)
    if not M.active or not S.PublicText(button) or button ~= "LeftButton" then return end
    local panel = LFGListFrame.SearchPanel
    local resultID = entry and entry.resultID
    if not S.Finite(resultID) or not S.Finite(panel.selectedResult)
        or panel.selectedResult ~= resultID then
        M.lastResult, M.lastAt = nil, nil
        return
    end
    local enabled, shown = panel.SignUpButton:IsEnabled(), panel:IsShown()
    if not S.Public(enabled) or enabled ~= true or not S.Public(shown) or shown ~= true then
        M.lastResult, M.lastAt = nil, nil
        return
    end
    local now = GetTime()
    if not S.Finite(now) then return end
    local doubleClick = M.lastResult == resultID and M.lastAt
        and now >= M.lastAt and now - M.lastAt <= CLICK_WINDOW
    M.lastResult, M.lastAt = resultID, now
    local dialogShown = LFGListApplicationDialog:IsShown()
    if not doubleClick or not S.Public(dialogShown) or dialogShown == true then return end
    M.lastResult, M.lastAt = nil, nil
    if not S.Dispatch(NS.Finish, LFGListSearchPanel_SignUp, panel) then
        S.Print(S.Text("Group finder dialog could not be opened by the client."))
        return
    end
    -- This hook runs within the user's second hardware click. Shift keeps
    -- the native role/note dialog open. Never bypass its validity gate.
    QuickApply(resultID)
end

-- The note is saved when editing ends, not per keystroke; a change made in
-- combat (when settings are locked) is saved once combat ends.
local function SaveNote(self)
    local text = self.pendingNote
    if text == nil or NS.IsCombatLocked() then return end
    self.pendingNote = nil
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    if text ~= (self.config.note or "") then S.Set(ID, "note", text) end
end

local function NoteChanged(self, box)
    self.pendingNote = box:GetText()
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", SaveNote, true)
        return
    end
    SaveNote(self)
end

local function NoteBox(self, panel)
    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetPoint("BOTTOMLEFT", 16, 14)
    edit:SetPoint("BOTTOMRIGHT", -12, 14)
    edit:SetHeight(24)
    edit:SetAutoFocus(false)
    edit:SetMaxBytes(NOTE_BYTES)
    edit:SetScript("OnEscapePressed", function(box)
        box:SetText(self.config.note or "")
        box:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
    edit:SetScript("OnEditFocusLost", function(box) NoteChanged(self, box) end)
    return edit
end

local function ShowNote(self)
    local dialog = LFGListApplicationDialog
    if not self.active or not self.config or not self.config.showNote then
        if self.notePanel then self.notePanel:Hide() end
        return
    end
    if not self.notePanel then
        local panel = S.CreateFrame("Frame", nil, dialog)
        panel:SetPoint("TOPLEFT", dialog, "TOPRIGHT", 8, 0)
        panel:SetSize(260, 100)
        local back = S.CreateTexture(panel, nil, "BACKGROUND")
        back:SetAllPoints(panel)
        back:SetColorTexture(.04, .05, .07, .96)
        local label = S.CreateFontString(panel, nil, "OVERLAY")
        label:SetPoint("TOPLEFT", 12, -10)
        label:SetPoint("TOPRIGHT", -12, -10)
        S.SetStyledFont(label, S.GlobalFontPath(), 12, "OUTLINE", 1, true, 70, 1)
        label:SetText(S.Text("Saved note: select and copy, then paste into the application."))
        self.notePanel, self.noteEdit = panel, NoteBox(self, panel)
    end
    self.noteEdit:SetText(self.pendingNote or self.config.note or "")
    self.notePanel:Show()
end

function M:Enable()
    if not self.hooked then
        self.hooked = true
        hooksecurefunc("LFGListSearchEntry_OnClick", OnEntryClick)
        LFGListApplicationDialog:HookScript("OnShow", function() ShowNote(self) end)
    end
end

function M:Refresh()
    if self.notePanel and not self.config.showNote then self.notePanel:Hide() end
end

function M:Disable()
    if self.notePanel then self.notePanel:Hide() end
    self.pendingNote = nil
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.lastResult, self.lastAt = nil, nil
end

S.Install(ID, M)
