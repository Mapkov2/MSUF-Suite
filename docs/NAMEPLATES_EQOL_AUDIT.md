# Nameplates: EQoL-Abgleich und Jundies-Default

Stand: 2026-09-27. Abgeglichen mit der lokal installierten **EnhanceQoL 13.0.5**,
`Settings/CombatDungeon.lua` und `Settings/UIOptions.lua`, nicht nur mit den Optionsbeschriftungen.
Die folgende Liste ordnet die **47** Eintraege von `DEFAULT_NAMEPLATE_FEATURE_KEYS`
sowie vier weitere Funktionen aus UIOptions, Bindings und Profiles zu (**51 Zuordnungen**).
Die Zuordnung alleine beweist keine vollstaendige Laufzeit- oder visuelle Gleichheit.

## Aktuelle Korrektur: NPC-Farben und native Castbar (27.09.2026)

Auf Nutzerwunsch ist die eigene Castbar-Darstellung entfernt: keine Texturauswahl,
MSUF-Medienkopplung, eigene Fuellung/Hintergrund/Rahmen oder Cast-Farboptionen mehr.
Die entsprechenden Laufzeit-Hooks und Medien-Caches sind entfernt. Auch alte
Profilwerte aktivieren sie nicht mehr. Sichtbarkeit, Blizzard-Castdetails,
Schriftoptionen und Drag-Offsets bleiben verfuegbar. Die Vorschau nutzt Blizzards
Cast-Atlas. Historische Cast-Abschnitte weiter unten beschreiben verworfene Staende.
EQoL 13.0.5 aendert hier Cast-Schriften, aber keine Nameplate-Castfuelltextur.

NPC-Typfarben verwenden wieder zuerst `UnitHasPowerType(unit, Mana)`, wie im
frueheren Suite-Stand und in Platynators `Display/Utilities.lua` (`HasMana`).
Der Wechsel auf den aktuell angezeigten `UnitPowerType` hatte diese Prioritaet
verloren. Der Fallback wertet seine beiden Rueckgaben getrennt auf Lesbarkeit aus;
ein gesperrter Wert verwirft nicht mehr den anderen oeffentlichen Hinweis.
Unbekannte Typen bleiben bei Blizzard. Rollen werden weiterhin nur bei den
bestehenden Metadaten-/Kontext-Ereignissen aktualisiert.

Nach dem gemeldeten Rueckfall wurden zwei weitere Abbrueche behoben: Ein
geheimer Bedrohungswert unterdrueckt jetzt nur noch den Bedrohungs-Override,
nicht die NPC-Grundfarbe. Bei einer als normal/elite/rare bekannten NPC-Platte
ohne lesbaren Power-Hinweis wird wie in EQoL Melee verwendet; eine unbekannte
Klassifikation bleibt unangetastet. Ein geheimer Player-Control-Hinweis blockiert
eine bereits oeffentlich als NPC identifizierte Platte nicht mehr. Regressionstests
pruefen diese Faelle direkt auf Rolle und sichtbarer Balkenfuellung.

Der erneute Abgleich mit EQoL `13.0.5` findet alle 47 exportierten
Nameplate-Schluessel sowie Guild/Title, Friendly-NPC-Binding und Importschutz
im Suite-Menue. Zielwechsel aktualisieren nur die Zielmarkierung;
Bedrohungs-, Level- und Power-Ereignisse nur die betroffene NPC-Farbe und
Marker. Der Bedrohungs-API-Aufruf folgt wie bei Blizzard und EQoL dem
`usePlayerForAggroHighlightThreat`-Flag des nativen Nameplate-Frames.
Diese Entlastung betrifft Ereignisarbeit, nicht die von Blizzard selbst
gezeichneten Platten. Sie ist kein gemessener CPU-Wert.

Wiederholte Quest-Log-Ereignisse werden ausserhalb von Instanzen zu einem
abbrechbaren einmaligen Refresh zusammengefasst. Im Dungeon startet dafuer kein
Timer, ebenso wenig ohne sichtbare Platten. Unveraenderte Font-Schatten und Aura-Klickzustaende werden nicht erneut
geschrieben. Das Modul verwendet weiterhin keinen OnUpdate-Handler oder
periodischen Ticker; CPU-Gleichheit zu EQoL ist damit nicht gemessen.

Der erweiterte Offline-Test reproduzierte die falsche Melee-Einstufung vor der
Korrektur. Er prueft nun Mana-Faehigkeit gegen abweichende aktuelle PowerTypes,
teilweise gesperrte Rueckgaben, Dungeon-/Outdoor-Faelle und die gesamte
Gesundheitsbalkenfarbe. Cast-Tests brechen bei eigenen Textur-/Farbschreibzugriffen,
Overlays oder Cast-Hooks ab. Menue-/Preset-Tests schliessen die entfernten Optionen aus.
Diese Tests beweisen nicht die Darstellung oder Taint-Freiheit im laufenden Client.

Quellen: installierte Platynator- und EQoL-Version; Blizzard `upstream/live`
(`09b9db79`, 12.1.0.69933), `UnitDocumentation.lua`, `CastingBarFrame.lua` und
`Blizzard_NamePlateCastingBar.lua/.xml`.

## Vollstaendige Zuordnung

Die Suite bietet getrennte Schriftoptionen fuer Enemy/Friendly-Namen sowie Enemy/Friendly-Casttexte. Farben sind
ueber die drei Punkte der jeweiligen Sektion und unter **Colors > Suite > Nameplates** erreichbar.

| EQoL-Einstellung | Suite-Einstellung(en) |
| --- | --- |
| `auraClickthrough` | `auraClickthrough` |
| `slugOutline` | `enemyTextEnabled`, `friendlyTextEnabled`, `enemyCastTextEnabled`, `friendlyCastTextEnabled` |
| `textCustomFont` | `enemyCustomFont`, `friendlyCustomFont`, `enemyCastCustomFont`, `friendlyCastCustomFont` |
| `textFont` | `enemyNameFont`, `friendlyNameFont`, `enemyCastFont`, `friendlyCastFont` |
| `textOutline` | `enemyTextOutline`, `friendlyTextOutline`, `enemyCastOutline`, `enemyTextShadow`, `friendlyTextShadow`, `enemyCastTextShadow`, `friendlyCastOutline`, `friendlyCastTextShadow` |
| `textSize` | `enemyNameSize`, `friendlyNameSize`, `enemyHealthTextSize` |
| `castTextSize` | `enemyCastSize`, `friendlyCastSize` |
| `friendlyPlayerNamesOnly` | `friendlyNamesOnly` |
| `friendlyPlayerClassColorNames` | `friendlyNameClassColor` |
| `hideFriendlyPlayerRealms` | `friendlyRealm` |
| `eliteMarkers` | `enemyEliteMarker`, `friendlyEliteMarker` |
| `eliteMarkerAnchor` | `enemyEliteMarkerAnchor`, `friendlyEliteMarkerAnchor` |
| `eliteMarkerSize` | `enemyEliteMarkerSize`, `friendlyEliteMarkerSize` |
| `mobColors` | `enemyRoleColors` |
| `mobColorsInDungeons` | `enemyColorsInDungeons` |
| `mobColorsOutsideDungeons` | `enemyColorsOutside` |
| `questMarkers` | `enemyQuestMarker`, `friendlyQuestMarker` |
| `questMarkerAnchor` | `enemyQuestMarkerAnchor`, `friendlyQuestMarkerAnchor` |
| `questMarkerSize` | `enemyQuestMarkerSize`, `friendlyQuestMarkerSize` |
| `targetMarkers` | `enemyTargetMarker` |
| `targetMarkerAtlas` | `enemyTargetStyle` |
| `targetMarkerHideFriendly` | `enemyTargetHideFriendly` |
| `targetMarkerSize` | `enemyTargetMarkerSize` |
| `healthbarTexture` | `enemyHealthTexture`, `friendlyHealthTexture` |
| `focusHealthbarTexture` | `enemyFocusHealthTexture`, `friendlyFocusHealthTexture` |
| `mobColorFocus` | `enemyFocusColor` |
| `mobColorFocusEnabled` | `enemyFocusEnabled` |
| `mobColorBoss` | `enemyBossColor` |
| `mobColorBossEnabled` | `enemyBossEnabled` |
| `mobColorMiniboss` | `enemyMinibossColor` |
| `mobColorMinibossEnabled` | `enemyMinibossEnabled` |
| `mobColorCaster` | `enemyCasterColor` |
| `mobColorCasterEnabled` | `enemyCasterEnabled` |
| `mobColorMelee` | `enemyMeleeColor` |
| `mobColorMeleeEnabled` | `enemyMeleeEnabled` |
| `mobColorNeutral` | `enemyNeutralColor` |
| `mobColorNeutralEnabled` | `enemyNeutralEnabled` |
| `mobColorTapped` | `enemyTappedColor` |
| `mobColorTappedEnabled` | `enemyTappedEnabled` |
| `mobColorTankMode` | `enemyTankModeColor` |
| `mobColorThreatLost` | `enemyThreatLostColor` |
| `mobColorThreatLostEnabled` | `enemyThreatLostEnabled` |
| `mobColorThreatWarning` | `enemyThreatWarningColor` |
| `mobColorThreatWarningEnabled` | `enemyThreatWarningEnabled` |
| `mobColorTrivial` | `enemyTrivialColor` |
| `mobColorTrivialEnabled` | `enemyTrivialEnabled` |
| `mobTankMode` | `enemyTankMode` |
| `UnitNamePlayerGuild` (UIOptions) | `playerGuildNames`: Blizzard / zeigen / verstecken |
| `UnitNamePlayerPVPTitle` (UIOptions) | `playerTitles`: Blizzard / zeigen / verstecken |
| `EQOL_TOGGLE_FRIENDLY_NPCS` (Bindings) | `friendlyNPCs`, Taste **Toggle friendly NPC nameplates** unter MSUF Suite |
| `importProtection.nameplates` (Profiles) | `protectImport`: aktuelle Nameplates bei Full-Suite-Import behalten |

## Verhalten und bewusste Unterschiede

- Blizzard erstellt und verwaltet weiterhin Nameplates, Health/Cast-Fortschritt, Auren,
  Absorbs und Zielauswahl. Kein eigenes Health- oder Cast-Update-System.
- Farbprioritaet: aktivierte Fokusfarbe, sicherer Tank-Aggrostatus, Bedrohung,
  Tapped, zusaetzliche Questfarbe, Neutral, Boss/Miniboss/Caster/Melee/Trivial.
  Deaktivierte Fokusfarbe faellt auf die darunterliegende Regel zurueck.
  Deaktivierte Bedrohungsfarbe laesst die aktive Blizzard-Bedrohungsfarbe stehen.
- Tankmodus verwendet Blizzards effektive Tankrolle und Threat-Lead-Status.
  Status 0 mit bestehender Bedrohungsliste bedeutet sicher; Status 3 bedeutet
  verlorene Bedrohung beim Tank bzw. Aggro beim Nicht-Tank. Warnfarben funktionieren
  auch ohne Tankmodus. Keine Vergleiche oder Berechnungen mit Secret Values.
- PvP und spielerkontrollierte Einheiten erhalten keine NPC-Rollenfarbe.
  Effektives Level/LFG-Referenzlevel und Lieutenant-Erkennung dienen der Boss-Einstufung;
  Mana ist ein Caster-Hinweis, keine vollstaendige NPC-Datenbank.
- Questmarker erkennen eigene unerledigte Welt-Questziele anhand oeffentlicher
  Tooltip-Daten; fertige und reine Gruppenmitglieder-Ziele werden ausgefiltert.
  Wie EQoL: keine Tooltip-Scans in Instanzen. Ergebnisse werden bis zum relevanten
  Quest-/Einheitenwechsel gespeichert; unbekannte Daten bleiben unbekannt.
- Health- und Fokus-Textur funktionieren fuer Enemy und Friendly unabhaengig von Rollenfarben.
  Eine wiederverwendete Maske bewahrt die native Silhouette auch bei Rollenfarben;
  Atlas/Textur und TexCoords werden beim Zuruecksetzen wiederhergestellt.
  Geheime TexCoords werden nicht gespeichert oder zur Maskierung verwendet.
- Elite/Rare/Boss-Marker sind Texturen mit Groesse 8-48 und neun Ankerpunkten
  plus X/Y. Die Suite verwendet Blizzard-Atlanten (Gold/Silber/Boss), nicht
  EQoLs eigene Elite-Grafik. Keine Font-Glyphen als Marker.
- Alle acht EQoL-Zielmarker-Atlanten (einschliesslich `pvptalents-selectedarrow`) plus Jundies-Pfeile sind vorhanden,
  inklusive Groesse, X/Y und Ausblenden fuer freundliche Ziele.
- Outline, Thick Outline, Monochrome, SLUG und deren Kombinationen, Schatten,
  globale MSUF-Schrift/Flags sowie Beibehalten der Blizzard-Locale-Schrift sind vorhanden.
  Fontgroesse 0 bewahrt die native Groesse; Customize-off stellt die native Typografie wieder her.
- Realm-Namen verwenden auf Retail 12.1 Blizzards eigene CVar
  `nameplateShowFriendlyRealmName`. Kein Eingriff in geschuetzte Options-Tabellen.
- Auren-Clickthrough deckt moderne Auren, Loss of Control und den alten Buff-Pool ab.
- Gildennamen/Titel wirken wie bei EQoL auf Welt-Namen. Der NPC-Toggle ist eine manuelle
  Taste bei aktivem Modul; im Kampf bleibt er gesperrt.
- Importschutz gilt fuer vollstaendige Suite-Importe. Der Schalter des aktiven Profils
  entscheidet; explizite Nameplate-Importe und Factory-Reset ersetzen weiterhin das Modul.

## Jundies

Quelle ist das vom Benutzer bestaetigte **Platynator DEFAULT**, Design **Enemy Nameplates**.
Default und Jundies-Reset werden aus derselben Suite-Regeltabelle erzeugt.

| Merkmal | Default |
| --- | --- |
| Layout | Blizzard Modern, Medium, Name links, Wert + Prozent rechts |
| Schrift | Expressway ExtraBold, Outline + SLUG; Friendly Expressway Regular mit Schatten |
| Rahmen | Schwarz, 1 px; schwarzer Hintergrund mit 50 % Deckkraft |
| Melee / Trivial | `#be301d` |
| Caster | `#00bfff` |
| Miniboss | `#9370db` |
| Boss / Fokus | `#ff00ff` |
| Neutral | `#e5db00` |
| Quest | `#ff7e00` |
| Tapped | `#6e6e6e` |
| Bedrohung / Uebergang | `#dd6f00` / `#ffe93a` |
| Questmarker | Blizzard-Questtextur links ausserhalb der Platte; Elite-Zusatzmarker aus |
| Castbar | Sichtbar; Blizzard-Cast und -Interruptlogik, nur Schrift und Position werden angepasst |

Bekannte alte Factory-Farben/Outline werden nur bei Look=Jundies einmal migriert.
Custom-Profile bleiben erhalten; zum vollstaendigen Uebernehmen im Modul **Look > Jundies** waehlen.
SavedVariables werden nicht extern umgeschrieben.

Dies ist ein Skin von Blizzards Platten, keine pixelidentische Platynator-Engine.
Blizzards Zahlenformat, native Geometrie, Castdauer/Interrupt-Meldungen und
Verfuegbarkeit freundlicher Platten bleiben clientabhaengig. Platynators eigene
Offtank-, Interrupt-Bereitschafts- und Energiebalkenlogik wird nicht nachgebaut;
diese gehoert auch nicht zu EQoLs Default-Nameplate-Funktionen.

## Interaktiver Editor

Enemy- und Friendly-Beispiel mit direktem Maus-Drag fuer Name, Health-Text,
Castbar, Spellname, Zauberziel, Zaubericon, Unterbrechungsschild, Auren, Raidmarker
und Blizzard-Elite-/Rare-Icon; zusaetzlich Target-/Elite-/Questmarker auf beiden Seiten.
Gemeinsame Classic-MSUF PreviewSelectionBar und PreviewHelpers: Auswahl,
exakte X/Y-Werte, Pfeiltasten (Shift 5, Ctrl 10), Reset, Escape-Abbruch,
Zoom, Hintergrund-Pan, Hintergrundauswahl und vergroesserte Ansicht.
Zwoelf Rollenbeispiele sowie Outdoor/Dungeon, Health, Cast, Target und Friendly-Modus.
Start-here-Einstellungen liegen zusammen mit Aktivierung und Status in **Frame Basics**.
Die Farbregeln, Enemy, Friendly und Castbar haben ihre passenden Drei-Punkte-Farbmenues;
kein separater Nameplate-Farbbutton mehr. Friendly Focus ist ein eigener Vorschauknopf.
Live-Offsets werden ausserhalb des Kampfes auf Blizzards vorhandene Regionen angewendet.

## Laufzeit und Pruefgrenze

- Keine eigenen OnUpdate-Schleifen, Ticker, Health-/Cast-/Combatlog-Events.
- Ereignisse pro Einheit aktualisieren nur die betroffene aktive Platte.
- Ziel/Fokus aktualisieren die vorherige und neue Platte; Kontextwechsel aktualisieren aktive Platten.
- Font/Media-Aufloesung bei Konfigurationswechsel; Quest- und Kontext-Caches.
- Blizzards Cast-Fuellung und Hintergrund bleiben nativ; Schrift und Drag-Offsets werden nur bei relevanten Aktualisierungen angewendet.
- Standardlayout braucht keinen UpdateAnchors-Hook. Hooks fuer benutzerdefinierte
  Offsets/Texturen werden nur bei Verwendung installiert; deaktivierte Hooks kehren sofort zurueck.
- Eigene Texturen und Schrift werden auch bei erstmals im Kampf erscheinenden Platten angewendet.
- Keine manuellen Aufrufe von ApplyFrameOptions, CompactUnitFrame_SetUpFrame,
  CompactUnitFrame_UpdateAll oder SetUnit; keine Aenderungen an nativen Unit-/Options-Feldern.

Offline-Verifikation: EQoL-Schemaabdeckung, konkrete Runtime-Regressionsfaelle,
Migrationen, Drag/Keyboard/Zoom/Reset, Farben-Zugriff, Mainline/Forever-Loadgraph,
Lua-5.1-Syntax und Suite-Strukturpruefung. Das beweist keinen Live-Kampf,
keine visuelle Gleichheit, Taintfreiheit oder gemessene CPU-Verbesserung.
Perfy wurde nicht erneut ausgefuehrt.

## Quellenstand

- Blizzard `upstream/live` = `09b9db7948abc9b9648dedaab51eb0cf3ee67b31` (12.1.0.69933).
- `Blizzard_NamePlates/Blizzard_NamePlateBase.lua`, `Blizzard_NamePlateUnitFrame.lua`,
  `Blizzard_NamePlateConstants.lua`, `Blizzard_UnitFrame/Shared/CompactUnitFrame.lua`.
- `Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua`.
- EQoL `Settings/CombatDungeon.lua` SHA256:
  `07876267b636ec378363d751a63908b98381902a1dc52fb267393654f4cc83fe`.

## Nutzung nach der Aenderung

Nach dem Aktualisieren der Addon-Dateien einmal `/reload` ausfuehren.
Bestehende Custom-Profile bleiben bestehen. Fuer die kompletten Factory-Werte
im Modul **Frame Basics > Look > Jundies** waehlen.

## Nacharbeit: Castbar, Gruppenfilter und native Icons (27.09.2026)

- Cast-Skin bindet die Fuellebene auch nach Blizzards `UpdateBarFillTexture`.
  Dieser Hook erfasst erstmals angelegte und ausgetauschte Texturen bei
  Cast-/Channel-Start, Interrupt-Aenderungen und Abschluss. Er liest keine
  Castzeit/-fortschrittswerte. Wiederverwendete Platten verlieren den alten Besitzer.
- Vorschau verwendet eine echte StatusBar mit einem festen Beispielwert.
  Das ist kein Nachweis fuer die Sichtbarkeit eines laufenden Zaubers im Client.
- Friendly > `Player names only: party / raid members`: aktiviert Blizzards
  Spielernamen-Modus und blendet fremde freundliche Spielernamen aus.
  Gruppen-/Raidwechsel aktualisieren aktive Platten ereignisgesteuert;
  unbekannte Mitgliedschaft wird nicht gefiltert. Verbotene Friendly-Frames
  werden nicht veraendert. Der Vorschauknopf `Group / outsider` zeigt beide Faelle.
- Neue native Drag-Elemente: Blizzard-Elite-/Rare-Textur, Zaubericon,
  Unterbrechungsschild und Zauberziel. Die Elite-Textur wird unabhaengig
  vom Layout-Fussabdruck ihres nativen Frames verschoben.
- Castbar-Drag nimmt ihre Bestandteile gemeinsam mit; individuelle Offsets
  kompensieren Blizzards gegenseitige Anker. Modern und Classic verwenden
  umgekehrte Icon-/Bar-Abhaengigkeiten. Wiederholtes Layout akkumuliert nichts.
- Zielmarkierung verwendet direkt `MSUF_NS.BossTargetIndicator.Apply` auf
  einem Suite-eigenen Host: einfach/doppelt/dreifach, Raute, Kreuz, Rahmen,
  Rahmen + Pfeil; neun Anker, vier Richtungen, einzeln/beidseitig innen/aussen,
  Groesse 8–96, X/Y -500–500 und Farbe. EQoL-Atlasvarianten bleiben waehlbar.
  Bossframe-Profile werden nicht beschrieben. Ohne diesen Renderer im MSUF-Host
  bleibt Blizzards native Zielmarkierung erhalten.
- Castoberflaechen und Zielgeometrie werden bei unveraenderter Konfiguration
  nicht erneut aufgebaut. Kein eigener Cast-Timer, keine neue OnUpdate-Schleife.

Zusaetzliche Quellen: Blizzard `upstream/live`,
`Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua` und
`Blizzard_NamePlates/Blizzard_NamePlateCastingBar.lua`,
`Blizzard_NamePlateClassificationFrame.lua`, `Blizzard_NamePlates.xml`;
Classic MSUF `UnitFrames/Engine/Elements/MSUF_UF_BossTargetIndicator.lua`.

Regressionstests umfassen jetzt spaete Casttexturen im Kampf, Recycling,
Gruppenfilter und Alpha-Restoration, native Icon-Offets, Modern-/Classic-Anker,
echten MSUF-Marker-Renderer und dessen Formwechsel sowie Maus-Drag/Reset der
Elite-Vorschau. Live-Darstellung, Taintfreiheit und CPU-Zeiten bleiben im Client
zu pruefen; Perfy wurde nicht neu ausgefuehrt.

## Nacharbeit: vollstaendiger Quellenumfang und Castbar-Anpassungen (27.09.2026)

Der fruehere 47-Key-Abgleich liess die Funktionen ausserhalb der EQoL-Exportliste
und den Friendly-Geltungsbereich einzelner Funktionen aus. Die Tabelle und Fixture
enthalten jetzt auch diese Optionen; verifiziert sind deren Menue-Anbindung und
gezielte Laufzeitfaelle im Offline-Harness.

Die zusaetzliche Cast-Fuelltextur ist entfernt. `SetStatusBarTexture` ersetzt die
Textur auf Blizzards echter StatusBar; `SetStatusBarColor` setzt Farbe/Deckkraft,
wenn die native Farbe oeffentlich und wiederherstellbar ist. Die Vorschau nutzt
dasselbe Verfahren. Es gibt keine zweite Fuellung ueber der nativen Castbar.
Geheime Farben bleiben bei Blizzard. Geheime Texturen werden weder gespeichert
noch zur Wiederherstellung verwendet; dieser Cast bleibt dann nativ.

Nach Blizzards `UpdateBarFillTexture` wird die gewaehlte Textur erneut angewendet,
auch wenn Blizzard dasselbe Texture-Objekt wiederverwendet. Oeffentliche native
Textur/Atlas/Farbe werden beim Abschalten wiederhergestellt, ohne die Castlogik
aufzurufen. Der native Hintergrund ist waehrend des Skins transparent und wird
beim Abschalten wiederhergestellt; die eingestellte Deckkraft mischt sich nicht
mehr mit einem zweiten Hintergrund. Jundies nutzt 100 % Fuell-Deckkraft;
nur sein alter 35-%-Default wird einmalig migriert. Custom-Profile bleiben bestehen.

Explizite Cast-Textur hat Vorrang vor MSUF. MSUF-Link liefert Textur und Hintergrundtextur;
die lokalen Farb- und Deckkraftwerte werden nicht mehr durch MSUF ueberschrieben.
Vorschau und Laufzeit verwenden dieselbe native Fuellung und Medienauswahl.

Quellen: `upstream/live` und `upstream/forever`,
`Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua`,
`Blizzard_NamePlates/Blizzard_NamePlateCastingBar.xml` und
`Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua` und
`SimpleStatusBarAPIDocumentation.lua`.
Neue Regressionen pruefen den echten Cast-Texturersatz/Override/Reset, Masken und native TexCoords,
Friendly-Fokus/Marker/Castfonts, Import-Schutz, NPC-Keybinding, Frame-Basics-Platzierung,
alle vier Farbmenues und Friendly-Marker-Drag. Live-Sichtbarkeit und Kampf-Taint
sind durch diese Offline-Tests nicht bewiesen.

Abschliessender Stand dieses Durchlaufs: 11 gezielte Contract-Laeufe bestanden
(Nameplates-Runtime, EQoL-Zuordnung, Profile, Menue und Loadgraph jeweils fuer
Retail/Forever, Controller, Platform und beide relevanten Strukturpruefungen).
18 geaenderte Lua-Dateien bestehen Lua-5.1-Syntax, Bindings.xml besteht XML-Parsing.
14 Produktionsdateien stimmen per SHA256 mit dem installierten Retail-Addon ueberein;
die bestehende Layout.lua-Reparatur fuer eingeschraenkte Regionen stimmt ebenfalls ueberein.
