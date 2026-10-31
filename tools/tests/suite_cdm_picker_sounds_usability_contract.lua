-- Package 3: real pooled picker/sound UI and editor metadata, with the lead's
-- two popover calls exercised at the same post-layout boundary.
local root, only = assert(arg[1]), arg[2]
local originalLoad, P = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, ns)
        if path:find("MSUF_Suite_Options/Menu/Bridge.lua", 1, true) then P = ns end
        if path:find("MSUF_Suite_Options/Pages/CooldownManagerData.lua", 1, true) then
            local media = ns.Suite.SharedMedia()
            local fetch = media.Fetch
            media.Fetch = function(self, kind, name, silent)
                if name ~= "Missing-Pkg3" then return fetch(self, kind, name, silent) end
            end
            ns.Suite.SharedMedia = function() return media end
        end
        return chunk(addon, ns)
    end
end
assert(originalLoad(root .. "/tools/tests/suite_cooldown_manager_options_contract.lua"))()
loadfile = originalLoad
local Page, Suite, S = P.CDMPage, P.Suite, P.S
local CDM, ID = Suite.CDM, Page.ID
local function Click(button) return button:GetScript("OnClick")(button) end
local function Run(id, fn)
    if not only or only == id then fn(); print("PASS cdm-picker " .. id) end
end
local function OpenPicker()
    Page.ClosePopups()
    Page.Select("ess")
    assert(Page.TogglePicker(CreateFrame("Button")))
    return Page.picker
end
local function Filter(picker, text)
    picker.search:SetText(text)
    Page.FilterPicker()
end

Run("U07", function()
    Enum.CooldownViewerCategory = { TrackedBuff = 2, TrackedBar = 3, SpecAgnosticTracked = 6, EquipSlotTracked = 7 }
    local C = { EMPTY = {}, Catalog = { BAR_OF = {}, TAIL = {}, generation = 1 }, GuideProfiles = {},
        Const = { QUESTION_ICON = 134400 }, Presets = { RACIALS = {}, CONSUMABLES = {},
            RaidEssentials = function() end, Defensives = function() end } }
    local NS = { CDM = CDM, RootDB = {}, Database = { GetActiveProfileName = function() return "Pkg3" end } }
    assert(originalLoad(root .. "/MSUF_Suite_CooldownManager/Editor.lua"))("test", { NS = NS, Suite = Suite, CDM = C })
    local config = S.Config(ID)
    local context = C.Editor.Context(99901, 8, config, "MAGE")
    assert(context.catalogUnavailable == true and context.catalogCount == 0,
        "U07: an unobserved empty catalog must be distinct from an empty selection")
    local target = Page.TargetContext
    Page.TargetContext = function() return context end
    Page.selected = "buf"
    Page.ClearNote()
    assert(Page.CatalogUnavailable():find("Log in on this character and specialization", 1, true))
    Page.ui.PaintPreviewNote()
    assert(Page.ui.previewLine:GetText() == Page.CatalogUnavailable(), "U07: preview omitted unavailable catalog state")
    local render = S.CooldownManagerRenderPreview
    local visible = Page.ui.previewBody.IsVisible
    Page.ui.previewBody.IsVisible = function() return true end
    S.CooldownManagerRenderPreview = function() end
    Page.ui.PaintPreview()
    assert(Page.ui.message:GetText() == Page.CatalogUnavailable(), "U07: empty canvas looks like an empty selection")
    S.CooldownManagerRenderPreview = render
    Page.ui.previewBody.IsVisible = visible
    NS.RootDB.cdmEditorCatalog = { Pkg3 = { [99902] = {
        { key = "s133", name = "Fireball", texture = 123, slot = "ess", family = 1, known = true } } } }
    context = C.Editor.Context(99902, 8, config, "MAGE")
    assert(context.observed and not context.catalogUnavailable and Page.CatalogUnavailable() == nil,
        "U07: an observed empty bar was mistaken for missing metadata")
    Page.TargetContext = target
end)

Run("U13", function()
    local picker = OpenPicker()
    local count = 0
    for _, row in ipairs(picker.rows) do
        if row:IsShown() and row.item.kind == "entry" then
            local left, right = row.text.points[1], row.text.points[2]
            assert(right and right[1] == "RIGHT" and right[2] == row.status and right[3] == "LEFT",
                "U13: name rectangle is not bounded by the status column")
            local statusLeft = row:GetWidth() - 4 - row.status:GetWidth()
            local nameRight = statusLeft + right[4]
            assert(left[4] < nameRight and nameRight < statusLeft, "U13: picker name intersects status")
            count = count + 1
        end
    end
    assert(count > 0)
    picker:Hide()
end)

Run("U19", function()
    local picker = OpenPicker()
    local query = "No matching spell name Pkg3"
    Filter(picker, query)
    assert(picker.empty:IsShown() and picker.lookup and picker.lookup:IsShown(), "U19: current query has no lookup action")
    Click(picker.lookup)
    assert(picker.idBox:GetText() == query, "U19: lookup requires retyping the query")
    Filter(picker, "")
    assert(not picker.lookup:IsShown(), "U19: empty query offers a meaningless lookup")
    picker:Hide()
end)

Run("F04", function()
    local picker, id, ready, requests = OpenPicker(), 987654321, false, 0
    local name, icon, request = C_Item.GetItemNameByID, C_Item.GetItemIconByID, C_Item.RequestLoadItemDataByID
    C_Item.GetItemNameByID = function(value) if value == id then return ready and "Loaded item" or nil end; return name(value) end
    C_Item.GetItemIconByID = function(value) if value == id then return ready and 456 or nil end; return icon(value) end
    C_Item.RequestLoadItemDataByID = function(value) if value == id then requests = requests + 1 else request(value) end end
    picker.idBox:SetText(tostring(id))
    Page.EchoCustom()
    assert(not picker.addB:IsEnabled() and requests > 0)
    assert(picker.events.ITEM_DATA_LOAD_RESULT, "F04: cooldown picker does not watch custom item completion")
    local event = picker:GetScript("OnEvent")
    ready = true
    event(picker, "ITEM_DATA_LOAD_RESULT", id + 1, true)
    assert(not picker.addB:IsEnabled(), "F04: unrelated item completion refreshed the lookup")
    event(picker, "ITEM_DATA_LOAD_RESULT", id, true)
    assert(picker.customItem == id and picker.addB:IsEnabled() and picker.echo:GetText():find("Loaded item", 1, true),
        "F04: loaded custom item remains unavailable until retyping")
    ready = false
    Page.EchoCustom()
    local before = requests
    event(picker, "ITEM_DATA_LOAD_RESULT", id, false)
    assert(requests == before, "F04: failed completion retried the load")
    picker:Hide()
    assert(not next(picker.events) and not picker.pendingItem, "F04: hidden picker retains item watches")
    ready = true
    event(picker, "ITEM_DATA_LOAD_RESULT", id, true)
    assert(not picker.addB:IsEnabled(), "F04: a hidden picker refreshed its lookup")
    C_Item.GetItemNameByID, C_Item.GetItemIconByID, C_Item.RequestLoadItemDataByID = name, icon, request
end)

Run("U15", function()
    local play = S.CooldownManagerPlaySound
    S.CooldownManagerPlaySound = function() return false end
    Page.ClearNote()
    assert(Page.PlaySound("file:123") == false and Page.noteError and Page.note,
        "U15: false playback result failed silently")
    S.CooldownManagerPlaySound = nil
    Page.ClearNote()
    assert(Page.PlaySound("lsm:Missing-Pkg3") == false and Page.noteError and Page.note,
        "U15: unknown shared media failed silently")
    assert(Page.SoundLabel("lsm:Missing-Pkg3") == "The sound Missing-Pkg3 is unavailable.",
        "U15: unresolved stored sound looks available")
    assert(Page.SoundLabel("lsm:Bell") == "Bell", "U15: valid media was marked unavailable")
    Page.ClosePopups()
    assert(Page.OpenSoundPicker(CreateFrame("Button"), "lsm:Missing-Pkg3"))
    assert(Page.soundPicker.items[2].text == Page.SoundLabel("lsm:Missing-Pkg3"),
        "U15: missing stored media disappeared from the picker")
    Page.soundPicker:Hide()
    local file = PlaySoundFile
    PlaySoundFile = function() return true end
    Page.ClearNote()
    assert(Page.PlaySound("lsm:Bell") and Page.note == nil, "U15: successful fallback was reported as failure")
    PlaySoundFile, S.CooldownManagerPlaySound = file, play
end)

Run("U16", function()
    Page.ClosePopups()
    assert(Page.OpenSoundPicker(CreateFrame("Button"), ""))
    local sounds = Page.soundPicker
    sounds.search:SetText("No sound matches Pkg3")
    Page.FilterSounds()
    assert(sounds.empty and sounds.empty:IsShown() and sounds.empty:GetText() == "No matching sounds.",
        "U16: unmatched sound search shows a blank panel")
    assert(sounds.clear and sounds.clear:IsShown(), "U16: empty search has no Clear search action")
    Click(sounds.clear)
    assert(sounds.search:GetText() == "" and not sounds.empty:IsShown() and not sounds.clear:IsShown()
        and sounds.rows[1]:IsShown(), "U16: clearing the search did not restore the list")
    local first = sounds.rows[1]
    Page.FilterSounds()
    assert(sounds.rows[1] == first, "U16: filter rebuild replaced pooled rows")
    sounds:Hide()
end)

Run("U14", function()
    S.Config(ID).muteSounds = true
    Page.ClosePopups()
    Page.OpenSoundPicker(CreateFrame("Button"), "lsm:Bell")
    assert(Page.soundPicker.muteNote and Page.soundPicker.muteNote:IsShown(), "U14: sound controls hide mute state")
    Page.soundPicker:Hide()
    assert(Page.TogglePopover({ key = "a1459", family = 2, name = "Buff" }, CreateFrame("Button")))
    -- No direct PaintSoundControls call: opening the popover must paint the note.
    local row = Page.popover.rows.lossSound
    assert(row.muteNote and row.muteNote:IsShown() and row.muteNote:GetText() == "Alerts are muted.",
        "U14: opening the popover with muted alerts omitted the note")
    local showTip, text = Page.ShowTip
    Page.ShowTip = function(_, _, tip) text = tip end
    row.play.hooks.OnEnter(row.play)
    assert(text == "This sound preview ignores mute.", "U14: Play tooltip hides forced playback")
    Page.ShowTip = showTip
    local note = row.muteNote
    S.Config(ID).muteSounds = false
    Page.PaintPopover()
    assert(not note:IsShown() and row.muteNote == note, "U14: mute toggle did not reuse and hide the note")
    Page.ClosePopups()
end)

local function FlashFixture(row)
    if row.flashFixture then return end
    row.flashFixture = true
    function row:GetPoint(i) return unpack(self.points[i or 1]) end
    local create = row.CreateTexture
    row.CreateTexture = function(self, ...)
        local texture = create(self, ...)
        function texture:CreateAnimationGroup()
            local animation = { SetFromAlpha = function(self, v) self.from = v end,
                SetToAlpha = function(self, v) self.to = v end, SetDuration = function(self, v) self.duration = v end }
            return { CreateAnimation = function() return animation end, SetScript = function(self, _, fn) self.finish = fn end,
                Play = function(self) self.played = true; self.plays = (self.plays or 0) + 1 end, Stop = function() end, animation = animation }
        end
        return texture
    end
end

-- The search rows of the spell options and the resolver the host would call.
local function SpellSearch()
    local resolver
    Page.spellSearchRegistered = nil
    P.M.RegisterSearchTargetResolver = function(_, fn) resolver = fn; return true end
    P.AppendToolSearchActions, P.AppendGraphicsSearchRows = function() end, function() end
    P.QualityOfLifeSearchFeatures = {}
    assert(originalLoad(root .. "/MSUF_Suite_Options/Menu/SearchActions.lua"))("test", P)
    local rows, pages = {}, {}
    for _, page in ipairs(P.pages) do pages[page.key] = page end
    P.AppendSearchActionRows(rows, pages)
    local function Find(label)
        for _, row in ipairs(rows) do if row.label == label then return row end end
    end
    return resolver, rows, Find
end
-- Every popover row, existing and new, gets the animation fixture.
local function FlashRows()
    if Page.popover then
        for _, row in pairs(Page.popover.rows) do FlashFixture(row) end
    end
    local createFrame = CreateFrame
    CreateFrame = function(...)
        local frame = createFrame(...)
        FlashFixture(frame)
        return frame
    end
    return function() CreateFrame = createFrame end
end

Run("U18", function()
    local resolver, rows, Find = SpellSearch()
    local target = Find("Sound when lost")
    assert(target and target.prepareKind == "suiteCDMSpell" and target.prepareValue == "lossSound" and resolver,
        "U18: spell-option search stops at the list without a reveal target")
    local _, prepared = resolver(Page.PAGE, target)
    assert(not prepared.prepareKind and target.prepareKind == "suiteCDMSpell", "U18: resolver mutated the saved result")
    assert(Page.SpellSearchHint() == "Click a spell to change Sound when lost.", "U18: search did not set list hint")
    Page.ClosePopups()
    -- PaintPopover itself reveals the row.
    local restore = FlashRows()
    assert(Page.TogglePopover({ key = "a1459", family = 2, name = "Buff" }, CreateFrame("Button")))
    local pop, row = Page.popover, Page.popover.rows.lossSound
    assert(pop.scroll:GetVerticalScroll() > 0 and row.searchFlash:IsShown() and row.searchAnimation.played,
        "U18: next popover open did not scroll to and highlight the matching row")
    assert(pop.scroll:GetVerticalScroll() <= pop.content:GetHeight() - (pop:GetHeight() - pop.top - 10),
        "U18: reveal scrolled past the end of the list")
    assert(row.searchAnimation.animation.duration == 1.2 and not Page.searchSpellOption, "U18: reveal is not bounded/consumed")
    row.searchAnimation.finish()
    assert(not row.searchFlash:IsShown(), "U18: brief highlight did not finish")
    local flash = row.searchFlash
    resolver(Page.PAGE, target)
    assert(not pop:IsShown(), "U18: search kept an old popover open")
    assert(Page.TogglePopover({ key = "a1459", family = 2, name = "Buff" }, CreateFrame("Button")))
    assert(row.searchFlash == flash and row.searchAnimation.played, "U18: reveal did not reuse the highlight")
    for _, candidate in ipairs(rows) do if candidate.label == "Stack comparison" then target = candidate end end
    resolver(Page.PAGE, target)
    assert(Page.TogglePopover({ key = "a1459", family = 2, name = "Buff" }, CreateFrame("Button")))
    assert(pop.rows.stackGlow.searchFlash:IsShown() and not Page.searchSpellOption,
        "U18: inline comparison search did not reveal its host row")
    restore()
    Page.ClosePopups()
end)

-- A search for a spell option ends with what it was started for.
Run("U18b", function()
    local resolver, _, Find = SpellSearch()
    local restore = FlashRows()
    local buff = { key = "a1459", family = 2, name = "Buff" }
    local function Search(label)
        Page.ClosePopups()
        resolver(Page.PAGE, Find(label))
    end
    local function Plays()
        local row = Page.popover.rows.lossSound
        return row.searchAnimation and row.searchAnimation.plays or 0
    end
    assert(Page.TogglePopover(buff, CreateFrame("Button")))
    Page.ClosePopups()
    Page.Select("ess")
    Search("Remove from bar")
    assert(Page.SpellSearchHint() == "Click a spell, then use Remove from bar.", "U18b: an action reads like a setting")
    Search("Sound when lost")
    assert(Page.SpellSearchHint() == "Click a spell to change Sound when lost.")
    -- A bar change.
    Page.Select("buf")
    assert(Page.SpellSearchHint() == nil and Page.searchSpellOption == nil, "U18b: the hint outlived a bar change")
    local plays = Plays()
    assert(Page.TogglePopover(buff, CreateFrame("Button")))
    assert(Plays() == plays, "U18b: a popover revealed a search from another bar")
    Page.ClosePopups()
    -- A new note.
    Search("Sound when lost")
    Page.Note("Moved it.")
    Page.ClearNote()
    assert(Page.SpellSearchHint() == nil, "U18b: the hint came back after a note")
    assert(Page.TogglePopover(buff, CreateFrame("Button")))
    assert(Plays() == plays, "U18b: a popover revealed a search that a note ended")
    Page.ClosePopups()
    -- The page hiding; a cached layout hiding late is not the page.
    Search("Sound when lost")
    Page.Deactivate({})
    assert(Page.SpellSearchHint(), "U18b: a cached layout hiding ended the search")
    Page.Deactivate(Page.ui)
    assert(Page.SpellSearchHint() == nil and Page.searchSpellOption == nil, "U18b: the hint outlived the page")
    restore()
    Page.ClosePopups()
end)
Run("U19", function()
    local ensure, setPreview = Page.EnsureRuntime, S.CooldownManagerSetPreview
    local requested
    Page.EnsureRuntime = function() end
    Page.previewOn, Page.simulating = false, false
    S.CooldownManagerSetPreview = function(on)
        requested = on
        if on then error("preview activation failure") end
        return true
    end
    local ok, failure = pcall(Page.Activate)
    assert(not ok and tostring(failure):find("preview activation failure", 1, true), "U19: activation failure not exercised")
    assert(requested == true and Page.previewOn == false, "U19: wrong partial activation state")
    Page.Deactivate({})
    assert(requested == true, "U19: stale layout cancelled the current preview")
    Page.Deactivate(Page.ui)
    assert(requested == false, "U19: failed activation left runtime preview requested after close")
    S.CooldownManagerSetPreview = function(on) requested = on; return not on end
    Page.Activate()
    assert(requested == true and Page.previewOn == false, "U19: inactive module did not retain its pending request")
    Page.Deactivate(Page.ui)
    assert(requested == false, "U19: closing inactive module left a future preview request")
    Page.EnsureRuntime, S.CooldownManagerSetPreview = ensure, setPreview
end)
print("Package 3 usability contracts passed" .. (only and (": " .. only) or ""))
