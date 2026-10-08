-- The tooltip-hide rule of the Suite's own frames: OnLeave hides the shared
-- GameTooltip only while the frame being left still owns it
-- (GameTooltip:IsOwned), as the Bags, DataTexts and CooldownManager do. A
-- frame that hid it unconditionally (GameTooltip_Hide, a bare
-- GameTooltip:Hide()) could close a tooltip another frame took over.
-- Covers QualityOfLife J-Z with EnemyCastStack, BuffReminders, Chat and
-- Nameplates.
local root = assert(arg[1], "repository root required")

-- The files in TOC order (QualityOfLife: J-Z and EnemyCastStack only).
local function Files()
    local files = {}
    for _, addon in ipairs({ "MSUF_Suite_QualityOfLife", "MSUF_Suite_BuffReminders", "MSUF_Suite_Chat",
        "MSUF_Suite_Nameplates" }) do
        local toc = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
        for line in toc:read("*a"):gmatch("[^\r\n]+") do
            local first = line:sub(1, 1)
            local wanted = addon ~= "MSUF_Suite_QualityOfLife" or first >= "J" and first <= "Z"
                or line == "EnemyCastStack.lua" or line == "CharacterExtras.lua" or line == "GroupRaidShortcuts.lua"
            if line:match("%.lua$") and not line:match("^#") and wanted then files[#files + 1] = addon .. "/" .. line end
        end
        toc:close()
    end
    return files
end

local checked = 0
for _, path in ipairs(Files()) do
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    checked = checked + 1
    local number = 0
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        number = number + 1
        local code = line:gsub("%-%-.*$", "")
        local where = path .. ":" .. number
        assert(not code:find("GameTooltip_Hide", 1, true),
            where .. " hides the tooltip through GameTooltip_Hide without asking who owns it")
        if code:find("GameTooltip:Hide()", 1, true) then
            assert(code:find("GameTooltip:IsOwned(", 1, true),
                where .. " hides the shared tooltip without GameTooltip:IsOwned")
        end
    end
end
assert(checked > 40, "the tooltip rule scanned only " .. checked .. " files")
print("Tooltip leave rule: " .. checked .. " files hide the shared tooltip only while they own it")
