-- The feature-header help works with current and older MSUF hosts.
local root = assert(arg[1])
local file = assert(io.open(root .. "/MSUF_Suite_Options/Pages/QualityOfLife.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local body = assert(source:match("local function AddFeatureHelp%b().-\nend"), "feature help missing")
local function Widget(kind)
    local self = { kind = kind, scripts = {} }
    function self:SetPoint(...) self.point = { ... } end
    function self:SetSize(w, h) self.width, self.height = w, h end
    function self:EnableMouse(value) self.mouse = value end
    function self:SetAllPoints(parent) self.allPoints = parent end
    function self:SetJustifyH(value) self.justifyH = value end
    function self:SetJustifyV(value) self.justifyV = value end
    function self:SetScript(key, fn) self.scripts[key] = fn end
    function self:GetScript(key) return self.scripts[key] end
    return self
end
for _, current in ipairs({ false, true }) do
    local made, glyph, tooltip, delegated
    local P = { W = {}, T = { colors = { text = {}, muted = {} } }, M = {} }
    function P.T.Font(_, _, text, color, role)
        glyph = Widget("FontString")
        glyph.text, glyph.color, glyph.role = text, color, role
        return glyph
    end
    function P.T.ApplySurface(widget, material) widget.material = material end
    function P.M.AddTooltip(widget, title, details, opts)
        tooltip = { widget = widget, title = title, details = details, opts = opts }
        widget:SetScript("OnEnter", function() tooltip.shown = true end)
    end
    if current then
        function P.W.HelpButton(parent, title, details)
            delegated = true
            made = Widget("Button")
            made.parent = parent
            P.M.AddTooltip(made, title, details, { hook = true })
            return made
        end
    end
    local env = { P = P, Tr = function(text) return text end, HELP = { first = "First instructions", second = "Second instructions" },
        ipairs = ipairs, table = table, CreateFrame = function(kind, _, parent)
            made = Widget(kind)
            made.parent = parent
            return made
        end }
    local chunk = assert(loadstring(body .. "\nreturn AddFeatureHelp"))
    setfenv(chunk, env)
    local details = Widget("Panel")
    chunk()(details, { title = "Feature" }, { { key = "first" }, { key = "second" } })
    assert(made.kind == "Button", "feature help is not clickable")
    assert(made.point[1] == "TOPRIGHT" and made.point[4] == -54 and made.point[5] == -10,
        "feature help overlaps the title or reset control")
    assert(tooltip.title == "Feature" and tooltip.details == "First instructions\n\nSecond instructions",
        "feature help lost a section's instructions")
    if current then
        assert(delegated, "feature help does not use the shared host button")
    else
        assert(made.width == 24 and made.height == 24 and made.material == "card",
            "older host has no framed 24-pixel help target")
        assert(glyph.role == "body" and glyph.color == P.T.colors.text and glyph.justifyH == "CENTER"
            and glyph.justifyV == "MIDDLE", "older host still has a tiny, low-contrast question mark")
        made:GetScript("OnClick")(made)
        assert(tooltip.shown, "older host cannot open help with a click")
    end
end
print("feature help: shared host and readable older-host fallback passed")
