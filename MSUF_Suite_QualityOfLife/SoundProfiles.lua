local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local IN_COMBAT = { inCombat = true }
local CVARS = { Sound_MusicVolume = "Music", Sound_AmbienceVolume = "Ambience", Sound_SFXVolume = "Effects" }
-- The activities (S.InstanceKind) that always have a volume profile. Battlegrounds
-- and arenas ("pvp") keep the player's own volumes until their profile is on.
local PROFILES = { world = true, party = true, raid = true }
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }
-- At most this many sound file IDs of the player's list count (mutedFileIDs).
local MAX_MUTED = 200
local NONE = {}
-- The files this module muted. Edits and disable undo exactly these, so a
-- file muted by something else is never unmuted here.
local muted = {}
-- Mutes the files of wanted ({ [fileDataID] = true }) and unmutes the rest of
-- the ones muted here.
local function SyncMuted(wanted)
    for id in pairs(muted) do
        if not wanted[id] then
            UnmuteSoundFile(id)
            muted[id] = nil
        end
    end
    for id in pairs(wanted) do
        if not muted[id] then
            MuteSoundFile(id)
            muted[id] = true
        end
    end
end
local function Restore()
    for key in pairs(CVARS) do S.RestoreCVar("soundProfiles", key) end
    M.kind = nil
end
-- The activity whose volume profile applies now. Without "Apply volume
-- profiles" none does; unset (an older profile) counts as on.
local function Profile()
    local c = M.config
    if c.applyVolumes == false then return nil end
    local kind = S.InstanceKind()
    if PROFILES[kind] or (kind == "pvp" and c.pvpProfile) then return kind end
end
local function Apply()
    if not M.active or NS.InCombat() then return end
    local fishing = S.instances.fishingComfort
    if fishing and fishing.audio then return end
    local kind = Profile()
    if not kind then
        Restore()
        return
    end
    if M.kind == kind then return end
    Restore()
    for key, suffix in pairs(CVARS) do M.context:CVar(key, M.config[kind .. suffix] / 100) end
    M.kind = kind
end
-- The profiles follow the activity, so their events are heard only while
-- they are applied; muting sound files needs none.
local function SyncEvents(self)
    for _, event in ipairs(EVENTS) do
        if self.config.applyVolumes ~= false then
            self.context:Event(event, Apply, IN_COMBAT)
        else
            self.context:RemoveEvent(event)
        end
    end
end
function M:Enable()
    self:Refresh()
end
function M:Refresh()
    SyncEvents(self)
    Restore()
    Apply()
    SyncMuted(S.QoLParseIDs(self.config.mutedFileIDs, MAX_MUTED))
end
function M:Disable()
    Restore()
    SyncMuted(NONE)
end
function S.SuspendSoundProfile()
    if M.kind then Restore() end
end
S.RefreshSoundProfile = Apply
S.Install("soundProfiles", M)
