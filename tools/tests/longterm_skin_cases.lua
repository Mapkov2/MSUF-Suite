-- Independent lifecycle regressions. Product chunks are always loaded from root;
-- existing fixtures supply native widgets/codec, never copied product functions.
local root, case = assert(arg[1]), assert(arg[2])
local reference, host = arg[3], arg[4]

local function Read(path)
    local file = assert(io.open(path, "rb"), path)
    local text = file:read("*a")
    file:close()
    return text
end

local function Inject(relative, marker, body, prefixOnly)
    local source = Read(root .. "/" .. relative)
    local at = assert(source:find(marker, 1, true), "fixture marker changed: " .. marker)
    local suffix = prefixOnly and "" or source:sub(at)
    assert(loadstring(source:sub(1, at - 1) .. body .. suffix, "@longterm-" .. case))()
end

local function Noop() end

local function PublicWorld()
    local world = { reports = {}, attempts = 0, healthy = 0, cleanups = 0, cleaned = 0 }
    securecallfunction = function(callback, ...)
        local values = { pcall(callback, ...) }
        if not values[1] then
            world.reports[#world.reports + 1] = tostring(values[2])
            return
        end
        return unpack(values, 2, table.maxn(values))
    end
    C_Timer = { After = function(_, callback) callback() end }
    local NS = {
        publicAPIMajor = 2, publicAPIMinor = 1,
        IsCombatLocked = function() return false end,
        DB = { enabled = true, theme = {}, geometry = {}, icons = { windowActions = {} } },
        Defaults = { icons = { windowActions = {} } },
        Clamp = function(value, low, high) return math.max(low, math.min(high, tonumber(value) or low)) end,
        ControlSkin = { GetOwner = Noop, DisableOwner = Noop, states = {} },
        WindowActionSkin = { GetOwner = Noop, DisableOwner = Noop },
        IconSkin = { GetOwner = Noop, DisableOwner = Noop },
        Cosmetics = { GetOwner = Noop, RestoreOwner = Noop },
        CombatGate = { Cancel = Noop, RunOrDefer = function(_, callback) callback() end },
        Typography = { GetSelection = Noop, GetSelectionPath = Noop },
        Theme = { GetColor = Noop },
    }
    NS.Surface = {
        Attach = function(target)
            world.attempts = world.attempts + 1
            if world.attempts == world.failAttach then error("contract: one target apply") end
            world.healthy = world.healthy + 1
            NS.Registry.RegisterSurface(target, { visible = true, refresh = Noop })
            return target
        end,
        SetVisible = function(target, value)
            if value == false then
                world.cleanups = world.cleanups + 1
                if world.cleanups == world.failCleanup then error("contract: one target cleanup") end
                world.cleaned = world.cleaned + 1
            end
            local surface = NS.Registry.GetSurface(target)
            if surface then surface.visible = value end
            return true
        end,
        SetNativeStateSync = Noop,
    }
    for _, name in ipairs({ "Safety", "Registry", "PublicAPI", "PublicAPIMethods" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/Core/" .. name .. ".lua"))("MSUF_Suite_Skin", NS)
    end
    world.NS, world.api = NS, NS.PublicAPI.API
    function world:Reset()
        self.attempts, self.healthy, self.cleanups, self.cleaned = 0, 0, 0, 0
        self.reports, self.failAttach, self.failCleanup = {}, nil, nil
    end
    function world:Populate(acrossClients)
        self.clients, self.targets = {}, {}
        local shared = not acrossClients and assert(self.api:RegisterAddon("LongtermShared"))
        for index = 1, 3 do
            local client = shared or assert(self.api:RegisterAddon("Longterm" .. index))
            local frame = { CreateTexture = Noop, IsProtected = function() return false, false end }
            assert(client:SkinFrame(frame, { role = "panel" }))
            self.clients[index], self.targets[index] = client, frame
        end
        NS.PublicAPI.Activate()
    end
    return world
end

if case == "public-fault" then
    local checked = 0
    for _, acrossClients in ipairs({ false, true }) do
        for _, scenario in ipairs({ "login", "profile", "resume", "refresh", "cleanup", "release", "unregister" }) do
            if not acrossClients or (scenario ~= "release" and scenario ~= "unregister") then
                for failedAt = 1, 3 do
                    local world = PublicWorld()
                    local NS = world.NS
                    world:Populate(acrossClients)
                    if scenario ~= "login" then NS.Safety.Dispatch(NS.PublicAPI.OnPlayerLogin) end
                    if scenario == "resume" then
                        NS.DB.enabled = false
                        NS.Registry.NotifyListeners("adapter", "master")
                    end
                    world:Reset()
                    local cleaning = scenario == "cleanup" or scenario == "release" or scenario == "unregister"
                    if cleaning then world.failCleanup = failedAt else world.failAttach = failedAt end
                    local ok, reason
                    if scenario == "login" then NS.Safety.Dispatch(NS.PublicAPI.OnPlayerLogin)
                    elseif scenario == "profile" then NS.Registry.NotifyListeners("profile", "activate")
                    elseif scenario == "resume" then
                        NS.DB.enabled = true
                        NS.Registry.NotifyListeners("adapter", "master")
                    elseif scenario == "refresh" then ok, reason = NS.Safety.Dispatch(NS.PublicAPI.RefreshAll)
                    elseif scenario == "cleanup" then
                        NS.DB.enabled = false
                        NS.Registry.NotifyListeners("adapter", "master")
                    elseif scenario == "release" then
                        ok, reason = NS.Safety.Dispatch(world.clients[1].ReleaseAll, world.clients[1])
                    else ok, reason = NS.Safety.Dispatch(world.clients[1].Unregister, world.clients[1]) end
                    local attempts, healthy = world.attempts, world.healthy
                    if cleaning then attempts, healthy = world.cleanups, world.cleaned end
                    local label = scenario .. "/" .. tostring(acrossClients) .. "/" .. failedAt
                    assert(attempts == 3 and healthy == 2 and #world.reports == 1,
                        label .. ": one target fault aborted healthy targets: " .. attempts .. "/" .. healthy)
                    if scenario == "refresh" or scenario == "release" or scenario == "unregister" then
                        assert(ok == false and reason == "error", label .. ": public request hid failure")
                    end
                    world:Reset()
                    NS.DB.enabled = true
                    if scenario == "release" then assert(world.clients[1]:ReleaseAll())
                    elseif scenario == "unregister" then assert(world.clients[1]:Unregister())
                    else
                        NS.Registry.NotifyListeners("adapter", "master")
                        assert(world.healthy == 3, label .. ": retained target did not recover")
                        for index = 1, 3 do assert(world.clients[index]:Release(world.targets[index])) end
                    end
                    for _, target in ipairs(world.targets) do
                        assert(NS.Registry.GetSurface(target).visible == false, label .. ": cleanup stranded a surface")
                    end
                    checked = checked + 1
                end
            end
        end
    end
    -- Successful direct requests retain their normal return contract.
    local world = PublicWorld()
    world.NS.PublicAPI.OnPlayerLogin()
    local client = assert(world.api:RegisterAddon("LongtermDirect"))
    local target = { CreateTexture = Noop, IsProtected = function() return false, false end }
    assert(client:SkinFrame(target, { role = "panel" }))
    world:Reset()
    world.failAttach = 1
    local ok, reason = world.NS.Safety.Dispatch(client.RefreshAll, client)
    assert(ok == false and reason == "error" and #world.reports == 1, "direct refresh fault was not returned")
    world:Reset()
    assert(client:RefreshAll() and client:Release(target))
    print("longterm public fault matrix: " .. checked .. " first/middle/last paths plus direct recovery")
    return
end

if case == "archive" then
    Inject("tools/tests/suite_skin_profile_import_contract.lua", "-- A friend's string", [=[
for index = 1, 62 do assert(Database.CreateProfile("Archive " .. index, true)) end
assert(#Database.GetProfileNames() == 64, "creation positive control")
local encoded = assert(IO.ExportAll())
assert(IO.ImportAll(encoded), "64-profile archive did not roundtrip")
assert(#Database.GetProfileNames() == 64 and Accent("Default") == .11 and Accent("Raid") == .22,
    "64-profile roundtrip lost values")
assert(Database.CreateProfile("Profile 65", true), "archive bound must not limit creation")
local savedRoot, serialized = Database.GetRoot(), #blobs
local refused, reason = IO.ExportAll()
assert(refused == nil and reason == "too-many-profiles", "65-profile archive was exported as usable")
assert(#blobs == serialized and Database.GetRoot() == savedRoot and #Database.GetProfileNames() == 65,
    "refused export serialized or mutated the store")
local single = assert(IO.ExportProfile("Raid"))
local profile, name = IO.PrepareProfile(single)
assert(profile and name == "Raid" and profile.theme.colors.accent[1] == .22,
    "single-profile export stopped working with 65 existing profiles")
assert(IO.ImportProfile(single, "Raid", true) and #Database.GetProfileNames() == 65,
    "single-profile replacement stopped working with 65 existing profiles")
blobs[#blobs + 1] = {addon="MapkoSkin",format=1,kind="database",activeProfile="Default",
    payload=NS.CopyValue(Database.GetRoot().profiles)}
local imported, importReason = IO.ImportAll(IO.prefix .. "cbor:" .. #blobs)
assert(imported == false and importReason == "too-many-profiles" and #Database.GetProfileNames() == 65,
    "import count admission diverged or mutated profiles")
print("longterm archive: 64 roundtrip, 65 refusal, single-profile export/import at 65")
]=], true)
    return
end

local bodies = {}
bodies["public-partial"] = [=[
do
    namespace.DB.enabled = true
    namespace.PublicAPI.OnPlayerLogin()
    local reports, dispatch = {}, namespace.Safety.Dispatch
    namespace.Safety.Dispatch = function(callback, ...)
        local values = {pcall(callback,...)}
        if not values[1] then reports[#reports+1]=tostring(values[2]); return end
        return unpack(values,2,table.maxn(values))
    end
    local client = assert(namespace.PublicAPI.API:RegisterAddon("LongtermPartial"))
    local target = new_frame("Frame", nil, UIParent)
    local protected = false
    target.IsProtected = function() return protected, protected end
    local attach = namespace.Surface.Attach
    namespace.Surface.Attach = function(frame, spec)
        local state, reason = attach(frame,spec)
        if frame == target and state then error("contract: after real Surface.Attach") end
        return state, reason
    end
    namespace.Safety.Dispatch(client.SkinFrame,client,target,{role="panel"})
    namespace.Surface.Attach = attach
    local surface = assert(namespace.Registry.GetSurface(target), "real Surface.Attach never registered")
    assert(surface.visible == true and #reports == 1, "partial apply fault was not reported")
    protected = true
    local released, reason = client:Release(target)
    assert(released == false and reason == "protected-target", "unsafe partial owner was forgotten: " .. tostring(reason))
    assert(surface.visible == true, "unsafe cleanup touched visual state")
    protected = false
    assert(client:Release(target) and surface.visible == false, "safe cleanup retry lost the partial surface")
    assert(client:SkinFrame(target,{role="panel"}) and client:Release(target), "released target could not be reclaimed")
    namespace.Safety.Dispatch = dispatch
    print("longterm partial apply: real attached surface retained through protected refusal and cleaned on retry")
end
]=]
bodies["micro-preview"] = [=[
do
    local settings = namespace.DB.icons.microMenu
    namespace.DB.skins.microMenu = true
    local previewIcons, applyIcon = {}, namespace.MicroMenuVisual.ApplyIcon
    namespace.MicroMenuVisual.ApplyIcon = function(icon,...)
        previewIcons[#previewIcons+1]=icon
        return applyIcon(icon,...)
    end
    local embedded = assert(namespace.Options.embeddedHost)
    embedded:Show()
    -- ApplyIcon creates/configures the artwork only when its style changes;
    -- later tint-only repaints keep the same real preview texture objects.
    settings.iconStyle,settings.tint="bold","native"
    assert(embedded:ShowPage("icons"))
    for _, style in ipairs({"blizzard","blizzardIcons"}) do
        for _, tint in ipairs({"native","monochrome"}) do
            settings.iconStyle,settings.tint=style,tint
            assert(embedded:ShowPage("icons"))
            local button,texture=new_frame("Button",nil,UIParent),new_region("Texture")
            texture:SetDesaturated(false)
            assert(namespace.MicroMenuStates.ApplyTextureTint(button,texture,"normal",settings))
            assert(texture:IsDesaturated()==(tint=="monochrome"),"runtime positive control")
            assert(#previewIcons>=4,"actual preview did not paint")
            for _,icon in ipairs(previewIcons) do
                assert(icon:IsDesaturated()==texture:IsDesaturated(),style.."/"..tint..": preview/runtime desaturation differs")
            end
        end
    end
    namespace.MicroMenuVisual.ApplyIcon=applyIcon
    print("longterm micro preview: native/monochrome parity for both native artwork styles")
end
]=]
bodies["checkmarks"] = [=[
do
    for _,kind in ipairs({"normal","foreign-desaturation","foreign-color","original-desaturated"}) do
        local texture=new_region("Texture")
        local original=kind=="original-desaturated"
        texture:SetVertexColor(1,.82,0,1)
        texture:SetDesaturated(original)
        local owner="longterm-checkmark-"..kind
        assert(namespace.Checkmarks.TrackTexture(texture,owner,"checkmark"))
        assert(texture:IsDesaturated()==true,"checkmark apply positive control")
        if kind=="foreign-desaturation" then texture:SetDesaturated(false) end
        if kind=="foreign-color" or original then texture:SetVertexColor(.2,.4,.9,1) end
        assert(namespace.Checkmarks.UntrackOwner(owner))
        local r,g,b=texture:GetVertexColor()
        local foreign=kind=="foreign-color" or original
        assert(r==(foreign and .2 or 1) and g==(foreign and .4 or .82) and b==(foreign and .9 or 0),
            kind..": newer RGB was overwritten or original tint not restored")
        assert(texture:IsDesaturated()==original,kind..": independently owned desaturation was not restored")
    end
    print("longterm checkmark restore: independent RGB/desaturation ownership and positive controls")
end
]=]
bodies["stats"] = [=[
do
    assert(namespace.Client.modernEquipment,"stats requires Mainline")
    namespace.DB.enabled=true
    namespace.DB.skins.blizzardWindows=true
    namespace.DB.characterStats.enabled=true
    namespace.DB.characterStats.diminishingReturns=false
    namespace.DB.characterDetails.view="modern"
    namespace.DB.skinCategories.character=true
    GameFontNormal=GameFontNormal or new_region("FontString")
    GameFontNormal:SetFont("Fonts\\FRIZQT__.TTF",12,"")
    GameTooltip.IsOwned=function() return false end
    local pane=new_frame("Frame","LongtermStats",UIParent)
    pane.IsVisible=function() return true end
    pane:SetSize(220,600)
    for _,key in ipairs({"ItemLevelCategory","AttributesCategory","EnhancementsCategory"}) do
        local category=new_frame("Frame",nil,pane)
        category.Title=new_region("FontString")
        category.Title:SetFont("Fonts\\ORIGINAL.TTF",11,"")
        category.Title:SetTextColor(1,.82,0,1)
        category.Title:SetPoint("CENTER",category,"CENTER",3,4)
        category.Title.justify="RIGHT"
        category.Title.GetJustifyH=function(self) return self.justify end
        category.Title.SetJustifyH=function(self,value) self.justify=value end
        pane[key]=category
    end
    pane.ItemLevelFrame=new_frame("Frame",nil,pane)
    pane.ItemLevelFrame.Value=new_region("FontString")
    pane.ItemLevelFrame.Value:SetFont("Fonts\\ORIGINAL.TTF",20,"")
    local row=new_frame("Frame",nil,pane)
    row.IsVisible=function() return true end
    row.Label,row.Value=new_region("FontString"),new_region("FontString")
    row.Label:SetFont("Fonts\\ORIGINAL.TTF",11,"")
    row.Value:SetFont("Fonts\\ORIGINAL.TTF",11,"")
    row.Label:SetText("Other stat:")
    pane.statsFramePool={EnumerateActive=function() return next,{[row]=true},nil end}
    local title=pane.ItemLevelCategory.Title
    for _,kind in ipairs({"normal","foreign-font","foreign-color","foreign-geometry","foreign-both",
        "foreign-repaint","foreign-geometry-repaint"}) do
        assert(select(1,title:GetFont())=="Fonts\\ORIGINAL.TTF","positive setup lost original font")
        namespace.CharacterStats.Apply(pane,"longterm-stats")
        assert(namespace.CharacterStats.views[pane] and select(1,title:GetFont())~="Fonts\\ORIGINAL.TTF",
            "actual stats view did not paint")
        local font=kind=="foreign-font" or kind=="foreign-both" or kind=="foreign-repaint"
        local color=kind=="foreign-color" or kind=="foreign-both" or kind=="foreign-repaint"
        if font then title:SetFont("Fonts\\LATER.TTF",17,"OUTLINE") end
        if color then title:SetTextColor(.2,.4,.9,1) end
        local geometry=kind=="foreign-geometry" or kind=="foreign-geometry-repaint"
        if geometry then
            title:ClearAllPoints();title:SetPoint("BOTTOM",pane,"TOP",13,14);title:SetJustifyH("CENTER")
        end
        if kind=="foreign-repaint" then
            -- A normal font/palette change repaints an already active view.
            GameFontNormal:SetFont("Fonts\\NEW_THEME.TTF",12,"")
            namespace.DB.theme.colors.title={.8,.7,.6,1}
            namespace.CharacterStats.RefreshFonts()
            local paintedPath,paintedSize=title:GetFont()
            assert(paintedPath=="Fonts\\NEW_THEME.TTF" and paintedSize==17,
                "actual font refresh lost the rebased native minimum size")
        end
        if kind=="foreign-geometry-repaint" then
            namespace.CharacterStats.Refresh(namespace.CharacterStats.views[pane])
            assert(title:GetPoint(1)=="LEFT" and title:GetJustifyH()=="LEFT","actual layout did not reapply")
        end
        namespace.CharacterStats.Disable(pane,"longterm-stats")
        local path,size,flags=title:GetFont()
        local r,g,b=title:GetTextColor()
        assert(path==(font and "Fonts\\LATER.TTF" or "Fonts\\ORIGINAL.TTF") and size==(font and 17 or 11)
            and flags==(font and "OUTLINE" or ""),kind..": cleanup overwrote newer font or failed native restore")
        assert(r==(color and .2 or 1) and g==(color and .4 or .82) and b==(color and .9 or 0),
            kind..": cleanup overwrote newer color or failed native restore")
        local point,relative,relativePoint,x,y=title:GetPoint(1)
        assert(point==(geometry and "BOTTOM" or "CENTER") and x==(geometry and 13 or 3)
            and y==(geometry and 14 or 4) and title:GetJustifyH()==(geometry and "CENTER" or "RIGHT"),
            kind..": cleanup did not respect independent anchors/justification")
        title:SetFont("Fonts\\ORIGINAL.TTF",11,"");title:SetTextColor(1,.82,0,1)
        title:ClearAllPoints();title:SetPoint("CENTER",pane.ItemLevelCategory,"CENTER",3,4);title:SetJustifyH("RIGHT")
    end
    -- The fixture's SecretValues stand-in was installed before Safety loaded.
    -- Poisoned readers exercise unreadable ownership, including a temporary
    -- SecretWhenAnchoringSecret GetPoint answer across refresh and recovery.
    for _,property in ipairs({"font","color","point","justify"}) do
        namespace.CharacterStats.Apply(pane,"longterm-stats")
        local secret=newproxy(true)
        getmetatable(secret).__tostring=function() error("secret stringification") end
        local previousSecret=issecretvalue
        issecretvalue=function(value) return rawequal(value,secret) end
        local getter=({font="GetFont",color="GetTextColor",point="GetPoint",justify="GetJustifyH"})[property]
        local originalReader=title[getter]
        title[getter]=function() return secret,secret,secret,secret,secret end
        local writes=0
        local setters=({font={"SetFont"},color={"SetTextColor"},point={"ClearAllPoints","SetPoint"},
            justify={"SetJustifyH"}})[property]
        local originals={}
        for _,setter in ipairs(setters) do
            local original=title[setter]
            originals[setter]=original
            title[setter]=function(self,...) writes=writes+1;return original(self,...) end
        end
        namespace.CharacterStats.Disable(pane,"longterm-stats")
        assert(writes==0,property..": unreadable property was overwritten during cleanup")
        title[getter]=originalReader
        for setter,original in pairs(originals) do title[setter]=original end
        issecretvalue=previousSecret
        title:SetFont("Fonts\\ORIGINAL.TTF",11,"");title:SetTextColor(1,.82,0,1)
        title:ClearAllPoints();title:SetPoint("CENTER",pane.ItemLevelCategory,"CENTER",3,4);title:SetJustifyH("RIGHT")
    end
    namespace.CharacterStats.Apply(pane,"longterm-stats")
    local secret,originalReader,previousSecret=newproxy(true),title.GetPoint,issecretvalue
    issecretvalue=function(value) return rawequal(value,secret) end
    title.GetPoint=function() return secret,secret,secret,secret,secret end
    namespace.CharacterStats.Refresh(namespace.CharacterStats.views[pane])
    title.GetPoint,issecretvalue=originalReader,previousSecret
    namespace.CharacterStats.Disable(pane,"longterm-stats")
    assert(title:GetPoint(1)=="CENTER","temporary secret anchoring discarded its recoverable native snapshot")
    print("longterm stats restore: font/color/anchors/justification ownership and positive controls")
end
]=]
bodies["model"] = [=[
do
    assert(namespace.Client.isForever,"model requires Forever")
    namespace.DB.enabled=true
    namespace.DB.skins.blizzardWindows=true
    namespace.DB.theme.look="foreverGlass"
    CharacterFrame=new_frame("Frame","CharacterFrame",UIParent)
    CharacterModelScene=new_frame("ModelScene","CharacterModelScene",CharacterFrame)
    local names={"CharacterModelFrameBackgroundTopLeft","CharacterModelFrameBackgroundTopRight",
        "CharacterModelFrameBackgroundBotLeft","CharacterModelFrameBackgroundBotRight"}
    for _,name in ipairs(names) do
        local texture=new_region("Texture");texture:SetVertexColor(1,1,1,1);_G[name]=texture
    end
    local texture=CharacterModelFrameBackgroundTopLeft
    for _,kind in ipairs({"normal","foreign","reapply"}) do
        assert(namespace.CharacterPanel.Apply("longterm-model"))
        assert(select(1,texture:GetVertexColor())==.36,"real model tint positive control")
        if kind~="normal" then texture:SetVertexColor(.2,.4,.9,.7) end
        if kind=="reapply" then
            assert(namespace.CharacterPanel.Apply("longterm-model"))
            assert(select(1,texture:GetVertexColor())==.36,"reapply positive control")
        end
        assert(namespace.CharacterPanel.Disable("longterm-model"))
        local r,g,b,a=texture:GetVertexColor()
        assert(r==(kind=="normal" and 1 or .2) and g==(kind=="normal" and 1 or .4)
            and b==(kind=="normal" and 1 or .9) and a==(kind=="normal" and 1 or .7),
            kind..": model cleanup overwrote newer color/baseline")
        texture:SetVertexColor(1,1,1,1)
    end
    print("longterm model restore: native/foreign/reapply ownership")
end
]=]

assert(bodies[case], "unknown long-term skin case: " .. case)
-- The absorption contract takes exactly root, standalone reference, host (or
-- Forever), matching run_suite_tests.py. Keep its local widget constructors.
arg = { root, assert(reference), assert(host) }
Inject("tools/tests/suite_skin_absorption_contract.lua", 'print("Suite skin: "', bodies[case], false)
