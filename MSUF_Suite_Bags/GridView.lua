local _, P = ...
local S, M = P.Suite, P.BagsModule
-- Widgets and text shared by the bag view (InventoryView.lua) and the bank
-- view (BankInventory.lua): fonts that follow the MSUF font, buttons, group
-- titles, row counters and the fallback when a selected group disappears.
local G = { texts = setmetatable({}, { __mode = "k" }) }
P.GridView = G

-- The chosen bag font, else the global MSUF font. A path (never nil), so a
-- changed global font is noticed by the cached comparison below.
function G.FontPath()
    return S.ResolveFont(M.config.font) or S.GlobalFontPath()
end

local function ApplyFont(text, path)
    if text.suiteFontPath == path then return end
    S.SetFont(text, path, G.texts[text], "OUTLINE")
    text.suiteFontPath = path
end

function G.Font(parent, size)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    text:SetJustifyH("LEFT")
    G.texts[text] = size or 12
    ApplyFont(text, G.FontPath())
    return text
end

-- Runs on every module refresh, which a global MSUF font change triggers.
function G.RefreshFonts()
    local path = G.FontPath()
    for text in pairs(G.texts) do ApplyFont(text, path) end
end

function G.Button(parent, label, width, callback, height)
    local button = S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    button:SetText(S.Text(label))
    button:SetScript("OnClick", callback)
    return button
end

-- Built-in group names are Suite English text; set, category and bank tab
-- names are the player's own words, bag, slot and material names come
-- localized from the client. The expansion suffix is composed after the
-- translation, so each part reaches the reader in their language.
function G.GroupLabel(group)
    local label = group.translate and S.Text(group.label) or group.label
    if group.expansionName then return string.format(S.Text("%s - %s"), label, group.expansionName) end
    return label
end

function G.CountLabel(label, count)
    return string.format(S.Text("%s (%d)"), label, count)
end

-- Header label of a group cell, from a pool owned by the view.
function G.PaintHeader(pool, index, parent, anchor, x, y, width, group)
    local label = pool[index]
    if not label then
        label = G.Font(parent)
        pool[index] = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetText(G.GroupLabel(group))
    label:Show()
    return label
end

function G.PositionText(text, scroll, visibleRows, lineCount)
    if lineCount > 0 then
        text:SetText(string.format(S.Text("Rows %d-%d of %d"), scroll + 1,
            math.min(lineCount, scroll + visibleRows), lineCount))
    else
        text:SetText(S.Text("No matching items"))
    end
end

-- A movable Suite window that Escape closes. Blizzard's CloseSpecialWindows
-- walks UISpecialFrames through securecall (UIParentPanelManager.lua).
function G.Window(name, width, height, title)
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
function G.Build(Model, model, items, config, state, context, selected)
    context.selected = selected
    Model.Build(model, items, config, state, context)
    if selected and selected ~= "all" and not model.groupsByKey[selected] then
        context.selected = "all"
        Model.Build(model, items, config, state, context)
        return "all"
    end
    return selected
end
