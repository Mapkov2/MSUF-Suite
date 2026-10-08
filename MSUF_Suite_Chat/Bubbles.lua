local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Speech bubbles (styleBubbles). Each frame C_ChatBubbles.GetAllChatBubbles
-- returns holds one ChatBubbleTemplate child: its String and nine-slice art.
-- A bubble carries no chat type, so a line the player just heard is kept
-- with its source (NS.ChatBubbleSources) for HEARD_SECONDS; a bubble that
-- starts showing exactly that text is styled for the source. Bubbles are
-- looked for only while a heard line still waits for one: on the next frame,
-- then every PASS_SECONDS until each waiting line found its bubble or ran
-- out of time. A bubble that hides takes its native look back at once, so
-- a recycled one never keeps a stale style. The Suite keeps every native
-- value it replaced and hands it back only while the bubble still shows the
-- Suite's own, so Blizzard's later changes stay. Inside instances Blizzard
-- makes every bubble forbidden: lines heard there are not even kept.
local M = C.M
M.cvars = { chatBubbles = true, chatBubblesParty = true, chatBubblesRaid = true }
local HEARD_SECONDS, PASS_SECONDS = 0.6, 0.15
local MAX_BUBBLES, MAX_HEARD = 64, 48
-- ChatBubbleTemplate's nine-slice pieces (NineSliceLayouts "ChatBubble") and its tail.
local CHROME = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center", "Tail",
}
local PublicText, Public, Finite, RGB = S.PublicText, S.Public, S.Finite, S.RGB
local IsForbidden = NS.Safety.IsForbidden
-- chat event -> the setting keys of its source
local sourceKeys = {}
for _, source in ipairs(NS.ChatBubbleSources) do
    local key = source.key
    local keys = {
        style = "bubbleStyle" .. key, own = "bubbleOwn" .. key, font = "bubbleFont" .. key,
        size = "bubbleSize" .. key, text = "bubbleText" .. key, fill = "bubbleFill" .. key,
        opacity = "bubbleOpacity" .. key, edge = "bubbleEdge" .. key, pad = "bubblePad" .. key,
        width = "bubbleWidth" .. key,
    }
    for _, event in ipairs(source.events) do sourceKeys[event] = keys end
end
-- text -> source keys / deadline / a bubble showed it
local heard, heardUntil, found = {}, {}, {}
local heardCount = 0
local views = setmetatable({}, { __mode = "k" })
local scanner
local inInstance = false

local function Same(current, applied)
    return applied ~= nil and Public(current) and current == applied
end

------------------------------------------------------------------ owned values
local function OwnFont(view, fontKey, fontSize)
    local region = view.region
    local path, size, flags = region:GetFont()
    if not (Same(path, view.appliedPath) and Same(size, view.appliedSize)) then
        if not (PublicText(path) and Finite(size) and Public(flags)) then return end
        view.fontPath, view.fontSize, view.fontFlags = path, size, flags
    end
    region:SetFont(S.ResolveFont(fontKey) or S.GlobalFontPath(), fontSize, view.fontFlags)
    view.appliedPath, view.appliedSize = region:GetFont()
end

local function OwnColor(view, r, g, b)
    local region = view.region
    local currentR, currentG, currentB, currentA = region:GetTextColor()
    if not (Same(currentR, view.appliedR) and Same(currentG, view.appliedG) and Same(currentB, view.appliedB)) then
        if not (Finite(currentR) and Finite(currentG) and Finite(currentB) and Finite(currentA)) then return end
        view.colorR, view.colorG, view.colorB, view.colorA = currentR, currentG, currentB, currentA
    end
    region:SetTextColor(r, g, b, 1)
    view.appliedR, view.appliedG, view.appliedB = region:GetTextColor()
end

-- Blizzard sizes the String to the text; the Suite only narrows it.
local function OwnWidth(view, maxWidth)
    local region = view.region
    local width = region:GetWidth()
    if not Finite(width) then return end
    if not Same(width, view.appliedWidth) then view.width = width end
    region:SetWidth(math.min(view.width, maxWidth))
    view.appliedWidth = region:GetWidth()
end

local function OwnChrome(view)
    local parts, before, applied = view.chrome, view.chromeBefore, view.chromeApplied
    for i = 1, #CHROME do
        local part = parts[i]
        if part then
            local alpha = part:GetAlpha()
            if not Same(alpha, applied[i]) and Finite(alpha) then before[i] = alpha end
            if before[i] ~= nil then
                part:SetAlpha(0)
                applied[i] = part:GetAlpha()
            end
        end
    end
end

local function Release(view)
    if not view.painted then return end
    view.painted = nil
    view.fill:Hide()
    for i = 1, 4 do view.edges[i]:Hide() end
    local region = view.region
    if view.appliedPath ~= nil then
        local path, size = region:GetFont()
        if Same(path, view.appliedPath) and Same(size, view.appliedSize) then
            region:SetFont(view.fontPath, view.fontSize, view.fontFlags)
        end
        view.appliedPath, view.appliedSize = nil, nil
    end
    if view.appliedR ~= nil then
        local r, g, b = region:GetTextColor()
        if Same(r, view.appliedR) and Same(g, view.appliedG) and Same(b, view.appliedB) then
            region:SetTextColor(view.colorR, view.colorG, view.colorB, view.colorA)
        end
        view.appliedR, view.appliedG, view.appliedB = nil, nil, nil
    end
    if view.appliedWidth ~= nil then
        if Same(region:GetWidth(), view.appliedWidth) then region:SetWidth(view.width) end
        view.appliedWidth = nil
    end
    local parts, before, applied = view.chrome, view.chromeBefore, view.chromeApplied
    for i = 1, #CHROME do
        if parts[i] and applied[i] ~= nil then
            if Same(parts[i]:GetAlpha(), applied[i]) then parts[i]:SetAlpha(before[i]) end
            applied[i] = nil
        end
    end
end

------------------------------------------------------------------ painting
-- A flat backdrop with a one-pixel border, made once per bubble.
local function CreateBackdrop(view)
    local content = view.content
    local fill = C.Fill(content, "BACKGROUND")
    view.fill, view.edges = fill, {}
    for i = 1, 4 do
        local edge = C.Fill(content, "BORDER")
        if i <= 2 then
            local side = i == 1 and "TOP" or "BOTTOM"
            edge:SetPoint(side .. "LEFT", fill, side .. "LEFT")
            edge:SetPoint(side .. "RIGHT", fill, side .. "RIGHT")
            edge:SetHeight(1)
        else
            local side = i == 3 and "LEFT" or "RIGHT"
            edge:SetPoint("TOP" .. side, fill, "TOP" .. side)
            edge:SetPoint("BOTTOM" .. side, fill, "BOTTOM" .. side)
            edge:SetWidth(1)
        end
        view.edges[i] = edge
    end
end

-- The shared bubble look, or the source's own one while it uses it.
local SHARED = {
    font = "bubbleFont", size = "bubbleFontSize", text = "bubbleTextColor", fill = "bubbleBackground",
    opacity = "bubbleAlpha", edge = "bubbleBorder", pad = "bubblePadding", width = "bubbleMaxWidth",
}
local function Look(c, keys, part)
    if c[keys.own] then return c[keys[part]] end
    return c[SHARED[part]]
end

local function Paint(view, keys)
    local c, region = M.config, view.region
    OwnFont(view, Look(c, keys, "font"), Look(c, keys, "size"))
    local r, g, b = RGB(Look(c, keys, "text"))
    OwnColor(view, r, g, b)
    OwnWidth(view, Look(c, keys, "width"))
    OwnChrome(view)
    if not view.fill then CreateBackdrop(view) end
    local pad, fill = Look(c, keys, "pad"), view.fill
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
    fill:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
    C.Tint(fill, Look(c, keys, "fill"), Look(c, keys, "opacity"))
    fill:Show()
    local border = Look(c, keys, "edge")
    for i = 1, 4 do
        C.Tint(view.edges[i], border, 100)
        view.edges[i]:Show()
    end
    view.painted = keys
end

local function BubbleHidden(content)
    local view = views[content]
    if not view then return end
    Release(view)
    view.text, view.source = nil, nil
end

local function NewView(content)
    local view = { content = content, region = content.String, chrome = {}, chromeBefore = {}, chromeApplied = {} }
    for i = 1, #CHROME do
        local part = content[CHROME[i]]
        if part and not IsForbidden(part) then view.chrome[i] = part end
    end
    views[content] = view
    content:HookScript("OnHide", BubbleHidden)
    return view
end

-- Only a bubble whose text changed is looked at again.
local function Update(content)
    local view = views[content] or NewView(content)
    local text = PublicText(view.region:GetText())
    if text == view.text then return end
    view.text = text
    local keys = text and heard[text]
    view.source = keys
    if keys then found[text] = true end
    if keys and M.config[keys.style] then Paint(view, keys) else Release(view) end
end

------------------------------------------------------------------ discovery
-- Forgets the heard lines whose time ran out. True while one that is left
-- still waits for its bubble.
local function Expire(now)
    local waiting = false
    for text, deadline in pairs(heardUntil) do
        if deadline <= now then
            heard[text], heardUntil[text], found[text] = nil, nil, nil
            heardCount = heardCount - 1
        elseif not found[text] then
            waiting = true
        end
    end
    return waiting
end

-- One pass over the accessible bubbles (forbidden ones are never returned).
-- True while a heard line still waits for its bubble.
local function Pass(now)
    local bubbles = C_ChatBubbles.GetAllChatBubbles(false)
    for i = 1, math.min(#bubbles, MAX_BUBBLES) do
        local content = bubbles[i]:GetChildren()
        if content and not IsForbidden(content) and content.String then Update(content) end
    end
    return Expire(now)
end

local function ScanStep(frame, elapsed)
    frame.wait = frame.wait - elapsed
    if frame.wait > 0 then return end
    frame.wait = PASS_SECONDS
    if not (M.active and M.config.styleBubbles) or inInstance or not Pass(GetTime()) then frame:Hide() end
end

local function ForgetHeard()
    for text in pairs(heardUntil) do heard[text], heardUntil[text], found[text] = nil, nil, nil end
    heardCount = 0
    if scanner then scanner:Hide() end
end

-- callback(module, event, text, ...) for the source events, also in combat.
local function Heard(_, event, text)
    text = PublicText(text)
    if inInstance or not text then return end
    if not heard[text] then
        -- Discovery stops once every line found its bubble; lines that
        -- expired since then make room here.
        if heardCount >= MAX_HEARD then Expire(GetTime()) end
        if heardCount >= MAX_HEARD then return end
        heardCount = heardCount + 1
    end
    heard[text], heardUntil[text], found[text] = sourceKeys[event], GetTime() + HEARD_SECONDS, nil
    if not scanner then
        scanner = S.CreateFrame("Frame")
        scanner:Hide()
        scanner:SetScript("OnUpdate", ScanStep)
    end
    if not scanner:IsShown() then
        scanner.wait = 0
        scanner:Show()
    end
end

-- hideInstanceBubbles turns Blizzard's three bubble settings off inside
-- instances and hands them back outside.
local function ZoneChanged()
    inInstance = IsInInstance() == true
    if inInstance then ForgetHeard() end
    if M.config.hideInstanceBubbles and inInstance then
        for name in pairs(M.cvars) do M.context:CVar(name, "0") end
    else
        for name in pairs(M.cvars) do S.RestoreCVar("chat", name) end
    end
end

function C.BubblesDisable()
    ForgetHeard()
    for _, view in pairs(views) do
        Release(view)
        view.text, view.source = nil, nil
    end
end

function C.BubblesRefresh(self)
    local c, context = self.config, self.context
    for event in pairs(sourceKeys) do
        if c.styleBubbles then C.ListenInCombat(context, event, Heard) else context:RemoveEvent(event) end
    end
    if c.styleBubbles or c.hideInstanceBubbles then
        C.ListenInCombat(context, "PLAYER_ENTERING_WORLD", ZoneChanged)
        C.ListenInCombat(context, "ZONE_CHANGED_NEW_AREA", ZoneChanged)
    else
        context:RemoveEvent("PLAYER_ENTERING_WORLD")
        context:RemoveEvent("ZONE_CHANGED_NEW_AREA")
    end
    ZoneChanged()
    if not c.styleBubbles then
        C.BubblesDisable()
        return
    end
    -- Changed settings reach the bubbles already styled.
    for _, view in pairs(views) do
        local keys = view.source
        if keys and view.content:IsShown() and PublicText(view.region:GetText()) == view.text then
            if c[keys.style] then Paint(view, keys) else Release(view) end
        end
    end
end
