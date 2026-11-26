local _, P = ...
local Page = P.CDMPage
if not Page then return end
local CDM = P.Suite.CDM

-- A search for a spell option: the option the next popover reveals and the
-- hint under the grid. It ends with that reveal, a bar change, a new note or
-- the page hiding (Page.ClearSpellSearch, CooldownManagerBars.lua).
local function SearchOption()
    if Page.searchSpellOption and Page.searchSpellSlot ~= Page.selected then Page.ClearSpellSearch() end
    return Page.searchSpellOption
end
function P.ResolveCDMSpellSearchTarget(pageKey, target)
    if pageKey ~= Page.PAGE or not target or target.prepareKind ~= "suiteCDMSpell" then return end
    if P.Combat() then return false end
    Page.ClosePopups()
    -- A number picks a header action, a name a spell option.
    local key = tonumber(target.prepareValue) or target.prepareValue
    Page.searchSpellOption, Page.searchSpellSlot = key, Page.selected
    Page.searchSpellHint = string.format(type(key) == "number" and P.Tr("Click a spell, then use %s.")
        or P.Tr("Click a spell to change %s."), target.label)
    local prepared = {}
    for name, value in pairs(target) do prepared[name] = value end
    prepared.prepareKind, prepared.prepareValue = nil, nil
    return pageKey, prepared
end
function Page.SpellSearchHint()
    SearchOption()
    return Page.searchSpellHint
end
-- Called at the end of PaintPopover. Layout has not run yet, so the scroll
-- range comes from the heights PaintPopover just set, not from the ScrollFrame.
function Page.PaintSpellOptionFeedback(pop)
    Page.PaintSoundControls(pop)
    local key = SearchOption()
    local row = key and (pop.rows[key] or type(key) == "number" and pop.actions[key])
    if key and not row then
        for _, field in ipairs(Page.FIELDS) do
            if field.op == key then
                row = pop.rows[field.key]
                break
            end
        end
    end
    if not row or not row:IsShown() then return false end
    local scroll, content = pop.scroll, pop.content
    local _, relative, _, _, y = row:GetPoint(1)
    if relative == content then
        -- The viewport starts at pop.top and ends 10 px above the popover's bottom.
        local range = content:GetHeight() - (pop:GetHeight() - pop.top - 10)
        scroll:SetVerticalScroll(math.max(0, math.min(-y, range)))
    end
    if not row.searchFlash then
        local flash = row:CreateTexture(nil, "OVERLAY")
        flash:SetAllPoints(row)
        flash:SetColorTexture(Page.Accent())
        local group = flash:CreateAnimationGroup()
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.3)
        fade:SetToAlpha(0)
        fade:SetDuration(1.2)
        group:SetScript("OnFinished", function() flash:Hide() end)
        row.searchFlash, row.searchAnimation = flash, group
    end
    row.searchFlash:Show()
    row.searchAnimation:Stop()
    row.searchAnimation:Play()
    Page.ClearSpellSearch()
    Page.ui.PaintNote()
    return true
end
function P.ResolveCDMInspectionTarget(pageKey, target)
    if pageKey ~= Page.PAGE or target.prepareKind ~= "suiteCDMBar" then return nil end
    if P.Combat() or not CDM.KEYS[target.prepareValue] then return false end
    if not Page.Select(target.prepareValue) then return false end
    local prepared = {}
    for key, value in pairs(target) do prepared[key] = value end
    prepared.prepareKind, prepared.prepareValue = nil, nil
    return pageKey, prepared
end
