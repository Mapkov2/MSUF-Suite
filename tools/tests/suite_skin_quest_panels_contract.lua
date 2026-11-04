-- Native QuestFramePanelTemplate pages are 384x512, while
-- their visible root is 338x496. A surface on the page spills 46px right/16px down.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_generic_windows_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find('local rowChild = Frame(nil)', 1, true))
local body = [======[
local mode = { role = "shell", allowImplicitProtected = true }
local faded = {}
NS.Cosmetics.Fade = function(region) faded[region] = true; return true end
local function Native(name, parent, width, height)
    local frame = Frame(name)
    frame.parent, frame.width, frame.height = parent, width, height
    function frame:GetParent() return self.parent end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    frame.Bg = { name = name .. "Bg" }
    return frame
end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    NS.Client.isForever = flavor == "Forever"
    QuestFrame = Native("QuestFrame", UIParent, 338, 496)
    GossipFrame = Native("GossipFrame", UIParent, 338, 496)
    local pages = { "QuestFrameRewardPanel", "QuestFrameProgressPanel", "QuestFrameDetailPanel", "QuestFrameGreetingPanel" }
    for _, name in ipairs(pages) do
        local page = Native(name, QuestFrame, 384, 512)
        _G[name] = page
        QuestFrame.children[#QuestFrame.children + 1] = page
        local inset = Native(name .. "Inset", page, 303, 400)
        page.children[1] = inset
    end
    for _, window in ipairs({ QuestFrame }) do
        Check(GenericWindows.ApplyFrame(window, "quest-panels", mode), "NPC window did not skin")
        Check(window.surfaceSpec and window.width == 338 and window.height == 496, "visible NPC shell changed")
        for _, page in ipairs(window.children) do
            Check(not page.surfaceSpec or page.surfaceVisible == false, "oversized NPC page draws a second shell: " .. page.name)
            Check(faded[page.Bg], "native parchment remains on a content-only NPC page")
            Check(page.width == 384 and page.height == 512 and page.parent == window, "native NPC layout was changed")
            if page.children[1] then Check(page.children[1].surfaceSpec, "NPC page contents stopped being skinned") end
            page.surfaceSpec, page.surfaceVisible = { role = "panel" }, true
        end
        Check(GenericWindows.ApplyFrame(window, "quest-panels", mode), "NPC reskin failed")
        for _, page in ipairs(window.children) do
            Check(page.surfaceVisible == false, "a cached oversized page surface survived reskin")
        end
    end
    -- Gossip's GreetingPanel has no global name or Bg member in either client.
    local greeting = Frame(nil)
    greeting.parent, greeting.width, greeting.height = GossipFrame, 384, 512
    function greeting:GetParent() return self.parent end
    greeting.MaterialTopLeft = {}
    GossipFrame.GreetingPanel, GossipFrame.children[1] = greeting, greeting
    Check(GenericWindows.ApplyFrame(GossipFrame, "quest-panels", mode) and GossipFrame.surfaceSpec,
        "gossip lost its visible root shell")
    Check(not greeting.surfaceSpec, "anonymous gossip content grew an oversized surface")
    local popup = Native("QuestLogPopupDetailFrame", UIParent, 338, 496)
    Check(GenericWindows.ApplyFrame(popup, "quest-panels", mode) and popup.surfaceSpec,
        "standalone quest details lost their shell")
    local foreign = Native("QuestFrameProgressPanel", popup, 384, 512)
    popup.children[1] = foreign
    Check(GenericWindows.ApplyFrame(popup, "quest-panels", mode) and foreign.surfaceSpec,
        "a same-named foreign panel was suppressed")
    GenericWindows.Disable("quest-panels")
end
print("suite_skin_quest_panels_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@skin_quest_panels_contract"))()
