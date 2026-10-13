local root = assert(arg[1])
local originalLoad, P = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, ns)
        if path:find('MSUF_Suite_Options/Menu/Bridge.lua',1,true) then P=ns end
        return chunk(addon, ns)
    end
end
assert(originalLoad(root .. '/tools/tests/suite_cooldown_manager_options_contract.lua'))()
loadfile = originalLoad
-- Use the actual sticky record, resolver and expander. Checking fixedHeight
-- alone misses Close clearing ActiveHeight before the host reserves its slot.
local create = CreateFrame
CreateFrame = function(...)
    local frame = create(...)
    function frame:GetPoint(i) return unpack(self.points[i or 1] or {}) end
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetFrameLevel() return self.frameLevel or 1 end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    return frame
end
local function LoadHost(host)
    local dir = root .. '/../' .. host .. '/MidnightSimpleUnitFrames_Options/Shell/Menu2/'
    local path = dir .. 'MSUF_Menu2_Widgets_PreviewDock.lua'
    local file = io.open(path, 'rb')
    if not file then path = dir .. 'MSUF_Menu2_Widgets.lua'; file = assert(io.open(path, 'rb')) end
    local source = file:read('*a'); file:close()
    local first = assert(source:find('function W.AttachStickyPageHeader(', 1, true))
    local last = assert(source:find('function M.CloseFixedPreviewExpander(', first, true))
    local prelude = [[
        local M, W, T, Tr = ...
        local max, min = math.max, math.min
        local RegisterSearchObject = function() end
        local PixelLayoutRegion = function(region) return region end
    ]]
    assert(loadstring(prelude .. source:sub(first, last - 1), '@' .. path))(P.M, P.W, P.T, P.Tr)
end
local function Bottom(frame)
    local point = frame.points[1]
    if not point then return frame:GetHeight() end
    assert(point[1]:find('TOP', 1, true), 'fixture expects a top anchor')
    local parent, anchor = point[2], point[3]
    local top = anchor:find('BOTTOM', 1, true) and Bottom(parent) or Bottom(parent) - parent:GetHeight()
    return top - (point[5] or 0) + frame:GetHeight()
end
local function Build(width, host, mode)
    local wrapper, headerHost = CreateFrame('Frame'), CreateFrame('Frame')
    wrapper:SetSize(width, 900); headerHost:SetSize(width, 900)
    local ctx={key=P.CDMPage.PAGE,width=width,wrapper=wrapper,entry={},refreshers={},widgets={},sections={},pageItems={}}
    local b=P.W.PageBuilder(ctx)
    function b:Section(title,height)
        local section=CreateFrame('Frame',nil,wrapper)
        section._msuf2Width=width
        section:SetSize(width,height)
        section:SetPoint('TOPLEFT', wrapper, 'TOPLEFT', 0, 0)
        return section
    end
    local ui={sections={}}
    P.CDMPage.ui=nil
    P.CDMPage.BuildPreview(ctx,b,ui)
    local section=ui.previewBody:GetParent()
    local fixed=section._msuf2FixedPagePreviewRecord
    local expander=section._msuf2FixedPreviewExpanderRecord
    local needed=40+ui.previewBody:GetHeight()+8
    assert(fixed.fixedHeight>=needed,'CDM_COMPACT_BODY_EXCEEDS_NATIVE_STICKY_RESERVATION')
    P.M.activeKey=ctx.key
    P.M.frame:Show()
    P.M.RelayoutPageHeaderHost=function() fixed:Activate(headerHost,0) end
    local settings=CreateFrame('Frame',nil,headerHost)
    settings:SetSize(width,300)
    local function Check(label, compact)
        local reserved=fixed:ResolveHeight()
        local required=40+ui.previewBody:GetHeight()+8
        assert(reserved>=required,
            label..': CDM_COMPACT_RESOLVER_CLIPS_BODY ('..reserved..' < '..required..')')
        assert(section:GetHeight()==reserved,label..': section and sticky reservation disagree')
        settings:ClearAllPoints()
        settings:SetPoint('TOPLEFT',section,'BOTTOMLEFT',0,-8)
        for _,frame in ipairs({ui.canvas,ui.previewLine,ui.status}) do
            assert(Bottom(frame)<=Bottom(section)-8,label..': preview content overlaps following settings')
        end
        assert(Bottom(ui.status)<=Bottom(settings)-settings:GetHeight()-8,label..': status overlaps settings')
        assert(ui.selection:IsShown()==not compact,label..': wrong selection-bar visibility')
    end
    P.M.SetFixedPreviewExpandedPreference(false)
    fixed:Activate(headerHost,0)
    fixed.onActivate()
    Check('initial compact',true)
    for i=1,3 do
        assert(expander:Open('FIXED_PREVIEW_BUTTON'),'actual host expander did not open')
        Check('expanded '..i,false)
        expander:Close('FIXED_PREVIEW_BUTTON')
        Check('collapsed '..i,true)
        fixed:Deactivate()
        fixed:Activate(headerHost,0)
        fixed.onActivate()
        Check('cached compact '..i,true)
    end
    fixed:Deactivate()
    print('CDM compact lifecycle',host,mode,width,'passed')
end
for _,host in ipairs({'_repo_backups/6.22','MidnightSimpleUnitFrames'}) do
    LoadHost(host)
    for _,mode in ipairs({'legacy','host'}) do
        P.M.HOST_API_VERSION=nil
        if mode=='host' then
            assert(loadfile(root..'/../MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_HostProtocol.lua'))('MSUF',{MSUF2=P.M})
        end
        local suite={HostBridge={}}
        assert(loadfile(root..'/MSUF_Suite/Core/HostBridgeMenu.lua'))('MSUF_Suite',suite)
        P.HM=suite.HostBridge.Menu2(P.M)
        assert(P.HM.mode==mode,'fixture did not select requested host bridge')
        assert(loadfile(root..'/MSUF_Suite_Options/Pages/CooldownManagerPreview.lua'))('MSUF_Suite_Options',P)
        Build(1040,host,mode)
        Build(720,host,mode)
        Build(420,host,mode)
    end
end
print('CDM compact preview: real host collapse and cached return reserve all content on both bridges passed')
