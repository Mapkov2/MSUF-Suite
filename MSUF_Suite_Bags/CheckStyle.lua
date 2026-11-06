local _, P = ...
local S = P.Suite
local Checks = { buttons = setmetatable({}, {__mode="k"}) }
P.BagCheckStyle = Checks

local function Paint(check)
    local c = S.Config("bags")
    local enabled, checked = check:IsEnabled(), check:GetChecked() == true
    local ar,ag,ab = S.RGB(c.accentColor)
    local r,g,b = S.RGB(c.backgroundColor)
    check.bagCheckEdge:SetColorTexture(ar,ag,ab,checked and .8 or .3)
    check.bagCheckFill:SetColorTexture(r,g,b,1)
    if check.bagCheckLabel then
        check.bagCheckLabel:SetTextColor(enabled and .94 or .5, enabled and .95 or .5, enabled and .98 or .5)
    end
    for i=1,2 do
        check.bagCheckArms[i]:SetShown(checked)
        check.bagCheckArms[i]:SetAlpha(enabled and 1 or .4)
    end
end

function Checks.Apply(check, label)
    local native = check:GetCheckedTexture()
    if native then native:SetAlpha(0) end
    local edge = S.CreateTexture(check,nil,"ARTWORK",nil,0)
    edge:SetPoint("CENTER")
    edge:SetSize(23,23)
    local fill = S.CreateTexture(check,nil,"ARTWORK",nil,1)
    fill:SetPoint("CENTER")
    fill:SetSize(21,21)
    check.bagCheckEdge,check.bagCheckFill = edge,fill
    local arms = {}
    for i=1,2 do
        local arm = S.CreateTexture(check,nil,"OVERLAY")
        arm:SetColorTexture(.94,.95,.98,1)
        arm:SetSize(3,i==1 and 7 or 12)
        arm:SetPoint("CENTER",i==1 and -3 or 2,i==1 and -1 or 1)
        arm:SetRotation(i==1 and math.pi/4 or -math.pi/4)
        arms[i] = arm
    end
    check.bagCheckArms = arms
    if label then
        local text = S.CreateFontString(check,nil,"OVERLAY")
        S.SetFont(text,S.GlobalFontPath(),12,"")
        text:SetText(S.Text(label))
        text:SetPoint("LEFT",check,"RIGHT",8,0)
        check.bagCheckLabel = text
        check:SetHitRectInsets(0,-text:GetStringWidth()-8,0,0)
    end
    hooksecurefunc(check,"SetChecked",Paint)
    check:HookScript("OnClick",Paint)
    check:HookScript("OnEnable",Paint)
    check:HookScript("OnDisable",Paint)
    Checks.buttons[check] = true
    Paint(check)
end

function Checks.Refresh()
    for check in pairs(Checks.buttons) do Paint(check) end
end
