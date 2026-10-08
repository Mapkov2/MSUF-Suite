dofile(arg[1] .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_skin_surface_ensure_contract.lua", [=[
BH3("CX9-03",function()
    local target=Target()
    local style={role="card",radius=4,inset=1}
    local state=Surface.Attach(target,style)
    local fill,edge=0,0
    state.fill.SetPoint=function() fill=fill+1 end
    state.edge.SetPoint=function() edge=edge+1 end
    style.inset=5;Surface.Attach(target,style)
    assert(fill>0 and edge>0,"CX9-03: changing inset repainted but did not reanchor existing textures")
    fill,edge=0,0;Surface.Attach(target,style)
    assert(fill==0 and edge==0,"CX9-03: unchanged inset performed redundant geometry writes")
end)
]=])
