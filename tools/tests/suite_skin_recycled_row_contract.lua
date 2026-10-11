-- Recycled ScrollBox rows. Blizzard initializes a pooled row again on every
-- scroll and data refresh; GenericWindowsFrames (RefreshRowNodes) then tracks
-- the row's gold text over its recorded nodes (BlizzardYellow.TrackFrames)
-- and its buttons' native glyphs (Checkmarks.TrackFrame -> TrackButton).
-- Raid trace 2026-10-11, capture 4 frame 5056 (out of combat): 60 such
-- initializations cost 9.8 ms (165 us each; TrackFrames 99 us over 16 nodes
-- and 8 FontStrings, three TrackButton calls 54 us). With the real Safety,
-- BlizzardYellow and Checkmarks:
--   * an unchanged recycled row is not enumerated again and its text gets no
--     write; text Blizzard turned gold, a FontString it added and a node whose
--     regions turned secret are still handled;
--   * a button whose art has no role is not classified again while its art
--     reads the same; changed art is tracked;
--   * both shortcuts answer exactly like a pass without them over seeded
--     random sequences of Blizzard changes (a second world whose rows and
--     buttons are new objects on every pass, so nothing is ever cached);
--   * Safety reads issecretvalue once at load and still refuses secrets;
--   * Lua VM instructions and allocation of one row refresh.
local root = assert(arg[1], "Suite root required")
local MEASURE_ONLY = os.getenv("MSUF_BUDGET_MEASURE") == "1"
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

-- A secret: any use other than issecretvalue raises, like the client.
local SecretMT = {}
for _, event in ipairs({ "__index", "__newindex", "__eq", "__lt", "__le", "__concat", "__add", "__sub",
    "__mul", "__div", "__unm", "__len", "__call" }) do
    SecretMT[event] = function() error("contract: a secret was used (" .. event .. ")") end
end
local function Secret() return setmetatable({}, SecretMT) end
-- A colour channel the client hands out as a secret number.
local SECRET_NUMBER = 0.123456
-- The client's issecretvalue: present before any addon loads.
issecretvalue = function(value) return getmetatable(value) == SecretMT or value == SECRET_NUMBER end
securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end

local desired = { 0.2, 0.6, 0.9, 1 }
local function RoleColor(role)
    local length = #role
    return (length % 7) / 7, (length % 5) / 5, (length % 3) / 3, 1
end
local actionTracks = {}
local NS = {
    DB = { enabled = true },
    IsCombatLocked = function() return false end,
    CombatGate = { RunOrDefer = function() return false, "combat" end },
    Registry = { AddListener = function() end, QueueJob = function(job) job() end },
    Theme = {
        GetColor = function(key)
            if key == "blizzardYellow" then return desired[1], desired[2], desired[3], desired[4] end
            return RoleColor(key)
        end,
    },
    BlizzardFontNames = {},
    WindowActionSkin = {
        HasOwnedStates = function() return false end,
        GetKind = function() return nil end,
        IsApplied = function() return false end,
        Disable = function() return true end,
        DisableOwner = function() end,
        Restore = function() end,
        -- Records the action each button was given on this pass.
        Track = function(button, _, kind)
            actionTracks[button] = kind
            return {}
        end,
    },
}
local skin = root .. "/MSUF_Suite_Skin/"
for _, file in ipairs({ "Core/Safety.lua", "Core/BlizzardYellow.lua", "Core/Checkmarks.lua" }) do
    assert(loadfile(skin .. file))("MSUF_Suite_Skin", NS)
end
local Safety, Yellow, Checkmarks = NS.Safety, NS.BlizzardYellow, NS.Checkmarks

------------------------------------------------------------------ stand-ins
-- Colours are stored in fields, so the stand-ins allocate nothing.
local function FontString(r, g, b, a)
    local text = { r = r, g = g, b = b, a = a or 1, writes = 0 }
    function text:GetObjectType() return "FontString" end
    function text:IsForbidden() return false end
    function text:GetTextColor()
        if self.secretColor then return Secret(), Secret(), Secret(), Secret() end
        return self.r, self.g, self.b, self.a
    end
    function text:SetTextColor(red, green, blue, alpha)
        self.writes = self.writes + 1
        self.r, self.g, self.b, self.a = red, green, blue, alpha or 1
    end
    return text
end

local function Region()
    local region = {}
    function region:GetObjectType() return "Texture" end
    function region:IsForbidden() return false end
    return region
end

local function Node(regions)
    local node = { regions = regions or {}, enumerations = 0 }
    function node:IsForbidden() return false end
    -- The Hierarchy aspect turns every region and the count secret.
    function node:GetRegions()
        self.enumerations = self.enumerations + 1
        if not self.hierarchySecret then return unpack(self.regions) end
        local secrets = {}
        for index = 1, #self.regions do secrets[index] = Secret() end
        return unpack(secrets)
    end
    function node:GetNumRegions()
        if self.hierarchySecret then return Secret() end
        return #self.regions
    end
    return node
end

local function Enumerations(nodes)
    local count = 0
    for _, node in ipairs(nodes) do count = count + node.enumerations end
    return count
end

local function ShowsDesired(text)
    return text.r == desired[1] and text.g == desired[2] and text.b == desired[3]
end

local SLOT_GETTERS = { "GetCheckedTexture", "GetDisabledCheckedTexture", "GetNormalTexture",
    "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
local SLOT_FIELDS = { "CheckedTexture", "DisabledCheckedTexture", "leftTexture2", "Icon" }

local function ArtTexture(atlas, path)
    local texture = { atlas = atlas, path = path, reads = 0, r = 1, g = 1, b = 1, a = 1, vertexWrites = 0 }
    function texture:IsForbidden() return self.forbidden == true end
    local function Read(self, value)
        if self.forbidden then error("contract: read a forbidden texture") end
        self.reads = self.reads + 1
        return value
    end
    function texture:GetAtlas()
        if self.secretAtlas then return Read(self, Secret()) end
        return Read(self, self.atlas)
    end
    function texture:GetTextureFilePath() return Read(self, self.path) end
    -- A file ID, or the path the texture was set with.
    function texture:GetTexture() return Read(self, self.file or self.path) end
    function texture:GetVertexColor() return self.r, self.g, self.b, self.a end
    function texture:SetVertexColor(r, g, b, a)
        self.vertexWrites = self.vertexWrites + 1
        self.r, self.g, self.b, self.a = r, g, b, a or 1
    end
    function texture:SetDesaturated(value) self.desaturated = value end
    function texture:IsDesaturated() return self.desaturated == true end
    return texture
end

local function SlotGetter(getter)
    return function(self) return self.slots[getter] end
end

-- slots: getter name -> texture; fields: field name -> value.
local function ArtButton(slots, fields, children)
    local button = { slots = slots or {}, children = children or {} }
    for key, value in pairs(fields or {}) do button[key] = value end
    for _, getter in ipairs(SLOT_GETTERS) do button[getter] = SlotGetter(getter) end
    function button:IsForbidden() return false end
    function button:IsProtected() return false, false end
    function button:GetChildren() return unpack(self.children) end
    return button
end

-- Calls of Checkmarks' AssetRole (the role scan) while body runs.
local assetRoleLine
do
    local file = assert(io.open(skin .. "Core/Checkmarks.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local line = 0
    for text in (source .. "\n"):gmatch("([^\n]*)\n") do
        line = line + 1
        if text:find("^local function AssetRole%(") then assetRoleLine = line end
    end
    assert(assetRoleLine, "Checkmarks.lua has no AssetRole")
end
local function RoleScans(body)
    local scans = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info.linedefined == assetRoleLine and info.source:find("Checkmarks%.lua$") then scans = scans + 1 end
    end, "c")
    body()
    debug.sethook()
    return scans
end

------------------------------------------------------------------ budget
-- One recycled row as frame 5056 initialized it: 16 recorded nodes holding
-- 8 FontStrings (none of them gold), the row button and two child buttons
-- whose art has no role (3 textures each). One refresh (RefreshRowNodes:
-- TrackFrames, then Checkmarks.TrackFrame), measured on fresh module state
-- before any other section: Lua VM instructions, calls into the skin's Lua
-- functions, calls of the client stand-ins (natives, issecretvalue included)
-- and kilobytes allocated. MSUF_BUDGET_MEASURE=1 prints the four and stops
-- there; the base was measured that way against the files before this change.
--   before:   9942 instructions, 471 skin calls, 359 natives, 0 KB
--   now:      6428 instructions, 210 skin calls, 272 natives, 0 KB
-- Budgets are "now" plus 2%. Lower them after an optimization; raise one only
-- with a dated reason.
local ROW_BUDGET = { instructions = 6557, skinCalls = 214, natives = 277 }
do
    local nodes = {}
    for index = 1, 16 do
        local regions = { Region(), Region() }
        if index % 2 == 0 then regions[#regions + 1] = FontString(1, 1, 1) end
        nodes[index] = Node(regions)
    end
    local function Art()
        return ArtButton({ GetNormalTexture = ArtTexture("questlog-unknown"),
            GetPushedTexture = ArtTexture("questlog-unknown-pressed"),
            GetHighlightTexture = ArtTexture(nil, "Interface\\Buttons\\UI-Common-MouseHilight") })
    end
    local row = Art()
    row.children = { Art(), Art() }
    local function Refresh()
        Yellow.TrackFrames(nodes, #nodes)
        Checkmarks.TrackFrame(row, "rows")
    end
    for _ = 1, 3 do Refresh() end
    local instructions, skinCalls, natives = 0, 0, 0
    debug.sethook(function() instructions = instructions + 1 end, "", 1)
    Refresh()
    debug.sethook(function()
        local source = debug.getinfo(2, "S").source
        if source:find("MSUF_Suite_Skin", 1, true) then
            skinCalls = skinCalls + 1
        elseif source:find("suite_skin_recycled_row_contract", 1, true) then
            natives = natives + 1
        end
    end, "c")
    Refresh()
    debug.sethook()
    collectgarbage("collect")
    collectgarbage("stop")
    local kilobytes = collectgarbage("count")
    for _ = 1, 100 do Refresh() end
    kilobytes = collectgarbage("count") - kilobytes
    collectgarbage("restart")
    if MEASURE_ONLY then
        print(("row refresh: %d instructions, %d skin calls, %d natives, %.2f KB per 100")
            :format(instructions, skinCalls, natives, kilobytes))
        os.exit(0)
    end
    Check(instructions <= ROW_BUDGET.instructions and skinCalls <= ROW_BUDGET.skinCalls
        and natives <= ROW_BUDGET.natives and kilobytes < 0.1,
        ("one recycled row refresh: %d instructions, %d skin calls, %d natives (budget %d, %d, %d), %.2f KB per 100")
            :format(instructions, skinCalls, natives, ROW_BUDGET.instructions, ROW_BUDGET.skinCalls,
                ROW_BUDGET.natives, kilobytes))
end

------------------------------------------------------------------ gold text of a recycled row
do
    local white, grey = FontString(1, 1, 1), FontString(0.5, 0.5, 0.5)
    local nodes = { Node({ Region(), white, Region() }), Node({ grey }), Node({ Region() }), Node({}) }
    Check(Yellow.TrackFrames(nodes, #nodes) == 0 and white.writes == 0 and grey.writes == 0
        and Enumerations(nodes) == 4, "the first pass over a row did not read each node once")
    for _ = 1, 3 do Yellow.TrackFrames(nodes, #nodes) end
    Check(Enumerations(nodes) == 4 and white.writes == 0 and grey.writes == 0,
        "an unchanged recycled row was enumerated again or its text was written")

    -- Blizzard turns a label gold for the new element: it is tinted.
    grey:SetTextColor(1, 0.82, 0, 1)
    grey.writes = 0
    Check(Yellow.TrackFrames(nodes, #nodes) == 1 and grey.writes == 1 and ShowsDesired(grey)
        and Yellow.directStates[grey] ~= nil, "a recycled row whose text Blizzard turned gold was not tinted")
    -- ... and back to its own colour: left alone, as before.
    grey:SetTextColor(0.5, 0.5, 0.5, 1)
    grey.writes = 0
    Check(Yellow.TrackFrames(nodes, #nodes) == 0 and grey.writes == 0 and grey.r == 0.5,
        "a recycled row repainted text Blizzard gave its own colour")

    -- Blizzard creates a gold label on a node: the region count grows.
    local added = FontString(1, 0.82, 0)
    table.insert(nodes[3].regions, added)
    Check(Yellow.TrackFrames(nodes, #nodes) == 1 and added.writes == 1 and ShowsDesired(added)
        and nodes[3].enumerations == 2, "a FontString Blizzard added to a recycled row was missed")
    -- A label reparented away (the count falls) is no longer this row's.
    table.remove(nodes[1].regions, 2)
    white:SetTextColor(1, 0.82, 0, 1)
    white.writes = 0
    Yellow.TrackFrames(nodes, #nodes)
    Check(white.writes == 0 and nodes[1].enumerations == 2, "a FontString that left the row was still tracked")

    -- Hierarchy aspect: a secret count or region is never recorded or compared.
    nodes[2].hierarchySecret = true
    grey:SetTextColor(1, 0.82, 0, 1)
    grey.writes = 0
    local before = nodes[2].enumerations
    Yellow.TrackFrames(nodes, #nodes)
    Yellow.TrackFrames(nodes, #nodes)
    Check(nodes[2].enumerations == before + 2 and grey.writes == 0,
        "a node with secret regions was cached or its secret regions were used")
    nodes[2].hierarchySecret = false
    Yellow.TrackFrames(nodes, #nodes)
    Yellow.TrackFrames(nodes, #nodes)
    Check(nodes[2].enumerations == before + 3 and grey.writes >= 1 and ShowsDesired(grey),
        "a node whose regions became readable again was not read afresh once")
    local secretRegionText = FontString(1, 0.82, 0)
    local mixed = { Node({ Secret(), secretRegionText }) }
    Yellow.TrackFrames(mixed, 1)
    Yellow.TrackFrames(mixed, 1)
    Check(mixed[1].enumerations == 2 and ShowsDesired(secretRegionText),
        "a node with one secret region was cached or its readable text skipped")
    local secretColor = FontString(1, 0.82, 0)
    secretColor.secretColor = true
    local secretNodes = { Node({ secretColor }) }
    Check(Yellow.TrackFrames(secretNodes, 1) == 0 and Yellow.TrackFrames(secretNodes, 1) == 0
        and secretColor.writes == 0, "text whose colour is secret was tinted")

    -- Native gold is what Safety.SameColor calls gold within COLOR_NATIVE, on
    -- each channel and at the edges of the tolerance.
    local agreed, samples = true, 0
    for _, red in ipairs({ 0.98, 0.985, 0.99, 1 }) do
        for _, green in ipairs({ 0.8, 0.805, 0.81, 0.82, 0.83, 0.835, 0.84 }) do
            for _, blue in ipairs({ 0, 0.01, 0.015, 0.02 }) do
                local label = FontString(red, green, blue)
                Yellow.TrackFrames({ Node({ label }) }, 1)
                local native = Safety.SameColor(red, green, blue, nil, 1, 0.82, 0, nil, Safety.COLOR_NATIVE)
                agreed = agreed and (label.writes == 1) == native
                samples = samples + (native and 1 or 0)
            end
        end
    end
    Check(agreed and samples > 0 and samples < 112, "native gold was classified unlike Safety.SameColor")

    -- Single frames (window passes, surfaces) keep their full read.
    local single = Node({ FontString(1, 1, 1) })
    Yellow.TrackFrame(single)
    Yellow.TrackFrame(single)
    Check(single.enumerations == 2, "BlizzardYellow.TrackFrame started caching a single frame")

    -- An unchanged recycled row allocates nothing.
    for _ = 1, 3 do Yellow.TrackFrames(nodes, #nodes) end
    collectgarbage("collect")
    collectgarbage("stop")
    local kilobytes = collectgarbage("count")
    for _ = 1, 500 do Yellow.TrackFrames(nodes, #nodes) end
    kilobytes = collectgarbage("count") - kilobytes
    collectgarbage("restart")
    Check(kilobytes < 0.5, ("500 recycled row passes allocated %.2f KB"):format(kilobytes))
end

------------------------------------------------------------------ button art of a recycled row
do
    local normal, pushed = ArtTexture("questlog-unknown"), ArtTexture("questlog-unknown-pressed")
    local highlight = ArtTexture(nil, "Interface\\Buttons\\UI-Common-MouseHilight")
    local button = ArtButton({ GetNormalTexture = normal, GetPushedTexture = pushed,
        GetHighlightTexture = highlight })
    local function Track() Checkmarks.TrackButton(button, "rows") end
    Check(RoleScans(Track) > 0 and RoleScans(Track) > 0, "a button's first two passes did not scan its art")
    Check(RoleScans(Track) == 0 and RoleScans(Track) == 0,
        "a revisited button whose art has no role was classified again")
    Check(normal.vertexWrites == 0 and pushed.vertexWrites == 0 and highlight.vertexWrites == 0
        and Checkmarks.buttons[button] == nil, "a button without a role was tracked")

    -- Blizzard changes the art: the next pass tracks it.
    normal.atlas = "common-dropdown-icon-back"
    Check(RoleScans(Track) > 0 and normal.vertexWrites == 1 and Checkmarks.states[normal]
        and Checkmarks.states[normal].colorRole == "blizzardArrow" and Checkmarks.buttons[button],
        "a button whose art changed to a known glyph was not tracked")
    Check(RoleScans(Track) > 0, "a button with a role stopped scanning its art")
    normal.atlas = "questlog-unknown"
    Track()
    Track()
    Check(RoleScans(Track) == 0, "a button that lost its role was classified again on every pass")
    -- A new texture object in a slot.
    local check = ArtTexture("checkmark-minimal")
    button.slots.GetCheckedTexture = check
    Check(RoleScans(Track) > 0 and check.vertexWrites == 1 and Checkmarks.states[check].colorRole == "checkmark",
        "a texture Blizzard put into a slot was not tracked")
    button.slots.GetCheckedTexture = nil
    Track()
    Track()
    -- A field slot, a file path.
    button.Icon = ArtTexture(nil, "Interface/Buttons/UI-PlusButton-Up.blp")
    Check(RoleScans(Track) > 0 and Checkmarks.states[button.Icon].colorRole == "blizzardExpand",
        "a field texture Blizzard set was not tracked")
    button.Icon = nil
    -- A file path (GetTextureFilePath) and a texture (GetTexture) each count:
    -- here GetTexture answers a file ID, which is no path.
    highlight.file = 136235
    Track()
    Track()
    highlight.path = "Interface\\Buttons\\UI-PlusButton-Hilight"
    Check(RoleScans(Track) > 0 and Checkmarks.states[highlight].colorRole == "blizzardExpandHover",
        "a changed texture file path was not tracked")
    highlight.path = "Interface\\Buttons\\UI-Common-MouseHilight"
    Track()
    Track()
    highlight.file = "Interface\\Buttons\\UI-CheckBox-Check"
    Check(RoleScans(Track) > 0 and Checkmarks.states[highlight].colorRole == "checkmark",
        "a changed texture was not tracked")
    highlight.file = 136235
    Track()
    Track()

    -- Secret and forbidden art: never compared or read, and never cached wrong.
    pushed.secretAtlas = true
    Track()
    Track()
    Check(RoleScans(Track) == 0, "a secret atlas (read as none, like the scan) kept the button scanning")
    pushed.secretAtlas = false
    pushed.atlas = "checkmark-minimal"
    Check(RoleScans(Track) > 0 and Checkmarks.states[pushed].colorRole == "checkmark",
        "a secret atlas that became a known glyph was not tracked")
    pushed.atlas = "questlog-unknown-pressed"
    pushed.forbidden = true
    Track()
    Track()
    Check(RoleScans(Track) == 0, "a forbidden texture kept the button scanning")
    pushed.forbidden = false
    pushed.atlas = "checkmark-minimal"
    Check(RoleScans(Track) > 0, "a texture that is no longer forbidden was not scanned")
    pushed.atlas = "questlog-unknown-pressed"
    Track()
    Track()

    -- Disabled or in combat: nothing is read or written.
    NS.DB.enabled = false
    normal.reads = 0
    Check(Checkmarks.TrackButton(button, "rows") == false and normal.reads == 0, "a disabled skin read the art")
    NS.DB.enabled = true

    -- A revisited button without a role allocates nothing.
    collectgarbage("collect")
    collectgarbage("stop")
    local kilobytes = collectgarbage("count")
    for _ = 1, 500 do Track() end
    kilobytes = collectgarbage("count") - kilobytes
    collectgarbage("restart")
    Check(kilobytes < 0.5, ("500 button passes allocated %.2f KB"):format(kilobytes))
end

------------------------------------------------------------------ differential worlds
-- World A keeps its rows and buttons, so both shortcuts engage. World B gets
-- new node and button objects on every pass over the same regions and
-- textures: nothing is cached there, which is the pass without shortcuts.
-- Both see the same seeded Blizzard changes; every pass must end the same.
local function Random(seed)
    local state = seed
    return function(limit)
        state = (state * 1103515245 + 12345) % 2147483648
        return state % limit + 1
    end
end

local TEXT_COLORS = {
    { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.5, 0.5, 0.5 }, { 1, 0.825, 0.005 }, { 0.95, 0.8, 0.1 },
}
do
    local roll = Random(20261011)
    local worlds = {}
    for world = 1, 2 do
        local nodes = {}
        for index = 1, 5 do
            local regions = {}
            for slot = 1, index % 3 + 1 do
                regions[slot] = slot % 2 == 0 and Region() or FontString(1, 0.82, 0)
            end
            nodes[index] = { regions = regions }
        end
        worlds[world] = { nodes = nodes, persistent = {} }
        for index, node in ipairs(nodes) do worlds[world].persistent[index] = Node(node.regions) end
    end
    local function Texts(world)
        local texts = {}
        for _, node in ipairs(worlds[world].nodes) do
            for _, region in ipairs(node.regions) do
                if region.SetTextColor then texts[#texts + 1] = region end
            end
        end
        return texts
    end
    local function Pass(world, fresh)
        local list = {}
        for index, node in ipairs(worlds[world].nodes) do
            local target = fresh and Node(node.regions) or worlds[world].persistent[index]
            target.hierarchySecret = node.hierarchySecret
            list[index] = target
        end
        return Yellow.TrackFrames(list, #list)
    end
    local STEPS, passes = 2500, 0
    for step = 1, STEPS do
        -- 1-4 Blizzard colours a label, 5 adds a region (up to six), 6 one leaves, 7 the
        -- Hierarchy aspect flips, 8 the configured colour changes, else none.
        local action, node, value = roll(12), roll(5), roll(#TEXT_COLORS)
        for world = 1, 2 do
            local model = worlds[world].nodes[node]
            local texts = Texts(world)
            if action <= 4 and #texts > 0 then
                local text = texts[(node * 7 + step) % #texts + 1]
                local color = TEXT_COLORS[value]
                text:SetTextColor(color[1], color[2], color[3], 1)
            elseif action == 5 and #model.regions < 6 then
                model.regions[#model.regions + 1] = value % 2 == 0 and Region()
                    or FontString(TEXT_COLORS[value][1], TEXT_COLORS[value][2], TEXT_COLORS[value][3])
            elseif action == 6 and #model.regions > 0 then
                table.remove(model.regions, (step % #model.regions) + 1)
            elseif action == 7 then
                model.hierarchySecret = not model.hierarchySecret
            elseif action == 8 and world == 1 then
                desired[1] = value / 10
            end
        end
        local countedA, countedB = Pass(1, false), Pass(2, true)
        passes = passes + #worlds[1].nodes
        local textsA, textsB = Texts(1), Texts(2)
        local same = countedA == countedB and #textsA == #textsB
        for index = 1, #textsA do
            local a, b = textsA[index], textsB[index]
            same = same and a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a and a.writes == b.writes
                and (Yellow.directStates[a] == nil) == (Yellow.directStates[b] == nil)
        end
        Check(same, "step " .. step .. ": a recorded row pass left its text differently from a full pass")
    end
    -- The recorded path carried most node passes.
    Check(Enumerations(worlds[1].persistent) < passes / 2,
        "the differential row world rarely used its recorded FontStrings")
    desired[1] = 0.2
end

-- Mostly art without a role, so the skip engages between Blizzard's changes.
local ATLASES = { false, "questlog-unknown", "questlog-unknown-pressed", "ui-hud-unknown", "Garr_Unknown",
    "questlog-unknown", false, "ui-hud-unknown", "checkmark-minimal", "redbutton-exit", "redbutton-exit-pressed",
    "redbutton-exit-disabled", "common-button-dropdown-open", "128-redbutton-plus", "128-redbutton-plus-pressed",
    "128-redbutton-plus-disabled", "common-dropdown-icon-next" }
local PATHS = { false, "Interface\\Buttons\\UI-Common-MouseHilight", "Interface\\QuestFrame\\UI-Quest",
    false, "Interface\\Buttons\\UI-CheckBox-Check", "Interface/Buttons/UI-PlusButton-Up.blp",
    "interface\\common\\ui-dropdownradiochecks" }
do
    local roll = Random(1103)
    local worlds = {}
    for world = 1, 2 do
        local textures = {}
        for index = 1, 6 do textures[index] = ArtTexture(nil, nil) end
        worlds[world] = { textures = textures, slots = {}, fields = {} }
        worlds[world].button = ArtButton(worlds[world].slots, nil)
    end
    local function Fresh(world)
        local model = worlds[world]
        local button = ArtButton(model.slots, nil)
        for key, value in pairs(model.fields) do button[key] = value end
        return button
    end
    local owners = { "rows", "window" }
    local STEPS, skipped = 3000, 0
    for step = 1, STEPS do
        -- 1-3 a slot gets a texture or none, 4-6 an atlas changes, 7-8 a file
        -- path or texture, 9 forbidden flips, 10 a secret atlas flips, 11
        -- Blizzard repaints a texture, else nothing changes.
        local action, slot, value, texture = roll(16), roll(10), roll(#ATLASES), roll(6)
        for world = 1, 2 do
            local model = worlds[world]
            local target = model.textures[texture]
            if action <= 3 then
                local object = value % 3 ~= 0 and model.textures[(value + slot) % 6 + 1] or nil
                if slot <= #SLOT_GETTERS then
                    model.slots[SLOT_GETTERS[slot]] = object
                else
                    model.fields[SLOT_FIELDS[slot - #SLOT_GETTERS]] = object
                    model.button[SLOT_FIELDS[slot - #SLOT_GETTERS]] = object
                end
            elseif action <= 6 then
                target.atlas = ATLASES[value] or nil
            elseif action <= 8 then
                local path = PATHS[value % #PATHS + 1] or nil
                if action == 7 then
                    target.path = path
                else
                    target.file = slot % 3 == 0 and 136235 or path
                end
            elseif action == 9 then
                target.forbidden = not target.forbidden
            elseif action == 10 then
                target.secretAtlas = not target.secretAtlas
            elseif action == 11 then
                target:SetVertexColor(1, 1, 1, 1)
            end
        end
        local owner = owners[step % 2 + 1]
        local fresh = Fresh(2)
        actionTracks[worlds[1].button], actionTracks[fresh] = nil, nil
        local changedA, changedB
        if RoleScans(function() changedA = Checkmarks.TrackButton(worlds[1].button, owner) end) == 0 then
            skipped = skipped + 1
        end
        changedB = Checkmarks.TrackButton(fresh, owner)
        local same = changedA == changedB and actionTracks[worlds[1].button] == actionTracks[fresh]
            and (Checkmarks.buttons[worlds[1].button] == true) == (Checkmarks.buttons[fresh] == true)
        Checkmarks.buttons[worlds[1].button] = nil
        for index = 1, 6 do
            local a, b = worlds[1].textures[index], worlds[2].textures[index]
            local stateA, stateB = Checkmarks.states[a], Checkmarks.states[b]
            same = same and a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
                and a.vertexWrites == b.vertexWrites and a.desaturated == b.desaturated
                and (stateA == nil) == (stateB == nil)
                and (stateA == nil or stateA.colorRole == stateB.colorRole and stateA.owner == stateB.owner)
        end
        Check(same, "step " .. step .. ": a skipped button pass ended differently from a full pass")
    end
    Check(skipped > STEPS / 5, ("the differential button world skipped only %d of %d passes"):format(skipped, STEPS))
end

------------------------------------------------------------------ Safety
do
    local secret = Secret()
    local forbidden = { IsForbidden = function() return secret end }
    local protectedSecret = { IsForbidden = function() return false end, IsProtected = function() return secret, false end }
    local colorful = { IsForbidden = function() return false end,
        GetTextColor = function() return 1, SECRET_NUMBER, 0, 1 end, GetName = function() return secret end }
    Check(Safety.Public(1) and Safety.Public("x") and not Safety.Public(secret), "Safety.Public accepted a secret")
    Check(Safety.IsForbidden(forbidden) and Safety.Call(forbidden, "IsForbidden") == nil,
        "a secret IsForbidden answer did not count as forbidden")
    Check(Safety.Read(colorful, "GetName") == nil and Safety.ReadColor(colorful, "GetTextColor") == nil,
        "Safety.Read or ReadColor returned a secret")
    Check(not Safety.SameColor(1, SECRET_NUMBER, 0, 1, 1, SECRET_NUMBER, 0, 1)
        and not Safety.SameColor(1, 0.82, 0, SECRET_NUMBER, 1, 0.82, 0, SECRET_NUMBER)
        and not Safety.ColorMatches({ 1, 0.82, 0, 1 }, 1, 0.82, SECRET_NUMBER, 1)
        and not Safety.Public(SECRET_NUMBER), "a secret colour channel matched")
    local protected, explicit = Safety.GetProtection(protectedSecret)
    Check(protected and explicit and not Safety.CanDecorate(protectedSecret, true)
        and not Safety.CanControl(protectedSecret, true) and not Safety.CanCreateRegions(protectedSecret, true),
        "a secret IsProtected answer did not count as protected")
    Check(Safety.SameColor(1, 0.82, 0, nil, 1, 0.82, 0, 1) and Safety.ColorMatches({ 1, 0.82, 0 }, 1, 0.82, 0)
        and not Safety.SameColor(1, 0.82, 0, 1, 1, 0.84, 0, 1)
        and Safety.SameColor(1, 0.82, 0, 1, 1, 0.83, 0, 1, Safety.COLOR_NATIVE),
        "Safety's colour tolerances changed")
    -- issecretvalue is the client's and never changes: Safety reads it once.
    local loadedWith = issecretvalue
    issecretvalue = function() return false end
    Check(not Safety.Public(secret), "Safety read issecretvalue again after load")
    issecretvalue = nil
    local bare = assert(loadfile(skin .. "Core/Safety.lua"))("MSUF_Suite_Skin", {})
    issecretvalue = loadedWith
    Check(bare.Public(secret) and bare.Public(1), "a client without issecretvalue lost the nil fallback")
end

print(("suite_skin_recycled_row_contract: %d checks passed"):format(checks))
