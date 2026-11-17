local _, NS = ...

-- Spoken 3.9 exposes its tabs and their page models. Style those exact panels;
-- its pictures, portraits, narration and page selection stay with Spoken.
local Skin = {}
NS.CompendiumSkin = Skin
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local hooked = setmetatable({}, { __mode = "k" })
local headers = setmetatable({}, { __mode = "k" })
local headerArt = { "headLeft", "headMiddle", "headRight", "bannerFill", "bannerTop", "bannerBottom",
    "bannerLeft", "bannerRight", "bannerRail" }

local function Changed()
    if NS.AddonSkins.IsEnabled("spoken") then
        local compendium = rawget(_G, "SpokenCompendium")
        NS.AddonSkins.RefreshFrame(Safety.Field(compendium, "window"))
    end
end

local function Hook(object, key)
    if not Safety.HasMethod(object, key) then return end
    local methods = hooked[object]
    if not methods then methods = {} hooked[object] = methods end
    local method = Safety.Field(object, key)
    if methods[key] == method then return end
    hooksecurefunc(object, key, Changed)
    methods[key] = Safety.Field(object, key)
end

function Skin.Install()
    local compendium = rawget(_G, "SpokenCompendium")
    for _, key in ipairs({ "Open", "Select", "Window", "Relayout", "NewPage" }) do Hook(compendium, key) end
end

local function PageText(frame, owner, remaining, depth)
    if remaining <= 0 or depth > 12 or not Visuals.Safe(frame) then return remaining - 1 end
    remaining = remaining - 1
    for _, region in ipairs({ Safety.Call(frame, "GetRegions") }) do
        if Safety.Read(region, "GetObjectType") == "FontString" then Visuals.Text(region, owner, "text") end
    end
    for _, child in ipairs({ Safety.Call(frame, "GetChildren") }) do
        if remaining <= 0 then break end
        remaining = PageText(child, owner, remaining, depth + 1)
    end
    return remaining
end

local function ListChrome(frame, owner, budget, depth)
    if budget <= 0 then return 0 end
    budget = budget - 1
    if depth > 8 or not Visuals.Safe(frame) then return budget end
    local head = Safety.Field(frame, "headLeft")
    local banner = Safety.Field(frame, "bannerFill")
    if head or banner then
        local active = Safety.Read(head, "IsShown") == true or Safety.Read(banner, "IsShown") == true
        for index = 1, #headerArt do Visuals.Fade(Safety.Field(frame, headerArt[index]), owner) end
        if active then Visuals.Surface(frame, owner, "panel") headers[frame] = owner
        elseif headers[frame] == owner then NS.Surface.SetVisible(frame, false) end
        Visuals.Tint(Safety.Field(frame, "edge"), owner, "accent")
        Visuals.Tint(Safety.Field(frame, "wash"), owner, "accent")
    end
    for _, child in ipairs({ Safety.Call(frame, "GetChildren") }) do
        if budget <= 0 then break end
        budget = ListChrome(child, owner, budget, depth + 1)
    end
    return budget
end

function Skin.Paint(frame, owner)
    local compendium = rawget(_G, "SpokenCompendium")
    local window = Safety.Field(compendium, "window")
    if not Safety.Public(window) or window ~= frame then return false end
    local tabs = Safety.Field(compendium, "tabs")
    if type(tabs) ~= "table" then return false end
    local count = 0
    for _, tab in pairs(tabs) do
        count = count + 1
        if count > 16 then break end
        local panel = Safety.Field(tab, "panel")
        if Visuals.Safe(panel) then
            Hook(panel, "Refresh")
            Visuals.Panel(Safety.Field(panel, "inset"), owner, "panel")
            Visuals.Panel(Safety.Field(panel, "pageInset"), owner, "panel")
            ListChrome(Safety.Field(panel, "inset"), owner, 480, 0)
            local page = Safety.Field(panel, "page")
            for _ = 1, 2 do
                if Safety.Field(page, "frame") then break end
                page = Safety.Field(page, "page") -- Spoken Places wraps the common page.
            end
            local pageFrame = Safety.Field(page, "frame")
            if Visuals.Safe(pageFrame) then
                Visuals.Panel(pageFrame, owner, "panel")
                for _, key in ipairs({ "bg", "backplate", "divider" }) do Visuals.Fade(Safety.Field(page, key), owner) end
                -- TextView's fade strips repeat the parchment at the scroll edges.
                -- Match these explicit strips, never the picture's underlying atlas file.
                local body = Safety.Field(page, "body")
                local strips = Safety.Field(body, "strips")
                if type(strips) == "table" then
                    for index = 1, math.min(#strips, 64) do Visuals.Fade(strips[index], owner) end
                end
                PageText(pageFrame, owner, 640, 0)
                Hook(page, "Show")
                Hook(body, "SetText")
                Hook(body, "SetParts")
            end
        end
    end
    return true
end
