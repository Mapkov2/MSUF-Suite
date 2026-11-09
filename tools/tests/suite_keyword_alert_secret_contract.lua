local root = assert(arg[1], "repository root required")
local Fixtures = dofile(root .. "/tools/tests/comfort_fixture.lua")
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()

local path = root .. "/MSUF_Suite_QualityOfLife/KeywordAlerts.lua"
local secretText, secretNumber = Secrets.New("string"), Secrets.New("number")
wipe = function(value) for key in pairs(value) do value[key] = nil end return value end

for _, forever in ipairs({ false, true }) do
    local fixture = Fixtures.New(root, forever)
    local suite = fixture.S
    local clock, notices, window = 100, 0
    GetTime = function() return clock end
    GetServerTime = function() return secretNumber end
    suite.PublicText = function(value)
        return not issecretvalue(value) and type(value) == "string" and value ~= "" and value or nil
    end
    suite.Finite = function(value)
        return not issecretvalue(value) and type(value) == "number"
            and value == value and value > -math.huge and value < math.huge
    end
    suite.Print = function() notices = notices + 1 end
    suite.Notifications = { Push = function() end }
    suite.ToolListWindow = { Open = function(_, spec) window = spec end }
    fixture:Load("MSUF_Suite_QualityOfLife/KeywordAlerts.lua")
    local alerts = fixture:Start("keywordAlerts", { words = "ping", phraseOptions = "ping\tchannel:Trade\t", cooldown = 30 })
    local function Emit(text, author, channel)
        fixture:Emit(alerts, "CHAT_MSG_CHANNEL", text, author, nil, nil, nil, nil, nil, nil, channel)
    end

    local stopWatch = Secrets.Watch(path, { strict = true })
    Emit(secretText, "Author", "Trade")
    Emit("ping", secretText, "Trade")
    Emit("ping", "Author", secretText)
    clock = secretNumber
    Emit("ping", "Author", "Trade")
    assert(notices == 0, "restricted text, sender, channel or clock must not trigger a named alert")
    clock = 100
    Emit("|cffffffffping|r", "Author", "Trade")
    alerts:Open()
    window.selectTab(alerts, "matches")
    local rows = window.rows()
    assert(notices == 1 and #rows == 1 and rows[1].text == "Author: ping", "readable match survives an unavailable server clock")
    local violations = stopWatch()
    assert(#violations == 0, table.concat(violations, "\n"))
end
print("PASS keyword alerts: strict secret watcher on both client fixtures")
