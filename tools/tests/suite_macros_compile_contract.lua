local root = assert(arg[1], "repository root required")
local secret = {}
local namespace = { IsSecret = function(value) return value == secret end }
for _, file in ipairs({ "Model", "Compile", "Templates" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/Macros/" .. file .. ".lua"))("MSUF_Suite", namespace)
end
local Macros, Model = namespace.Macros, namespace.Macros.Model
local checks = 0
local function Equal(actual, wanted, message)
    checks = checks + 1
    assert(actual == wanted, (message or "different value") .. ": " .. tostring(actual) .. " / " .. tostring(wanted))
end
local function Compile(document, expected)
    local body, errorKey = Macros.Compile(document)
    Equal(body, expected, errorKey)
    return body
end
local function Reject(document, expected)
    local body, errorKey = Macros.Compile(document)
    Equal(body, nil, "invalid macro was accepted")
    Equal(errorKey, expected, "wrong validation error")
end
local function Branch(value, conditions)
    return { value = value, conditions = conditions or {} }
end
local function Condition(key, value, negate)
    return { key = key, value = value or "", negate = negate == true }
end

local doc = Model.New("focus")
doc.steps[1].branches[1].value = "Kick"
doc.steps[1].branches[2].value = "Kick"
Compile(doc, "#showtooltip\n/cast [@focus,harm,nodead][harm,nodead] Kick")
Equal(doc.steps[1].branches[1].value, "Kick", "compiler mutated the document")
local separate = Model.New("focus")
Equal(separate.steps[1].branches[1].value, "", "templates share draft state")
Equal(Model.Normalize(separate).steps[1].branches[1].useFirst, false, "old drafts keep independent actions")

doc.steps[1].branches[2].value = "Saved separate action"
doc.steps[1].branches[2].useFirst = true
Compile(doc, "#showtooltip\n/cast [@focus,harm,nodead][harm,nodead] Kick")
Equal(doc.steps[1].branches[2].value, "Saved separate action", "inheritance discarded custom action")
doc.steps[1].branches[1].value = "Rebuke"
Compile(doc, "#showtooltip\n/cast [@focus,harm,nodead][harm,nodead] Rebuke")
doc.steps[1].branches[2].useFirst = false
Compile(doc, "#showtooltip\n/cast [@focus,harm,nodead] Rebuke;[harm,nodead] Saved separate action")
doc.steps[1].branches[1].useFirst = true
Reject(doc, "Invalid macro action")
doc.steps[1].branches[1].useFirst = false
doc.steps[1].branches[2].useFirst = secret
Equal(Model.Normalize(doc), nil, "secret inheritance flag was accepted")

doc = Model.New()
doc.steps[1].branches = { Branch("Heal", { Condition("mod", "alt") }),
    Branch("Other", { Condition("mod", "shift") }), Branch("Stored", { Condition("help") }) }
doc.steps[1].branches[3].useFirst = true
Compile(doc, "#showtooltip\n/cast [mod:alt] Heal;[mod:shift] Other;[help] Heal")

doc = Model.New("sequence")
doc.steps[1].sequence = { "Heal" }
doc.steps[1].branches[1].useFirst = true
Reject(doc, "Invalid macro action")

doc = Model.New("help-harm")
doc.steps[1].branches[1].value = "Flash Heal"
doc.steps[1].branches[2].value = "Flash Heal"
doc.steps[1].branches[3].value = "Smite"
Compile(doc, "#showtooltip\n/cast [mod:alt,@player][help,nodead] Flash Heal;[harm,nodead] Smite")
doc.steps[1].branches[1].conditions[1].value = "none"
Compile(doc, "#showtooltip\n/cast [nomod,@player][help,nodead] Flash Heal;[harm,nodead] Smite")

doc = Model.New("mouseover")
doc.steps[1].branches[1].value = "Heal"
Compile(doc, "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Heal")
Equal(Model.Normalize(doc).steps[1].branches[3].useFirst, true, "self fallback shares the chosen spell")
doc = Model.New("mouseover-harm")
doc.steps[1].branches[1].value = "Smite"
Compile(doc, "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] Smite")
doc = Model.New("cursor")
doc.steps[1].branches[1].value = "Blizzard"
Compile(doc, "#showtooltip\n/cast [@cursor] Blizzard")

doc = Model.New("mouseover-mark")
doc.steps[1].branches[1].value = "Heal"
Compile(doc, "#showtooltip\n/tm [@mouseover,help,nodead][help,nodead][@player] !8"
    .. "\n/cast [@mouseover,help,nodead][help,nodead][@player] Heal")
Equal(Model.Normalize(doc).steps[1].raidMarker, 8, "attached marker survives persistence")
doc.steps[1].branches[2].useFirst = false
doc.steps[1].branches[2].value = "Renew"
Compile(doc, "#showtooltip\n/tm [@mouseover,help,nodead][help,nodead][@player] !8"
    .. "\n/cast [@mouseover,help,nodead] Heal;[help,nodead] Renew;[@player] Heal")
doc.steps[1].raidMarker = 0
Compile(doc, "#showtooltip\n/tm [@mouseover,help,nodead][help,nodead][@player] 0"
    .. "\n/cast [@mouseover,help,nodead] Heal;[help,nodead] Renew;[@player] Heal")
Equal(doc.steps[1].branches[2].value, "Renew", "marker compilation mutated action")

doc = Model.New()
doc.steps[1].branches = { Branch("Heal", { Condition("unit", "mouseover"), Condition("help") }), Branch("Renew") }
doc.steps[1].raidMarker = 7
Compile(doc, "#showtooltip\n/tm [@mouseover,help] !7;!7\n/cast [@mouseover,help] Heal;Renew")
for _, invalid in ipairs({ -1, 9, 0.5, "8", false, {}, secret, math.huge, 0 / 0 }) do
    doc.steps[1].raidMarker = invalid
    Reject(doc, "Invalid macro action")
end
doc.steps[1].raidMarker = nil
Equal(Model.Normalize(doc).steps[1].raidMarker, nil, "legacy actions default marker to off")

for _, command in ipairs({ "castsequence", "castrandom" }) do
    doc = Model.New()
    doc.steps = { Model.NewStep(command) }
    doc.steps[1].sequence = { "Heal", "Renew" }
    doc.steps[1].branches[1].conditions = { Condition("unit", "focus"), Condition("help") }
    doc.steps[1].raidMarker = 1
    Compile(doc, "#showtooltip\n/tm [@focus,help] !1\n/" .. command .. " [@focus,help] Heal,Renew")
end
for _, command in ipairs({ "use", "startattack", "petattack" }) do
    doc = Model.New()
    doc.steps = { Model.NewStep(command) }
    local value = command == "use" and "item:5512" or ""
    doc.steps[1].branches[1] = Branch(value, { Condition("unit", "mouseover"), Condition("exists") })
    doc.steps[1].raidMarker = 2
    Compile(doc, "#showtooltip\n/tm [@mouseover,exists] !2\n/" .. command .. " [@mouseover,exists]"
        .. (value ~= "" and " " .. value or ""))
    if value == "" then
        doc.steps[1].branches[1].value = "focus"
        Reject(doc, "Invalid macro action value")
    end
end
for _, command in ipairs({ "party", "petdismiss", "target", "assist", "cleartarget", "tm", "wm", "cwm", "raw" }) do
    doc = Model.New()
    doc.steps = { Model.NewStep(command) }
    doc.steps[1].branches[1].value = command == "party" and "Ready" or command == "tm" and "8"
        or command == "wm" and "1" or command == "cwm" and "all" or ""
    doc.steps[1].raw = "/cast Heal"
    doc.steps[1].raidMarker = 8
    Reject(doc, "Invalid macro action")
end
doc = Model.New("cursor")
doc.steps[1].branches[1].value = "Blizzard"
doc.steps[1].raidMarker = 8
Reject(doc, "Invalid macro condition")

doc = Model.New()
doc.steps[1].branches[1].value = string.rep("a", 229)
Compile(doc, "#showtooltip\n/cast " .. string.rep("a", 229))
doc.steps[1].raidMarker = 8
Compile(doc, "#showtooltip\n/tm !8\n/cast " .. string.rep("a", 229))
doc.steps[1].branches[1].value = string.rep("a", 230)
Reject(doc, "The macro exceeds the 255-character limit")

-- A native line reparses conditions; the cast immediately invalidates its initial gate.
local function ExecuteStateChangingMacro(text, gate)
    local changed, marked, castTarget = false, nil, nil
    for line in text:gmatch("[^\n]+") do
        local command = line:match("^/(%w+)")
        if command == "tm" or command == "cast" then
            local target
            for conditions in line:gmatch("%[([^%]]+)%]") do
                if not changed or not conditions:find(gate, 1, true) then
                    target = conditions:match("@([%w]+)") or "target"
                    break
                end
            end
            if command == "tm" then
                marked = target
            else
                castTarget, changed = target, true
            end
        end
    end
    return marked, castTarget, changed
end
for _, gate in ipairs({ "form:1", "nostealth" }) do
    doc = Model.New()
    local condition = gate == "form:1" and Condition("form", "1") or Condition("stealth", "", true)
    doc.steps[1].branches = { Branch("Heal", { condition, Condition("unit", "mouseover") }),
        Branch("Heal", { Condition("unit", "player") }) }
    doc.steps[1].raidMarker = 8
    local body = Macros.Compile(doc)
    local marked, castTarget, changed = ExecuteStateChangingMacro(body, gate)
    Equal(changed, true, "fixture must change the gate during cast")
    Equal(castTarget, "mouseover", "cast uses initial target selection")
    Equal(marked, castTarget, "instant condition change redirected the attached mark")
end

doc = Model.New("sequence")
doc.steps[1].sequence = { "Renew", "Flash Heal", "item:5512" }
doc.steps[1].reset = { target = true, combat = true, seconds = 5, mod = "shift" }
doc.steps[1].branches[1].conditions = { Condition("combat") }
Compile(doc, "#showtooltip\n/castsequence [combat] reset=target/combat/5/shift Renew,Flash Heal,item:5512")
doc.steps[1].reset.seconds = 0.5
Reject(doc, "Invalid sequence reset")
doc.steps[1].reset.seconds = 5
doc.steps[1].sequence[2] = "Flash Heal,/run print(1)"
Reject(doc, "Invalid spell or item")
doc.steps[1].sequence = {}
Reject(doc, "Add a sequence step")

doc = Model.New()
doc.steps[1].branches = { Branch("Heal"), Branch("Smite", { Condition("harm") }) }
Reject(doc, "Place the fallback rule last")
doc.steps[1].branches = { Branch("Heal", { Condition("help"), Condition("harm") }) }
Reject(doc, "Conflicting macro conditions")
doc.steps[1].branches[1].conditions = { Condition("dead"), Condition("dead", "", true) }
Reject(doc, "Conflicting macro conditions")
doc.steps[1].branches[1].conditions = { Condition("unit", "focus"), Condition("unit", "player") }
Reject(doc, "Choose one target per rule")
doc.steps[1].branches[1].conditions = { Condition("unit", "party5") }
Reject(doc, "Invalid macro condition")
doc.steps[1].branches[1].conditions = { Condition("unit", "party01") }
Reject(doc, "Invalid macro condition")
doc.steps[1].branches[1].conditions = { Condition("unit", "raid40") }
Compile(doc, "#showtooltip\n/cast [@raid40] Heal")
doc.steps[1].branches[1].conditions = { Condition("advflyable"), Condition("vehicleui", "", true) }
Compile(doc, "#showtooltip\n/cast [advflyable,novehicleui] Heal")
doc.steps[1].branches[1].conditions = { Condition("advflyable", "", true), Condition("vehicleui") }
Compile(doc, "#showtooltip\n/cast [noadvflyable,vehicleui] Heal")

for _, injected in ipairs({ "Heal\n/run print(1)", "Heal; Smite", "Heal[combat]", "Heal\r/use 13", "Heal\000" }) do
    doc = Model.New()
    doc.steps[1].branches[1].value = injected
    Equal(Macros.Compile(doc), nil, "injected action accepted")
end
doc = Model.New()
doc.steps[1].branches[1].value = "Heal"
doc.steps[1].branches[1].conditions = { Condition("known", "123; /run print(1)") }
Reject(doc, "Invalid macro condition")
doc.steps[1].branches[1].conditions = { Condition("health", "25") }
Reject(doc, "Invalid macro action")

doc = Model.New()
doc.mode, doc.raw = "raw", "/run print('draft only')\r\n/cast Heal"
Compile(doc, "/run print('draft only')\n/cast Heal")
doc.raw = string.rep("a", 255)
Compile(doc, doc.raw)
doc.raw = string.rep("a", 256)
Reject(doc, "The macro exceeds the 255-character limit")
local rejectedBody, _, _, visibleBody = Macros.Compile(doc)
Equal(rejectedBody, nil, "oversize publishing remains blocked")
Equal(visibleBody, doc.raw, "oversize preview remains visible")
doc.raw = string.rep("\195\164", 255)
Compile(doc, doc.raw)
Equal(Model.Count(doc.raw), 255, "UTF-8 character counter")
doc.raw = "\237\160\128"
Reject(doc, "Invalid macro text")
doc.raw = "\240\128\128\128"
Reject(doc, "Invalid macro text")
doc.raw = "\244\144\128\128"
Reject(doc, "Invalid macro text")

doc = Model.New("health")
local resolved
local body = Macros.Compile(doc, function(prepared)
    resolved = prepared
    return "#showtooltip\r\n/use item:5512"
end)
Equal(body, "#showtooltip\n/use item:5512", "consumable resolver")
Equal(resolved.consumable.kind, "health", "resolver receives whole document")
Equal(resolved.consumable.managed, true, "managed template intent")
Equal(resolved ~= doc, true, "resolver receives independent normalized state")
Reject(doc, "Consumable data is not ready")

local samples = { equipslot = "16 item:123", tm = "8", wm = "1", cwm = "all",
    changeactionbar = "2", swapactionbar = "1 2" }
for _, command in ipairs(Model.Commands) do
    doc = Model.New()
    doc.steps = { Model.NewStep(command.key) }
    local step = doc.steps[1]
    if command.argument == "sequence" then
        step.sequence = { "Heal", "Renew" }
    elseif command.argument == "raw" then
        step.raw = "/run print('not executed')"
    elseif command.argument ~= "none" and command.argument ~= "optional" then
        step.branches[1].value = samples[command.key] or "Example"
    end
    Equal(type(Macros.Compile(doc)), "string", "native command failed: " .. command.key)
end

doc = Model.New()
doc.steps = { Model.NewStep("tm") }
doc.steps[1].branches[1].conditions = { Condition("unit", "focus") }
for marker = 0, 8 do
    local value = tostring(marker)
    doc.steps[1].branches[1].value = value
    Compile(doc, "#showtooltip\n/tm [@focus] " .. value)
    if marker > 0 then
        for _, prefix in ipairs({ "!", "~" }) do
            doc.steps[1].branches[1].value = prefix .. value
            Compile(doc, "#showtooltip\n/tm [@focus] " .. prefix .. value)
        end
    end
end
for _, value in ipairs({ "9", "-1", "0.5", "!0", "~0", "!9", "01", "skull" }) do
    doc.steps[1].branches[1].value = value
    Reject(doc, "Invalid macro action value")
end
doc.steps[1].branches[1] = Branch("!8", { Condition("unit", "cursor") })
Reject(doc, "Invalid macro condition")

doc = Model.New()
doc.steps = { Model.NewStep("cwm") }
doc.steps[1].branches[1].value = "all"
Compile(doc, "#showtooltip\n/cwm 1\n/cwm 2\n/cwm 3\n/cwm 4\n/cwm 5\n/cwm 6\n/cwm 7\n/cwm 8")
doc.steps[1].branches = { Branch("all", { Condition("mod", "shift") }), Branch("2") }
Compile(doc, "#showtooltip\n/cwm [mod:shift] 1;\n/cwm [mod:shift] 2;2\n/cwm [mod:shift] 3;"
    .. "\n/cwm [mod:shift] 4;\n/cwm [mod:shift] 5;\n/cwm [mod:shift] 6;\n/cwm [mod:shift] 7;\n/cwm [mod:shift] 8;")
Equal(doc.steps[1].branches[1].value, "all", "canonical clear-all mutated saved value")
doc.steps[1].branches[1] = Branch("3", { Condition("mod", "shift") })
Compile(doc, "#showtooltip\n/cwm [mod:shift] 3;2")
for _, command in ipairs({ "wm", "cwm" }) do
    doc.steps = { Model.NewStep(command) }
    for _, value in ipairs({ "0", "9", "-1", "01", "square" }) do
        doc.steps[1].branches[1].value = value
        Reject(doc, "Invalid macro action value")
    end
end
for _, command in ipairs({ "petmoveto", "petstay", "stopspelltarget", "leavevehicle" }) do
    doc = Model.New()
    doc.steps = { Model.NewStep(command) }
    doc.steps[1].branches[1].conditions = { Condition("mod", "shift") }
    Compile(doc, "#showtooltip\n/" .. command .. " [mod:shift]")
    doc.steps[1].branches[1].value = "unexpected"
    Reject(doc, "This command needs no value")
end
doc = Model.New()
doc.steps = { Model.NewStep("petdismiss") }
Compile(doc, "#showtooltip\n/petdismiss")
doc.steps[1].branches[1].conditions = { Condition("combat") }
Reject(doc, "This command does not support conditions")
for _, command in ipairs({ "targetenemy", "targetenemyplayer", "targetfriend", "targetfriendplayer",
    "targetparty", "targetraid", "targetlastenemy", "targetlastfriend" }) do
    doc = Model.New()
    doc.steps = { Model.NewStep(command) }
    Compile(doc, "#showtooltip\n/" .. command)
    doc.steps[1].branches[1].value = "1"
    Compile(doc, "#showtooltip\n/" .. command .. " 1")
end
doc = Model.New()
doc.steps = { Model.NewStep("changeactionbar") }
doc.steps[1].branches[1].value = "2"
Compile(doc, "#showtooltip\n/changeactionbar 2")
for _, invalid in ipairs({ "0", "7", "-1", "1.5", "bad" }) do
    doc.steps[1].branches[1].value = invalid
    Reject(doc, "Invalid macro action value")
end
doc.steps = { Model.NewStep("swapactionbar") }
doc.steps[1].branches[1].value = "1 2"
Compile(doc, "#showtooltip\n/swapactionbar 1 2")
for _, invalid in ipairs({ "0 2", "1 7", "7 1", "1", "1 2 3", "one two" }) do
    doc.steps[1].branches[1].value = invalid
    Reject(doc, "Invalid macro action value")
end
doc = Model.New()
doc.steps = { Model.NewStep("party") }
doc.steps[1].branches[1].value = "Ready; {skull}"
Compile(doc, "#showtooltip\n/party Ready; {skull}")
doc.steps[1].branches[1].conditions = { Condition("combat") }
Reject(doc, "This command does not support conditions")

for _, field in ipairs({ "version", "name", "scope", "mode", "icon", "raw", "steps", "showTooltip", "consumable" }) do
    doc = Model.New()
    doc[field] = secret
    Equal(Model.Normalize(doc), nil, "secret document field accepted: " .. field)
end
doc = Model.New()
doc.steps[1].branches[1].value = secret
Equal(Model.Normalize(doc), nil, "secret branch accepted")
doc = Model.New()
doc.steps = { [1] = Model.NewStep(), [3] = Model.NewStep(), [5] = Model.NewStep() }
Equal(Model.Normalize(doc), nil, "sparse actions accepted")
doc = Model.New()
for i = 1, Model.MAX_STEPS + 1 do doc.steps[i] = Model.NewStep() end
Equal(Model.Normalize(doc), nil, "unbounded actions accepted")
doc = Model.New()
doc.name = string.rep("\195\164", 16)
Equal(type(Model.Normalize(doc)), "table", "UTF-8 macro name")
doc.name = doc.name .. "a"
Equal(Model.Normalize(doc), nil, "macro name limit")
print("PASS suite macros compiler: " .. checks .. " checks")
