local root = assert(arg[1])
local sourceOverride = arg[2]
local time, nextID, metadataReads = 100, 0, 0
local secret = {}
local Frame = {}
Frame.__index = Frame
function Frame:new(parent)
    nextID = nextID + 1
    return setmetatable({ parent = parent, shown = true, serial = nextID, hooks = {}, scripts = {} }, self)
end
function Frame:CreateTexture() return Frame:new(self) end
function Frame:CreateFontString() return Frame:new(self) end
function Frame:CreateAnimationGroup() return Frame:new(self) end
function Frame:CreateAnimation() return Frame:new(self) end
function Frame:SetPoint(...) self.point = {...} end
function Frame:ClearAllPoints() end
function Frame:SetSize() end
function Frame:SetFrameStrata() end
function Frame:EnableMouse() end
function Frame:SetJustifyH() end
function Frame:SetWordWrap() end
function Frame:SetFromAlpha() end
function Frame:SetToAlpha() end
function Frame:SetDuration() end
function Frame:Play() self.playing = true end
function Frame:Stop() self.playing = false end
function Frame:SetAlpha(value) self.alpha = value end
function Frame:SetScale(value) self.scale = value end
function Frame:SetColorTexture(...) self.color = {...} end
function Frame:SetText(value) self.text = value end
function Frame:SetTextColor(...) self.textColor = {...} end
function Frame:SetScript(kind, fn) self.scripts[kind] = fn end
function Frame:HookScript(kind, fn)
    self.hooks[kind] = self.hooks[kind] or {}
    table.insert(self.hooks[kind], fn)
end
function Frame:Run(kind)
    if self.scripts[kind] then self.scripts[kind](self) end
    for _, fn in ipairs(self.hooks[kind] or {}) do fn(self) end
end
function Frame:Show()
    if not self.shown then self.shown = true; self:Run('OnShow') end
end
function Frame:Hide()
    if self.shown then self.shown = false; self:Run('OnHide') end
end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:IsProtected() return false end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
UIParent = Frame:new()
GetTime = function() return time end
GetZoneText = function() return 'Zone' end
GetSubZoneText = function() return '' end
C_ChallengeMode = { IsChallengeModeActive = function() return false end }
C_Scenario = { GetInfo = function() return 'Scenario', 1, 1 end }
Enum = { EventToastEventType = {} }
GetAchievementInfo = function(id)
    metadataReads = metadataReads + 1
    if id == 999 then return id, nil end
    if id == 998 then return id, secret end
    return id, 'Achievement '..id, 10, true
end
hooksecurefunc = function(object, name, fn)
    local original = object[name]
    object[name] = function(...)
        local values = { original(...) }
        fn(...)
        return unpack(values)
    end
end
local S = {}
S.Public = function(value) return value ~= secret end
S.Number = function(value) return value ~= secret and type(value) == 'number' and value == value end
S.Finite = S.Number
S.PublicText = function(value) return value ~= secret and type(value) == 'string' and value ~= '' and value or nil end
S.ReadText = function(fn, ...) return S.PublicText(fn(...)) end
S.Text = function(text) return text end
S.Dispatch = function(fn, ...) local ok, msg = pcall(fn, ...); assert(ok, msg) end
S.CreateFrame = function(_, _, parent) return Frame:new(parent) end
S.CreateTexture = function(frame) return frame:CreateTexture() end
S.CreateFontString = function(frame) return frame:CreateFontString() end
S.SetStyledFont = function() end
S.ResolveFont = function() return 'font' end
S.GlobalFontPath = S.ResolveFont
S.RGB = function() return 1, 1, 1 end
S.RegisterOwnedMover = function() end
S.Install = function(_, module) S.module = module end
local context = { saved = {}, events = {} }
function context:Skin() return nil end
function context:After(_, fn) self.dismiss = fn end
function context:Cancel(fn) if self.dismiss == fn then self.dismiss = nil end end
function context:Coalesce(_, fn) return { Request = function() fn(S.module) end } end
function context:Event(event, fn) self.events[event] = fn end
function context:Mute(frame)
    self.saved[frame] = self.saved[frame] or frame:GetParent()
    frame:SetParent(self.muteHost)
    return true
end
function context:Unmute(frame)
    if self.saved[frame] then frame:SetParent(self.saved[frame]); self.saved[frame] = nil end
end
function context:HideUnprotected() end
context.muteHost = Frame:new(UIParent)
local NS = { Safety = { IsForbidden = function() return false end }, HUDTextArgs = function() end }
local native = { active = {}, pending = {}, frames = {} }
AchievementAlertSystem = native
native.setUpFunction = function(frame, id) frame.id = id; return true end
native.alertFramePool = {}
function native.alertFramePool:EnumerateActive() return pairs(native.active) end
function native:ShowAlert(id)
    local frame
    for _, item in ipairs(self.frames) do if not self.active[item] then frame = item; break end end
    if not frame then
        frame = Frame:new(UIParent)
        frame.shown = false
        frame:SetScript('OnHide', function(f)
            native.active[f] = nil
            -- Actual native release/reset refills immediately, before addon OnHide post-hooks.
            if #native.pending > 0 then native:ShowAlert(table.remove(native.pending, 1)) end
        end)
        self.frames[#self.frames + 1] = frame
    end
    self.active[frame] = true
    self.setUpFunction(frame, id)
    frame:Show()
    self.last = frame
    return true
end
assert(loadfile(sourceOverride or root..'/MSUF_Suite_Modules/Announcements.lua'))('MSUF_Suite_Modules', { NS = NS, Suite = S })
local m = S.module
m.context = context
m.config = { achievements=true, zone=false, eventToasts=false, quests=false, scenario=false, level=false,
    duration=2, scale=100, anchor=1, x=0, y=-90 }
m:Enable()
local function Finish()
    time = time + 2
    m.leave:Run('OnFinished')
end
local function Count(id)
    local key, count = 'achievement:'..id, 0
    if m.current and m.current.key == key then count = count + 1 end
    for _, item in ipairs(m.queue) do if item.key == key then count = count + 1 end end
    return count
end
native:ShowAlert(10)
assert(Count(10)==1, 'numeric native achievement was muted without a Suite replacement')
assert(native.last:GetParent()==context.muteHost, 'represented achievement was not muted')
Finish()
assert(Count(10)==0, 'banner finish did not clear displayed entry')
context.events.PLAYER_REGEN_ENABLED(m, 'PLAYER_REGEN_ENABLED')
assert(Count(10)==0, 'native lifetime rescan replayed an already delivered achievement')
local readMark = metadataReads
for i=1,20 do context.events.PLAYER_REGEN_ENABLED(m, 'PLAYER_REGEN_ENABLED') end
assert(metadataReads == readMark, 'native receipt rescan re-read unchanged achievement metadata')
native:ShowAlert(20)
assert(Count(20)==1 and Count(10)==0, 'second ShowAlert replayed older active achievement')
Finish()
-- Native pool reuses frame 10 for another alert inside frame 10 OnHide.
native.pending[1] = 30
native.frames[1]:Hide()
assert(Count(30)==1, 'nested pool refill lost the new achievement')
Finish()
context.events.PLAYER_REGEN_ENABLED(m, 'PLAYER_REGEN_ENABLED')
assert(Count(30)==0, 'OnHide post-hook cleared the nested refill receipt')
-- Same-ID future event must still display after actual native pool reuse.
native.frames[1]:Hide()
native:ShowAlert(30)
assert(Count(30)==1, 'same-ID later achievement was suppressed by stale receipt')
print('independent native lifetime, rescan and nested pool reuse probes passed')
