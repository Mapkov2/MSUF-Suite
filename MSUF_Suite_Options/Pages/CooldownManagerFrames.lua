local _, P = ...
-- Frame tools of the cooldown manager page: picking the frame a bar attaches
-- to, and copying a bar's layout to the other specializations. Built on first
-- use (Page.Tools); every builder reaches the page's helpers through P and
-- Page alone and none is a local of the file, so the options load stays small.
local Page = P.CDMPage
if not Page then return end

-- The frame under the cursor: the first named frame at or above what
-- GetMouseFoci reports, nil inside the menu itself or over nothing named.
function Page.FindTools(tools)
    local Suite, M, Public = P.Suite, P.M, Page.Public
    local function NameOf(frame)
        local found
        for _ = 1, 40 do
            if type(frame) ~= "table" or Suite.Safety.IsForbidden(frame) or frame == M.frame then break end
            local name = frame:GetName()
            if not found and Public(name) and type(name) == "string" and name ~= "UIParent" and name ~= "WorldFrame"
                and rawget(_G, name) == frame then
                found = name
            end
            frame = frame:GetParent()
        end
        if M.frame and frame == M.frame then return nil end
        return found
    end
    function tools.UnderCursor()
        local foci = GetMouseFoci()
        if type(foci) ~= "table" then return nil end
        for i = 1, #foci do
            local name = NameOf(foci[i])
            if name then return name end
        end
    end
end

-- "Pick a frame": the next left click names the frame under the cursor
-- (GLOBAL_MOUSE_DOWN and GetMouseFoci: no polling). A right click, Escape,
-- combat or closing the menu cancels. The click still reaches what is under
-- the cursor. One history entry: the bar sits on the frame, flush, by name.
function Page.PickTools(tools)
    local S, M, Tr = P.S, P.M, P.Tr
    local ID, KEYS = Page.ID, P.Suite.CDM.KEYS
    local watcher, slot, hooked
    local function Attach(name)
        local keys, other = KEYS[slot], P.Suite.CDM.OTHER_ANCHOR
        local values = S.CooldownManagerConvertAnchor and S.CooldownManagerConvertAnchor(slot, other) or { [keys.anchor] = other }
        values[keys.anchorFrame] = name
        local ok
        P.WithHistory("Attach to a frame", "suite:cooldownManager.anchor", function()
            ok = P.SetMany(ID, values)
            return ok
        end)
        if not ok then return Page.Fail("That did not work.") end
        Page.Note(string.format(Tr("%s is attached to %s."), Page.BarName(slot), name))
        P.Refresh()
    end
    local function OnEvent(self, event, button)
        if event ~= "GLOBAL_MOUSE_DOWN" or button == "RightButton" then return self:Hide() end
        if button ~= "LeftButton" then return end
        local name = tools.UnderCursor()
        if not name then
            return Page.Fail("There is no named frame under the cursor. Click another spot, or press Escape.")
        end
        self:Hide()
        Attach(name)
    end
    local function OnKey(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then self:Hide() end
    end
    local function Watcher()
        local frame = S.CreateFrame("Frame", nil, UIParent)
        frame:Hide()
        frame:EnableMouse(false)
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnEvent", OnEvent)
        frame:SetScript("OnKeyDown", OnKey)
        frame:SetScript("OnShow", function(self)
            self:RegisterEvent("GLOBAL_MOUSE_DOWN")
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
        end)
        frame:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
        return frame
    end
    function tools.Pick()
        if P.Combat() then return end
        watcher = watcher or Watcher()
        if not hooked and M.frame then
            hooked = true
            M.frame:HookScript("OnHide", function() watcher:Hide() end)
        end
        slot = Page.selected
        Page.Note(Tr("Click the frame to attach this bar to. A right click or Escape cancels."))
        watcher:Show()
    end
end

-- "Copy layout to other specializations": the bar's layout as the
-- per-specialization data keeps it (positionsData): position, attachment (the
-- frame name too), growth, rows and sizes together; r marks Essential x/y
-- counted from Blizzard's bar.
function Page.CopyTools(tools)
    local Tr, ID, CDM = P.Tr, Page.ID, P.Suite.CDM
    local function Layout(bar)
        local layout = {}
        for suffix, key in pairs(CDM.PLACE_KEYS[bar]) do layout[suffix] = P.Get(ID, key) end
        if bar == "ess" and P.Get(ID, "essOnViewer") == true then layout.r = true end
        return layout
    end
    local function Same(a, b)
        if type(a) ~= "table" then return false end
        for key, value in pairs(b) do
            if a[key] ~= value then return false end
        end
        for key in pairs(a) do
            if b[key] == nil then return false end
        end
        return true
    end
    -- To every other specialization of the class, or to `only`. Returns true
    -- and how many specializations changed, or false and why.
    function tools.CopyLayout(bar, only)
        if P.Combat() then return false, "Finish combat before editing the suite" end
        local current = Page.PlayerSpec()
        if Page.ForeignSpec() or not current then return false, "Your specialization is not known yet." end
        if P.Get(ID, "specPositions") ~= true then
            return false, "Turn on \"Save bar layout per specialization\" first."
        end
        local data, layout, count = CDM.Codec.DecodePositions(P.Get(ID, "positionsData")), Layout(bar), 0
        for _, spec in ipairs(Page.ClassSpecs({})) do
            if spec ~= current and (only == nil or only == spec) then
                local places = data.specs[spec] or {}
                if not Same(places[bar], layout) then
                    data.specs[spec], places[bar], count = places, layout, count + 1
                end
            end
        end
        if count == 0 then return true, 0 end
        local text, reason = CDM.Codec.EncodePositions(data)
        if not text then return false, reason end
        local ok
        P.WithHistory("Copy layout to other specializations", "suite:cooldownManager.layout", function()
            ok, reason = P.Set(ID, "positionsData", text)
            return ok
        end)
        if not ok then return false, reason end
        return true, count
    end
    local function CopyText(count)
        return string.format(Tr("Copied the layout of this bar to %d other specializations."), count)
    end
    -- With its Undo line, as the list copy has.
    function tools.Copy(only)
        local ok, count = Page.WithUndo(CopyText, { "positionsData" }, function() return tools.CopyLayout(Page.selected, only) end)
        if not ok then return Page.Fail(count) end
        if count == 0 then Page.Note(Tr("Your other specializations have this layout already.")) end
    end
end

-- The buttons: "Pick a frame" under the frame name, and the copy button with
-- its menu (all other specializations, or one of them) in the Layout section.
function Page.ButtonTools(tools)
    local S, W, HM, Tr, Public = P.S, P.W, P.HM, P.Tr, Page.Public
    local ID, PAGE = Page.ID, Page.PAGE
    local items = {}
    local function Pick(value) tools.Copy(value ~= 0 and value or nil) end
    function tools.OpenCopy(owner)
        if P.Combat() or not W.OpenDropdown then return end
        local current = Page.PlayerSpec()
        items[1] = items[1] or {}
        items[1].value, items[1].text = 0, "All other specializations"
        local n = 1
        for _, spec in ipairs(Page.ClassSpecs({})) do
            if spec ~= current then
                n = n + 1
                local item = items[n] or {}
                items[n] = item
                local _, name = GetSpecializationInfoByID(spec)
                item.value, item.text, item.translate = spec, Public(name) and name or tostring(spec), false
            end
        end
        for i = n + 1, #items do items[i] = nil end
        Page.dropdownOpen = true
        W.OpenDropdown(owner, items, nil, Pick)
    end
    function tools.PickButton(ctx, body, y, width, sectionId)
        HM.SkipHistoryCheckpoint(P.Button(ctx, body, "Pick a frame", 16, y - 2, math.floor((width - 12) / 2), tools.Pick,
            function() return S.Availability(ID) and P.Get(ID, "enabled") end,
            P.Meta(PAGE, ID, "editor.pickFrame", "action", sectionId)))
        return y - 36
    end
    function tools.CopyButton(ctx, body, y, width, sectionId)
        local button
        button = P.Button(ctx, body, "Copy layout to other specializations", 16, y - 4, width,
            function() tools.OpenCopy(button) end,
            function()
                return S.Availability(ID) and P.Get(ID, "enabled") and P.Get(ID, "specPositions") == true
                    and not Page.ForeignSpec()
            end, P.Meta(PAGE, ID, "editor.copyLayout", "action", sectionId))
        HM.SkipHistoryCheckpoint(button)
        button:HookScript("OnEnter", function(self)
            Page.ShowTip(self, Tr("Copy layout to other specializations"),
                Tr("Gives this bar's place, attachment, growth, rows and sizes to your other specializations. You can undo it."))
        end)
        button:HookScript("OnLeave", Page.HideTip)
        return y - 40
    end
end

function Page.Tools()
    local tools = Page.toolset
    if tools then return tools end
    tools = {}
    Page.toolset = tools
    Page.FindTools(tools)
    Page.PickTools(tools)
    Page.CopyTools(tools)
    Page.ButtonTools(tools)
    return tools
end
