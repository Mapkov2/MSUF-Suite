-- WoW's chat-focus diagnostics must work without Lua's desktop debug library.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, why) checks = checks + 1 assert(value, why) end
local secret = newproxy()
local function IsSecret(value) return rawequal(value, secret) end
local Suite = { DevBarAnimation = {}, IsSecret = IsSecret, Client = { isForever = true }, RootDB = {} }
Suite.Dispatch = function(callback, ...) return callback(...) end
SlashCmdList = {}
local captures, owner, queued, reads = nil, nil, {}, 0
EventRegistry = { RegisterCallback = function(_, event, callback, target)
    Check(event == "ChatFrame.OnEditBoxFocusGained", "probe registered an unrelated event")
    captures, owner = callback, target
end }
C_CVar = { GetCVar = function(key) return key == "addonChatRestrictionsForced" and "1" or "0" end }
C_Timer = { After = function(delay, callback) queued[#queued + 1] = { delay, callback } end }
C_AddOns = { IsAddOnLoaded = function() return false end }
issecurevariable = function() return true end
issecrettable = function() return false end
canaccesstable = function() return true end
date = os.date
hash_ChatTypeInfoList, hash_SlashCmdList = {}, {}
local nativeDebug = debug
debug = nil -- Match the actual WoW client, including cold load.
local source = os.getenv("SUITE_DEV_MODE_SOURCE") or root .. "/MSUF_Suite/Core/DevMode.lua"
assert(loadfile(source))("MSUF_Suite", Suite)
Check(type(captures) == "function", "Forever chat diagnostics were not registered")
local sample = function() end
local script = sample
local box = { header = {}, chatFrame = {}, ProcessChatType = sample }
function box:IsForbidden() return false end
function box:GetScript() return script end
function box:GetName() return "ChatFrame1EditBox" end
function box:GetText() return secret end
function box:HasSecretValues() return true end
function box:HasAnySecretAspect() return true end
function box:GetAttribute() return secret end
local function Focus()
    queued = {}
    captures(owner, box)
    Check(#queued == 3 and queued[1][1] == 0 and queued[2][1] == 1 and queued[3][1] == 4,
        "chat diagnostics changed their scheduled phases")
    for _, job in ipairs(queued) do job[2]() end
    local entries = Suite.RootDB.devChatTaintProbe.entries
    for index = #entries - 3, #entries do
        local entry = entries[index]
        Check(entry.complete and entry.boxName == "ChatFrame1EditBox" and entry.textSecret == true,
            "optional source metadata interrupted the remaining capture")
        Check(entry.flags.addonChatRestrictionsForced == "1" and entry.flags.addonMapRestrictionsForced == "0",
            "optional metadata changed diagnostic flags")
    end
    return entries[#entries]
end
local absent = {
    { label = "nil debug" },
    { label = "non-table debug", value = false },
    { label = "secret debug", value = secret },
    { label = "no getinfo", value = {} },
    { label = "non-function getinfo", value = { getinfo = true } },
    { label = "secret getinfo", value = { getinfo = secret } },
}
for _, case in ipairs(absent) do
    debug = case.value
    local entry = Focus()
    Check(entry.processSource == nil and next(entry.scripts) == nil, case.label .. " produced invalid metadata")
end
local info
debug = { getinfo = function(callback, options)
    reads = reads + 1
    Check(callback == sample and options == "S", "source query received secret or incorrect arguments")
    return info
end }
info = { source = "@Interface/AddOns/Example/Chat.lua", linedefined = 42 }
local entry = Focus()
Check(entry.processSource.file == "Interface/AddOns/Example/Chat.lua" and entry.processSource.line == 42,
    "available source metadata was lost")
for _, invalid in ipairs({ false, secret, { source = false } }) do
    info = invalid
    entry = Focus()
    Check(entry.processSource == nil, "invalid or secret source metadata escaped: " .. type(invalid))
end
info = { source = secret, linedefined = secret }
entry = Focus()
Check(entry.processSource.file == "<dynamic-or-native>" and entry.processSource.line == "<secret>",
    "secret source metadata was not reduced to safe markers")
for _, dynamic in ipairs({ "private chat text", "[C]", "@C:/private/path.lua" }) do
    info = { source = dynamic, linedefined = secret }
    entry = Focus()
    Check(entry.processSource.file == "<dynamic-or-native>" and entry.processSource.line == "<secret>",
        "dynamic source text or secret line leaked into metadata")
end
box.ProcessChatType, script = secret, secret
local before = reads
Focus()
Check(reads == before, "secret callbacks reached the source query")
Check(#Suite.RootDB.devChatTaintProbe.entries == 24, "diagnostics lost their bounded history")
debug = nativeDebug
print("Suite Dev Mode optional source metadata: " .. checks .. " checks passed")
