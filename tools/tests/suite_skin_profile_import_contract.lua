-- Skin profile import: an import never replaces an existing profile unless the
-- player confirmed it, a replacement can be undone, and an import string is
-- bounded before it is inflated. Real Database, ProfileIO, options history and
-- Profiles page; the client codec is a stand-in that round-trips tables.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end
local function Load(path, ns, addon)
    assert(loadfile(root .. "/" .. path))(addon or "MSUF_Suite_Skin", ns)
end

-- The client's securecallfunction reports an error and returns nothing.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

------------------------------------------------------------------ codec
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local blobs, codecCalls = {}, { decompress = 0, deserialize = 0 }
Enum = { CompressionMethod = { Deflate = 0 } }
C_EncodingUtil = {
    SerializeCBOR = function(value)
        blobs[#blobs + 1] = Copy(value)
        return "cbor:" .. #blobs
    end,
    DeserializeCBOR = function(payload)
        codecCalls.deserialize = codecCalls.deserialize + 1
        if payload == "cbor:raise" then error("contract: malformed CBOR") end
        local id = tonumber(payload:match("^cbor:(%d+)$"))
        return id and Copy(blobs[id]) or nil
    end,
    -- Never shorter here, so exports keep the plain payload.
    CompressString = function(text) return "deflate:" .. text end,
    DecompressString = function(text)
        codecCalls.decompress = codecCalls.decompress + 1
        return text:match("^deflate:(.*)$")
    end,
    EncodeBase64 = function(text) return text end,
    DecodeBase64 = function(text) return text end,
}

------------------------------------------------------------------ engine
local locked = false
local NS = {
    Client = { isForever = false, isMainline = true },
    IsCombatLocked = function() return locked end,
    -- Typography.lua (loads after Database.lua) defines the face list.
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    Theme = { RefreshDynamicLook = Noop },
    Typography = { Restore = Noop, ApplyConfigured = Noop },
    Adapters = { ApplyAll = Noop },
    Registry = { RefreshAll = Noop, NotifyListeners = Noop, AddListener = Noop },
}
for _, file in ipairs({ "Defaults", "Database", "DatabaseProfiles", "ProfileIO", "Safety" }) do
    Load("MSUF_Suite_Skin/Core/" .. file .. ".lua", NS)
end
local Database, IO = NS.Database, NS.ProfileIO
local function Profile(accentRed)
    local profile = NS.CopyValue(NS.Defaults)
    profile.theme.colors.accent[1] = accentRed
    return profile
end
local function Accent(name) return Database.GetProfile(name).theme.colors.accent[1] end
MSUFSuiteSkinDB = { activeProfile = "Default", profiles = { Default = Profile(0.11), Raid = Profile(0.22) } }
Database.Initialize()

-- A friend's string, exported from their own "Default".
local friend = Profile(0.77)
blobs[#blobs + 1] = { addon = "MapkoSkin", format = 1, kind = "profile", name = "Default", payload = friend }
local friendText = IO.prefix .. "cbor:" .. #blobs

------------------------------------------------------------------ engine rules
-- No name typed: the exported name is taken, so the import lands beside it.
local ok, name = IO.ImportProfile(friendText)
Check(ok and name == "Default (2)", "an import without a name did not pick a free name: " .. tostring(name))
Check(math.abs(Accent("Default") - 0.11) < 1e-9, "an import without a name replaced the player's Default")
Check(math.abs(Accent("Default (2)") - 0.77) < 1e-9 and Database.GetActiveProfileName() == "Default (2)",
    "the imported profile was not stored and activated under its free name")
ok, name = IO.ImportProfile(friendText)
Check(ok and name == "Default (3)", "a second import reused a taken name: " .. tostring(name))

-- A typed name that is taken is refused until the replacement is confirmed.
local reason, existing
ok, reason, existing = IO.ImportProfile(friendText, "  Raid ")
Check(not ok and reason == "profile-exists" and existing == "Raid",
    "an import onto a taken name was not refused with the name: " .. tostring(reason))
Check(math.abs(Accent("Raid") - 0.22) < 1e-9, "a refused import changed the existing profile")
ok, name = IO.ImportProfile(friendText, "Raid", true)
Check(ok and name == "Raid" and math.abs(Accent("Raid") - 0.77) < 1e-9
    and Database.GetActiveProfileName() == "Raid", "a confirmed replacement did not replace the profile")
ok, name = IO.ImportProfile(friendText, "Fresh")
Check(ok and name == "Fresh", "an import onto a free typed name was refused")

-- Free names keep to the name limit and never cut a UTF-8 character.
local full = string.rep("a", Database.maxProfileNameBytes)
Database.SetProfile(full, Profile(0.5))
local free = IO.FreeName(full)
Check(free == string.rep("a", Database.maxProfileNameBytes - 4) .. " (2)",
    "a free name for a full-length name broke the length limit: " .. tostring(free))
-- "ä" is two bytes; the room left for the name ends inside or after it.
local split = string.rep("a", 35) .. "\195\164" .. "bbb"
Database.SetProfile(split, Profile(0.5))
Check(IO.FreeName(split) == string.rep("a", 35) .. " (2)",
    "a free name cut a UTF-8 character in half: " .. tostring(IO.FreeName(split)))
local whole = string.rep("a", 34) .. "\195\164" .. "bbbb"
Database.SetProfile(whole, Profile(0.5))
Check(IO.FreeName(whole) == string.rep("a", 34) .. "\195\164" .. " (2)",
    "a free name dropped a UTF-8 character it had room for")

------------------------------------------------------------------ adapter switches
-- Adapters other addons register keep their switch through every profile
-- copy (import, copy current, standalone undo); only plain booleans with a
-- bounded id are copied, at most 64 of them.
local switched = Profile(0.6)
switched.skins.ContractAddonWindow = false
switched.skins.ContractAddonPanel = true
switched.skins.ContractBroken = "yes"
switched.skins[string.rep("x", 65)] = false
for index = 1, 80 do switched.skins["ContractExtra" .. index] = true end
local sanitized = Database.SanitizeProfile(switched)
Check(sanitized.skins.ContractAddonWindow == false and sanitized.skins.ContractAddonPanel == true,
    "a profile copy dropped the switch of an adapter another addon registered")
Check(sanitized.skins.ContractBroken == nil and sanitized.skins[string.rep("x", 65)] == nil,
    "a profile copy kept a malformed adapter switch")
local extras = 0
for id, value in pairs(sanitized.skins) do
    if NS.Defaults.skins[id] == nil then
        extras = extras + 1
        Check(type(value) == "boolean", "a copied adapter switch is not a boolean")
    end
end
Check(extras == 64, "a profile copy kept " .. extras .. " foreign adapter switches instead of 64")
Check(sanitized.skins.objectiveTracker == nil, "a retired skin switch came back through a copy")
blobs[#blobs + 1] = { addon = "MapkoSkin", format = 1, kind = "profile", name = "Switched",
    payload = { skins = { ContractAddonWindow = false } } }
ok, name = IO.ImportProfile(IO.prefix .. "cbor:" .. #blobs)
Check(ok and Database.GetProfile(name).skins.ContractAddonWindow == false,
    "an imported profile lost the switch of another addon's adapter")

------------------------------------------------------------------ bounds
-- The compressed payload is capped before DecompressString can inflate it.
local before = codecCalls.decompress
ok, reason = IO.ImportProfile(IO.prefix .. string.rep("x", IO.maxCompressedBytes + 1))
Check(not ok and reason == "import-too-large" and codecCalls.decompress == before,
    "an oversized payload reached DecompressString: " .. tostring(reason))
Check(IO.maxEncodedBytes >= math.ceil(IO.maxCompressedBytes / 3) * 4,
    "the text limit refuses strings whose payload is within the cap")
local serialize = C_EncodingUtil.SerializeCBOR
C_EncodingUtil.SerializeCBOR = function() return string.rep("s", IO.maxCompressedBytes + 1) end
local exported, exportReason = IO.ExportProfile("Default")
C_EncodingUtil.SerializeCBOR = serialize
Check(exported == nil and exportReason == "export-too-large",
    "an export larger than an import may be was written")
-- DeserializeCBOR raising for malformed data is reported and fails the import.
local reports = #reported
ok, reason = IO.ImportProfile(IO.prefix .. "cbor:raise")
Check(not ok and reason == "deserialize-failed" and #reported == reports + 1,
    "a raising CBOR decode escaped or was swallowed: " .. tostring(reason))
local source = assert(io.open(root .. "/MSUF_Suite_Skin/Core/ProfileIO.lua", "rb")):read("*a")
Check(not source:find("TODO", 1, true), "ProfileIO still ships an unresolved TODO")

------------------------------------------------------------------ options
-- The Profiles page: a taken name arms the import button; only a second
-- click on the same text and name replaces, as one undo step.
local function Frame()
    local frame = { scripts = {} }
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:SetText(text) self.text = text end
    function frame:GetText() return self.text end
    function frame:IsShown() return true end
    return setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return Noop end
    end })
end
-- The transfer box is the page's only EditBox; the stand-in keeps its text.
local editBoxes = {}
CreateFrame = function(kind)
    local frame = Frame()
    if kind == "EditBox" then editBoxes[#editBoxes + 1] = frame end
    return frame
end
PlaySound, SOUNDKIT = Noop, { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
NS.L = setmetatable({}, { __index = function(_, key) return key end })
NS.Surface = { SkinOwnedButton = function() return {} end, Attach = Noop }
MapkoSkin = NS
local private = {}
Load("MSUF_Suite_Skin_Options/MSKIN_OptionsBootstrap.lua", private, "MSUF_Suite_Skin_Options")
local O = NS.Options
O.CreateText = function(_, text) local label = Frame(); label.text = text; return label end
O.CreatePanel = function() return Frame() end
O.SetTextColor = function(text, role) text.role = role end
O.CreateSectionTitle = Noop
Load("MSUF_Suite_Skin_Options/Shell/Widgets.lua", private, "MSUF_Suite_Skin_Options")
local inputs, builder = {}, nil
O.CreateInput = function(_, label, _, setter) inputs[label] = setter; return Frame() end
O.CreateCycle = function() return Frame() end
O.RegisterPage = function(_, _, pageBuilder) builder = pageBuilder end
Load("MSUF_Suite_Skin_Options/Pages/Profiles.lua", private, "MSUF_Suite_Skin_Options")
builder(Frame())
local importButton, importLabel
for button, state in pairs(O.widgetStates) do
    if state.label.text == "Import profile" then importButton, importLabel = button, state.label end
end
Check(importButton ~= nil, "the Import profile button was not built")
local edit = assert(editBoxes[1], "the transfer box was not built")
local function Click()
    importButton:GetScript("OnClick")(importButton, "LeftButton")
end
local lastStatus
local setTextColor = O.SetTextColor
O.SetTextColor = function(text, role)
    lastStatus = text
    return setTextColor(text, role)
end

Database.SetActiveProfile("Default")
O.ClearHistory()
edit:SetText(friendText)
inputs["Profile name"]("Raid")
Database.SetProfile("Raid", Profile(0.22))
Click()
Check(math.abs(Accent("Raid") - 0.22) < 1e-9, "the first click on a taken name replaced the profile")
Check(importLabel.text == "Confirm replace" and lastStatus.role == "danger"
    and lastStatus.text:find("already exists", 1, true),
    "a taken name did not arm the button with a warning: " .. tostring(lastStatus.text))
Check(#timers == 1, "the replace arm never expires")
Click()
Check(math.abs(Accent("Raid") - 0.77) < 1e-9 and Database.GetActiveProfileName() == "Raid",
    "the confirming click did not replace the profile")
Check(importLabel.text == "Import profile" and lastStatus.role == "success",
    "the confirmed replacement left the button armed or reported no success")
Check(O.GetHistoryState() == "Import profile", "the replacement recorded no undo step")
Check(O.Undo() and math.abs(Accent("Raid") - 0.22) < 1e-9,
    "undo did not bring the replaced profile back")

-- An expired arm or a changed text or name starts over instead of replacing.
Database.SetActiveProfile("Default")
Click()
Check(importLabel.text == "Confirm replace", "a click on a taken name did not arm")
timers[#timers]()
Check(importLabel.text == "Import profile", "the replace arm did not expire")
Click()
Check(math.abs(Accent("Raid") - 0.22) < 1e-9 and importLabel.text == "Confirm replace",
    "a click after the arm expired replaced the profile")
edit:SetText(friendText .. " ")
Click()
Check(math.abs(Accent("Raid") - 0.22) < 1e-9 and importLabel.text == "Confirm replace",
    "a click after the text changed replaced the profile")
inputs["Profile name"]("Other")
Database.SetProfile("Other", Profile(0.33))
Click()
Check(math.abs(Accent("Other") - 0.33) < 1e-9 and math.abs(Accent("Raid") - 0.22) < 1e-9,
    "a click after the name changed replaced a profile")
-- Without a name the import lands on a free name, and nothing is armed.
inputs["Profile name"]("")
Click()
Check(importLabel.text == "Import profile" and lastStatus.role == "success"
    and lastStatus.text:find("Default (4)", 1, true),
    "an import without a name was not placed beside the taken name: " .. tostring(lastStatus.text))
Check(#reported == reports + 1, "the options import raised: " .. table.concat(reported, "; "))

print("Suite skin profile import: " .. checks .. " checks passed")
