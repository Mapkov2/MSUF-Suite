local _, NS = ...

-- The skin reads its text by key from its English table (enUS.lua): a key is
-- the English text itself or names it there. The English text is shown in
-- the reader's language through the Suite's localization (MSUF's locale
-- table, which MSUF_Suite/Locales fills for every supported language; MSUF's
-- own wording wins where it has one), so one set of packs covers the Suite
-- and the skin. tools/suite_locale_tool.py extracts the English table.
local localeTables = {}

function NS.RegisterLocale(locale, values)
    if type(locale) ~= "string" or type(values) ~= "table" then
        return
    end
    localeTables[locale] = values
end

function NS.InitializeLocalization()
    local english = localeTables.enUS
    -- MSUF_Suite is this addon's dependency (the TOC's Dependencies line).
    local Text = _G.MSUFSuite.Text

    -- The English source text of a key (the key when the table lacks it).
    local function SourceText(key)
        local text = english[key]
        if text == nil then return key end
        return text
    end
    NS.SourceText = SourceText

    -- Each key is looked up once; the reader's language does not change while
    -- the interface runs.
    NS.L = setmetatable({}, {
        __index = function(resolved, key)
            local text = SourceText(key)
            if type(text) == "string" then text = Text(text) end
            rawset(resolved, key, text)
            return text
        end,
    })
    localeTables = nil
end
