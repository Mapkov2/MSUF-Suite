local _, P = ...
-- The module's runtime state (TOC order: Data, State, then its users).
local R = P.BuffReminders
-- Every runtime field of the module, one table per concern. The module
-- runtime sets config, context, active and id itself; nothing else is kept
-- on the module table. A field is nil until its file first sets it.
R.STATE = {
    -- Event registration (Controller). suspended: in combat every listener
    -- but PLAYER_REGEN_ENABLED is released. aura: the UNIT_AURA registration
    -- ("group", "player" or false); weapon: the weapon events are registered.
    listen = { "suspended", "aura", "weapon" },
    -- The reminder list and its evaluation (Controller, Entries). entries:
    -- the compiled list; poisonStates: one record per Rogue poison group;
    -- hasAura, hasFood and hasWeapon: the event groups the list needs;
    -- needsFullRefresh: the next evaluation re-reads every entry;
    -- countsDirty: the item counts are read again; thresholdTimer and
    -- thresholdAt: the pending advance warning and its deadline.
    list = { "entries", "poisonStates", "hasAura", "hasFood", "hasWeapon", "needsFullRefresh",
        "countsDirty", "thresholdTimer", "thresholdAt" },
    -- The secure frames (Controller, Alerts, Cursor). host and its buttons;
    -- preview: the Edit Mode label, previewShown its shown state, previewing
    -- while Edit Mode shows every entry; mask: the bit mask of the shown
    -- buttons (nil repaints); layout: the layout settings applied last;
    -- newAlert: a newly shown reminder still owes its sound.
    view = { "host", "buttons", "preview", "previewShown", "previewing", "mask", "layout", "newAlert" },
    -- Following the cursor (Cursor): the OnUpdate driver (it runs while the
    -- host follows) and whether the host left its saved anchor.
    cursor = { "driver", "displaced" },
    -- The known food auras (Readers): ids holds one snapshot per aura
    -- instance; known is nil until a rescan, false while unreadable;
    -- scanKeys is the rescan's reused key list.
    food = { "ids", "known", "scanKeys" },
    -- The automatic consumable picks of the last compile (Entries): the
    -- flask, rune, oil and food picked (false for none), whether the map
    -- potion was in the bags, the last food eaten from the bags and whether
    -- the player stood on a potion map.
    stock = { "flask", "rune", "oil", "food", "potion", "lastFood", "onPotionMap" },
    -- The group (Group). settings: the group options of the last roster
    -- read; buffers: the two roster buffers; units and unitList: the member
    -- set and the member events' unit filter ("player" first); classes: the
    -- classes in the group; listChanged: the member events need the new
    -- list; presence: the group buff per member; soulstonePresence,
    -- beaconLightPresence and beaconFaithPresence: the player's own aura per
    -- member, with soulstoneKnown, beaconLightKnown and beaconFaithKnown;
    -- dirty, rosterDirty, flush and flushPending: the coalesced member pass.
    group = { "settings", "buffers", "units", "unitList", "classes", "listChanged", "presence",
        "soulstonePresence", "beaconLightPresence", "beaconFaithPresence", "soulstoneKnown",
        "beaconLightKnown", "beaconFaithKnown", "dirty", "rosterDirty", "flush", "flushPending" },
    -- The notice lines below the buttons (Special, Group): one field per
    -- notice (Special's NOTICES), the shown set (mask), its text and label, the
    -- summon that may teach a demon look (summonDemon, summonAt, summonPet).
    notices = { "petPassive", "healthstoneMissing", "soulstoneMissing", "beaconMissing", "wrongDemon",
        "mask", "text", "label", "summonDemon", "summonAt", "summonPet" },
    -- Where the player is (Preparation): the instance type (false while
    -- unreadable), the content setting key, whether a keystone has not
    -- started yet (preKey), the keystone's time limit and whether it started.
    environment = { "instanceType", "key", "preKey", "keystoneSeconds", "challengeStarted" },
    -- The ready check mana note (Preparation): its hide timer and label.
    readyCheck = { "timer", "label" },
}

-- Gives an owner (the module, or a test's owner) one empty table per concern.
function R.NewState(owner)
    for concern in pairs(R.STATE) do owner[concern] = {} end
    return owner
end
