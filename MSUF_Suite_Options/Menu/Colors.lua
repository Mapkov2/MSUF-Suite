local _, P = ...
local W, Tr, HM = P.W, P.Tr, P.HM

local function SkinColorRow(skin, entry)
    local key = entry[1]
    return {
        id = "skin." .. key,
        kind = "color",
        label = Tr(skin.SourceText(entry[2]) or key),
        get = function()
            local color = skin.Theme.GetColorTable(key)
            return color[1], color[2], color[3], color[4]
        end,
        set = function(r, g, blue, alpha)
            skin.Theme.SetColor(key, r, g, blue, alpha)
            P.Refresh()
        end,
        settingKey = "msufsuite.skin." .. key,
        sectionId = "colors_suite_skin",
    }
end

-- Loading the skin engine and its palette belongs to opening that section.
local function SkinColorsProvider()
    local skin = _G.MapkoSkin
    if not skin and not P.Combat() then
        P.Suite.Skin.EnsureEngine()
        skin = _G.MapkoSkin
    end
    if not (skin and skin.addonName == "MSUF_Suite_Skin" and skin.Theme and skin.ColorOrder) then return end
    return skin
end

function P.BuildSkinColors(ctx, b)
    P.LazySection(b, "colors_suite_skin", Tr("Suite skin"), false, {
        content = function(section)
            local skin = SkinColorsProvider()
            if not skin then return -18 end
            local width = math.max(240, (HM.GetSectionWidth(section) or b.width or 720) - 32)
            local rows = {}
            for _, entry in ipairs(skin.ColorOrder) do rows[#rows + 1] = SkinColorRow(skin, entry) end
            local grid = W.SettingsRows(ctx, section, { x = 16, y = -18, width = width, columns = 2, rows = rows })
            return grid.bottomY
        end,
        shell = function(section)
            P.AttachSectionReset(ctx, section, "Suite skin", function()
                if P.Combat() then return false end
                local skin = SkinColorsProvider()
                if not skin or not skin.Theme.ResetColors then return false end
                local ok = P.WithHistory("Reset Suite skin colors", "suite:skin.colors.reset", function()
                    skin.Theme.ResetColors()
                    return true
                end)
                if ok then P.Refresh() end
                return ok
            end)
        end,
        finish = function(section, y) P.FinishBody(b, section, y) end,
    })
end
