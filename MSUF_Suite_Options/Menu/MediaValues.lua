local _, P = ...
local M, Tr = P.M, P.Tr
-- Cold menu choices; runtime painters resolve selected media only on a style change.
function P.FontValues(selected, defaultLabel)
    local values = { { value = "", text = Tr(defaultLabel or "MSUF global font (default)") } }
    local seen = { [""] = true }
    local source = M.GlobalPage and M.GlobalPage.FontValues and M.GlobalPage.FontValues(false) or {}
    for _, entry in ipairs(source) do
        if entry.value ~= nil and not seen[entry.value] then
            values[#values + 1] = { value = entry.value, text = entry.text }
            seen[entry.value] = true
        end
    end
    if type(selected) == "string" and selected ~= "" and not seen[selected] then
        values[#values + 1] = { value = selected, text = Tr("Unavailable font: %s"):format(selected) }
    end
    return values
end

function P.TextureValues(selected)
    local items = M.StatusBarTextureItems and M.StatusBarTextureItems(Tr("Module default")) or {}
    local values, seen = {}, {}
    if not (items[1] and items[1].value == "") then
        values[1] = { value = "", text = Tr("Module default") }
        seen[""] = true
    end
    for _, entry in ipairs(items) do
        if entry.value ~= nil and not seen[entry.value] then
            values[#values + 1] = entry
            seen[entry.value] = true
        end
    end
    if type(selected) == "string" and selected ~= "" and not seen[selected] then
        values[#values + 1] = { value = selected, text = Tr("Unavailable texture: %s"):format(selected) }
    end
    return values
end

function P.BorderValues(selected)
    local values = { { value = "", text = Tr("Module default") } }
    local media = P.Suite.SharedMedia()
    local names = media and media:List("border") or {}
    local found = selected == ""
    for _, name in ipairs(names) do
        values[#values + 1] = { value = name, text = name }
        found = found or name == selected
    end
    if selected ~= "" and not found then values[#values + 1] = { value = selected, text = selected } end
    return values
end

