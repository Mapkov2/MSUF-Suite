local _, NS = ...

local Safety = NS.Safety
local Field = Safety.Field
local Read = Safety.Read
local Public = Safety.Public
local Dispatch = Safety.Dispatch
local ColorMatches = Safety.ColorMatches
local COLOR_OWN = Safety.COLOR_OWN

-- Shared helpers for the Blizzard window adapters. This file loads before
-- every adapter that uses them (see the TOC). Visual helpers take the
-- adapter's skin context: { owner = cosmetic/control owner key, surfaces =
-- optional weak set of surfaces to hide on disable }. They only act outside
-- combat, skip forbidden and protected targets, and never replace Blizzard
-- code. Adapters own implicitly protected Blizzard trees outside combat, so
-- every spec passed here is marked allowImplicitProtected.
local AdapterKit = {}
NS.AdapterKit = AdapterKit

local WEAK_KEYS = { __mode = "k" }

function AdapterKit.WeakSet()
    return setmetatable({}, WEAK_KEYS)
end

local function Finish(callback, ...)
    return true, callback(...)
end

-- Runs callback(...) as its own error boundary (Safety.Dispatch): an error
-- is reported to the error handler and the caller goes on. Returns true and
-- the callback's results, or nil when the callback raised.
function AdapterKit.Isolate(callback, ...)
    return Dispatch(Finish, callback, ...)
end

-- value, or nil when it is secret.
local function PublicValue(value)
    if Public(value) then return value end
    return nil
end
AdapterKit.PublicValue = PublicValue

local function PublicValues(first, second, third, fourth, fifth)
    return PublicValue(first), PublicValue(second), PublicValue(third),
        PublicValue(fourth), PublicValue(fifth)
end

-- Up to five results of a Blizzard function called with valid arguments.
-- Each secret result reads as nil; nil when fn is missing on this client.
function AdapterKit.ReadValues(fn, ...)
    if type(fn) ~= "function" then return nil end
    return PublicValues(fn(...))
end

-- Look changes can change what a skin pass produces. Caches of objects that
-- were already skinned compare against this generation. Color changes only
-- repaint existing surfaces and keep it.
local skinGeneration = 1
local SKIN_DOMAINS = { theme = true, appearance = true, geometry = true, profile = true }
local generationOwner = {}
local generationListening = false

local function OnSkinDomainChanged(_, domain)
    if SKIN_DOMAINS[domain] then skinGeneration = skinGeneration + 1 end
end

function AdapterKit.SkinGeneration()
    if not generationListening then
        generationListening = true
        NS.Registry.AddListener(generationOwner, OnSkinDomainChanged)
    end
    return skinGeneration
end

-- Follows a parentKey chain; nil as soon as one link is missing.
function AdapterKit.Path(object, ...)
    for index = 1, select("#", ...) do
        object = Field(object, (select(index, ...)))
        if not object then return nil end
    end
    return object
end

-- Same as Path for a key list stored as data.
function AdapterKit.PathOf(object, keys)
    for index = 1, #keys do
        object = Field(object, keys[index])
        if not object then return nil end
    end
    return object
end

-- True when every listed member is present: an exact template contract.
function AdapterKit.HasFields(object, fields)
    for index = 1, #fields do
        if not Field(object, fields[index]) then return false end
    end
    return true
end

function AdapterKit.ObjectType(object)
    local objectType = Read(object, "GetObjectType")
    return type(objectType) == "string" and objectType or nil
end

function AdapterKit.IsShown(region)
    return Read(region, "IsShown") == true
end

-- A secret parent reads as nil: it is never compared.
function AdapterKit.ParentIs(frame, parent)
    return parent ~= nil and Read(frame, "GetParent") == parent
end

function AdapterKit.IsDescendantOf(frame, ancestor, maxDepth)
    if not frame or not ancestor then return false end
    local current = frame
    for _ = 1, maxDepth or 12 do
        if current == ancestor then return true end
        local parent = Read(current, "GetParent")
        if not parent or parent == current then return false end
        current = parent
    end
    return current == ancestor
end

local function VisitValues(callback, a, b, c, ...)
    for index = 1, select("#", ...) do
        callback((select(index, ...)), a, b, c)
    end
end

-- callback(region, a, b, c) for each direct region, without a result table.
function AdapterKit.ForEachRegion(frame, callback, a, b, c)
    if Safety.IsForbidden(frame) or type((Field(frame, "GetRegions"))) ~= "function" then return end
    VisitValues(callback, a, b, c, frame:GetRegions())
end

-- callback(object, a, b) for at most limit active objects of a Blizzard pool.
function AdapterKit.ForEachActive(pool, limit, callback, a, b)
    if type((Field(pool, "EnumerateActive"))) ~= "function" then return 0 end
    local count = 0
    for object in pool:EnumerateActive() do
        if count >= limit then break end
        count = count + 1
        callback(object, a, b)
    end
    return count
end

-- Registers callback(owner, row) for initialized rows: the event fires after
-- Blizzard's row initializer, for new and for recycled rows. Returns the event
-- name needed for unregistration, or nil when the ScrollBox cannot register.
function AdapterKit.RegisterRowCallback(scrollBox, callback, owner)
    if Safety.IsForbidden(scrollBox) or type((Field(scrollBox, "RegisterCallback"))) ~= "function" then
        return nil
    end
    local event = ScrollBoxListMixin.Event.OnInitializedFrame
    scrollBox:RegisterCallback(event, callback, owner)
    return event
end

function AdapterKit.UnregisterRowCallback(scrollBox, event, owner)
    if type(event) == "string" and owner ~= nil
        and Safety.Invoke(scrollBox, "UnregisterCallback", event, owner) then
        return true
    end
    return false
end

-- ScrollBox:ForEachFrame indexes its view, which exists only after Blizzard
-- initialized the list. Paged content frames have no view and are always ready.
function AdapterKit.ForEachRow(scrollBox, callback)
    if Safety.IsForbidden(scrollBox) or type((Field(scrollBox, "ForEachFrame"))) ~= "function" then
        return false
    end
    if type(scrollBox.HasView) == "function" and scrollBox:HasView() ~= true then return false end
    scrollBox:ForEachFrame(callback)
    return true
end

-- hooksecurefunc raises when the hooked member is not a function, so both
-- helpers check first. A missing target (mixin not loaded) hooks nothing.
function AdapterKit.HookFunction(target, method, callback)
    if type((Field(target, method))) ~= "function" then return false end
    hooksecurefunc(target, method, callback)
    return true
end

function AdapterKit.HookGlobal(name, callback)
    if type(_G[name]) ~= "function" then return false end
    hooksecurefunc(name, callback)
    return true
end

function AdapterKit.CancelDeferred(state)
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
        state.deferred[key] = nil
    end
end

local function CanPaint(target)
    return type(target) == "table" and not NS.IsCombatLocked() and Safety.CanDecorate(target, true)
end

local function CanCreateRegions(target)
    return type(target) == "table" and not NS.IsCombatLocked()
        and Safety.CanCreateRegions(target, true)
end

function AdapterKit.Fade(context, region)
    return CanPaint(region) and NS.Cosmetics.Fade(region, context.owner) == true
end

function AdapterKit.FadeFields(context, target, fields)
    for index = 1, #fields do
        AdapterKit.Fade(context, Field(target, fields[index]))
    end
end

-- Fades the nine standard pieces stored directly on nineSlice.
function AdapterKit.FadeNineSlice(context, nineSlice)
    if not CanPaint(nineSlice) then return false end
    NS.Cosmetics.FadeNineSlice(nineSlice, context.owner)
    return true
end

-- Zero vertex alpha survives Blizzard's own region-alpha animations.
function AdapterKit.SuppressVertexAlpha(context, region)
    return CanPaint(region) and NS.Cosmetics.SuppressVertexAlpha(region, context.owner) == true
end

local function IsSurfaceTexture(surface, region)
    return surface ~= nil and (region == surface.fill or region == surface.edge
        or region == surface.depth or region == surface.highlight
        or region == surface.pushed or region == surface.disabled)
end

local function FadeTextureRegion(region, context, exception, surface)
    if region ~= exception and not IsSurfaceTexture(surface, region)
        and AdapterKit.ObjectType(region) == "Texture" then
        AdapterKit.Fade(context, region)
    end
end

-- Fades every direct Texture region of an exact, verified decorative frame
-- except one semantic exception.
function AdapterKit.FadeTextures(context, frame, exception)
    AdapterKit.ForEachRegion(frame, FadeTextureRegion, context, exception, nil)
end

-- Same, but keeps the textures of the frame's own MapkoSkin surface.
function AdapterKit.FadeNativeTextures(context, frame)
    AdapterKit.ForEachRegion(frame, FadeTextureRegion, context, nil, NS.Registry.GetSurface(frame))
end

local function FadeAtlasRegion(region, context, atlas)
    if Read(region, "GetAtlas") == atlas then AdapterKit.Fade(context, region) end
end

function AdapterKit.FadeAtlas(context, frame, atlas)
    AdapterKit.ForEachRegion(frame, FadeAtlasRegion, context, atlas)
end

local function Track(context, target)
    local surfaces = context.surfaces
    if surfaces then surfaces[target] = true end
end

-- Surface keeps a reference to spec: pass tables that are not changed later.
function AdapterKit.Attach(context, target, spec)
    if not CanCreateRegions(target) then return false end
    spec.allowImplicitProtected = true
    local surface = NS.Surface.Attach(target, spec)
    if not surface then return false end
    Track(context, target)
    return true, surface
end

-- ControlSkin copies spec. method defaults to ApplyButton; other values are
-- ApplyTab, ApplySearchBox and ApplyThreeSliceButton.
function AdapterKit.SkinControl(context, control, spec, method)
    if not CanCreateRegions(control) then return false end
    spec.allowImplicitProtected = true
    if not NS.ControlSkin[method or "ApplyButton"](control, context.owner, spec) then return false end
    Track(context, control)
    return true
end

-- IconSkin reads its spec only during the call, so one scratch spec serves
-- every item button without a table per button.
local itemIconSpec = {}

function AdapterKit.SkinItemIcon(button, owner, icon, nativeBorder, allowImplicitProtected)
    itemIconSpec.icon = icon
    itemIconSpec.nativeBorder = nativeBorder
    itemIconSpec.allowImplicitProtected = allowImplicitProtected == true
    local state = NS.IconSkin.Apply(button, owner, itemIconSpec)
    itemIconSpec.icon = nil
    itemIconSpec.nativeBorder = nil
    return state ~= nil
end

function AdapterKit.HideSurfaces(context)
    for target in pairs(context.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
end

-- A surface spec built once at load. Unset flags keep Surface's defaults:
-- no list-item transparency, no forced edge and a visible fill.
function AdapterKit.SurfaceSpec(role, radius, inset, listItem, forceEdge, fillVisible)
    return {
        role = role,
        radius = radius,
        inset = inset or 0,
        listItem = listItem == true,
        forceEdge = forceEdge == true,
        fillVisible = fillVisible ~= false,
        allowImplicitProtected = true,
    }
end

local SELECTION_INDICATOR_SPEC = AdapterKit.SurfaceSpec("navigationActive", 8, 2, true, true)

-- An owned, mouse-transparent frame over a navigation button, parented to
-- the content panel Blizzard shows while that button is selected. Panel
-- visibility then mirrors the selection without a hook, timer or polling;
-- the transparent center keeps the native icon and label readable.
-- matchLevel also copies the button's strata and level. The indicator is
-- created, reparented and anchored here, so this runs outside combat only.
function AdapterKit.SelectionIndicator(context, indicators, button, panel, matchLevel)
    if NS.IsCombatLocked() or not button or not panel or not Safety.CanDecorate(panel, true) then
        return false
    end
    local indicator = indicators[button]
    if not indicator then
        indicator = CreateFrame("Frame", nil, panel)
        indicators[button] = indicator
    end
    indicator:SetParent(panel)
    indicator:ClearAllPoints()
    indicator:SetAllPoints(button)
    if matchLevel then
        local strata = Read(button, "GetFrameStrata")
        if type(strata) == "string" then indicator:SetFrameStrata(strata) end
        local level = Read(button, "GetFrameLevel")
        if type(level) == "number" then indicator:SetFrameLevel(level) end
    end
    indicator:EnableMouse(false)
    indicator:Show()
    if AdapterKit.Attach(context, indicator, SELECTION_INDICATOR_SPEC) then return true end
    indicator:Hide()
    return false
end

function AdapterKit.HideIndicators(indicators)
    for _, indicator in pairs(indicators) do
        indicator:Hide()
    end
end

-- Reversible theme text colors. roles holds the font objects this set
-- currently themes. The native color is captured when a font object is
-- claimed, or again with recapture when Blizzard repainted the text since our
-- last paint, and is restored only while our color is still installed. A
-- forgotten font object keeps its two color tables for its next claim, so
-- rows that alternate between meaningful and plain colors allocate nothing.
function AdapterKit.NewTextColors()
    return {
        originals = AdapterKit.WeakSet(),
        roles = AdapterKit.WeakSet(),
        installed = AdapterKit.WeakSet(),
    }
end

local function InstallTextColor(colors, fontObject, role)
    local installed = colors.installed[fontObject]
    if not installed then
        installed = {}
        colors.installed[fontObject] = installed
    end
    installed[1], installed[2], installed[3], installed[4] = NS.Theme.GetColor(role)
    installed[4] = installed[4] or 1
    fontObject:SetTextColor(installed[1], installed[2], installed[3], installed[4])
end

-- An unreadable native color is stored as missing and never restored.
local function CaptureOriginal(colors, fontObject, r, g, b, a)
    local original = colors.originals[fontObject]
    if not original then
        if r then colors.originals[fontObject] = { r, g, b, a } end
    elseif r then
        original[1], original[2], original[3], original[4] = r, g, b, a
    else
        original[1] = nil
    end
end

local function HasOriginal(colors, fontObject)
    local original = colors.originals[fontObject]
    return original ~= nil and original[1] ~= nil
end

function AdapterKit.SetTextColor(colors, fontObject, role, recapture)
    if Safety.IsForbidden(fontObject) or type((Field(fontObject, "SetTextColor"))) ~= "function" then
        return false
    end
    local r, g, b, a = Safety.ReadColor(fontObject, "GetTextColor")
    if not colors.roles[fontObject] or not HasOriginal(colors, fontObject) then
        CaptureOriginal(colors, fontObject, r, g, b, a)
    elseif recapture and r and not ColorMatches(colors.installed[fontObject], r, g, b, a, COLOR_OWN) then
        CaptureOriginal(colors, fontObject, r, g, b, a)
    end
    colors.roles[fontObject] = role
    InstallTextColor(colors, fontObject, role)
    return true
end

-- True while fontObject is themed by this set and still shows its color.
function AdapterKit.ShowsTextColor(colors, fontObject, r, g, b, a)
    return colors.roles[fontObject] ~= nil
        and ColorMatches(colors.installed[fontObject], r, g, b, a, COLOR_OWN)
end

-- Forgets fontObject without touching it: Blizzard has since painted a color
-- of its own, which stays and is not restored on disable.
function AdapterKit.ForgetTextColor(colors, fontObject)
    colors.roles[fontObject] = nil
end

function AdapterKit.RefreshTextColors(colors)
    for fontObject, role in pairs(colors.roles) do
        InstallTextColor(colors, fontObject, role)
    end
end

function AdapterKit.RestoreTextColors(colors)
    for fontObject in pairs(colors.roles) do
        local original = colors.originals[fontObject]
        local r, g, b, a = Safety.ReadColor(fontObject, "GetTextColor")
        if HasOriginal(colors, fontObject)
            and ColorMatches(colors.installed[fontObject], r, g, b, a, COLOR_OWN) then
            fontObject:SetTextColor(original[1], original[2], original[3], original[4])
        end
    end
    colors.originals = AdapterKit.WeakSet()
    colors.roles = AdapterKit.WeakSet()
    colors.installed = AdapterKit.WeakSet()
end

local SEARCH_BOX_SPEC = { role = "input", useControlShape = true, pillHeight = 28, inset = 1 }

-- The search box look of the purpose-built windows (EncounterJournal,
-- PlayerSpells): the input control, its text and its placeholder text, in
-- the reversible colors of context.textColors.
function AdapterKit.SkinSearchBox(context, searchBox)
    if not searchBox or not Safety.CanCreateRegions(searchBox, true) then return end
    AdapterKit.SkinControl(context, searchBox, SEARCH_BOX_SPEC, "ApplySearchBox")
    AdapterKit.SetTextColor(context.textColors, searchBox, "text")
    AdapterKit.SetTextColor(context.textColors, Field(searchBox, "Instructions"), "muted")
end

return AdapterKit
