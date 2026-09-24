local _, NS = ...

-- Independent, bounded equipment snapshots. No addon dependency or UI hooks.
-- APIs: wow-ui-source upstream/live 8ea15b61, ItemDocumentation.lua and
-- TooltipInfoSharedDocumentation.lua (typed enchant/socket/upgrade lines).
-- Factual current enchant IDs/ranks and inventory masks verified against
-- SimulationCraft's extracted client data, build 12.1.0.69587, commit
-- cebc6c6d7408b694afda47de38d2737ec5783e96, permanent_enchant.inc.
-- No external addon implementation, localized names or assets are included.
local Info = {}
NS.EquipmentInfo = Info
local rank = {}
for _, id in ipairs({7934,7936,7938,7956,7958,7960,7962,7964,7966,7968,7970,7972,
    7974,7976,7978,7980,7982,7984,7986,7988,7990,7992,7994,7996,7998,8000,8002,
    8004,8006,8008,8010,8012,8014,8016,8018,8020,8022,8024,8026,8028,8030,8032,
    8034,8036,8038,8040,8158,8160,8162,8612,8614,8688}) do
    rank[id], rank[id+1] = 1, 2 -- Each pair individually verified in that snapshot.
end
local armorEnchants = {INVTYPE_HEAD=true,INVTYPE_SHOULDER=true,INVTYPE_CHEST=true,
    INVTYPE_ROBE=true,INVTYPE_LEGS=true,INVTYPE_FEET=true,INVTYPE_FINGER=true}
local weapons = {INVTYPE_WEAPON=true,INVTYPE_WEAPONMAINHAND=true,INVTYPE_WEAPONOFFHAND=true,
    INVTYPE_2HWEAPON=true,INVTYPE_RANGED=true,INVTYPE_RANGEDRIGHT=true}
-- Subclasses covered by the current weapon enchant mask 0x000ebfff.
local weaponClasses = {[0]=true,true,true,true,true,true,true,true,true,true,true,true,true,true,
    [15]=true,[17]=true,[18]=true,[19]=true}
local statKeys = {"ITEM_MOD_CRIT_RATING_SHORT","ITEM_MOD_HASTE_RATING_SHORT","ITEM_MOD_MASTERY_RATING_SHORT",
    "ITEM_MOD_VERSATILITY","ITEM_MOD_CR_LIFESTEAL_SHORT","ITEM_MOD_CR_AVOIDANCE_SHORT","ITEM_MOD_CR_SPEED_SHORT",
    "ITEM_MOD_STRENGTH_SHORT","ITEM_MOD_AGILITY_SHORT","ITEM_MOD_INTELLECT_SHORT","ITEM_MOD_STAMINA_SHORT"}
Info.statKeys = statKeys
local function Public(value)
    if type(issecretvalue)=="function" and issecretvalue(value) then return nil end
    return value
end
local function Read(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c=pcall(fn,...)
    if ok then return Public(a),Public(b),Public(c) end
end
local function Number(value)
    value=Public(value)
    return type(value)=="number" and value==value and value>=0 and value<1e9 and value or nil
end
local function Text(value)
    value=Public(value);return type(value)=="string" and value or nil
end
local function Field(object,key)
    object=Public(object)
    return type(object)=="table" and Public(object[key]) or nil
end
local function ItemIdentity(link,result)
    if not C_Item or type(C_Item.GetItemInfo)~="function" then return end
    local ok,name,_,quality,_,_,_,_,_,equip,texture,_,class,subclass,_,expansion=pcall(C_Item.GetItemInfo,link)
    if ok then
        result.name,result.quality,result.equip,result.texture=Text(name),Number(quality),Text(equip),Number(texture)
        result.class,result.subclass,result.expansion=Number(class),Number(subclass),Number(expansion)
    end
end
local function Reset(result)
    local gems,stats=result.gemInfo or {},result.stats or {}
    for key in pairs(result) do result[key]=nil end
    result.gemInfo,result.stats=gems,stats
    for _,gem in ipairs(gems) do for key in pairs(gem) do gem[key]=nil end end
    for key in pairs(stats) do stats[key]=nil end
end
function Info.Invalidate(result) if result then result.settled=false end end
function Info.Read(link,unit,slot,result,identity)
    result=result or {}
    link=Text(link)
    if NS.IsCombatLocked() then return result end
    if result.link==link and result.identity==identity and result.settled then return result end
    Reset(result);result.link=link;result.identity=identity
    if not link then result.settled=true;return result end
    result.itemID=tonumber(link:match("item:(%d+):"))
    local enchantID=link:match("item:%d+:(%d*):")
    result.enchantID=enchantID and (tonumber(enchantID) or 0) or nil
    result.enchanted=result.enchantID and result.enchantID>0 or false
    result.enchantRank=result.enchantID and rank[result.enchantID]
    ItemIdentity(link,result)
    result.itemLevel=Number(Read(C_Item and C_Item.GetDetailedItemLevelInfo,link))
    result.sockets=Number(Read(C_Item and C_Item.GetItemNumSockets,link))
    result.gems=0
    if C_Item and type(C_Item.GetItemGemID)=="function" then
        for index=1,4 do
            local gem=result.gemInfo[index]
            if not gem then gem={};result.gemInfo[index]=gem end
            local ok,id=pcall(C_Item.GetItemGemID,link,index)
            if not ok or (type(issecretvalue)=="function" and issecretvalue(id)) then result.gemsRestricted=true end
            gem.id=ok and Number(id) or nil
            if gem.id==0 then gem.id=nil end
            if gem.id and gem.id>0 then
                result.gems=result.gems+1
                local name,gemLink=Read(C_Item.GetItemGem,link,index)
                gem.name,gem.link=Text(name),Text(gemLink)
                gem.texture=Number(Read(C_Item.GetItemIconByID,gem.id))
                gem.pending=(type(C_Item.GetItemGem)=="function" and not gem.link)
                    or (type(C_Item.GetItemIconByID)=="function" and not gem.texture)
                result.gemsPending=result.gemsPending or gem.pending
            end
        end
        if result.gemsRestricted then result.gems=nil end
    else result.gems=nil end
    local upgrade=Read(C_Item and C_Item.GetItemUpgradeInfo,link)
    result.upgradeCurrent=Number(Field(upgrade,"currentLevel"))
    result.upgradeMax=Number(Field(upgrade,"maxLevel"))
    result.upgradeTrack=Text(Field(upgrade,"trackString"))
    if result.upgradeCurrent and result.upgradeMax and result.upgradeMax>0 and result.upgradeCurrent<=result.upgradeMax then
        result.upgradeText=string.format("%d/%d",result.upgradeCurrent,result.upgradeMax)
    end
    local stats=Read(C_Item and C_Item.GetItemStats,link)
    if type(stats)=="table" then
        for _,key in ipairs(statKeys) do result.stats[key]=Number(Field(stats,key)) end
    end
    local tooltip=Read(C_TooltipInfo and C_TooltipInfo.GetInventoryItem,unit,slot)
    local lines=Field(tooltip,"lines")
    local types=Enum and Enum.TooltipDataLineType
    local socketLines,filledLines=0,0
    if type(lines)=="table" and types then
        for index=1,math.min(#lines,80) do
            local line=Field(lines,index)
            local kind=Field(line,"type")
            if kind and kind==types.ItemEnchantmentPermanent then
                local text=Text(Field(line,"leftText"))
                result.enchantText=text and text:gsub("|A:.-|a",""):gsub("|T.-|t",""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
            elseif kind and kind==types.GemSocket then
                socketLines=socketLines+1
                if Field(line,"gemIcon") then filledLines=filledLines+1 end
            elseif kind and kind==types.ItemUpgradeLevel then
                result.upgradeDescription=Text(Field(line,"leftText"))
            end
        end
        if socketLines>0 and not result.sockets then result.sockets=socketLines end
        if socketLines>0 and not result.gems and not result.gemsRestricted then result.gems=filledLines end
    end
    if result.sockets and result.gems and result.sockets>=result.gems then
        result.emptySockets=result.sockets-result.gems
    end
    result.gemSlotsKnown=not result.gemsRestricted and ((C_Item and type(C_Item.GetItemGemID)=="function") or result.gems==0)
    -- No socketability guess: actual empty sockets are not the same thing as
    -- optional sockets that a season-specific consumable might add later.
    result.pending=not result.name or not result.itemLevel or result.gemsPending or result.gemsRestricted
        or (C_TooltipInfo and type(C_TooltipInfo.GetInventoryItem)=="function" and type(lines)~="table")
    result.settled=not result.pending
    return result
end
function Info.Check(result,level)
    result.missingEnchant,result.lowEnchant,result.enchantApplicable=nil,false,nil
    result.warning=false
    if not result.link then result.unknown=false;return result end
    -- Gear from unsupported expansions/unknown item metadata stays unverified.
    -- Modern cloak, wrist, neck, trinkets and shields must not get false alerts.
    if result.expansion==11 and result.equip and result.class and result.subclass and level and level>=90 then
        result.enchantApplicable=(result.class==4 and armorEnchants[result.equip]==true and result.subclass<=4
                and (result.equip~="INVTYPE_LEGS" or result.subclass>=1))
            or (result.class==2 and weapons[result.equip]==true and weaponClasses[result.subclass]==true)
        result.missingEnchant=result.enchantApplicable and result.enchantID==0 or false
    end
    result.lowEnchant=result.enchantRank==1
    result.unknown=result.pending or result.enchantID==nil or result.emptySockets==nil or result.enchantApplicable==nil
        or (result.enchanted and not result.enchantRank)
    result.warning=result.missingEnchant or result.lowEnchant or (result.emptySockets and result.emptySockets>0)
    result.enchantLabel=result.missingEnchant and NS.L.GEAR_ENCHANT_MISSING or result.enchantText
        or (result.enchanted and NS.L.DOSSIER_ENCHANTED or result.enchantApplicable==nil and NS.L.GEAR_UNVERIFIED or "")
    result.enchantToken=result.missingEnchant and "danger" or result.lowEnchant and "warning" or result.enchanted and "success" or "muted"
    return result
end

function Info.AddTooltip(result)
    if not result or not GameTooltip or type(GameTooltip.AddLine)~="function" then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(NS.L.GEAR_TOOLTIP_TITLE,NS.Theme.GetColor("accent"))
    local quality=result.quality and _G["ITEM_QUALITY"..result.quality.."_DESC"]
    if type(quality)=="string" then GameTooltip:AddLine(quality,.8,.8,.8) end
    if result.enchantLabel and result.enchantLabel~="" then
        local r,g,b=NS.Theme.GetColor(result.enchantToken or "muted")
        GameTooltip:AddLine(result.enchantLabel,r,g,b,true)
    end
    if result.enchantRank then GameTooltip:AddLine(string.format(NS.L.GEAR_ENCHANT_RANK,result.enchantRank,2),1,.82,0) end
    if result.sockets and result.gems then GameTooltip:AddLine(string.format(NS.L.GEAR_SOCKET_DETAIL,result.gems,result.sockets,result.emptySockets or 0),.8,.8,.8,true) end
    if result.upgradeText then
        GameTooltip:AddLine((result.upgradeTrack or NS.L.GEAR_UPGRADE).." "..result.upgradeText,.8,.8,.8,true)
    end
    if result.unknown then GameTooltip:AddLine(NS.L.GEAR_CHECK_SCOPE,.7,.7,.7,true) end
    -- These are the current item's raw bonuses, not derived character totals.
    for _,key in ipairs(statKeys) do
        local value=result.stats and result.stats[key]
        if value and value>0 and _G[key] then GameTooltip:AddLine(string.format("%s: %d",_G[key],value),.7,.8,.9) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(NS.L.GEAR_STATUS_LEGEND,.7,.75,.8,true)
end

return Info
