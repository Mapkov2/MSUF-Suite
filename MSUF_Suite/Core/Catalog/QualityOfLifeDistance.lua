local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
B.Module("targetDistance", {
    title = "Target spell-range estimate", page = "suite_qualityOfLife", optIn = true, defaultEnabled = false,
    description = "Movable approximate target range from native spell checks. Values include the target's hitbox; unavailable ranges show dashes.",
    available = function()
        if NS.Client.isForever then return false, "Target spell-range estimates are available only in Retail" end
        return true
    end,
    editElement = "distance",
})
B.Section("targetDistance", "target_distance", "Target spell-range estimate", {
    B.String("format", "Distance format: {range} and {unit}", "{range} {unit}", 80),
    B.Choice("align", "Text alignment", 2, { "Left", "Center", "Right" }),
    B.Bool("attachTarget", "Attach below the target frame"),
    B.Number("width", "Display width", 180, 60, 500, 5),
    B.Number("fontSize", "Font size", 16, 10, 32, 1),
    B.Number("scale", "Scale (percent)", 100, 50, 200, 5),
    B.Color("color", "Text color", "ffffff"),
    B.Number("x", "Horizontal position", 0, -4000, 4000),
    B.Number("y", "Vertical position", -160, -3000, 3000),
    -- Below the target frame the display keeps its own offsets, so switching
    -- placements never moves it 160 pixels away from the frame.
    B.Number("attachX", "Horizontal offset", 0, -500, 500),
    B.Number("attachY", "Vertical offset", -8, -500, 500),
})
-- MSUF Edit Mode owns both placements; the rules stay for profiles and undo.
for _, key in ipairs({ "x", "y", "attachX", "attachY" }) do
    NS.SuiteCatalog.targetDistance.rules[key].hidden = true
end
