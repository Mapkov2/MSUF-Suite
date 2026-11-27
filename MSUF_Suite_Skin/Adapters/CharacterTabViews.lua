local _, NS = ...
local Safety, Kit, Chrome = NS.Safety, NS.AdapterKit, NS.PaperDollChrome
local Field = Safety.Field
local CURRENCY, REPUTATION = "TokenFrame", "ReputationFrame"
local TABS = {
    { REPUTATION, "ReputationDetailFrame" },
    { CURRENCY, "DetailFrame" },
    { "SkillsFrame", "SkillDetailFrame" },
    { "PVPRankFrame", "DetailFrame" },
    { "StatisticsFrame" },
}

local PANE = Chrome.Spec("panel", 4, 0)
local DETAIL = Chrome.Spec("card", 4, 0)
local FILTER = { role = "button", useControlShape = true, pillHeight = 26, inset = 1, regions = { "Background" } }
local LIST_MODE = { allowImplicitProtected = true, maxDepth = 1, maxNodes = 16 }

local function SkinList(state, view)
    local list = Field(view, "ScrollBox")
    if not list then return end
    Chrome.Attach(state, list, PANE, true)
    if NS.IsCombatLocked() or Safety.Read(list, "IsVisible") ~= true then return end
    local seen = state.nativeLists or {}
    state.nativeLists = seen
    if not seen[list] then seen[list] = NS.GenericWindows.ApplyDescendant(list, state.owner, LIST_MODE) end
    local bar = Field(view, "ScrollBar")
    if bar and not seen[bar] then seen[bar] = NS.ScrollBarSkin.Apply(bar, state.owner) ~= nil end
end

function NS.SkinCharacterTabViews(state, root)
    if not state.active then return end
    for index = 1, #TABS do
        local name, detailKey = unpack(TABS[index])
        local view = Field(_G, name)
        if view and Kit.ParentIs(view, root) then
            local detail = detailKey and Field(view, detailKey)
            SkinList(state, view)
            local filter = Field(view, "filterDropdown")
            if Kit.ParentIs(filter, view) then Kit.SkinControl(state, filter, FILTER) end
            if name == CURRENCY then
                local currencyDetail = detail or Field(view, "Popup")
                Chrome.Action(state, Field(currencyDetail, "CurrencyTransferToggleButton"))
            end
            if detail then
                Chrome.Attach(state, detail, DETAIL, true)
                if name == REPUTATION then Chrome.Action(state, Field(detail, "ViewRenownButton")) end
            end
        end
    end
end
