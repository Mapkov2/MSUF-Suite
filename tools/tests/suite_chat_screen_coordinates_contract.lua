-- Real Chat provider, Suite mover adapter and the host's numeric position path.
local root, flavor, host = assert(arg[1]), arg[2] or "Mainline", assert(arg[3])
local saved = arg
arg = { root, flavor, host, "positions" }
local F = dofile(root .. "/tools/tests/suite_chat_preview_contract.lua")
arg = saved
local env, S, NS, C = F.env, F.Suite.Suite, F.Suite, F.runtime.Chat
local function Load(path, addon, ns)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n") file:close()
    local mutations = {
        rawFields = { "Controller.lua", "screenPosition = true", "screenPosition = false" },
        scale = { "EditMode.lua", "local scale = SpecScale(spec)", "local scale = 1" },
        precision = { "Controller.lua", "precisePosition = true", "precisePosition = false" },
        bounds = { "Controller.lua", "getFrame = C.GetWindowMoverFrame", "getFrame = function() return ChatFrame1 end" },
    }
    local patch = mutations[arg[4]]
    if patch and path:sub(-#patch[1]) == patch[1] then
        local a, b = source:find(patch[2], 1, true)
        assert(a, "mutation site missing")
        source = source:sub(1, a - 1) .. patch[3] .. source:sub(b + 1)
    end
    local chunk = assert(loadstring(source, "@" .. path))
    setfenv(chunk, env)(addon, ns)
end
Load("MSUF_Suite_Modules/EditMode.lua", "MSUF_Suite_Modules", F.runtime)
Load("MSUF_Suite_Chat/Controller.lua", "MSUF_Suite_Chat", F.runtime)
local em, api = env.MSUF_EM2, env.MSUF_EditModeAPI
assert(em and api, "real Edit Mode API is unavailable")
local checks = 0
local function Check(ok, message) checks = checks + 1 assert(ok, message) end
local M, c = C.M, F.c
if arg[4] == "integerSchema" then
    S.catalog.chat.rules.windowX.step, S.catalog.chat.rules.windowY.step = 1, 1
end
c.lockWindowPosition = false
M.active, M.config, M.context = true, c, S.NewContext("chat")
S.states.chat.active, S.editMode = true, true
local frame = env.CreateFrame("Frame", "CoordinateReviewChat", env.UIParent)
frame:SetSize(496, 148)
frame:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 221, 67)
M.positionFrame, M.visuals[frame] = frame, {}
env.ChatFrame1 = frame
c.padding, c.sidebarPanel, c.tabHeight, c.tabPanelGap, c.tabPanel = 4, false, 24, 0, true
C.UpdateWindowMoverBounds(M)
M:RegisterMovers()
local key = "external:msufsuite.chat:window"
local record = em.ExternalElements.GetRecord(key)
Check(record ~= nil, "real Suite Chat mover was not registered")
local caps = api.GetCapabilities()
local controls = {}
for _, control in ipairs(em.ExternalElements.GetControls(key) or {}) do controls[control.id] = control end
Check(controls.windowWidth and controls.windowHeight, "Chat popup is missing size controls")
Check(em.ExternalElements.GetControlValue(key, "windowWidth") == 496
    and em.ExternalElements.GetControlValue(key, "windowHeight") == 148, "size fields did not read live chat dimensions")
if caps.positionFields then
    Check(not controls.windowX and not controls.windowY,
        "Chat still replaces shared screen coordinates with bottom-left profile offsets")
else
    Check(controls.windowX and controls.windowY, "legacy host lost numeric position editing")
end
if not caps.positionFields then
    print("Chat legacy screen position fallback " .. flavor .. ": " .. checks .. " checks passed")
    return
end

-- Native anchoring reports every rectangle in its own effective scale. Model
-- that C++ contract independently of the Suite's stored coordinate convention.
local ui, uiScale = env.UIParent, 1
local uiX, uiY = 37, 29
ui:SetSize(1920, 1080)
ui.GetScale, ui.GetEffectiveScale = function() return uiScale end, function() return uiScale end
ui.GetLeft, ui.GetBottom = function() return uiX end, function() return uiY end
ui.GetRight, ui.GetTop = function() return uiX + 1920 end, function() return uiY + 1080 end
local factors = { TOPLEFT = {0,1}, TOP = {.5,1}, TOPRIGHT = {1,1}, LEFT = {0,.5},
    CENTER = {.5,.5}, RIGHT = {1,.5}, BOTTOMLEFT = {0,0}, BOTTOM = {.5,0}, BOTTOMRIGHT = {1,0} }
local Rect
Rect = function(region)
    local scale = region:GetEffectiveScale()
    if region == ui then return uiX * scale, uiY * scale, 1920 * scale, 1080 * scale end
    local width, height = region.coordinateWidth(region) * scale, region.coordinateHeight(region) * scale
    local anchors = {}
    for index = 1, region:GetNumPoints() do
        local point, relative, edge, x, y = region:GetPoint(index)
        local l, b, w, h = Rect(relative)
        local rp, p = factors[edge], factors[point]
        anchors[index] = { l + rp[1] * w + x * scale, b + rp[2] * h + y * scale, p[1], p[2] }
    end
    local a, b = anchors[1], anchors[2]
    if b and a[3] ~= b[3] then width = (b[1] - a[1]) / (b[3] - a[3]) end
    if b and a[4] ~= b[4] then height = (b[2] - a[2]) / (b[4] - a[4]) end
    return a[1] - a[3] * width, a[2] - a[4] * height, width, height
end
local function Geometry(region)
    region.coordinateWidth, region.coordinateHeight = region.GetWidth, region.GetHeight
    function region:GetEffectiveScale()
        local scale, parent = self:GetScale(), self:GetParent()
        while parent do scale, parent = scale * parent:GetScale(), parent:GetParent() end
        return scale
    end
    function region:GetLeft() local x = Rect(self) return x / self:GetEffectiveScale() end
    function region:GetBottom() local _, y = Rect(self) return y / self:GetEffectiveScale() end
    function region:GetRight() local x, _, w = Rect(self) return (x + w) / self:GetEffectiveScale() end
    function region:GetTop() local _, y, _, h = Rect(self) return (y + h) / self:GetEffectiveScale() end
    function region:GetWidth() local _, _, w = Rect(self) return w / self:GetEffectiveScale() end
    function region:GetHeight() local _, _, _, h = Rect(self) return h / self:GetEffectiveScale() end
end
Geometry(frame)
local bounds = C.GetWindowMoverFrame()
Geometry(bounds)
local comparison = env.CreateFrame("Frame", nil, ui)
comparison:SetPoint("TOPLEFT", bounds, "TOPLEFT", 0, 0)
comparison:SetPoint("BOTTOMRIGHT", bounds, "BOTTOMRIGHT", 0, 0)
Geometry(comparison)
local function Paint()
    M.config = S.Config("chat")
    C.ApplyWindowPosition(M, M.visuals[frame], frame, true)
    C.UpdateWindowMoverBounds(M)
end
S.Apply = function(id) if id == "chat" then Paint() end end
S.Start() -- attach the real profile-history listener; unrelated renderers stay out of this fixture
local core = F.world.core
core.ApplyService.QueueFlush = function() return true end
core.ApplyService.Flush, core.ApplyService.Quiesce = function() end, function() end
core.UF.Apply = function() return true end
env.MSUF_UFCore_NotifyConfigChanged, env.MSUF_ForceReanchorAllUnitFrames_Once = function() end, function() end
Check(em.State.Enter("player") == true, "real Edit Mode session did not start")
em.Movers.Show() -- deliver the native next-frame mover creation before entering coordinates
Check(em.ExternalPopup.Open(key) == true, "real Chat popup did not open")
local mover = assert(em.Movers.Get(key), "real Chat mover did not materialize")
Geometry(mover)
local popup
for _, candidate in ipairs(F.world.widgets.frames) do
    if candidate.frameName == "MSUF_EM2_ExternalPopup" then popup = candidate end
end
Check(popup and popup._positionRow:IsShown(), "Chat popup does not use the common position row")
local function SamePosition()
    em.ExternalPopup.Sync()
    local x, y, width, height = em.Util.FramePositionValues(comparison)
    Check(tonumber(popup.xBox:GetText()) == x and tonumber(popup.yBox:GetText()) == y,
        "Chat coordinates disagree with an ordinary Edit Mode frame at the same visible rectangle")
    return x, y, width, height
end
local function Type(axis, value)
    local box = axis == "x" and popup.xBox or popup.yBox
    box:SetText(tostring(value))
    box:GetScript("OnEnterPressed")(box)
end
local function Set(axis, value)
    Type(axis, value)
    local x, y = SamePosition()
    local actual = axis == "x" and x or y
    Check(actual == value, ("typed coordinate did not land on the requested visible pixel: %s, %s ~= %s")
        :format(axis, actual, value))
end

for _, scale in ipairs({ 0.5, 0.711111, 1 }) do
    uiScale = scale
    for _, nativeScale in ipairs({ 0.75, 1, 1.25, 1.5 }) do
        frame:SetScale(nativeScale)
        for _, side in ipairs({ 0, 1, 2 }) do
            local sidebar = side ~= 0
            c = S.Config("chat")
            c.lockWindowPosition, c.windowX, c.windowY = true, 221, 67
            c.sidebarPanel, c.sidebarSide, c.sidebarWidth = sidebar, math.max(1, side), 28
            Paint()
            local x, y = SamePosition()
            if nativeScale == 1 and not sidebar then
                Check(x == -239 and y == -301, "Chat still reports native origin instead of its painted bounds")
            end
            local bottom = frame:GetBottom()
            Set("x", x - 19)
            Check(math.abs(frame:GetBottom() - bottom) < 0.001, "typing X moved Y")
            local left = frame:GetLeft()
            Set("y", y + 17)
            Check(math.abs(frame:GetLeft() - left) < 0.001, "typing Y moved X")
            local beforeX, beforeY = SamePosition()
            Set("x", beforeX + 1)
            Check(em.Undo.DoUndo() == true, "coordinate Undo failed")
            local undoX, undoY = SamePosition()
            Check(undoX == beforeX and undoY == beforeY, "Undo lost visible coordinates")
            Check(em.Undo.DoRedo() == true, "coordinate Redo failed")
            local redoX, redoY = SamePosition()
            Check(redoX == beforeX + 1 and redoY == beforeY, "Redo lost visible coordinates")
            local physicalX, physicalY = Rect(bounds)
            Check(em.ExternalElements.Nudge(key, -1, -1) == true, "one-pixel nudge failed")
            local nudgeX, nudgeY = SamePosition()
            Check(nudgeX == redoX - 1 and nudgeY == redoY - 1, "nudge used a different scale than numeric editing")
            for step = 2, 25 do
                Check(em.ExternalElements.Nudge(key, -1, -1) == true, "repeated nudge refused")
                local nx, ny = SamePosition()
                Check(nx == redoX - step and ny == redoY - step, "scaled nudge accumulated coordinate drift")
            end
            local afterX, afterY = Rect(bounds)
            Check(math.abs(afterX - physicalX + 25 * uiScale) < .000001
                and math.abs(afterY - physicalY + 25 * uiScale) < .000001, "fractional anchors drifted in physical space")
            local state = em.ExternalElements.CaptureState(key)
            local dx, dy = 7, -3
            Check(em.ExternalElements.ApplyMove(key, state, dx, dy, nil, nil, "preview"), "drag preview failed")
            local px, py = SamePosition()
            Check(px == redoX - 25 + dx and py == redoY - 25 + dy, "drag preview disagrees with numeric/nudge coordinates")
            Check(em.ExternalElements.ApplyMove(key, state, dx, dy, nil, nil, "commit"), "drag commit failed")
            local cx, cy = SamePosition()
            Check(cx == px and cy == py, "drag commit moved away from the visible preview")
        end
    end
end
uiScale, c = 1, S.Config("chat")
frame:SetScale(1.25)
c.sidebarPanel, c.windowX, c.windowY, c.lockWindowPosition = false, 221, 67, true
Paint()
Set("x", 200)
Set("x", -123)
Set("x", 0)
Set("y", 0)
local centerX, centerY = SamePosition()
Check(centerX == 0 and centerY == 0, "center crossing changed the coordinate reference")
local unchangedX, unchangedY = frame:GetLeft(), frame:GetBottom()
Set("x", 0)
Set("y", 0)
Check(frame:GetLeft() == unchangedX and frame:GetBottom() == unchangedY, "unchanged displayed coordinates moved the chat")
uiX, uiY, uiScale = 0, 0, .711111
c = S.Config("chat")
c.sidebarPanel, c.sidebarSide = true, 1
Paint()
Type("x", -4096)
Type("y", -4096)
local cornerX, cornerY = Rect(bounds)
Check(math.abs(cornerX) < .000001 and math.abs(cornerY) < .000001,
    "typed coordinates could not align the painted sidebar and frame with the bottom-left corner")
SamePosition()
Check(em.State.CancelAll() ~= false, "discard failed")
Check(not S.Config("chat").lockWindowPosition, "discard adopted the Suite anchor")

-- An unanchored native window may be far from saved offsets. Its first typed
-- move must adopt the visible origin, preserve the other axis and undo ownership.
M.context = S.NewContext("chat")
c = S.Config("chat")
c.lockWindowPosition, c.windowX, c.windowY = false, 12, 12
M.visuals[frame].positionLocked = nil
frame:ClearAllPoints()
frame:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", 93, 131)
Paint()
Check(em.State.Enter("player") == true, "second edit session failed")
em.Movers.Show()
Check(em.ExternalPopup.Open(key), "unanchored Chat popup failed")
local ox, oy = SamePosition()
local nativeX, nativeY = frame:GetLeft(), frame:GetBottom()
Set("x", ox + 11)
Check(S.Config("chat").lockWindowPosition, "first numeric move did not adopt the anchor")
Check(math.abs(frame:GetBottom() - nativeY) < .000001, "first move used stale saved Y")
Check(em.Undo.DoUndo(), "first adoption Undo failed")
local ux, uy = SamePosition()
Check(not S.Config("chat").lockWindowPosition and ux == ox and uy == oy, "Undo lost native origin/ownership")
Check(em.Undo.DoRedo(), "first adoption Redo failed")
local rx, ry = SamePosition()
Check(S.Config("chat").lockWindowPosition and rx == ox + 11 and ry == oy, "Redo lost adopted position")
Check(em.State.CancelAll() ~= false, "first adoption discard failed")
Check(not S.Config("chat").lockWindowPosition and math.abs(frame:GetLeft() - nativeX) < .000001
    and math.abs(frame:GetBottom() - nativeY) < .000001, "discard lost original native position")
Check(em.State.Enter("player") == true, "size edit session failed")
Check(em.ExternalPopup.Open(key), "Chat size popup failed")
local sizeBoxes = {}
for _, control in ipairs(popup._activeControlSet.numbers) do sizeBoxes[control.id] = control.box end
local function TypeSize(key, value)
    local box = assert(sizeBoxes[key])
    box:SetText(tostring(value))
    box:GetScript("OnEnterPressed")(box)
end
local previous = S.Config("chat")
local oldWidth, oldHeight = previous.windowWidth, previous.windowHeight
Check(tonumber(sizeBoxes.windowWidth:GetText()) == 496 and tonumber(sizeBoxes.windowHeight:GetText()) == 148,
    "editable fields display the mover bounds or stale profile sizes")
TypeSize("windowWidth", 496)
Check(not S.Config("chat").lockWindowSize, "accepting the current size adopted the lock")
TypeSize("windowWidth", 620)
local sized = S.Config("chat")
Check(sized.windowWidth == 620 and sized.windowHeight == 148 and sized.lockWindowSize,
    "editing width did not preserve the live height and adopt the size")
Check(not sized.lockWindowPosition, "editing width adopted the position lock")
Check(em.Undo.DoUndo() and not S.Config("chat").lockWindowSize, "size Undo lost native size ownership")
Check(em.Undo.DoRedo() and S.Config("chat").windowWidth == 620 and S.Config("chat").lockWindowSize,
    "size Redo lost the resized width")
-- The fixture isolates the popup and profile transaction from native chat painting.
frame:SetSize(620, 148)
TypeSize("windowHeight", 999)
Check(S.Config("chat").windowWidth == 620 and S.Config("chat").windowHeight == 800,
    "height edit did not preserve width and enforce the allowed range")
Check(em.State.CancelAll() ~= false, "size discard failed")
local restored = S.Config("chat")
Check(not restored.lockWindowSize and restored.windowWidth == oldWidth and restored.windowHeight == oldHeight,
    "discard did not restore size settings")
print("Chat screen coordinates and size " .. flavor .. ": " .. checks .. " checks passed")
