local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local W = H.New(root, flavor)
    local extent
    local setExtent = W.MM.SetExtent
    W.MM.SetExtent = function(key, left, right, top, bottom)
        if key == "queue" then extent = { left, right, top, bottom } end
        setExtent(key, left, right, top, bottom)
    end
    local native = W.New("Frame", nil, W.G.UIParent)
    local eye = W.New("Button", "QueueStatusButton", native)
    eye:SetSize(45, 45)
    eye:SetScale(.8)
    eye:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", -45, 4)
    local click = function() end
    eye:SetScript("OnClick", click)
    eye:Hide()
    H.Enable(W, { captured = true, queueStatusEnabled = true, queueStatusSize = 32,
        queueStatusX = -2, queueStatusY = -52 })
    W.Step()
    assert(not eye:IsShown(), "layout force-showed the native queue eye")
    assert(eye:GetParent() == W.MM.host and math.abs(eye:GetScale() - 32 / 45) < .00001)
    local point, relative, relativePoint, x, y = eye:GetPoint()
    assert(point == "CENTER" and relative == W.MM.host and relativePoint == "TOPLEFT"
        and math.abs(x * eye:GetScale() + 2) < .00001 and math.abs(y * eye:GetScale() + 52) < .00001,
        tostring(point) .. "/" .. tostring(relativePoint) .. "/" .. tostring(x) .. "/" .. tostring(y))
    assert(eye:GetScript("OnClick") == click, "queue click behavior changed")
    eye:Show()
    W.Step()
    eye:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", -45, 4)
    W.Step()
    assert(select(2, eye:GetPoint()) == W.MM.host, "native reanchor escaped minimap placement")
    assert(W.S.SetMany("minimap", { queueStatusX = 260, queueStatusY = -260 }))
    W.Step()
    local width, height = W.MM.Dimensions()
    assert(extent[2] == 276 - width and extent[4] == 276 - height,
        "queue hover bounds omit right or bottom overflow")
    assert(W.S.Set("minimap", "queueStatusEnabled", false))
    assert(eye:GetParent() == native and eye:GetScale() == .8, "queue opt-out lost native geometry")
    assert(W.S.Set("minimap", "queueStatusEnabled", true))
    assert(eye:GetParent() == W.MM.host)
    assert(W.S.Set("minimap", "enabled", false))
    assert(eye:GetParent() == native and eye:GetScale() == .8 and eye:GetScript("OnClick") == click)
end
print("Native queue eye: position, size, visibility, reanchor and restoration passed on both clients")
