local root = assert(arg[1])
local client = arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local checks = 0
local function Strict(W)
    local create = W.S.CreateFontString
    W.S.CreateFontString = function(...)
        local text = create(...)
        local setText = text.SetText
        function text:SetText(value)
            assert(self:GetFont(), "FontString:SetText Font not set before first text")
            checks = checks + 1
            return setText(self, value)
        end
        return text
    end
end
for _, font in ipairs({"", "Selected"}) do
    local W = H.New(root, {client=client,catalogPresentation=true,config={font=font}})
    Strict(W)
    W.S.ResolveFont = function(key) if key == "Selected" then return "Selected.ttf" end end
    W.S.GlobalFontPath = function() return "Global.ttf" end
    W.sizes[0] = 4
    W.Apply()
    W.OpenBags()
    W.Settle()
    local heading = W.M.windows[W.CF].heading
    assert(heading:GetText() == "Backpack" and heading:GetFont() == (font == "" and "Global.ttf" or "Selected.ttf"),
        "cold live heading lost its selected/global font or text")
    assert(#W.errors == 0, "live font setup reported an error")
end
-- Exercise the real cold-combat menu retry and both presentation choices.
-- Host menu text comes from its separate fixture; all Suite-created bare
-- text still has the native SetText precondition above.
local originalDofile = dofile
dofile = function(path)
    local result = originalDofile(path)
    if path:match("/suite_bags_harness.lua$") then
        local new = result.New
        result.New = function(...)
            local W = new(...)
            Strict(W)
            return W
        end
    end
    return result
end
assert(loadfile(root .. "/tools/tests/suite_bags_menu_preview_contract.lua"))()
dofile = originalDofile
assert(checks > 0, "strict native font precondition never ran")
print("Native font before first text: live, cold preview, selected/global font passed: " .. client)
