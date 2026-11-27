-- Inventory stays readable when the mailbox opens over an existing workflow.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    UIPanelWindows.MailFrame = { area = "left" }
    local mail = Native("MailFrame", 100, 100, 340, 490)
    local letter = Native("OpenMailFrame", 450, 100, 310, 350)
    local bag = Native("ContainerFrameCombinedBags", 800, 100, 350, 480)
    local split = Native("ContainerFrame4", 1200, 100, 210, 340)
    local other = Native("ProfessionsFrame", 1450, 100, 320, 470)
    mail:Hide(); letter:Hide(); split:Hide()
    Check(W.TrackFocus(other, "windows") and W.TrackFocus(bag, "windows"), "fixture lost its starting windows")
    Check(W.TrackFocus(mail, "windows") and W.TrackFocus(letter, "windows"), "native mailbox was not enrolled")
    Check(W.TrackFocus(split, "windows"), "split bag was not enrolled")
    Click(bag); Tick()
    Check(not Dimmed(bag) and Dimmed(other), "fixture bag was not in focus")
    for _, name in ipairs({ "BNToastFrame", "TimeAlertFrame" }) do
        local toast = Native(name, 780, 140, 240, 80)
        toast.CloseButton = Frame(nil, toast, "Button")
        toast:SetFrameStrata("LOW")
        toast:Hide()
        local tracked = W.TrackFocus(toast, "social")
        toast:Show(); Tick()
        Check(not tracked and F.active.frame == bag and not Dimmed(bag),
            "passive " .. name .. " took focus from inventory")
        toast:Hide(); Tick()
    end
    local settleMail = C_Timer.After
    local mailJobs = {}
    C_Timer.After = function(_, job) mailJobs[#mailJobs + 1] = job end
    local function FlushMailFocus()
        local jobs = mailJobs
        mailJobs = {}
        for _, job in ipairs(jobs) do job() end
    end
    _G.combatEdge = true
    mail:Show()
    if flavor == "Forever" then
        Check(F.active.frame == bag and not F.records[mail].extents,
            "mailbox focus scanned native chrome before Blizzard finished opening mail")
        split:Show()
        Check(not F.records[split].extents and #mailJobs == 1,
            "bags opened by the mailbox ran a synchronous focus pass or queued another pass")
        FlushMailFocus()
        Check(F.active.frame == split and F.records[mail].footprintCount == 1 and F.records[split].footprintCount,
            "mail and bag focus did not settle together while combat was still active")
    else
        Check(#mailJobs == 0, "Retail mailbox focus waited for the next frame")
        Tick()
        Check(F.active.frame == mail, "Retail mailbox focus did not settle in its opening frame")
        split:Show()
    end
    _G.combatEdge = false
    Tick()
    Check(not Dimmed(bag) and #F.records[bag].veils == 0, "the opening mailbox dims an already active bag")
    Check(not Dimmed(mail) and Dimmed(other), "mail exception changed unrelated window focus")
    Click(other); Tick()
    Check(not Dimmed(bag) and not Dimmed(split) and not Dimmed(mail), "mailing group lost focus after third-window input")
    letter:Show(); Tick()
    Check(not Dimmed(bag) and not Dimmed(mail) and not Dimmed(letter), "reading mail faded a mailing window")
    mail:Hide(); Tick()
    Check(not Dimmed(bag) and not Dimmed(letter), "a standalone open letter faded inventory")
    letter:Hide(); Click(other); Tick()
    Check(Dimmed(bag) and Dimmed(split), "closing mail retained the mailing group")
    split:Hide()
    mail:Show(); bag:Hide(); FlushMailFocus(); Click(other); Tick()
    Check(Dimmed(mail), "mail without inventory must obey normal focus")
    if flavor == "Forever" then
        mail:Hide(); Click(other)
        local order = F.records[mail].order
        mail:Show(); mail:Hide(); FlushMailFocus()
        Check(F.active.frame == other and not F.records[mail].focusVisible and not Dimmed(mail),
            "a mailbox closed before its focus pass came back into view")
        Check(F.records[mail].order > order, "queued mailbox show did not retain native opening order")
    end
    C_Timer.After = settleMail
end
print("suite_window_focus_mail_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@window_focus_mail_contract"))()
