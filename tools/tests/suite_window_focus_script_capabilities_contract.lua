-- The Forever simulator enumerates an AnimationGroup below an unnamed
-- MerchantFrame child. It exposes HookScript but rejects frame layout scripts.
local root=assert(arg[1])
local f=assert(io.open(root.."/tools/tests/suite_window_focus_contract.lua","rb"))
local source=f:read("*a"); f:close()
local stop=assert(source:find('    local a = Native("CharacterFrame"',1,true))
local body=[======[
    local merchant=Native("MerchantFrame",100,100,336,444)
    -- Discovery runs when at least two panel roots need a focus order.
    local bags=Native("ContainerFrameCombinedBags",650,100,360,500)
    assert(W.TrackFocus(bags,"inventory"))
    local holder=Frame(nil,merchant)
    local animation=Frame(nil,holder,"AnimationGroup")
    local mixed=Frame(nil,holder,"Frame")
    local sibling=Frame(nil,holder,"Button")
    local scanned=0
    merchant.GetChildren=function() scanned=scanned+1; return holder end
    holder.GetChildren=function() return animation,mixed,sibling end
    local function Restrict(node,scripts)
        function node:HasScript(event) return scripts[event]==true end
        local hook=node.HookScript
        function node:HookScript(event,cb)
            assert(self:HasScript(event),"unsupported script "..event.." on "..self.kind)
            return hook(self,event,cb)
        end
    end
    Restrict(animation,{OnPlay=true})
    Restrict(mixed,{OnShow=true,OnSizeChanged=true})
    local continued=false
    -- Catalog PaintEntryFrame calls TrackFocus before attaching any skin.
    -- If an unsupported descendant raises, its remaining paint cannot run.
    local function EnterWindow()
        assert(W.TrackFocus(merchant,"blizzardWindows"))
        continued=true
    end
    local ok,err=pcall(EnterWindow)
    Check(ok and continued, "merchant focus prevented the rest of the window paint: "..tostring(err))
    Tick()
    Check(F.records[merchant] and next(animation.hooks)==nil,"incompatible animation was hooked")
    Check(mixed.hooks.OnShow and mixed.hooks.OnSizeChanged and not mixed.hooks.OnHide,
        "partially supported descendant lost its valid layout hooks")
    Check(sibling.hooks.OnShow and sibling.hooks.OnHide and sibling.hooks.OnSizeChanged,
        "ordinary sibling after an animation lost layout tracking")
    local before=scanned
    sibling:Hide(); Tick()
    Check(scanned>before,"normal child's hide no longer updates the visible native tree")
    F.ReleaseOwner("blizzardWindows"); F.ReleaseOwner("inventory")
end
print("suite_window_focus_script_capabilities_contract: "..checks.." checks passed")
]======]
assert(loadstring(source:sub(1,stop-1)..body,"@window_focus_script_capabilities_contract"))()
