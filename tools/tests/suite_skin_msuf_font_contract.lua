local root = assert(arg[1])

local function Font(path, size, flags)
    local font = { path = path, size = size, flags = flags }
    function font:GetFont() return self.path, self.size, self.flags end
    function font:SetFont(nextPath, nextSize, nextFlags)
        self.path, self.size, self.flags = nextPath, nextSize, nextFlags
        return true
    end
    return font
end

local game = Font("Blizzard.ttf", 14, "OUTLINE")
local chat = Font("Chat.ttf", 12, "")
local foreign = Font("OtherAddon.ttf", 16, "")
GameFontNormal, ChatFrame1, OtherAddonFont = game, chat, foreign
NUM_CHAT_WINDOWS = 1
CommunitiesFrame, DeveloperConsole = { Chat = {} }, {}
GetFonts = function() return { "GameFontNormal", "OtherAddonFont" } end
GetLocale = function() return "enUS" end
EventUtil = { ContinueAfterAllEvents = function() end }

local msufPath = "MSUF.ttf"
MSUF_GetFontPath = function() return msufPath end
local NS = {
    DB = { enabled = true, typography = {
        enabled = true, followMSUF = true, face = "sharedMedia",
        sharedMediaFont = "Skin", applyChat = true, includeSpecial = true,
    } },
    BlizzardFontNames = { "GameFontNormal" },
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    Safety = {
        Public = function(value) return value ~= "secret" end,
        Call = function(object, name) return object[name](object) end,
    },
    SharedMedia = {
        FetchFont = function(name) return name == "Skin" and "Skin.ttf" or nil end,
        GetFontNames = function() return { "Skin" } end,
    },
    Client = { IsAddOnLoaded = function() return true end },
    CombatGate = { RunOrDefer = function() end, Cancel = function() end },
    CharacterDetails = { RefreshFonts = function() end },
    CharacterStats = { RefreshFonts = function() end },
    IsCombatLocked = function() return false end,
}
local typography = assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Typography.lua"))("MSUF_Suite_Skin", NS)

assert(typography.GetSelection() == "msuf" and typography.GetSelectionValues()[1] == "msuf")
assert(typography.ApplyConfigured())
assert(game.path == msufPath and chat.path == msufPath and foreign.path == "OtherAddon.ttf",
    "MSUF selection must reach Blizzard fonts and chat without changing another addon's font")
assert(game.size == 14 and game.flags == "OUTLINE" and chat.size == 12,
    "Blizzard's font size and outline must remain native")

msufPath = "Second.ttf"
assert(typography.ApplyConfigured() and game.path == msufPath and chat.path == msufPath,
    "a changed MSUF font must reach Blizzard and chat text")
assert(typography.SetSelection("arial") and typography.GetSelection() == "arial"
    and game.path == "Fonts\\ARIALN.TTF", "an explicit skin font must override the MSUF selection")
msufPath = "Third.ttf"
assert(typography.ApplyConfigured() and game.path == "Fonts\\ARIALN.TTF",
    "later MSUF font changes must respect the explicit skin selection")
assert(typography.SetSelection("lsm:Skin") and game.path == "Skin.ttf"
    and NS.DB.typography.followMSUF == false,
    "a SharedMedia font selection must stop following the MSUF font")
assert(typography.SetSelection("msuf") and game.path == msufPath,
    "selecting MSUF again must restore font following")
msufPath = "secret"
assert(typography.ApplyConfigured() and game.path == "Skin.ttf",
    "an unreadable MSUF font path must fall back to the saved Skin face")
assert(typography.SetEnabled(false) and game.path == "Blizzard.ttf" and chat.path == "Chat.ttf",
    "disabling the Blizzard font override must restore original paths")

print("suite skin MSUF font contract ok")
