local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders

local function Follow(driver)
    local self = driver.owner
    if not self.active or self.suspended or NS.IsCombatLocked() then
        driver:SetScript("OnUpdate", nil)
        return
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not S.Public(x) or not S.Public(y) or not S.Public(scale) or scale <= 0 then return end
    x, y = x / scale + (self.config.cursorOffsetX or 24), y / scale + (self.config.cursorOffsetY or 24)
    if driver.x == x and driver.y == y then return end
    driver.x, driver.y = x, y
    self.host:ClearAllPoints()
    self.host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    self.cursorDisplaced = true
end

function R.StopCursor(self, restore)
    local driver = self.cursorDriver
    if not driver then return end
    driver:SetScript("OnUpdate", nil)
    if restore and self.cursorDisplaced and not NS.IsCombatLocked() then
        local point = self.config.point == 2 and "TOP" or "CENTER"
        self.host:ClearAllPoints()
        self.host:SetPoint(point, UIParent, point, self.config.x, self.config.y)
        self.cursorDisplaced = nil
    end
    driver.x, driver.y, self.cursorFollowing = nil, nil, false
end

-- Cursor movement has no event. Only visible, opted-in OOC reminders attach
-- this input reader; it never reads aura/item state or creates Lua tables.
function R.SyncCursor(self)
    local visible = self.mask and self.mask ~= 0 or self.specialText and self.specialText ~= ""
    if not self.config.followCursor or not visible or S.editMode or self.suspended or NS.IsCombatLocked() then
        R.StopCursor(self, true)
        return
    end
    local driver = self.cursorDriver
    if not driver then
        driver = S.CreateFrame("Frame")
        driver.owner = self
        self.cursorDriver = driver
    end
    self.cursorFollowing = true
    driver:SetScript("OnUpdate", Follow)
    Follow(driver)
end
