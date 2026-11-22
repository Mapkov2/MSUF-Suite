# Addon skin compatibility

Use the consuming client's loaded TOC and the foreign addon's own source to locate the windows it actually creates. Record the inspected package and exact launch or build path. Prefer the public theme API, then an exact addon-owned boundary and finally a source-qualified frame. Qualify embedded controls separately so a foreign tab cannot take ownership of a Blizzard window.

| Addon | Inspected version and source | Suite coverage |
|---|---|---|
| Questie | [12.11.1](https://github.com/Questie/Questie/tree/1271825c7bb3be8bc342e489e0435e0d0232690d), Forever TOC and Modules/Options/QuestieOptionsWindow.lua, QuestieOptionsEngine.lua and QuestieOptionsControls.lua | Standalone settings chrome, selected-tab accents, batched settings rows |
| LFG Forever | [2.3.0](https://www.curseforge.com/wow/addons/lfg-forever/files/9705584), core/window.lua and core/slash.lua | Named window and exact launcher |
| Mastercraft | [2.0.7](https://www.curseforge.com/wow/addons/mastercraft-forever/files/9689205), Main.lua, Compact.lua, Goals.lua and Core.lua | Main, compact and goals windows |
| Kerzo Classic Quest Log | [6.6.0](https://www.curseforge.com/wow/addons/kerzo-classic-quest-log/files/9713053), interfaz/marco.lua, paneles/ajustesPaneles.lua and paneles/visorDetalle.lua | Settings, quest log and detached quest detail chrome |
| Kerzo Quest Expansion | [2.0.5](https://www.curseforge.com/wow/addons/kerzo-quest-expansion/files/9612947), interfaz/ventanaResumen.lua and interfaz/ventanaTintes.lua | Summary and tint dialogs |
| AtlasLoot Continued | [Forever build 12981](https://www.curseforge.com/wow/addons/atlasloot-continued/files/9710268), GUI/GUI.lua and Core/Changelog.lua | Main window, changelog and approved addon folders |
| High Fidelity World Map | [1.4.11](https://www.curseforge.com/wow/addons/hfwm/files/9604672), ToggleButton.lua and CaveRenderer.lua | Embedded HD/SD control and shared AceGUI styling |
| Pawn | [2.14.4 Forever](https://www.curseforge.com/wow/addons/pawn/files/9669292), PawnUI.xml | Main window and two string dialogs |
| Altoholic | [1.60.005](https://www.curseforge.com/wow/addons/altoholic/files/9171739), Altoholic/Main.xml and Altoholic/Core.lua | Main window, message box and applicable load-on-demand tabs |
| ALL THE THINGS | [5.4.15](https://www.curseforge.com/wow/addons/all-the-things/files/9718379), src/UI/Window Definitions.lua and src/base.lua | Main lists and copy dialog |
| Auctionator | Installed 347, Auctionator.toc and Source_ModernAH/Tabs/Main.lua | Shopping, selling and cancelling controls inside the auction house |
| Details! | Installed #Details.20261109.15410.172, Details.toc, Details_Camelot.toc, boot.lua and frames/window_bookmark.lua | Options, breakdown and bookmark windows |
| Leatrix Plus | Installed Retail 12.1.17, Leatrix_Plus.toc and Leatrix_Plus.lua | Source-qualified options window and help panel |

The client baselines for this group are [Forever 734f0653](https://github.com/Gethe/wow-ui-source/tree/734f065329cff4992835b01a84f210a297db91b6) and [Retail ab5cb850](https://github.com/Gethe/wow-ui-source/tree/ab5cb850a3f65e742959e379c4689353a2f4549f). Check Blizzard_Menu/Blizzard_Menu.toc and the loaded host window's own TOC when changing a native attachment.

On an addon update, open each affected window using its ordinary launcher, then change tabs, recycle list rows, change Suite's theme and disable or retry the skin. Check text overflow, semantic colors, native page ownership and original appearance on release. Record the result and package version in the release notes even when the code requires no change. Source inspection and harness checks are distinct from native input, combat, live rendering and frametime measurements.
