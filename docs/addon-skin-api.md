# Addon window skinning

The **Addon skins** tab on the Suite’s **Skinning** page has two switches.
**Skin registered addons** is enabled by default for addons that supply their
own integration. **Skin other addons** enables automatic styling and starts
disabled. Each of the 23 supported addons and AceGUI/AceConfig has its own switch. Installed addons are detected without loading them. These
integrations decorate windows; their data, saved settings and input remain owned
by the addon. Protected, forbidden and compositor-managed targets are skipped.
Native addon pages inherit the Blizzard Settings skin when it is enabled;
their addon switch supplies category-specific styling when that adapter is off.

The built-in catalog covers BugSack, Camping Kit, Dialogue UI, DoesItDie, Dungeon
Journal (ForeverDungeonJournal), Forever Fishing, Forever Leveling BiS, Journey
Guides, Keep or Toss, LayerSwap, LootTriage, OneForAll, OpenMap, Polestar, Questie,
RareScanner, Shortest Path Forever, Spoken, Total RP 3, TrueshotLodge, RestedXP,
Enhance QoL and Numy's AddonProfiler (`!!AddonProfiler`).
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
AddonProfiler includes its main window, native list controls and separate pinned
addon display. Only UI construction, opening and pin additions are observed;
profiling, data refresh and pooled value updates receive no Suite callbacks.
New FontStrings in its standalone rows are styled at construction.

Explicit close buttons retain their role through generic and AceGUI passes.
The close X has its own style under **Window buttons and icon borders > Close X
style** and starts with the Suite's Bare glyph, including existing profiles whose
other window buttons use Native. Choosing Native for the close X restores its
original artwork; Global follows the other window buttons. Custom styles suppress
the original X, extra borders
and backdrop pieces reversibly. The subsequent backdrop pass preserves the
chosen window-action surface.
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

## MSUF Suite Skinning API 2.6

The `MSUF_Suite_Skin` module provides the versioned skinning API for addons such as BetterFriendlist.
Declare `MSUF_Suite_Skin` as an optional dependency and register after the module loads.
The Suite publishes the API under the historical Lua global `_G.MapkoSkin`. The standalone
MapkoSkin addon also uses this name. Check `addonName` to select the Suite provider.
**Enable Skinning** is the master switch. **Skin registered addons** is on by
default and controls integrations such as BetterFriendlist. **Skin Blizzard
windows** controls native windows. **Skin other addons** controls the Suite's
automatic adapters. When a supported addon registers and cooperative skinning
is enabled, it takes precedence over its automatic adapter. Releasing that
registration or disabling registered skins returns control to the enabled adapter.
Older 2.x integrations can request their existing minimum version.

```lua
local provider = _G.MapkoSkin
if type(provider) ~= "table" or provider.addonName ~= "MSUF_Suite_Skin"
    or type(provider.GetAPI) ~= "function" then return end
local api = provider.GetAPI(2, 5)
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
`frame`, `button`, `tab`, `input`, `label`, `icon`, `menu`, `fade`, `dropdown`,
`checkButton`, `slider`, `scrollBar`, `window`, and `windowAction`. A window action
entry also supplies `action`, for example `"close"`. Options are the
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

### Controls and window actions

| Method | Targets and options |
| --- | --- |
| `SkinDropdown(trigger, options)` | Styles the trigger surface, text and arrow during hover, press, menu open and disable. `WowStyle1FilterDropdownTemplate` receives a separate down arrow because its original glyph is part of the background. An explicit `arrow` takes precedence. For a custom trigger, supply its `trigger`, `label` or `arrow` child. |
| `SkinCheckButton(button, options)` | Colors native check and radio indicators, including the disabled checked texture. A custom control may supply `indicator` and `label`. |
| `SkinSlider(slider, options)` | Styles a Slider or a `MinimalSliderWithSteppersTemplate` wrapper, including its built-in stepper textures and their individual disabled states. Optional `track`, `thumb`, `back` and `forward` identify authored parts. `backArt` and `forwardArt` can identify custom textures on their respective stepper buttons. |
| `SkinScrollBar(bar, options)` | Styles native Minimal and WowTrim bars, including the track, thumb and both steppers. Slider-based scrollbars accept the slider options. |
| `SkinWindowAction(button, action, options)` | Actions include `close`, `minimize`, `maximize`, `restore`, `expand` and `collapse`. Expand/collapse can request a `direction` of `left`, `right`, `up` or `down`. An explicit direction selects the chevron in the configured weight and colors. Native style retains the supplied art. |
| `RegisterWindow(frame, options)` | Opts an addon-owned top-level window into individual caption controls. `closeButton` supplies the caller's close button. `minimize` and `maximize` each opt in independently. The optional `title` labels the restore tab. Set `showOnRelease = false` to leave a minimized frame hidden when its controls are removed. |

Supply only regions belonging to the submitted control. The caller owns input,
selected values, visibility and labels. Releasing a target restores its adopted
art where it is still owned. An explicit `SkinTab(tab, { active = false })`
overrides native selection from the first paint.

```lua
skin:SkinWindowAction(preview.DockButton, "collapse", { direction = "left" })
skin:SkinWindowAction(settings.CloseButton, "close", { appearance = "caption" })
skin:RegisterWindow(friends, {
    closeButton = friends.CloseButton, minimize = true, maximize = true,
    title = "BetterFriendlist", minScale = 0.8, maxScale = 1.25, showOnRelease = false,
})
```

The caption appearance uses the Suite title-bar glyphs and hover, pressed and
disabled colors. The supplied button keeps its own hit area, anchors and
`OnClick`. Registering a window uses the caption appearance on its close button
while the Suite's window controls are enabled. Minimizing exposes a restore
tab. Maximizing fits to available screen space within the scale limits.
Restoring reinstates the previous scale and anchors. Combat locks these
actions. `Release(frame)` removes the registration and restores any fitted
geometry. By default a minimized window is shown when its controls are
released, including when a Suite setting removes the controls.

`GetWindowState(frame)` returns a snapshot with `fitted` and `minimized`.
Both flags can be true. Position savers, including `OnHide` handlers, should
skip saving temporary geometry while `fitted` is true.

`RestoreWindowGeometry(frame)` restores anchors and scale synchronously while
preserving visibility and minimization. Call it before changing the frame's
position, scale or size. It returns `true, "restored"` or `true, "normal"` on
success. If it returns `false, "combat"`, retry after combat before writing
geometry. An anchor error returns `false, "geometry-failed"` and keeps the
original geometry available for another restore attempt. Both methods only
operate on windows registered to the calling scope.
Use the `windowGeometry` capability to discover these methods.

With `windowFitBounds`, `RegisterWindow` takes two additional options for
`maximize = true`.

- `fitInsets` reserves space for controls extending beyond the frame. Values
  are distances in the frame's local units and scale with it. Supply any of
  `left`, `right`, `top` and `bottom`. Omitted edges are zero.
- `fitRect` chooses the available rectangle in `UIParent` units measured from
  its bottom-left corner. Supply all four edges. The Suite clips this rectangle
  to the current viewport. Omitting the rectangle uses the usual eight-unit
  screen margin.

The Suite centers the frame together with its reserved space. If the rectangle
is empty or the available space would require a scale below `minScale` (or
the Suite default), the maximize click keeps the current geometry. The fit
uses a copy of the option values. To update them, restore the window and
register it again with the new bounds.

```lua
local options = { minimize = true, maximize = true, showOnRelease = false }
if api:HasCapability("windowFitBounds") then
    options.fitInsets = { left = 44 } -- Modern side tabs
end
skin:RegisterWindow(friends, options)
```

### Handing off fallback artwork

`GetTargetStatus(target)` reads the last operation on that scope in constant
time. Hide a separate fallback only for `applied`. Textures submitted as
the control's native arrow, check or thumb continue to supply its visible art.

| Status | Meaning |
| --- | --- |
| `pending` / `queued` | Waiting for login or the queued batch. |
| `deferred` / `pending-visible` | Waiting for combat to end or for an eligible hidden host surface to appear. |
| `applied` | The requested visuals have been painted. |
| `native` / `suspended` | The action profile uses the caller's native art, or the relevant switch is off. |
| `failed` | The second return value gives the renderer's reason. A rejected submission also returns its reason directly. |
| `released` / `unknown-target` | The scope released the target or has no record of it. |

Check the status immediately after submitting a target. To receive a single
wake-up per scope for delayed completions, enable notifications and post-hook
the signal once. Subscribe to the existing appearance signal to handle settings
changes. The handlers can check only the targets for which the addon has fallbacks.

```lua
local function UpdateFallback()
    fallback:SetShown(skin:GetTargetStatus(button) ~= "applied")
end
skin:SetTargetNotifications(true)
hooksecurefunc(skin, "OnTargetsSettled", UpdateFallback)
hooksecurefunc(api, "OnAppearanceChanged", UpdateFallback)
skin:SkinWindowAction(button, "close", { appearance = "caption" })
UpdateFallback()
```

### Styling caller-owned Blizzard_Menu descriptions

When `menuDescriptionStyling` is available, call
`SkinMenuDescription(rootDescription)` after adding the standard rows in your
own generator. It opts in the existing descriptions and their submenus. The
Suite styles labels, indicators, hover and selection on rows from
`CreateTitle`, `CreateButton`, `CreateCheckbox` and `CreateRadio` inside
Blizzard's initializer. Blizzard handles input, disabled labels and
the release of pooled rows. The Suite paints when an opted-in row is
initialized out of combat and the scope is active. Style changes take effect
on the next initialization. `ReleaseAll()` and unregistering end the opt-in.

```lua
dropdown:SetupMenu(function(_, description)
    description:CreateTitle("Friends")
    description:CreateButton("Open settings", OpenSettings)
    description:CreateRadio("By name", IsSortByName, SetSortByName)
    skin:SkinMenuDescription(description)
end)
```

With `menuDescriptionFontOptions`, pass `{ preserveFont = true }` as the
second argument to `SkinMenuDescription` for font pickers and other menus that
set their own fonts. Each supported label keeps the font from its initializer.
The same option still applies the Suite's row colors, indicators, arrows and
highlights. Blizzard applies its disabled label color after row initialization.

With `menuSurface`, call `CreateMenuMixin(baseMixin)` on the same skin scope
before creating the root description. Use the resulting mixin for an addon-owned
dropdown or context menu. It draws the Suite's popup fill and border with
textures attached to Blizzard's compositor. It inherits the base mixin's
spacing and layout. The compositor releases the surface with each popup or
submenu. In combat or while the scope is inactive, newly opened popups use the
base mixin's surface. After `ReleaseAll()`, create a new mixin to opt in again.

```lua
-- Assign this only on a dropdown owned by your addon, before SetupMenu.
if api:HasCapability("menuSurface") then
    dropdown.menuMixin = skin:CreateMenuMixin(MenuVariants.GetDefaultMenuMixin())
end
dropdown:SetupMenu(function(_, description)
    PopulateFontChoices(description)
    if api:HasCapability("menuDescriptionFontOptions") then
        skin:SkinMenuDescription(description, { preserveFont = true })
    end
end)
```

For context menus, use `MenuVariants.GetDefaultContextMenuMixin()` as the base
and assign the result to your addon-owned context menu owner's `menuMixin`
before calling `MenuUtil.CreateContextMenu`. For a manually built root, pass
the mixin to `MenuUtil.CreateRootMenuDescription`.

`GetMenuStyle()` returns a detached snapshot containing RGBA arrays for
`text`, `title`, `disabled`, `highlight`, `selection`, `background`, `border`,
`check` and `arrow`, plus the selected font path when available. When the scope
is inactive it returns `nil` and a reason. Build the snapshot once per menu.
Use these tokens to paint your own custom popup.

## Verification boundary

Source/API contracts cover both supported client families. Native appearance,
combat/taint behavior and CPU/allocation measurements require in-game acceptance.
