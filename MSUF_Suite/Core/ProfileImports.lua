local _, Suite = ...
local Profiles, IO, DB = Suite.SuiteProfiles, Suite.ProfileIO, Suite.Database
local Host = Suite.HostBridge
local Operations = Profiles.ImportOperations
local SkinEngine, SkinSnapshot = Profiles.WorkbenchSkinEngine, Profiles.WorkbenchSkinSnapshot

local function BundleModules(text)
    if type(text) ~= "string" or #text > Profiles.maxBytes then return nil, "Invalid suite profile" end
    text = text:match("^%s*(.-)%s*$"):gsub("\r\n", "\n")
    local version, frames, modules, skinText = text:match("^MSUFS(3):([^\n]+)\n([^\n]+)\n([^\n]+)$")
    if not version then version, frames, modules = text:match("^MSUFS([12]):([^\n]+)\n([^\n]+)$") end
    if not frames or not frames:match("^MSUF[234]:") then return nil, "Invalid suite profile" end
    local decode = version == "1" and IO.PrepareLegacyProfile or IO.PrepareProfile
    local profile, why, marked = decode(modules)
    if not profile then return nil, why end
    return { version = version, profile = profile, coreText = frames, characterBound = marked,
        skinText = version == "3" and skinText or modules }
end

local function ProtectNameplates(profile)
    -- Full imports carry the active profile's protected settings forward.
    local current = Suite.DB and Suite.DB.suite and Suite.DB.suite.modules
    local plates = current and current.nameplates
    if plates and plates.protectImport then
        profile.suite.modules.nameplates = Suite.CopyValue(plates)
        profile.nameplateCVars = IO.NameplateSnapshot(Suite.DB.nameplateCVars)
        profile.nameplateShared = IO.CaptureNameplateShared()
    end
end

local function BundleSkin(bundle, skin)
    local profile, reason
    if bundle.version == "3" or (bundle.version == "1" and skin) then
        if not skin then return false, "Skin engine unavailable" end
        profile, reason = skin.ProfileIO.PrepareProfile(bundle.skinText)
    else
        profile, reason = SkinSnapshot(skin)
    end
    if skin and not profile then return false, reason end
    return true, profile
end

local function PrepareBundle(text)
    local bundle, reason = BundleModules(text)
    if not bundle then return false, reason end
    ProtectNameplates(bundle.profile)
    local skin = SkinEngine()
    local ok, skinProfile = BundleSkin(bundle, skin)
    if not ok then return false, skinProfile end
    bundle.modules = bundle.profile.suite.modules
    bundle.provider = { present = skin ~= nil, profile = skinProfile }
    return bundle
end
Profiles.WorkbenchPrepareBundle = PrepareBundle

function Profiles.Import(name, text)
    local clean, reason = Operations.NewName(name)
    if not clean then return false, reason end
    local bundle, why = PrepareBundle(text)
    if not bundle then return false, why end
    return Operations.Create(clean, bundle.coreText, bundle.profile, bundle.provider.profile)
end

local function IsSkin(text)
    return type(text) == "string" and text:match("^%s*MSKIN1:") ~= nil
end

local function ApplySkin(skin, profile)
    local database = skin.Database
    local previousName = database.GetActiveProfileName()
    local name = Host.ActiveFrameProfileName() or previousName
    local checkpoint, why = Suite.ProfileWorkbenchBridge.Checkpoint("Before importing skin settings")
    if not checkpoint then return false, why end
    local before = Suite.CopyValue(database.GetProfile(name))
    local ran, ok, reason = Suite.Dispatch(Suite.Finish, database.SetProfile, name, profile)
    if ran and ok then ran, ok, reason = Suite.Dispatch(Suite.Finish, database.SetActiveProfile, name) end
    if ran and ok then return true, reason end

    local restored = true
    if before then
        local wrote, accepted = Suite.Dispatch(Suite.Finish, database.SetProfile, name, before)
        restored = wrote and accepted
    end
    local switched, accepted = Suite.Dispatch(Suite.Finish, database.SetActiveProfile, previousName)
    restored = restored and switched and accepted
    if not before and database.GetProfile(name) then
        local removed, accepted = Suite.Dispatch(Suite.Finish, database.DeleteProfile, name)
        restored = restored and removed and accepted
    end
    if not restored then return false, "Profile import failed; restore the previous profiles manually" end
    return false, reason or "Profile import failed"
end

local function CommitModule(change)
    IO.lastNameplateReport = nil
    local ok, reason = Suite.Suite.SetMany(change.id, change.settings)
    if ok and change.chat then ok, reason = Suite.Suite.SetMany("chatComfort", change.chat) end
    if ok then ok, reason = IO.ApplyNameplateCVars(change.native) end
    if ok then ok, reason = IO.ApplyNameplateShared(change.shared) end
    if ok and change.native then IO.RememberNameplateCVars(nil, change.native) end
    local restore = change.restore
    if ok and restore then
        Suite.DB.nameplateCVars = Suite.CopyValue(restore.storedNative)
        Suite.DB.nameplateShared = Suite.CopyValue(restore.storedShared)
        Suite.DB.nameplateSharedPending = Suite.CopyValue(restore.pending)
        if Suite.DB.suite.moduleLooks then Suite.DB.suite.moduleLooks.nameplates = restore.look end
        Suite.Suite.Apply("nameplates")
    end
    return ok, reason
end

local function RestoreModule(change)
    local ran, restored = Suite.Dispatch(Suite.Finish, Suite.Suite.SetMany, change.id, change.before)
    local ok = ran and restored
    if change.beforeChat then
        ran, restored = Suite.Dispatch(Suite.Finish, Suite.Suite.SetMany, "chatComfort", change.beforeChat)
        ok = ok and ran and restored
    end
    if change.native or change.restore then
        ran, restored = Suite.Dispatch(Suite.Finish, IO.ApplyNameplateCVars, change.beforeNative)
        ok = ok and ran and restored
        Suite.DB.nameplateCVars = change.storedNative
    end
    Suite.DB.suite.moduleLooks = change.beforeLooks
    if change.shared or change.restore then
        ran, restored = Suite.Dispatch(Suite.Finish, Host.ApplyNameplateSettings, change.beforeShared)
        ok = ok and ran and restored
        Suite.DB.nameplateShared = change.storedShared
        Suite.DB.nameplateSharedPending = change.pendingShared
        local painted = Suite.Dispatch(Suite.Finish, Suite.Suite.Apply, "nameplates")
        ok = ok and painted
    end
    return ok == true
end

local function CaptureAndCommitModule(change)
    local _, sharedSnapshot = IO.CaptureNameplateShared()
    change.before = Suite.CopyValue(Suite.Suite.Config(change.id))
    change.beforeChat = change.chat and Suite.CopyValue(Suite.Suite.Config("chatComfort"))
    change.beforeLooks = Suite.CopyValue(Suite.DB.suite.moduleLooks)
    change.beforeNative = change.native and IO.CaptureNameplateCVars()
    change.storedNative = Suite.CopyValue(Suite.DB.nameplateCVars)
    change.beforeShared, change.storedShared = sharedSnapshot, Suite.CopyValue(Suite.DB.nameplateShared)
    change.pendingShared = Suite.DB.nameplateSharedPending
    change.captured = true
    return CommitModule(change)
end

local function ApplyModule(id, settings, chat, nameplateCVars, nameplateShared, restore)
    local checkpoint, checkpointWhy = Suite.ProfileWorkbenchBridge.Checkpoint("Before importing Suite settings")
    if not checkpoint then return false, checkpointWhy end
    local name = DB.GetActiveProfileName()
    local allowed, mutationReason = Suite.ProfileVariants.BeforeMutation(name)
    if not allowed then return false, mutationReason end
    local change = { id = id, settings = settings, chat = chat, native = nameplateCVars, shared = nameplateShared, restore = restore }
    local ran, ok, reason = Suite.Dispatch(Suite.Finish, CaptureAndCommitModule, change)
    if change.captured and (not ran or not ok) then
        local report = IO.lastNameplateReport
        local rollbackRan, restored = Suite.Dispatch(Suite.Finish, RestoreModule, change)
        IO.lastNameplateReport = report
        if not rollbackRan or not restored then reason = "Profile import failed; restore the previous profiles manually" end
    end
    Suite.Dispatch(Suite.ProfileVariants.AfterMutation, name)
    if ran and ok then IO.ReportNameplateImport() end
    return ran == true and ok == true, reason or (not ran and "Profile import failed" or nil)
end

function Profiles.RestoreNameplateSetup(snapshot)
    if Suite.InCombat() then return false, "Finish combat before restoring settings" end
    if snapshot.owner ~= Suite.DB or snapshot.profile ~= DB.GetActiveProfileName() then
        return false, "No previous nameplate setup is available"
    end
    return ApplyModule("nameplates", snapshot.settings, nil, snapshot.native, snapshot.shared, snapshot)
end

local function ReadSkin(skin, text)
    if not skin then return nil, "Skin engine unavailable" end
    return skin.ProfileIO.PrepareProfile(text)
end

function Profiles.ImportModule(text)
    if Suite.InCombat() then return false, "Finish combat before importing" end
    if IsSkin(text) then
        local skin = SkinEngine()
        local profile, reason = ReadSkin(skin, text)
        if not profile then return false, reason end
        return ApplySkin(skin, profile)
    end
    local id, settings, reason, chat, nameplateCVars, nameplateShared = IO.PrepareModuleProfile(text, true)
    if not id then return false, reason end
    return ApplyModule(id, settings, chat, nameplateCVars, nameplateShared)
end

local function CopySkin(skin)
    if not skin then return true end
    local profile = Suite.CopyValue(skin.Database.GetProfile(skin.Database.GetActiveProfileName()))
    if not profile then return false, "Skin profile unavailable" end
    return true, profile
end

local function MergeModule(profile, id, settings, chat, nameplateCVars, nameplateShared)
    if nameplateCVars then profile.nameplateCVars = nameplateCVars end
    if nameplateShared then profile.nameplateShared = IO.MergeNameplateShared(profile.nameplateShared, nameplateShared) end
    for key, value in pairs(settings) do profile.suite.modules[id][key] = value end
    if chat then
        for key, value in pairs(chat) do profile.suite.modules.chatComfort[key] = value end
    end
end

local function ExportFrames()
    local frames = Host.Profiles.Profiles_ExportSelectionToString("all")
    if type(frames) ~= "string" then return nil, "Frame profile export failed" end
    return frames
end

function Profiles.ImportModuleIntoNew(name, text)
    local clean, reason = Operations.NewName(name)
    if not clean then return false, reason end
    local id, settings, why, chat, nameplateCVars, nameplateShared, skinProfile
    if IsSkin(text) then
        skinProfile, why = ReadSkin(SkinEngine(), text)
        if not skinProfile then return false, why end
    else
        id, settings, why, chat, nameplateCVars, nameplateShared = IO.PrepareModuleProfile(text, true)
        if not id then return false, why end
    end
    local frames
    frames, why = ExportFrames()
    if not frames then return false, why end
    local profile
    profile, why = Operations.PrepareActive()
    if not profile then return false, why end
    if id then
        MergeModule(profile, id, settings, chat, nameplateCVars, nameplateShared)
        local copied
        copied, skinProfile = CopySkin(SkinEngine())
        if not copied then return false, skinProfile end
    end
    return Operations.Create(clean, frames, profile, skinProfile)
end

-- Jobs prepare private payloads. The final frame, Suite and Skin publication
-- is still one synchronous transaction, including the original rollback.
local Job = {}
Job.__index = Job
local applying

local function ReadSkinState(skin)
    if not skin then return end
    local db = skin.Database
    local name = db.GetActiveProfileName()
    return name, db.GetProfile(name), db.GetHistoryEpoch()
end

local function FrameImporter()
    return Host.Profiles.Profiles_ImportIntoNewProfile or Host.Profiles.Profiles_ImportExternal
end

local function CheckJob(job)
    if Suite.InCombat() then return false, "Finish combat before importing" end
    if Suite.suppressProfileSync then return false, "Profile import failed" end
    if Suite.RootDB ~= job.root or Suite.DB ~= job.activeSuite
        or DB.GetActiveProfileName() ~= job.suiteName or Host.ActiveFrameProfileName() ~= job.frameName
        or Host.CurrentFrameProfile() ~= job.activeFrames or Operations.PeekSkin() ~= job.skin then
        return false, "Profile import failed"
    end
    local name, profile, epoch = ReadSkinState(job.skin)
    if name ~= job.skinName or profile ~= job.activeSkin or epoch ~= job.skinEpoch
        or job.skinTarget and job.skin.Database.GetProfile(job.skinTarget) ~= job.skinTargetProfile then
        return false, "Profile import failed"
    end
    if job.name then
        if (job.kind == "bundle" and Host.Profiles.BeginImport ~= job.beginFrames) or FrameImporter() ~= job.importFrames then
            return false, "MSUF profile system unavailable"
        end
        local clean, reason = Operations.NewName(job.name)
        if not clean then return false, reason end
    end
    return true
end

local function Decode(job)
    if job.kind == "bundle" then
        local bundle, reason = BundleModules(job.text)
        if not bundle then return false, reason end
        job.bundle, job.profile, job.frames = bundle, bundle.profile, bundle.coreText
    elseif job.kind == "skin" then
        -- Loading an absent Skin engine can initialize its store. Keep that
        -- legacy fallback in the final phase, after the staleness checks.
        if not job.skin then return true end
        local profile, reason = ReadSkin(job.skin, job.text)
        if not profile then return false, reason end
        job.skinProfile = profile
    else
        local id, settings, reason, chat, nameplateCVars, nameplateShared = IO.PrepareModuleProfile(job.text, true)
        if not id then return false, reason end
        job.id, job.settings, job.chat, job.nameplateCVars = id, settings, chat, nameplateCVars
        job.nameplateShared = nameplateShared
    end
    return true
end

local function Validate(job)
    if job.skin and job.bundle.version ~= "2" then
        local ok, profile = BundleSkin(job.bundle, job.skin)
        if not ok then return false, profile end
        job.skinProfile = profile
    end
    return true
end

local function Stage(job)
    local hostJob = job.hostJob
    if not hostJob then
        if not job.beginFrames then return true end
        local reason
        hostJob, reason = job.beginFrames(job.frames, job.name)
        if not hostJob then return false, reason end
        job.hostJob = hostJob
    end
    if hostJob.completed < hostJob.total - 1 then
        local done, _, reason, stage = hostJob:Step()
        if done then return false, reason, stage end
        if hostJob.completed < hostJob.total - 1 then return true, nil, nil, true end
    end
    return true
end

local function Apply(job)
    local allowed, why = Suite.ProfileVariants.CanMutate()
    if not allowed then return false, why end
    local skin, skinProfile = job.skin, job.skinProfile
    if job.kind == "skin" and not skinProfile then
        skin = SkinEngine()
        skinProfile, why = ReadSkin(skin, job.text)
        if not skinProfile then return false, why end
    end
    if not job.name then
        if job.kind == "skin" then return ApplySkin(skin, skinProfile) end
        return ApplyModule(job.id, job.settings, job.chat, job.nameplateCVars, job.nameplateShared)
    end
    local profile, frames = job.profile, job.frames
    if job.bundle then
        ProtectNameplates(profile)
        if not skinProfile then
            local ok
            ok, skinProfile = BundleSkin(job.bundle, SkinEngine())
            if not ok then return false, skinProfile end
        end
    else
        -- A module-only import inherits the current setup. Read all inherited
        -- stores together: ordinary edits can keep the same table identity.
        frames, why = ExportFrames()
        if not frames then return false, why end
        profile, why = Operations.PrepareActive()
        if not profile then return false, why end
        if job.id then
            MergeModule(profile, job.id, job.settings, job.chat, job.nameplateCVars, job.nameplateShared)
            local ok
            ok, skinProfile = CopySkin(SkinEngine())
            if not ok then return false, skinProfile end
        end
    end
    return Operations.Create(job.name, frames, profile, skinProfile, nil, nil, job.hostJob)
end

local PHASES = {
    decode = Decode,
    validate = Validate,
    stage = Stage,
    apply = Apply,
}
local BUNDLE_PHASES = { "decode", "validate", "stage", "apply" }
local MODULE_PHASES = { "decode", "apply" }

local function RunPhase(job)
    local allowed, reason = CheckJob(job)
    if not allowed then return false, reason end
    return PHASES[job.phase](job)
end

function Job:Step()
    if self.done then return true, self.ok, self.reason, self.stage end
    if self.running or applying then return false end
    self.running = true
    if self.phase == "apply" then applying = self end
    local ran, ok, reason, stage, pending = Suite.Dispatch(Suite.Finish, RunPhase, self)
    if applying == self then applying = nil end
    self.running = nil
    if ran and ok and pending then return false end
    if ran and ok then
        self.completed = self.completed + 1
        if self.completed < self.total then
            self.phase = self.phases[self.completed + 1]
            return false
        end
    end
    self.done, self.ok, self.reason, self.stage = true, ran == true and ok == true, reason, stage
    if not self.ok and not self.reason then self.reason = "Profile import failed" end
    self.text, self.frames, self.bundle, self.profile, self.hostJob = nil, nil, nil, nil, nil
    self.settings, self.chat, self.skinProfile = nil, nil, nil
    self.root, self.activeSuite, self.activeFrames, self.activeSkin, self.skin = nil, nil, nil, nil, nil
    self.beginFrames, self.importFrames, self.skinTargetProfile, self.nameplateCVars = nil, nil, nil, nil
    self.nameplateShared = nil
    return true, self.ok, self.reason, self.stage
end

function Profiles.BeginImport(text, name)
    if Suite.InCombat() then return nil, "Finish combat before importing" end
    if not Suite.RootDB then return nil, "MSUF profile system unavailable" end
    if type(text) ~= "string" or #text > Profiles.maxBytes then return nil, "Invalid suite profile" end
    local kind = text:match("^%s*MSUFS[123]:") and "bundle" or IsSkin(text) and "skin" or "module"
    if name ~= nil then
        local reason
        name, reason = Operations.NewName(name)
        if not name then return nil, reason end
    elseif kind == "bundle" then
        return nil, "Enter a new profile name"
    end
    local skin = Operations.PeekSkin()
    local skinName, activeSkin, skinEpoch = ReadSkinState(skin)
    local frameName = Host.ActiveFrameProfileName()
    local skinTarget = kind == "skin" and not name and skin and frameName ~= skinName and frameName
    local phases = kind == "bundle" and BUNDLE_PHASES or MODULE_PHASES
    return setmetatable({
        text = text, name = name, kind = kind, phases = phases, completed = 0, total = #phases, phase = phases[1],
        root = Suite.RootDB, activeSuite = Suite.DB, suiteName = DB.GetActiveProfileName(),
        frameName = frameName, activeFrames = Host.CurrentFrameProfile(),
        beginFrames = kind == "bundle" and Host.Profiles.BeginImport or nil, importFrames = name and FrameImporter(),
        skin = skin, skinName = skinName, activeSkin = activeSkin, skinEpoch = skinEpoch,
        skinTarget = skinTarget, skinTargetProfile = skinTarget and skin.Database.GetProfile(skinTarget),
    }, Job)
end
