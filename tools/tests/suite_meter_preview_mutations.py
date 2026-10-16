"""Reject broken interaction paths in memory, without changing the checkout."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve().as_posix()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
cases = [
    ("Workspace.lua", 'onActivate = function() if ui and ui.refreshPreview then ui.refreshPreview() end end,',
     'onActivate = function() end,',
     "suite_meter_preview_editor_contract.lua", "interactive preview did not build"),
    ("PreviewCanvas.lua", 'ui.header:IsVisible() and ui.ctx.wrapper:IsVisible()', 'ui.header:IsVisible()',
     "suite_meter_preview_editor_contract.lua", "preview painted before its owning page was shown"),
    ("DamageMeterPreviewEditor.lua", 'handle.canMove = prefix ~= "window"',
     'handle.canMove = true; if prefix == "window" then handle.offsetPrefix = "w" .. preview.selected() end',
     "suite_meter_preview_editor_contract.lua", "window/header retained an Edit Mode drag"),
    ("DamageMeterPreviewEditor.lua", 'window = 0, header = 1, bars = 2', 'window = 0, header = 7, bars = 2',
     "suite_meter_preview_editor_contract.lua", "header surface can intercept an element hit"),
    ("DamageMeterPreviewEditor.lua", 'previousHeight ~= preview.propertiesHeight or selectionChanged', 'previousHeight ~= preview.propertiesHeight',
     "suite_meter_preview_editor_contract.lua", "header text properties overlap the offset toolbar"),
    ("DamageMeterPreviewProperties.lua", 'if handle.canMove then',
     'if true then handle.offsetPrefix = handle.offsetPrefix == "window" and "w" .. preview.selected() or handle.offsetPrefix',
     "suite_meter_preview_editor_contract.lua", "header reset moved the live window"),
    ("DamageMeterPreviewProperties.lua", 'container:SetShown(key ~= nil)', 'widget:SetShown(key ~= nil)',
     "suite_meter_preview_editor_contract.lua", "inactive native property parts remain visible"),
    ("DamageMeterPreviewProperties.lua", 'W.SettingsRows(preview.ui.ctx, slot,', 'W.SettingsRows(preview.ui.ctx, panel,',
     "suite_meter_preview_editor_contract.lua", "native property parts escape their visibility container"),
    ("DamageMeterPreviewProperties.lua", 'math.max(24, math.ceil(title:GetStringHeight()) + 8)', '24',
     "suite_meter_preview_editor_contract.lua", "wrapped field title overlaps its slider"),
    ("DamageMeterPreviewEditor.lua", 'local compact, narrow = width < 600, width < 260', 'local compact, narrow = false, false',
     "suite_meter_preview_editor_contract.lua", "narrow toolbar part escapes its width"),
    ("DamageMeterPreview.lua", 'local selectionHeight = preview.selectionHeight or 0',
     'local selectionHeight = preview.selection and preview.selection:IsShown() and 32 or 0',
     "suite_meter_preview_editor_contract.lua", "property panel overlaps the preview layers"),
    ("Rows.lua", "if holder:GetFrameLevel() ~= level then holder:SetFrameLevel(level) end", "",
     "suite_meter_icon_layout_contract.lua", "row border did not follow its bar slot"),
    ("DamageMeterPreviewProperties.lua", "math.max(0, math.ceil(panel.label:GetStringHeight()) - 12)", "0",
     "suite_meter_preview_editor_contract.lua", "icon controls lack reserved space"),
    ("DamageMeterPreviewProperties.lua", "preview.propertiesHeight, panel.lastHandle = 0, nil", "preview.propertiesHeight = 0",
     "suite_meter_preview_editor_contract.lua", "reselecting prior element leaves visible properties with zero reserved height"),
    ("DamageMeterPreview.lua", "stage:SetClipsChildren(true)", "viewport:SetClipsChildren(true)",
     "suite_meter_preview_editor_contract.lua", "sample clipping hides the offset toolbar"),
    ("Rows.lua", 'row.track = S.CreateTexture(bar, nil, "BACKGROUND")',
     'row.track = S.CreateTexture(row, nil, "BACKGROUND")',
     "suite_meter_icon_layout_contract.lua", "bar track did not follow its selected draw plane"),
    ("Rows.lua", 'list and c.iconOffsetX or 0, list and c.iconOffsetY or 0', '0, 0',
     "suite_meter_icon_layout_contract.lua", "class/spec icons did not share their position"),
    ("DamageMeterPreview.lua", '"iconOffset", "Bar icons"', '"nameOffset", "Bar icons"',
     "suite_meter_preview_editor_contract.lua", "icon drag did not write shared class/spec offsets"),
    ("DamageMeterPreview.lua", 'Properties(hits.icon, "iconSize",', 'Properties(hits.icon, "headerIconSize",',
     "suite_meter_preview_editor_contract.lua", "icon properties did not write shared size/layer"),
    ("DamageMeterPreview.lua", 'key .. "Offset", buttonLabels[key]', '"buttonsOffset", buttonLabels[key]',
     "suite_meter_preview_editor_contract.lua", "header drag did not write its own offset"),
    ("Window.lua", 'button:SetPoint("RIGHT", win.header, "RIGHT",', 'button:SetPoint("RIGHT", previous or win.header, "RIGHT",',
     "suite_meter_menu_preview_contract.lua", "header button retains a sibling anchor chain"),
    ("Window.lua", 'local elementSize = c[kind .. "Size"] > 0 and c[kind .. "Size"] or size', 'local elementSize = size',
     "suite_meter_menu_preview_contract.lua", "individual header size did not reach runtime"),
    ("Window.lua", '+ c.buttonsOffsetX + c[kind .. "OffsetX"]', '+ c.buttonsOffsetX',
     "suite_meter_menu_preview_contract.lua", "individual header offsets did not reach runtime"),
    ("Window.lua", 'c.titleSize > 0 and c.titleSize or c.headerFontSize', 'c.headerFontSize',
     "suite_meter_menu_preview_contract.lua", "individual header font size did not reach runtime: title"),
    ("Window.lua", 'c.headerTimerSize > 0 and c.headerTimerSize or c.headerFontSize', 'c.headerFontSize',
     "suite_meter_menu_preview_contract.lua", "individual header font size did not reach runtime: timer"),
    ("Window.lua", 'win.timer:SetPoint("RIGHT", win.header, "RIGHT",', 'win.timer:SetPoint("RIGHT", win.firstButton, "RIGHT",',
     "suite_meter_menu_preview_contract.lua", "header text retains a sibling anchor chain"),
    ("DamageMeterPreviewProperties.lua", 'math.min(fallback, P.Get(ID, "headerHeight"))', 'fallback',
     "suite_meter_preview_editor_contract.lua", "Auto header button size differs from the runtime clamp"),
    ("DamageMeterPreviewProperties.lua", 'if preview.properties.refreshing then return false end', '',
     "suite_meter_preview_editor_contract.lua", "selection range clamp mutated name font"),
    ("DamageMeterPreviewProperties.lua", 'handle.widthSetting == "windowWidth"', 'handle.offsetPrefix == "window"',
     "suite_meter_preview_editor_contract.lua", "header size scope claims to affect only the selected window"),
    ("DamageMeterPreviewProperties.lua", 'if key then values[key] = rules[key].default end', 'if key and key ~= "iconLayer" then values[key] = rules[key].default end',
     "suite_meter_preview_editor_contract.lua", "icon reset did not restore shared defaults"),
    ("DamageMeterPreviewProperties.lua", 'if preview.inCombat or P.Combat() or not preview.viewport:IsVisible()', 'if P.Combat() or not preview.viewport:IsVisible()',
     "suite_meter_preview_editor_contract.lua", "early combat wrote icon settings"),
    ("DamageMeterPreviewEditor.lua", "if focus and handle then E.Open(preview, handle) end",
     "if focus and handle then preview.ui:Focus(handle.previewSection) end",
     "suite_meter_preview_editor_contract.lua", "click did not highlight a control"),
    ("DamageMeterPreviewEditor.lua", "scale = function() return preview.stage:GetEffectiveScale() end",
     "scale = function() return 1 end",
     "suite_meter_preview_editor_contract.lua", "scaled drag did not persist native offsets"),
    ("DamageMeterPreviewLayers.lua", "Show(row, not win.capacity or i <= win.capacity)",
     "Show(row, layers.bars and (not win.capacity or i <= win.capacity))",
     "suite_meter_preview_editor_contract.lua", "bar paint layer hid row children"),
    ("DamageMeterPreviewEditor.lua", "if preview.inCombat or P.Combat() or not preview.viewport:IsVisible()",
     "if P.Combat() or not preview.viewport:IsVisible()",
     "suite_meter_preview_editor_contract.lua", "early combat wrote icon offsets"),
    ("Window.lua", 'timerRight - c.headerFontSize * 3 - 4 + c.titleOffsetX, M.style.baseline + c.titleOffsetY)',
     'timerRight - c.headerFontSize * 3 - 4 + c.titleOffsetX, c.titleOffsetY)',
     "suite_meter_menu_preview_contract.lua", "timer movement pulled or stretched the title field"),
    ("Rows.lua", 'value:SetPoint("RIGHT", bar, "RIGHT", -3 + vx, style.baseline + vy)',
     'value:SetPoint("RIGHT", bar, "RIGHT", -3, style.baseline)',
     "suite_meter_menu_preview_contract.lua", "value offset did not reach native rows"),
]
for filename, before, after, test, expected in cases:
    folder = "Menu" if filename in ("Workspace.lua", "PreviewCanvas.lua") else "Pages"
    target = f"MSUF_Suite_Options/{folder}/{filename}" if filename not in ("Rows.lua", "Window.lua") else f"MSUF_Suite_DamageMeter/{filename}"
    script = f'''
arg = {{ {json.dumps(root)}, "Mainline" }}
local original = loadfile
loadfile = function(path)
    if path:sub(-{len(target)}) == {json.dumps(target)} then
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a"); file:close()
        local a, z = assert(source:find({json.dumps(before)}, 1, true))
        return assert(loadstring(source:sub(1, a - 1) .. {json.dumps(after)} .. source:sub(z + 1), "@" .. path))
    end
    return original(path)
end
assert(original(arg[1] .. "/tools/tests/{test}"))()
'''
    run = subprocess.run([lua, "-"], input=script, cwd=root, capture_output=True, text=True, errors="replace")
    assert run.returncode and expected in run.stderr, f"{filename} ({before}): unexpected mutation result\n{run.stderr}"
print(f"Meter preview: {len(cases)} interaction/runtime regressions rejected without modifying source")
