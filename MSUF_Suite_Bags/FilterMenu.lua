local _, P = ...
local NS, S, UI = P.NS, P.Suite, P.BagWidgets
local Menu = { rows = {}, entries = {}, watched = setmetatable({}, { __mode = "k" }) }
P.BagFilterMenu = Menu
local Element = {}
Element.__index = Element

local function Add(parent, kind, label, callback)
    local node = setmetatable({ kind = kind, label = label, callback = callback, enabled = true, children = {} }, Element)
    parent.children[#parent.children + 1] = node
    return node
end
function Element:CreateTitle(label) return Add(self, "title", label) end
function Element:CreateDivider() return Add(self, "divider", "") end
function Element:CreateButton(label, callback) return Add(self, "button", label, callback) end
function Element:SetEnabled(enabled) self.enabled = enabled end

function Menu.Close()
    if Menu.frame then Menu.frame:Hide() end
end

local function Pick(row)
    local node = row.entry.node
    if NS.InCombat() or not node.enabled or not node.callback then return end
    local callback = node.callback
    Menu.Close()
    S.Dispatch(callback)
end

local function Flatten(node, depth)
    for i = 1, #node.children do
        local child = node.children[i]
        Menu.entries[#Menu.entries + 1] = { node = child, depth = depth }
        Flatten(child, depth + 1)
    end
end

local function Row(index)
    local row = Menu.rows[index]
    if row then return row end
    row = P.GridView.Button(Menu.child, "", 240, Pick, 24)
    row.label = P.GridView.Font(row, 12)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.line = S.CreateTexture(row, nil, "ARTWORK")
    row.line:SetPoint("LEFT", 8, 0)
    row.line:SetPoint("RIGHT", -8, 0)
    row.line:SetHeight(1)
    row.line:SetColorTexture(.4, .4, .4, .3)
    row.bagNavigation = true
    Menu.rows[index] = row
    return row
end

local function Event(frame, event)
    local ownerUnderMouse = Menu.owner and Menu.owner:IsMouseOver()
    if event == "PLAYER_REGEN_DISABLED" or not frame:IsMouseOver() and not ownerUnderMouse then Menu.Close() end
end

local function Hidden()
    Menu.frame:UnregisterAllEvents()
    Menu.owner, Menu.root = nil, nil
    for i = 1, #Menu.rows do Menu.rows[i].entry = nil end
    for i = #Menu.entries, 1, -1 do Menu.entries[i] = nil end
    NS.Registry.RemoveListener(Menu)
end
local function Changed(_, domain) if domain == "profile" then Menu.Close() end end
local function OwnerHidden(owner) if Menu.owner == owner then Menu.Close() end end

local function Create()
    Menu.frame = UI.Popup("MSUFSuiteBagsFilterMenu")
    Menu.frame:Hide()
    Menu.frame:SetSize(268, 300)
    Menu.scroll, Menu.child = UI.Scroll(Menu.frame, 238)
    Menu.scroll:SetPoint("TOPLEFT", 8, -8)
    Menu.scroll:SetPoint("BOTTOMRIGHT", -22, 8)
    Menu.frame:SetScript("OnEvent", Event)
    Menu.frame:SetScript("OnHide", Hidden)
end

function Menu.Show(owner, generator)
    if NS.InCombat() then return end
    if S.GamepadUI() and not NS.Client.HasControllerNavigation() then return S.ContextMenu(owner, generator) end
    if Menu.frame and Menu.frame:IsShown() and Menu.owner == owner then
        Menu.Close()
        return
    end
    UI.Prepare()
    if not Menu.frame then Create() else Menu.Close() end
    Menu.owner, Menu.root = owner, setmetatable({ children = {} }, Element)
    for i = #Menu.entries, 1, -1 do Menu.entries[i] = nil end
    generator(owner, Menu.root)
    Flatten(Menu.root, 0)
    for i, entry in ipairs(Menu.entries) do
        local row, node = Row(i), entry.node
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", Menu.child, "TOPLEFT", 0, -(i - 1) * 25)
        row:SetWidth(238)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 8 + entry.depth * 12, 0)
        row.label:SetPoint("RIGHT", -6, 0)
        row.label:SetText(node.label)
        row.label:SetShown(node.kind ~= "divider")
        row.line:SetShown(node.kind == "divider")
        row:SetEnabled(node.enabled and node.callback ~= nil)
        local shade = node.enabled and 1 or .5
        row.label:SetTextColor(shade, shade, shade)
        row:Show()
    end
    for i = #Menu.entries + 1, #Menu.rows do Menu.rows[i]:Hide() end
    Menu.child:SetHeight(math.max(1, #Menu.entries * 25))
    Menu.frame:SetHeight(math.min(UIParent:GetHeight() - 40, #Menu.entries * 25 + 16))
    Menu.frame:ClearAllPoints()
    Menu.frame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -3)
    Menu.scroll:SetVerticalScroll(0)
    UI.UpdateScroll(Menu.scroll)
    if not Menu.watched[owner] then owner:HookScript("OnHide", OwnerHidden) Menu.watched[owner] = true end
    NS.Registry.AddListener(Menu, Changed)
    Menu.frame:Show()
    if S.GamepadUI() and NS.Client.HasControllerNavigation() then
        NS.Client.AttachControllerWindow(Menu.frame)
        NS.Client.ResumeControllerWindow(Menu.frame)
    end
    Menu.frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    Menu.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end
