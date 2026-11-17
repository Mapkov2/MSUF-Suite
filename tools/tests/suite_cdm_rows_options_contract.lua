local root = assert(arg[1], "repository root required")
-- Exercise the visible row controls and their gates through the real page.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_options_contract.lua", [=[
do (function()
local basics = ctx.sections[2]
for _, suffix in ipairs({ "size", "laterSize", "perRow", "laterPerRow", "maxIcons" }) do
    assert(Control(suffix).parent == basics, "row settings must stay together in open Basics: " .. suffix)
end
local order = {}
for i, widget in ipairs(ctx.widgets) do order[widget] = i end
assert(order[Control("laterSize")] == order[Control("size")] + 1, "row sizes belong side by side")
assert(order[Control("laterPerRow")] == order[Control("perRow")] + 1, "row counts belong side by side")
for suffix, expected in pairs({
    perRow = "Icons per row. Cooldown bars can use a different count from the second row onward.",
    maxIcons = "Total icon limit across all rows of this bar. 0 shows all icons. This does not set the number of icons per row.",
    laterPerRow = "Icons per row from the second row onward. 0 uses Icons per row. Maximum icons still limits the whole bar.",
    laterSize = "Icon size from the second row onward. 0 uses Icon size. This is a size, not an icon count.",
}) do
    Fire(Control(suffix), "OnEnter")
    assert(tooltip.shown and table.concat(tooltip.lines, " "):find(expected, 1, true), "row tooltip must explain " .. suffix)
    Fire(Control(suffix), "OnLeave")
end
local reason = "Maximum icons prevents a second row. Raise the limit or set it to 0."
for _, slot in ipairs({ "ess", "c1" }) do
    picker.set(slot)
    if slot == "c1" then Control("kind").set(1) end
    Control("cooldownDuration").set(false)
    Control("perRow").set(5)
    Control("laterPerRow").set(8)
    Control("laterSize").set(24)
    Control("maxIcons").set(0)
    M.RequestRefresh()
    assert(Control("laterPerRow").enabled and Control("laterSize").enabled, "unlimited bars permit later rows")
    Control("maxIcons").set(5)
    M.RequestRefresh()
    assert(not Control("laterPerRow").enabled and not Control("laterSize").enabled, "a total cap of five cannot reach row 2")
    local enabled, why = P.Gates[ID](catalog.rules[CDM.KEYS.c1.laterPerRow])
    assert(not enabled and why == reason and Page.LaterRowsReason(slot) == reason, "the blocked controls must explain the total cap")
    Control("maxIcons").set(6)
    M.RequestRefresh()
    assert(Control("laterPerRow").enabled and Control("laterSize").enabled, "even one place after row 1 enables later rows")
    Control("perRow").set(6)
    M.RequestRefresh()
    assert(not Control("laterPerRow").enabled, "changing the first-row count must refresh the gate")
    Control("maxIcons").set(0)
    M.RequestRefresh()
    assert(Control("laterPerRow").enabled, "zero restores unlimited later rows")
    Control("cooldownDuration").set(true)
    M.RequestRefresh()
    assert(not Control("laterPerRow").enabled and not Control("laterSize").enabled, "timer bars cannot use icon rows")
    Control("cooldownDuration").set(false)
    M.RequestRefresh()
    assert(Control("laterPerRow").enabled and Control("laterSize").enabled, "returning to icons restores the controls")
    assert(Config()[CDM.KEYS[slot].laterPerRow] == 8 and Config()[CDM.KEYS[slot].laterSize] == 24,
        "gating preserves saved row settings")
end
for _, slot in ipairs({ "buf", "bar" }) do
    picker.set(slot)
    M.RequestRefresh()
    assert(not Control("laterPerRow").enabled and not Control("laterSize").enabled, "aura bars use their own row rules")
end
print("suite_cdm_rows_options_contract: ok")
end)() end
]=], "-- Basics holds the most used settings of the bar, the attachment complete.")
