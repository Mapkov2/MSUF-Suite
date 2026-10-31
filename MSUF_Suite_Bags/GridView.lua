local _, P = ...
local S, M = P.Suite, P.BagsModule
-- Widgets and text shared by the bag view (InventoryView.lua) and the bank
-- view (BankInventory.lua): fonts that follow the MSUF font, buttons, group
-- titles, row counters and the fallback when a selected group disappears.
local GridView = { texts = setmetatable({}, { __mode = "k" }) }
P.GridView = GridView

-- The chosen bag font, else the global MSUF font. A path (never nil), so a
-- changed global font is noticed by the cached comparison below.
function GridView.FontPath()
    return S.ResolveFont(M.config.font) or S.GlobalFontPath()
end

local function ApplyFont(text, path)
    if text.suiteFontPath == path then return end
    S.SetFont(text, path, GridView.texts[text], "OUTLINE")
    text.suiteFontPath = path
end

function GridView.Font(parent, size)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    text:SetJustifyH("LEFT")
    GridView.texts[text] = size or 12
    ApplyFont(text, GridView.FontPath())
    return text
end

-- Runs on every module refresh, which a global MSUF font change triggers.
function GridView.RefreshFonts()
    local path = GridView.FontPath()
    for text in pairs(GridView.texts) do ApplyFont(text, path) end
end

-- Parented after creation (P.ChildFrame, Bootstrap.lua): these buttons sit
-- in Blizzard's bag and bank windows.
function GridView.Button(parent, label, width, callback, height)
    local button = P.ChildFrame("Button", parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    button:SetText(S.Text(label))
    button:SetScript("OnClick", callback)
    return button
end

-- Built-in group names are Suite English text; set, category and bank tab
-- names are the player's own words, bag, slot and material names come
-- localized from the client. The expansion suffix is composed after the
-- translation, so each part reaches the reader in their language.
function GridView.GroupLabel(group)
    local label = group.translate and S.Text(group.label) or group.label
    if group.expansionName then return string.format(S.Text("%s - %s"), label, group.expansionName) end
    return label
end

function GridView.CountLabel(label, count)
    return string.format(S.Text("%s (%d)"), label, count)
end

-- A collapsible group's header is also a button: a click flips the group
-- (toggle(key)); a collapsed one shows a plus sign and its item count.
local COLLAPSE_ICON, HEADER_HEIGHT = 16, 18

local function HitClicked(hit)
    hit.toggle(hit.key)
end

local function HitEnter(hit)
    GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.Text(hit.collapsed and "Click to show these items" or "Click to hide these items"))
    GameTooltip:Show()
end

local function HeaderHit(label, parent)
    local hit = label.hit
    if hit then return hit end
    hit = P.ChildFrame("Button", parent)
    hit:SetHeight(HEADER_HEIGHT)
    hit:SetScript("OnClick", HitClicked)
    hit:SetScript("OnEnter", HitEnter)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    hit.plus = S.CreateTexture(hit, nil, "ARTWORK")
    hit.plus:SetSize(COLLAPSE_ICON, COLLAPSE_ICON)
    hit.plus:SetPoint("LEFT", 0, 0)
    hit.plus:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    label.hit = hit
    return hit
end

local function PlaceHit(label, parent, anchor, x, y, width, group, toggle)
    local hit = HeaderHit(label, parent)
    if hit.placeX ~= x or hit.placeY ~= y or hit.placeWidth ~= width or hit.placeAnchor ~= anchor then
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
        hit:SetWidth(width)
        hit.placeX, hit.placeY, hit.placeWidth, hit.placeAnchor = x, y, width, anchor
    end
    local collapsed = group.collapsed == true
    if hit.collapsed ~= collapsed then
        hit.collapsed = collapsed
        hit.plus:SetShown(collapsed)
    end
    hit.key, hit.toggle = group.key, toggle
    if not hit:IsShown() then hit:Show() end
end

-- Header label of a group cell, from a pool owned by the view. toggle makes
-- the header a button that collapses its group.
function GridView.PaintHeader(pool, index, parent, anchor, x, y, width, group, toggle)
    local label = pool[index]
    if not label then
        label = GridView.Font(parent)
        pool[index] = label
    end
    local text = GridView.GroupLabel(group)
    local shift = toggle and group.collapsed and COLLAPSE_ICON or 0
    if shift > 0 then text = GridView.CountLabel(text, group.hidden) end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + shift, y)
    label:SetWidth(width - shift)
    label:SetText(text)
    label:Show()
    if toggle then PlaceHit(label, parent, anchor, x, y, width, group, toggle) elseif label.hit then label.hit:Hide() end
    return label
end

-- Hides every header of a pool, with its button.
function GridView.HideHeaders(pool)
    for i = 1, #pool do
        pool[i]:Hide()
        if pool[i].hit then pool[i].hit:Hide() end
    end
end

function GridView.PositionText(text, scroll, visibleRows, lineCount)
    if lineCount > 0 then
        text:SetText(string.format(S.Text("Rows %d-%d of %d"), scroll + 1,
            math.min(lineCount, scroll + visibleRows), lineCount))
    else
        text:SetText(S.Text("No matching items"))
    end
end

-- A movable Suite window that Escape closes. Blizzard's CloseSpecialWindows
-- walks UISpecialFrames through securecall (UIParentPanelManager.lua).
function GridView.Window(name, width, height, title)
    local frame = S.CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText(S.Text(title))
    UISpecialFrames[#UISpecialFrames + 1] = name
    return frame
end

-- Builds the model; a selected custom or emptied group that vanished returns
-- the view to all items. Returns the selection that was built.
function GridView.Build(Model, model, items, config, state, context, selected)
    context.selected = selected
    Model.Build(model, items, config, state, context)
    if selected and selected ~= "all" and not model.groupsByKey[selected] then
        context.selected = "all"
        Model.Build(model, items, config, state, context)
        return "all"
    end
    return selected
end
