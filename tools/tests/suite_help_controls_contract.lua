-- Help belongs to the native feature header, with a body fallback on old hosts.
local root = assert(arg[1])
local file = assert(io.open(root .. "/MSUF_Suite_Options/Pages/QualityOfLife.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local body = assert(source:match("local function AddFeatureHelp%b().-\nend"), "feature help missing")
for _, native in ipairs({ false, true }) do
    local header, details, tooltip = {}, {}, nil
    local help = { first = "First instructions", second = "Second instructions" }
    local P = { M = {}, QoLHelpText = function(section) return help[section] end }
    function P.M.AddTooltip(widget, title, text, opts)
        tooltip = { widget = widget, title = title, text = text, opts = opts }
    end
    local HM = { GetSectionEntry = function(target)
        assert(target == details, "help resolved the wrong section")
        if native then return { header = header } end
    end }
    local env = { P = P, HM = HM, Tr = function(text) return text end, ipairs = ipairs, table = table }
    local chunk = assert(loadstring(body .. "\nreturn AddFeatureHelp"))
    setfenv(chunk, env)
    chunk()(details, { title = "Feature" }, { { key = "first" }, { key = "second" } })
    assert(tooltip and tooltip.widget == (native and header or details), "help is not attached to its section")
    assert(tooltip.title == "Feature" and tooltip.text == "First instructions\n\nSecond instructions",
        "feature help lost a section's instructions")
    assert(tooltip.opts.hook == true, "help must preserve native header interaction")
end
print("feature help: native accordion header and older-host body fallback passed")
