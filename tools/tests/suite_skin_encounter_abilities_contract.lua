-- Exact lore, SimpleHTML paragraphs, role bullets and pooled ability headers.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_encounter_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find('local journal, encounter, info, instance =', 1, true))
local body = [======[
EncounterJournal_SetBullets = Noop
EncounterJournal_UpdateButtonState = Noop
EncounterJournal_DisplayEncounter = Noop
function methods:GetParent() return self.parent end
function methods:SetTextColor(r, g, b)
    assert(not (locked and self.protected), "protected combat text write")
    self.r, self.g, self.b = r, g, b
    textWrites = textWrites + 1
end
function methods:SetAlpha(value)
    assert(not (locked and self.protected), "protected combat alpha write")
    self.alpha = value
end
local linkText = "Dodge |cff0088ff|Hspell:123|h[Ability]|h|r and attack."
local function HTML(parent)
    local html = Frame()
    html.parent, html.kind, html.r, html.g, html.b = parent, "SimpleHTML", .25, .1484375, .02
    html.text, html.hyperlinkCallback = linkText, Noop
    function html:GetTextColor(kind) assert(kind == "p", "missing HTML paragraph selector"); return self.r, self.g, self.b, 1 end
    function html:SetTextColor(kind, r, g, b)
        assert(kind == "p", "numeric FontString signature used on SimpleHTML")
        methods.SetTextColor(self, r, g, b)
    end
    return html
end
local function Description(parent)
    local desc = Frame()
    desc.parent, desc.Text = parent, HTML(nil)
    desc.Text.parent = desc
    return desc
end
local function Header(parent)
    local h = Frame()
    h.parent, h.button, h.description = parent, Frame(), Text(.25, .1484375, .02)
    h.button.parent, h.button.title, h.button.expandedIcon = h, Text(.2, .1, .01), Text(.2, .1, .01)
    h.button.abilityIcon, h.button.icon1 = Texture(), Texture()
    h.overviewDescription, h.descriptionBG, h.descriptionBGBottom = Description(h), Texture(), Texture()
    h.Bullets = { Description(h), Description(h) }
    return h
end
local journal, encounter, info = Frame("EncounterJournal"), Frame(), Frame()
journal.encounter, encounter.info = encounter, info
encounter.parent, info.parent = journal, encounter
local overview, details = Frame(), Frame()
overview.parent, details.parent = info, info
info.overviewScroll, info.detailsScroll = { child = overview }, { child = details }
overview.loreDescription = Text(.25, .1484375, .02)
overview.overviewDescription, overview.Bullets = Description(overview), { Description(overview) }
details.description = Text(.25, .1484375, .02)
local role, ability = Header(overview), Header(details)
overview.overviews, encounter.usedHeaders = { role }, { ability }
Check(NS.EncounterJournalSkin.Apply(journal, "abilities"), "journal did not apply")
local function Readable()
    Check(overview.loreDescription.r == color[1], "boss lore remains dark on the dark shell")
    Check(overview.overviewDescription.Text.r == color[1], "overview paragraph remains dark")
    Check(overview.Bullets[1].Text.r == color[1], "overview bullet remains dark")
    for _, h in ipairs({ role, ability }) do
        Check(h.description.r == color[1] and h.overviewDescription.Text.r == color[1], "ability body remains dark")
        Check(h.Bullets[1].Text.r == color[1] and h.Bullets[2].Text.r == color[1], "role bullets remain dark")
        Check(h.descriptionBG.alpha == 0 and h.descriptionBGBottom.alpha == 0, "white ability text remains on bright parchment")
        Check(h.button.abilityIcon.alpha == nil and h.button.icon1.alpha == nil, "semantic ability/role icons changed")
        Check(h.overviewDescription.Text.text == linkText and h.overviewDescription.Text.hyperlinkCallback == Noop,
            "ability hyperlinks/content changed")
    end
end
Readable()
local function Hook(name, ...)
    Check(type(hooks[name]) == "function", "native lifecycle hook missing: " .. name)
    hooks[name](...)
end
role.Bullets[2] = Description(role)
Hook("EncounterJournal_SetBullets", role.overviewDescription)
Check(role.Bullets[2].Text.r == color[1], "late role bullet did not inherit readable color")
ability.description.r = .25
Hook("EncounterJournal_UpdateButtonState", ability.button)
Check(ability.description.r == color[1], "reused expanded ability description remains dark")
overview.loreDescription.r, overview.overviewDescription.Text.r = .25, .25
Hook("EncounterJournal_DisplayEncounter")
Readable()
color = { .92, .9, .86, 1 }
NS.EncounterJournalSkin:OnThemeChanged()
Readable()
local beforeScans, beforeAttaches, beforeControls = scans, attaches, controls
locked = true
role.Bullets[1] = Description(role)
Hook("EncounterJournal_SetBullets", role.overviewDescription)
Check(role.Bullets[1].Text.r == color[1], "unprotected combat bullet stayed dark")
local protected = role.Bullets[2].Text
protected.protected, protected.r = true, .25
Hook("EncounterJournal_SetBullets", role.overviewDescription)
Check(protected.r == .25, "protected paragraph was written in combat")
locked = false; protected.protected = false
Hook("EncounterJournal_SetBullets", role.overviewDescription)
Check(protected.r == color[1], "paragraph did not recover after combat")
Check(scans == beforeScans and attaches == beforeAttaches and controls == beforeControls,
    "ability lifecycle performed tree scans or structural skin work")
journal.shown = false
local writes = textWrites
overview.loreDescription.r = .25
Hook("EncounterJournal_DisplayEncounter")
Check(textWrites == writes, "hidden journal repainted ability text")
journal.shown = true; journal.hooks.OnShow(journal)
Check(overview.loreDescription.r == color[1], "hidden ability update was lost on reopen")
local external = Header(Frame("Unrelated"))
Hook("EncounterJournal_SetBullets", external.overviewDescription)
Check(external.overviewDescription.Text.r == .25, "foreign HTML target was recolored")
local function Reuse()
    for _ = 1, 1000 do hooks.EncounterJournal_SetBullets(role.overviewDescription) end
end
local function Allocated()
    collectgarbage("collect"); collectgarbage("stop")
    local start = collectgarbage("count")
    Reuse()
    local growth = collectgarbage("count") - start
    collectgarbage("restart")
    return growth
end
Check(math.min(Allocated(), Allocated()) < 2, "reused ability paragraphs allocate per update")
NS.EncounterJournalSkin.Disable(journal, "abilities")
Check(role.overviewDescription.Text.r == .25 and ability.description.r == .25, "disabling did not restore native colors")
Check(role.descriptionBG.alpha == 1 and ability.descriptionBG.alpha == 1, "disabling did not restore native parchment")
writes = textWrites
Reuse()
Check(textWrites == writes, "disabled journal hooks still repaint text")
print("suite_skin_encounter_abilities_contract: " .. checks .. " checks passed")
]======]
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    assert(loadstring(source:sub(1, stop - 1) .. body, "@encounter_abilities_" .. flavor))()
end
