local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders

local function Follow(driver)
    local self = driver.owner
    if not self.active or self.listen.suspended or NS.IsCombatLocked() then
        driver:SetScript("OnUpdate", nil)
        return
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not S.Public(x) or not S.Public(y) or not S.Public(scale) or scale <= 0 then return end
    x, y = x / scale + (self.config.cursorOffsetX or 24), y / scale + (self.config.cursorOffsetY or 24)
    if driver.x == x and driver.y == y then return end
    driver.x, driver.y = x, y
    local host = self.view.host
    host:ClearAllPoints()
    host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    self.cursor.displaced = true
end

-- Stops following the cursor; the host stays where the cursor left it.
function R.StopCursor(self)
    local cursor = self.cursor
    local driver = cursor.driver
    if not driver then return end
    driver:SetScript("OnUpdate", nil)
    driver.x, driver.y = nil, nil
end

-- Stops following and, out of combat, puts the host back on its anchor.
local function ReturnToAnchor(self)
    local cursor = self.cursor
    if not cursor.driver then return end
    R.StopCursor(self)
    if not cursor.displaced or NS.IsCombatLocked() then return end
    local point = self.config.point == 2 and "TOP" or "CENTER"
    local host = self.view.host
    host:ClearAllPoints()
    host:SetPoint(point, UIParent, point, self.config.x, self.config.y)
    cursor.displaced = nil
end

-- Cursor movement has no event. Only visible, opted-in OOC reminders attach
-- this input reader; it never reads aura/item state or creates Lua tables.
function R.SyncCursor(self)
    local mask, text = self.view.mask, self.notices.text
    local visible = mask and mask ~= 0 or text and text ~= ""
    if not self.config.followCursor or not visible or S.editMode or self.listen.suspended or NS.IsCombatLocked() then
        ReturnToAnchor(self)
        return
    end
    local cursor = self.cursor
    local driver = cursor.driver
    if not driver then
        driver = S.CreateFrame("Frame")
        driver.owner = self
        cursor.driver = driver
    end
    driver:SetScript("OnUpdate", Follow)
    Follow(driver)
end
