"""English text the reader sees reaches translation, as whole sentences, and
the packs hold real translations.

* Shown text that once stayed English keeps its translation sink: refusal
  reasons, load failure fallbacks, the install failure line, the nameplate
  preview's sample names and the minimap preview's FPS and latency samples
  are in the extraction at their own call sites.
* AddOn load failures show Blizzard's text for the reason code
  (_G["ADDON_" .. reason], as Blizzard's AddOnUtil.lua does), not the code,
  and a status fills in a module's title translated.
* An options-page SetText with English source text either translates it or
  writes to a Menu2 widget that translates what it is given (T.Font,
  T.Button and the page helpers built on them). A plain font string shows
  the English as it is.
* Texts once joined from translated pieces are one format string each, in
  every pack, and the locale tool sees no runtime-built text in those files.
* Pack values hold no placeholders: no empty or question-mark values, no
  TODO marks, no mojibake, no label lowercased against its English, and no
  Simplified characters in Traditional Chinese or the reverse.

Usage: python tools/tests/suite_locale_reach_contract.py [repo root]
"""

import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("suite_locale_tool", ROOT / "tools" / "suite_locale_tool.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


records, extractor = tool.extract(ROOT)
by_english = {r.english: r for r in records}


def reached(english, rel):
    record = by_english.get(english)
    return record is not None and any(use[0] == rel for use in record.uses)


# ------------------------------------------------------------ shown text keeps its sink
CORE, OPTIONS = "MSUF_Suite/Core/", "MSUF_Suite_Options/Pages/"
SINKS = [
    ("Threat meter is available in WoW Forever", CORE + "Catalog/QualityOfLifeDetails.lua"),
    ("Flight route timer is available in WoW Forever", CORE + "Catalog/QualityOfLifeDetails.lua"),
    ("Installation failed", CORE + "Installer.lua"),
    ("not loaded", CORE + "Menu.lua"),
    ("not installed", CORE + "Suite.lua"),
    ("%d FPS", OPTIONS + "MinimapPreviewPaint.lua"),
    ("%d ms", OPTIONS + "MinimapPreviewPaint.lua"),
    # Menu2's M.BindDropdownAt translates its label (through W.Dropdown).
    ("Selected data", OPTIONS + "DataTextsEditor.lua"),
    ("MSUF style", OPTIONS + "DataTextsPresets.lua"),
]
# The nameplate preview names its sample plate after the previewed role.
style = (ROOT / CORE / "NameplateStyle.lua").read_text(encoding="utf-8")
roles = style[style.index("Style.Roles = {"):style.index("Style.RoleLabels")]
samples = re.findall(r'sample = "([^"]+)"', roles)
check(len(samples) >= 12, "NameplateStyle.Roles lost its sample names: %d" % len(samples))
SINKS += [(sample, CORE + "NameplateStyle.lua") for sample in samples]
for english, rel in SINKS:
    check(reached(english, rel), "%r is shown but never translated at %s" % (english, rel))

# ------------------------------------------------------------ Blizzard's load reason text
REASON = re.compile(r'type\((\w+)\) == "string" and _G\["ADDON_" \.\. \1\]')
for rel, statement in ((CORE + "Menu.lua", "Menu.error ="), (CORE + "Suite.lua", "local reason ="),
                       (OPTIONS + "CooldownManagerData.lua", "Page.loadFailed =")):
    source = (ROOT / rel).read_text(encoding="utf-8")
    at = source.find(statement)
    check(at >= 0 and REASON.search(source[at:at + 200]) is not None,
          "%s shows the raw AddOn load reason code instead of Blizzard's ADDON_<reason> text" % rel)

# A status names a module in the reader's language: StatusText translates
# the format and fills the stored values in again as they are.
STATUS = re.compile(r"FormatStatus\(")
for path in sorted(ROOT.glob("MSUF_Suite*/**/*.lua")):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for match in STATUS.finditer(line):
            for name in re.finditer(r"(\w+(?:\(\s*)?)?\b\w+\.(?:title|label)\b", line[match.end():]):
                check(name.group(0).startswith(("Text(", "Tr(")),
                      "%s:%d a status fills in an English title: %s"
                      % (path.relative_to(ROOT).as_posix(), number, line.strip()))

# ------------------------------------------------------------ SetText on plain font strings
# Creators whose widgets translate what SetText gives them (Menu2's T.Font
# and T.Button, and the page helpers that wrap them).
CREATOR = r"(?:P\.T\.Font|T\.Font|P\.T\.Button|T\.Button|W\.TopButton|W\.RoleButton|P\.Text|Label|Button)"
MADE = re.compile(r"(?:local\s+)?([\w.]+)\s*=\s*\(?" + CREATOR + r"\(")
SET_TEXT = re.compile(r"([\w.]+):SetText\(")
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
TRANSLATED = re.compile(r"\b(?:Tr|StatusText)\(")


def arguments(text, start):
    depth = 0
    for at in range(start, len(text)):
        if text[at] == "(":
            depth += 1
        elif text[at] == ")":
            depth -= 1
            if depth == 0:
                return text[start:at + 1]
    return text[start:]


for path in sorted((ROOT / "MSUF_Suite_Options").glob("**/*.lua")):
    rel = path.relative_to(ROOT).as_posix()
    lines = path.read_text(encoding="utf-8").splitlines()
    made = {name.split(".")[-1] for line in lines for name in MADE.findall(line)}
    for number, line in enumerate(lines, 1):
        for match in SET_TEXT.finditer(line):
            args = arguments(" ".join([line] + lines[number:number + 3]), match.end() - 1)
            # Shown literals: a literal compared against (prefix == "enemy") is a key.
            english = any(re.search(r"[A-Za-z]{2}", m.group(1)) for m in LITERAL.finditer(args)
                          if not args[:m.start()].rstrip().endswith(("==", "~="))
                          and not args[m.end():].lstrip().startswith(("==", "~=")))
            if english and not TRANSLATED.search(args) and match.group(1).split(".")[-1] not in made:
                failures.append("%s:%d a plain font string shows English text: %s" % (rel, number, line.strip()))

# ------------------------------------------------------------ whole format strings
FORMATS = [
    ("|cff9fc3e7[Guild]|r %s: Welcome to MSUF.", OPTIONS + "Chat.lua"),
    ("|cffc9d4dd[Party]|r Chat links and channels stay native.", OPTIONS + "Chat.lua"),
    ("%s (off)", OPTIONS + "CooldownManager.lua"),
    ("Sound kit %s", OPTIONS + "CooldownManagerData.lua"),
    ("Sound file %s", OPTIONS + "CooldownManagerData.lua"),
    ("Trinket slot %d: %s", OPTIONS + "CooldownManagerPicker.lua"),
    ("Click a spell for its settings · drag to reorder or onto a bar above · middle-click removes"
     " · + adds", OPTIONS + "CooldownManagerPreview.lua"),
    ("Click: settings · Drag: reorder · Middle-click: remove", OPTIONS + "CooldownManagerPreview.lua"),
]
packs = {locale: tool.read_locale(locale) for locale in tool.LOCALES}
for english, rel in FORMATS:
    check(reached(english, rel), "%s no longer translates %r as one text" % (rel, english))
    record = by_english.get(english)
    for locale in tool.LOCALES:
        check(record is not None and (locale in record.msuf or english in packs[locale]),
              "%s lacks the format string %r" % (locale, english))
FIXED = {rel for _, rel in FORMATS}
for rel, line, sink, expression, kind in extractor.dynamic:
    check(rel not in FIXED, "%s:%d builds text at runtime for %s: %s" % (rel, line, sink, expression))

# ------------------------------------------------------------ pack values
SIMPLIFIED = set("们这对来会后关开门进说让还从应该现样点击选择项条栏签图层级颜宽长画帧战斗团队员务区储载书龙钟锁键"
                 "转换据网络统设计时间为发显个动劳敌术师宠饰药装备绑经验别杀伤疗读录调节将无与并获隐侧边页缩档资讯"
                 "视觉风状态测试种类组织结构优简单复杂历记实际难题认证号码账户产业场积极闭维护坏销买卖价钱银铜质卫")
TRADITIONAL = set("們這對來會後關開門進說讓還從應該現樣點擊選擇項條欄籤圖層級顏寬長畫幀戰鬥團隊員務區儲載書龍鐘鎖鍵"
                  "轉換據網絡統設計時間為發顯個動勞敵術師寵飾藥裝備綁經驗別殺傷療讀錄調節將無與並獲隱側邊頁縮檔資訊"
                  "視覺風狀態測試種類組織結構優簡單複雜歷記實際難題認證號碼賬戶產業場積極閉維護壞銷買賣價錢銀銅質衛")
MOJIBAKE = re.compile("Ã[\u0080-¿ -¿]|â€|�")
LOWER = {"deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU"}
for locale, entries in packs.items():
    for english, text in entries.items():
        where = "%s %r = %r" % (locale, english, text)
        check(text.strip() != "" and not re.fullmatch(r"[?\s]+", text), "placeholder value: " + where)
        check(not re.search(r"\b(?:TODO|TBD|FIXME|XXX)\b", text), "unfinished value: " + where)
        check(not MOJIBAKE.search(text), "mojibake: " + where)
        if locale in LOWER and re.match(r"[A-Z][a-z]", english):
            check(not re.match(r"[a-zà-ÿа-я]", text), "label lowercased against its English: " + where)
        if locale == "zhTW":
            check(not (set(text) & SIMPLIFIED), "Simplified characters in Traditional Chinese: " + where)
        if locale == "zhCN":
            check(not (set(text) & TRADITIONAL), "Traditional characters in Simplified Chinese: " + where)

if failures:
    sys.exit("\n".join(failures[:60]) + ("\n... %d more" % (len(failures) - 60) if len(failures) > 60 else ""))
print("Suite locale reach: shown text keeps its sinks, load reasons use Blizzard's text, plain font strings get"
      " translated text, composed texts are whole format strings in every pack, pack values are real")
