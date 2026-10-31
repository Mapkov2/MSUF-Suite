local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module
local callbacks = {}
local function Widget(kind)
    local widget = { kind = kind, scripts = {}, shown = false }
    function widget:SetSize() end
    function widget:SetPoint() end
    function widget:SetFrameStrata() end
    function widget:EnableMouse() end
    function widget:SetMovable() end
    function widget:SetClampedToScreen() end
    function widget:SetAllPoints() end
    function widget:SetHeight() end
    function widget:SetColorTexture() end
    function widget:RegisterForDrag() end
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:SetAutoFocus() end
    function widget:SetText(value)
        if self.kind == "FontString" then assert(self.font, "uninitialized font") end
        self.text = value
    end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:SetFocus() self.focus = true end
    function widget:ClearFocus() self.focus = false end
    function widget:HighlightText() self.selected = true end
    function widget:StartMoving() end
    function widget:StopMovingOrSizing() end
    return widget
end
local S = {
    Install = function(_, value) module = value end,
    CreateFrame = function(kind) return Widget(kind) end,
    CreateTexture = function() return Widget("Texture") end,
    CreateFontString = function() return Widget("FontString") end,
    SetFont = function(label) label.font = true end,
    Text = function(value) return value end,
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
}
UIParent = Widget("Frame")
Support.QoLStyleFixture(root, S)
GetRealmName = function() return "Tarren Mill" end
GetNormalizedRealmName = function() return "TarrenMill" end
GetCurrentRegionName = function() return "EU" end
Menu = { ModifyMenu = function(tag, callback)
    assert(not callbacks[tag], "menu hook registered twice")
    callbacks[tag] = callback
end }
local progressCalls, progressName = 0, nil
local private = { Suite = S, ApplicantRaidProgress = { Populate = function(menu, name)
    progressCalls, progressName = progressCalls + 1, name
    menu:CreateTitle("Raid progress sample")
end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ChatProfileLinks.lua"))(
    "MSUF_Suite_QualityOfLife", private)
module.active = true
module.config = { raiderIO = true, warcraftLogs = true }
module.context = { Event = function() error("Menu should exist at login") end }
module:Enable()
assert(callbacks.MENU_UNIT_CHAT_ROSTER and callbacks.MENU_UNIT_PLAYER
    and callbacks.MENU_UNIT_PARTY and callbacks.MENU_UNIT_GUILD,
    "native UnitPopup tags were not registered")
module:Refresh()
module:Enable()

local function Popup(contextData, tag, owner)
    local entries = {}
    local rootDescription = {
        CreateDivider = function() entries.divider = true end,
        CreateTitle = function(_, value) entries.title = value end,
        CreateButton = function(_, label, callback) entries[label] = callback end,
    }
    callbacks[tag or "MENU_UNIT_CHAT_ROSTER"](owner, rootDescription, contextData)
    return entries
end
-- TARGET is also the menu of a non-player target, FOCUS covers every focus
-- unit: a unit menu offers profiles only while UnitIsPlayer publicly says so.
local players = { target = true }
UnitIsPlayer = function(unit) return players[unit] end
assert(Popup({ name = "Pmi", server = "Tarren Mill", unit = "target" }, "MENU_UNIT_TARGET").divider,
    "a player target lost its profile links")
players.target, players.focus = false, "secret"
assert(not Popup({ name = "Hogger", unit = "target" }, "MENU_UNIT_TARGET").divider,
    "an NPC target offered character profile links")
assert(not Popup({ name = "Hogger", unit = "focus" }, "MENU_UNIT_FOCUS").divider,
    "a focus unit with a secret player answer offered character profile links")
assert(not Popup({ name = "Hogger", unit = "secret" }, "MENU_UNIT_FOCUS").divider,
    "a secret unit token offered character profile links")
UnitIsPlayer = function() error("a menu without a unit asked UnitIsPlayer") end
local entries = Popup({ name = "Pmi-TarrenMill" })
assert(entries.title == "Character profiles" and entries["Copy Raider.IO URL"]
    and entries["Copy Warcraft Logs URL"] and not module.dialog,
    "menu construction copied a URL before a user click")
entries["Copy Raider.IO URL"]()
assert(module.dialog and module.dialog.edit.text ==
    "https://raider.io/characters/eu/tarren-mill/Pmi" and module.dialog.edit.selected,
    "Raider.IO URL did not use normalized realm and selected text")
entries["Copy Warcraft Logs URL"]()
assert(module.dialog.edit.text ==
    "https://www.warcraftlogs.com/character/eu/tarren-mill/Pmi",
    "Warcraft Logs URL was malformed")
module.config.raiderIO = false
entries = Popup({ name = "Blûm", server = "Dun Modr" })
assert(not entries["Copy Raider.IO URL"] and entries["Copy Warcraft Logs URL"],
    "disabled service kept its menu action")
entries["Copy Warcraft Logs URL"]()
local encodedTail = "/dun-modr/Bl%C3%BBm"
assert(module.dialog.edit.text:sub(-#encodedTail) == encodedTail,
    "UTF-8 name was not URL encoded")
-- Apostrophes go as whole sequences: a byte class would also cut the second
-- byte of Cyrillic "р" (D1 80). Spaces of the player's own realm come from
-- its display name, since lowercase words cannot be guessed.
module.config.raiderIO = true
entries = Popup({ name = "Pmi", server = "Ревущий фьорд’s" })
entries["Copy Raider.IO URL"]()
local cyrillicTail = "/%D0%A0%D0%B5%D0%B2%D1%83%D1%89%D0%B8%D0%B9-%D1%84%D1%8C%D0%BE%D1%80%D0%B4s/Pmi"
assert(module.dialog.edit.text:sub(-#cyrillicTail) == cyrillicTail,
    "the realm slug cut UTF-8 characters or kept the typographic apostrophe: " .. module.dialog.edit.text)
GetRealmName = function() return "Der Rat von Dalaran" end
GetNormalizedRealmName = function() return "DerRatvonDalaran" end
entries = Popup({ name = "Pmi-DerRatvonDalaran" })
entries["Copy Raider.IO URL"]()
assert(module.dialog.edit.text == "https://raider.io/characters/eu/der-rat-von-dalaran/Pmi",
    "the player's own realm lost the words its display name keeps")
entries = Popup({ name = "secret", server = "Realm" })
assert(not entries.divider, "secret character name leaked to the context menu")
-- The applicant menu has no contextData. Its member button supplies the IDs;
-- capture that identity before Blizzard reuses the row for another applicant.
local applicantTag = "MENU_LFG_FRAME_MEMBER_APPLY"
assert(callbacks[applicantTag], "native applicant context menu has no profile links")
local applicant = { applicantID = 42 }
local member = { memberIdx = 2, GetParent = function() return applicant end }
local applicantName, lookups = "Darkbloody-Ravencrest", 0
C_LFGList = { GetApplicantMemberInfo = function(applicantID, memberIdx)
    assert(applicantID == 42 and memberIdx == 2, "looked up a different applicant member")
    lookups = lookups + 1
    return applicantName
end }
entries = Popup(nil, applicantTag, member)
assert(entries["Copy Raider.IO URL"] and entries["Copy Warcraft Logs URL"] and lookups == 1,
    "applicant menu did not offer both profiles from its native owner")
assert(progressCalls == 1 and progressName == "Darkbloody-Ravencrest",
    "applicant progress did not use the selected member full name")
applicant.applicantID, member.memberIdx = 99, 1
entries["Copy Raider.IO URL"]()
assert(module.dialog.edit.text == "https://raider.io/characters/eu/ravencrest/Darkbloody" and lookups == 1,
    "row reuse changed the applicant selected for Raider.IO")
entries["Copy Warcraft Logs URL"]()
assert(module.dialog.edit.text == "https://www.warcraftlogs.com/character/eu/ravencrest/Darkbloody",
    "applicant Warcraft Logs link lost its cross-realm identity")
applicant.applicantID, member.memberIdx = 42, 2
for _, invalid in ipairs({ "secret", false, 0, -1, 1.5, math.huge, 0/0 }) do
    applicant.applicantID = invalid
    assert(not Popup(nil, applicantTag, member).divider, "invalid applicant ID offered profiles")
    applicant.applicantID, member.memberIdx = 42, invalid
    assert(not Popup(nil, applicantTag, member).divider, "invalid member index offered profiles")
    member.memberIdx = 2
end
applicant.applicantID = nil
assert(not Popup(nil, applicantTag, member).divider, "removed applicant offered profiles")
applicant.applicantID = 42
member.memberIdx = nil
assert(not Popup(nil, applicantTag, member).divider, "removed member offered profiles")
member.memberIdx = 2
assert(lookups == 1, "invalid IDs reached the applicant API")
applicantName = "secret"
assert(not Popup(nil, applicantTag, member).divider, "secret applicant name offered profiles")
applicantName = nil
assert(not Popup(nil, applicantTag, member).divider, "missing applicant name offered profiles")
applicantName = "Darkbloody-Ravencrest"
module.config.raiderIO = false
entries = Popup(nil, applicantTag, member)
assert(not entries["Copy Raider.IO URL"] and entries["Copy Warcraft Logs URL"],
    "applicant menu ignored the per-service setting")
module.config.warcraftLogs = false
module.config.raidProgress = true
local beforeProgressOnly = progressCalls
entries = Popup(nil, applicantTag, member)
assert(entries.title == "Raid progress sample" and progressCalls == beforeProgressOnly + 1
    and not entries["Copy Raider.IO URL"] and not entries["Copy Warcraft Logs URL"],
    "progress-only mode depended on a profile URL switch")
module.config.raidProgress = false
local beforeInactive, beforeProgressDisabled = lookups, progressCalls
assert(not Popup(nil, applicantTag, member).divider and lookups == beforeInactive,
    "disabled services still read applicant data")
assert(progressCalls == beforeProgressDisabled, "disabled progress still queried the provider")
module.config.raiderIO = true
entries = Popup(nil, applicantTag, member)
assert(entries["Copy Raider.IO URL"] and progressCalls == beforeProgressDisabled,
    "turning progress off changed profile links or still queried raid data")
module.config.raiderIO, module.config.warcraftLogs, module.config.raidProgress = true, true, true
beforeInactive = lookups
module.active = false
assert(not Popup(nil, applicantTag, member).divider and lookups == beforeInactive,
    "disabled module still read applicant data")
entries = Popup({ name = "Pmi", server = "Tarren Mill" })
assert(not entries.divider, "disabled module kept adding menu entries")
module:Disable()
assert(not module.dialog.shown and module.dialog.edit.text == "",
    "disable retained a copied profile URL")
print("Suite native chat profile menu links passed")
