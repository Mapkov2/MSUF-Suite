-- One contour discovery reads each root-invariant source once, not once per node.
-- Capture 13 (build 68f773e6df5a537b): Shown -> Promote -> Reconcile -> Chrome.Update
-- -> Discover -> Inspect -> Safety.Read/Call, 3226 Inspect calls / 3073 ms inclusive.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    local character = Native("CharacterFrame", 100, 100, 400, 500)
    W.TrackFocus(character, "cost")
    local professions = Native("ProfessionsFrame", 600, 200, 700, 658)
    W.TrackFocus(professions, "cost")
    local scans, made = 0, 0
    local function Children(parent, children)
        parent.GetChildren = function() scans = scans + 1; return unpack(children) end
    end
    local function Child(parent, kind, left, bottom, width, height)
        made = made + 1
        local child = Native("CostChild" .. made, left, bottom, width, height)
        child.parent, child.kind = parent, kind
        return child
    end
    -- Five nodes: two at depth 1, two at depth 2, one raised at depth 3.
    local page = Child(professions, "Frame", 600, 200, 700, 658)
    local card = Child(page, "Frame", 650, 400, 300, 100)
    local bar = Child(card, "Frame", 650, 400, 300, 20)
    bar.strata, bar.frameLevel = "HIGH", 100
    local tabs = Child(professions, "Frame", 620, 174, 400, 28)
    local tab = Child(tabs, "Button", 620, 174, 140, 28)
    Children(professions, { page, tabs })
    Children(page, { card }); Children(card, { bar }); Children(tabs, { tab })

    local hostReads, typeReads, scriptReads = 0, 0, 0
    local field = NS.Safety.Field
    NS.Safety.Field = function(target, key)
        if target == professions and key == "PortraitContainer" then hostReads = hostReads + 1 end
        return field(target, key)
    end
    local nativeType, nativeScript = bar.GetObjectType, bar.GetScript
    bar.GetObjectType = function(self) typeReads = typeReads + 1; return nativeType(self) end
    bar.GetScript = function(self, name) scriptReads = scriptReads + 1; return nativeScript(self, name) end

    professions:Hide()
    scans, hostReads, typeReads, scriptReads = 0, 0, 0, 0
    professions:Show()
    Check(scans == 4, "one show ran " .. scans .. " child scans for four parents: not exactly one discovery")
    Check(hostReads == 1, "one discovery resolved the root's artwork host " .. hostReads .. " times (once per node)")
    Check(typeReads == 1, "one discovery read a node's object type " .. typeReads .. " times")
    Check(scriptReads == 0, "a node too deep to extend the shell had its mouse script read " .. scriptReads .. " times")

    -- The same walk still finds what it found before.
    Click(character)
    local state = F.records[professions]
    Check(state.strata == "HIGH" and state.level > bar.frameLevel, "deep raised native content escaped its dim veil")
    local function Covered(rect)
        for _, veil in ipairs(state.veils) do
            if veil.dim and Intersects(veil.rect, rect) then return true end
        end
        return false
    end
    Check(Covered({ left = 620, bottom = 174, width = 140, height = 24 }), "native tab below the root lost its dimming")

    -- Nothing is kept across walks: a host and a region created while the
    -- window was closed are both seen by its next show.
    local portrait = Child(professions, "Frame", 600, 857, 1, 1)
    local art = Child(portrait, "Texture", 560, 830, 62, 62)
    function art:GetTexture() return "native-book" end
    function art:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
    portrait.portrait = art
    local sideTab = Child(professions, "Frame", 1300, 600, 50, 46)
    sideTab.scripts.OnMouseDown = function() end
    professions:Hide()
    professions.PortraitContainer = portrait
    Children(professions, { page, tabs, portrait, sideTab })
    hostReads = 0
    professions:Show()
    Check(hostReads == 1, "the reopened window resolved its artwork host " .. hostReads .. " times")
    Click(character)
    Check(Covered({ left = 562, bottom = 832, width = 30, height = 20 }), "late native portrait host was not rediscovered on show")
    Check(Covered({ left = 1300, bottom = 600, width = 50, height = 46 }), "late-created side tab was not rediscovered on show")
    professions:Hide(); character:Hide()
    Check(not driver.events.GLOBAL_MOUSE_DOWN and not driver.scripts.OnUpdate, "discovery left idle work behind")
end
print("suite_window_focus_discovery_cost_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@window_focus_discovery_cost_fixture"))()
