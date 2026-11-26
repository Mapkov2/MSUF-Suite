-- Repeated bag layout requests exercise the Suite owner that writes native geometry.
local root = assert(arg[1])
local secret = {}
local function Public(value) return not rawequal(value, secret) end
MSUFSuite = {
    Suite = {}, Public = Public, Number = function(value) return type(value) == "number" end,
    IsCombatLocked = function() return false end, Safety = { IsForbidden = function() return false end },
}
assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", {})
local context = MSUFSuite.Suite.NewContext("bags")
do
    local frame = { value = 1, reads = 0, writes = 0 }
    function frame:GetScale() self.reads = self.reads + 1; return self.value end
    function frame:SetScale(value)
        self.writes = self.writes + 1
        self.value = math.floor(value * 10 + .5) / 10
    end
    for i = 1, 100 do context:Scale(frame, 1) end
    assert(frame.reads == 100 and frame.writes == 0, "unchanged scale must read once per request")
    context:Scale(frame, 1.24)
    assert(frame.reads == 102 and frame.writes == 1 and frame.value == 1.2,
        "a native scale change must read the actual rounded result")
    context:RestoreProperty(frame, "SetScale")
    assert(frame.value == 1, "failed to restore the original scale after native rounding")
    context:Scale(frame, 1)
    frame.value = 1.5
    context:RestoreProperty(frame, "SetScale")
    assert(frame.value == 1.5, "a later foreign scale was overwritten")
end
do
    local parent, foreign = {}, {}
    local anchor = { "TOPLEFT", parent, "TOPLEFT", 12, -15 }
    local frame = { points = { anchor }, clears = 0, sets = 0, reads = 0 }
    function frame:GetNumPoints() return #self.points end
    function frame:GetPoint(i) self.reads = self.reads + 1; return unpack(self.points[i], 1, 5) end
    function frame:ClearAllPoints() self.clears = self.clears + 1; self.points = {} end
    function frame:SetPoint(point, relative, edge, x, y)
        self.sets = self.sets + 1
        self.points[#self.points + 1] = { point, relative, edge, math.floor(x + .5), y }
    end
    for i = 1, 100 do context:Anchor(frame, unpack(anchor)) end
    assert(frame.reads == 100 and frame.clears == 0 and frame.sets == 0, "rewrote an unchanged single anchor")
    context:Anchor(frame, "TOPLEFT", parent, "TOPLEFT", 9.1, -15)
    assert(frame.reads == 102 and frame.sets == 1 and frame.points[1][4] == 9, "changed anchor was not read back")
    context:RestorePoints(frame)
    assert(frame.points[1][4] == 12 and frame.points[1][2] == parent, "lost the original anchor")
    frame.points = { anchor, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1 } }
    context:Anchor(frame, unpack(anchor))
    assert(#frame.points == 1, "a matching first point concealed an extra anchor")
    context:RestorePoints(frame)
    assert(#frame.points == 2 and frame.points[2][1] == "BOTTOMRIGHT", "second anchor was not restored")
    frame.points = { { "TOPLEFT", parent, "TOPLEFT", secret, -15 } }
    local sets = frame.sets
    context:Anchor(frame, unpack(anchor))
    assert(frame.sets == sets and context.points[frame] == nil, "claimed a restricted anchor")
    frame.points = { anchor }
    context:Anchor(frame, unpack(anchor))
    frame.points = { { "CENTER", foreign, "CENTER", 0, 0 } }
    context:RestorePoints(frame)
    assert(frame.points[1][2] == foreign and context.points[frame] == nil, "restoration overwrote a later owner")
end
print("100 unchanged scale requests and 100 unchanged anchor requests each made 100 reads and zero writes")
