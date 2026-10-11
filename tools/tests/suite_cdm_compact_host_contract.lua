local root = assert(arg[1])
local host = root .. "/../MidnightSimpleUnitFrames"
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
local h=assert(io.open(host .. '/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua','rb'))
local source=h:read('*a'):gsub('\r','');h:close()
local start=assert(source:find('function W.FixedPreviewSection(ctx, builder, spec)',1,true))
local ending=assert(source:find('\n--- Add compact/full behavior',start,true))
local chunk=assert(loadstring(source:sub(start,ending-1)))
setfenv(chunk,setmetatable({W=P.W,max=math.max,min=math.min,FIXED_PREVIEW_MAX_HEIGHT=180},{__index=_G}))
P.W.AttachStickyPageHeader=function(section,opts) return {} end
chunk()
local function Build(width)
    local ctx={key=P.CDMPage.PAGE,width=width,refreshers={},widgets={},sections={},pageItems={}}
    local b=P.W.PageBuilder(ctx)
    function b:Section(title,height)
        local section=CreateFrame('Frame',nil,P.M.frame)
        section._msuf2Width=width
        section:SetSize(width,height)
        return section
    end
    local ui={sections={}}
    P.CDMPage.ui=nil
    P.CDMPage.BuildPreview(ctx,b,ui)
    local section=ui.previewBody:GetParent()
    local fixed=section._msuf2FixedPagePreviewRecord.fixedHeight
    local needed=40+ui.previewBody:GetHeight()+8
    print('width',width,'native compact section',fixed,'CDM body plus insets',needed)
    assert(fixed>=needed,'CDM_COMPACT_BODY_EXCEEDS_NATIVE_STICKY_RESERVATION')
end
Build(720)
Build(420)
print("CDM compact preview: actual host height contract at normal and narrow widths passed")
