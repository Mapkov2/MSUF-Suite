local root=assert(arg[1])
arg[2] = nil -- the loaded layout fixture owns its optional host argument
local file=assert(io.open(root..'/tools/tests/suite_nameplates_preview_layout_contract.lua','rb'))
local source=file:read('*a');file:close()
local marker='local body, section = ui.body, ui.body.parent'
local at=assert(source:find(marker,1,true))
local probe=[=[
local changed,enabled=false,true
local previousGet,previousSet=P.Get,P.Set
P.Get=function(id,key)
    if key=='enemyLevelEnabled' then return enabled end
    return previousGet(id,key)
end
P.Set=function(id,key,value)
    assert(id=='nameplates' and key=='enemyLevelEnabled')
    changed,enabled=true,value
    return true
end
P.SetTranslatedText=function(font,text) font:SetText(text) end
local level
for _,button in ipairs(ui.layerButtons) do if button.layerKey=='level' then level=button end end
assert(level,'real level chip missing')
level.scripts.OnEnter(level)
local hint=ui.hint:GetText()
level.scripts.OnClick(level,'LeftButton')
assert(changed and enabled==false,'real level chip did not change live setting')
print('level tooltip:',hint,'live enemyLevelEnabled after click:',enabled)
assert(hint:find('change live setting',1,true),
    'level chip says preview-only although it changes the live level setting')
P.Get,P.Set=previousGet,previousSet
]=]
assert(loadstring(source:sub(1,at-1)..probe..source:sub(at),'@nameplate-level-help-probe'))()
