local _, P = ...
local Kit = P.SkinPageKit

function P.BuildSkinQuestLogSection(ctx, builder, skin)
    local values = {
        { value = "blizzard", text = P.Tr("Blizzard") },
        { value = "compact", text = P.Tr("Compact") },
    }
    local row = Kit.Row("dropdown", "Quest list layout", "questLog.layout", "quests",
        function() return skin.WorldMapQuests.GetLayout() end,
        function(value)
            Kit.Change(skin, "Quest list layout", "questLog.layout",
                function() return skin.WorldMapQuests.SetLayout(value) end)
        end, values)
    Kit.Section(ctx, builder, "quests", "World map and quest log",
        "Switch instantly between Blizzard and a compact quest list with level, title and progress. Search, tracking and quest tooltips stay available.",
        { row }, false)
end
