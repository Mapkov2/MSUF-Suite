local _, P = ...
local Kit = P.SkinPageKit

local function Option(skin, label, key)
    local path = "addonSkins." .. key
    return Kit.Row("toggle", label, path, "addon_skins",
        function()
            return skin and skin.DB.addonSkins[key] == true or false
        end,
        function(value)
            local current = skin or Kit.Engine()
            return Kit.Change(current, label, path, function()
                return current.AddonSkins.SetOption(key, value)
            end)
        end)
end

-- Use the same catalog for the visible controls and cold search metadata.
-- Search never loads the optional engine or creates the legacy skin editor.
function P.BuildSkinAddonSection(ctx, builder, skin)
    local rows = {
        Option(skin, "Skin other addons", "enabled"),
        Option(skin, "AceGUI / AceConfig windows", "aceGUI"),
    }
    for _, entry in ipairs(P.Suite.AddonSkinDefinitions) do
        rows[#rows + 1] = Option(skin, entry.label, entry.id)
    end
    return Kit.Section(ctx, builder, "addon_skins", "Addon skins",
        "Apply your current skin to supported addon windows. Enable the addons you want to skin.", rows, true)
end
