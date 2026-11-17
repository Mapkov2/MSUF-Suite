# Addon window skinning

Users open the Suite's **Skinning** page and select the **Addon skins** tab, then
enable **Skin other addons**. In German: **Oberflächengestaltung > Addon-Skins >
Andere Addons skinnen**.
The feature starts disabled. Each of the 22 supported addons and AceGUI/AceConfig
has its own switch. Installed addons are detected without loading them. These
integrations decorate windows; their data, saved settings and input remain owned
by the addon. Protected, forbidden and compositor-managed targets are skipped.
Native addon pages inherit the Blizzard Settings skin when it is enabled;
their addon switch supplies category-specific styling when that adapter is off.

The built-in catalog covers BugSack, Camping Kit, Dialogue UI, DoesItDie, Dungeon
Journal (ForeverDungeonJournal), Forever Fishing, Forever Leveling BiS, Journey
Guides, Keep or Toss, LayerSwap, LootTriage, OneForAll, OpenMap, Polestar, Questie,
RareScanner, Shortest Path Forever, Spoken, Total RP 3, TrueshotLodge, RestedXP and Enhance QoL.
Availability depends on the installed addon's client support and version.

Spoken includes its classic, minimal and Dialogue UI players, settings,
compendium, contribution dialogs and menus. Player construction is observed
even when narration starts automatically. Portraits, models, audio playback,
native input and the addon's own update scripts remain owned by Spoken.
Its Dialogue UI player retains its native parchment geometry with Suite colors
and fonts. That variant uses no shared animated surfaces: changes and restore
wait until Spoken releases its own framebuffer.
The Compendium's parchment, marble insets and scroll-edge strips use Suite panels
and readable text; story pictures, portraits and quest symbols remain visible.

RestedXP includes its legacy guide shell, V2 guide widget, menus and AceConfig
settings. Newly pooled V2 content requests one coalesced root pass. Its implicitly
protected shell is decorated only outside combat; explicit secure item/quest
buttons retain their native scripts, attributes and artwork.
V2 guide banners, custom background/border groups and pooled floating active-step
windows use the same skin. Enhance QoL's Config Center also follows its switch,
including content rebuilt by LibSettingsDesigner.
The shared LibSettingsDesigner adapter observes the library's own `Open` edge
for supported addon namespaces, including compartment, keybinding and Settings
launches. It replaces decorative shell images, texture styles and legacy panels
from the Suite; addon files, values, icons, color swatches and input stay owned by
the addon. Native background-alpha writes refresh the restoration snapshot,
including a deliberate zero, without polling or following ordinary value updates.

Built-in discovery runs at login, enable and exact addon launchers such as slash,
broker and compartment callbacks. Ordinary mouse clicks do not scan the UI.
Unchanged window shows reuse the applied skin. RXP pooled widgets receive one
construction pass; ordinary guide updates do not repaint the guide window.
Disabling the addon skin invalidates those construction records so reused pool
objects regain their skin after enabling it again. No idle ticker is added.
Existing RXP widget collections are caught up once after enable or a native theme
rebuild, including fonts and controls beyond the initial tree budget. A pooled
window's actual acquisition refreshes its rebuilt controls; plain shows stay clean.

## Cooperative integrations (API 2.3)

Addons can supply their own exact targets through the versioned public API.
Declare `MSUF_Suite_Skin` as an optional dependency, and register after it loads.
Existing API 2.0â€“2.2 integrations remain compatible. Cooperative integrations
follow the main skin enable setting, as in previous API versions.
For a supported builtin addon, cooperative registration takes priority over its
automatic adapter. Unregistering returns the visible windows to that adapter.

```lua
local provider = _G.MapkoSkin
local api = provider and provider.GetAPI(2, 3)
if not api then return end
local skin = api:RegisterAddon("MyAddon", { integrationVersion = 1 })
if not skin then return end

local accepted, reason, count = skin:SkinBatch({
    { kind = "frame", target = MyWindow, options = { role = "shell" } },
    { kind = "button", target = MyWindow.SaveButton },
    { kind = "input", target = MyWindow.SearchBox },
    { kind = "label", target = MyWindow.Title },
    { kind = "fade", target = MyWindow.BackgroundTexture },
    { kind = "menu", target = MyWindow },
})
```

`SkinBatch` accepts a plain, dense array of at most 256 explicit entries. Kinds:
`frame`, `button`, `tab`, `input`, `label`, `icon`, `menu`, `fade`. Options are the
same as the corresponding individual API method; `menu` accepts the existing
boolean `contentOnly` option. Shape errors accept zero entries. A target rejected
by the existing safety/ownership checks stops the batch and returns the count of
previously accepted entries. This is intentionally not an atomic transaction.

Call once on construction or pool acquisition, and for newly created controls.
Requests for the same target coalesce into the existing render queue. The API
does no discovery, subtree traversal, polling or callbacks into addon code.
Theme changes and combat deferral use the existing centralized lifecycle.
For large interfaces split construction into batches of up to 256 targets.
Never call from an `OnUpdate` or a frequent combat event.

Use `skin:Release(target)` when returning a pooled object; `skin:ReleaseAll()`
releases the current targets while keeping registration reusable. Use
`skin:Unregister()` at integration shutdown. Release before another window claims
the same pooled control. Keep semantic art, item colors and layout in your addon;
submit only the decorative regions you want hidden with `fade`.

The existing individual methods, capabilities, `GetColor`, `GetFont`, `GetLook`,
`SkinWindowAction`, scoped release and explicit content animation remain available.
This path avoids the built-in window discovery needed by noncooperative addons.

## Verification boundary

Source/API contracts cover both supported client families. Native appearance,
combat/taint behavior and CPU/allocation measurements require in-game acceptance.
