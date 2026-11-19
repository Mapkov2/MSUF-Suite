local root = assert(arg[1], "Suite root required")
local secret = {}
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function Boot(forever)
    local world = { items = {}, timers = {}, writes = 0, name = "Recipient-Realm", subject = "" }
    local function Frame()
        local frame = { hooks = {} }
        function frame:HookScript(event, fn) self.hooks[event] = fn end
        function frame:Fire(event, ...)
            if self.hooks[event] then self.hooks[event](self, ...) end
        end
        return frame
    end
    MailFrame, SendMailFrame, SendMailNameEditBox, SendMailSubjectEditBox = Frame(), Frame(), Frame(), Frame()
    SendMailFrame.sendMode = "send"
    function SendMailFrame:IsVisible() return world.visible end
    function SendMailSubjectEditBox:GetText() return world.subject end
    function SendMailSubjectEditBox:SetText(value)
        Check(not world.nativeEvent and not world.combat, "Suite wrote during a native event or combat")
        world.writes = world.writes + 1
        world.subject = value:sub(1, 64)
        if world.externalSubject then world.subject = world.externalSubject end
        -- Native subject OnTextChanged calls SendMailFrame_CanSend.
        world.sendEnabled = #world.subject > 0 and #SendMailNameEditBox:GetText() > 0
        self:Fire("OnTextChanged", false)
    end
    function SendMailNameEditBox:GetText() return world.name end
    function SendMailNameEditBox:SetText() error("recipient field must stay untouched") end
    SendMail = function() error("Suite sent a draft") end
    ATTACHMENTS_MAX_SEND = 12
    HasSendMailItem = function(index)
        local value = world.items[index]
        if value == secret then return secret end
        return value ~= nil
    end
    GetSendMailItem = function(index)
        local item = assert(world.items[index])
        return item[1], nil, nil, item[2]
    end
    C_Mail = {
        IsCODEnabled = function()
            if world.cod == nil then return false end
            return world.cod
        end,
        IsCommandPending = function() return world.mailPending == true end,
    }
    C_Timer = { After = function(delay, fn)
        Check(delay == 0, "attachment refresh must have a single next-frame delay")
        world.timers[#world.timers + 1] = fn
    end }
    EventUtil = { ContinueOnAddOnLoaded = function(addon, fn)
        Check(addon == "Blizzard_MailFrame", "wrong native mail provider")
        world.loadMail = fn
    end }
    function world:Flush()
        local jobs = self.timers
        self.timers = {}
        for _, job in ipairs(jobs) do job() end
    end
    function world:Event(event)
        self.nativeEvent = true
        if event == "MAIL_SEND_SUCCESS" then
            self.subject, self.items, self.sendEnabled = "", {}, false
        end
        MailFrame:Fire("OnEvent", event)
        self.nativeEvent = false
    end
    function world:Attach(name, count, slot)
        self.items[slot or 1] = { name, count }
        self:Event("MAIL_SEND_INFO_UPDATE")
    end
    function world:Edit(value)
        self.subject = value
        SendMailSubjectEditBox:Fire("OnTextChanged", true)
    end

    local suite = {
        Client = { isForever = forever },
        InCombat = function() return world.combat end,
        Safety = { IsForbidden = function(frame) return frame.forbidden == true end },
        Public = function(value) return value ~= secret end,
        IsSecret = function(value) return value == secret end,
        PublicText = function(value) if type(value) == "string" and value ~= "" then return value end end,
        Finite = function(value) return type(value) == "number" and value < math.huge and value > -math.huge end,
    }
    for line in io.lines(root .. "/MSUF_Suite/MSUF_Suite_Mainline.toc") do
        if line == [[Core\ForeverMailSubject.lua]] then
            assert(loadfile(root .. "/MSUF_Suite/Core/ForeverMailSubject.lua"))("MSUF_Suite", suite)
        end
    end
    if world.loadMail then world.loadMail() end
    return world
end

local w = Boot(true)
w.visible = true
w:Attach("Runecloth", 1)
w:Attach("Runecloth", 2)
Check(w.subject == "" and w.writes == 0, "subject changed in the native attachment stack")
w:Flush()
Check(w.subject == "Runecloth (2)" and w.sendEnabled, "first attachment must populate subject and enable native Send")
Check(#w.timers == 0 and w.writes == 1 and w.name == "Recipient-Realm", "attachment updates must coalesce")

w.items[1] = nil
w:Attach("Golden Pearl", 1, 5)
w:Flush()
Check(w.subject == "Golden Pearl", "first remaining attachment can be after a gap")
w:Attach(nil, nil, 5)
w:Flush()
Check(w.subject == "Golden Pearl", "uncached item was treated as removal")
w.items = {}
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == "" and not w.sendEnabled, "removing the last item leaves a stale generated subject")

w:Attach("Linen", 1)
w:Edit("Original message")
w:Flush()
Check(w.subject == "Original message", "queued update overwrote the player's typing")
w:Edit("")
w:Attach("Linen", 2)
w.visible = false
w.visible = true
SendMailFrame:Fire("OnShow")
w:Flush()
Check(w.subject == "", "manually cleared subject was refilled after switching tabs")
w:Event("MAIL_SEND_SUCCESS")
w:Attach("Silk", 1)
w:Flush()
Check(w.subject == "Silk", "new draft retained manual ownership after a send")

w:Event("MAIL_SEND_SUCCESS")
w:Attach("Silk", 5)
w.subject, w.visible, w.items = "", false, {}
MailFrame:Fire("OnHide")
w:Flush()
Check(w.subject == "" and #w.timers == 0, "closed mailbox retained a deferred draft update")
w.visible = true
w:Attach("Wool", 1)
w:Flush()
Check(w.subject == "Wool", "reopened mailbox retained an old draft")

w:Event("MAIL_SEND_SUCCESS")
w.cod, w.combat = true, false
w:Attach("Linen", 1)
w:Flush()
Check(w.subject == "", "Suite interfered with native C.O.D. subject handling")
w.cod, w.combat = false, true
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == "", "addon edited a subject in combat")
w.combat, w.mailPending = false, true
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == "", "addon edited a subject during a pending mail command")
w.mailPending = false
SendMailFrame.sendMode = "reply"
w:Event("MAIL_UNLOCK_SEND_ITEMS")
w:Flush()
Check(w.subject == "", "addon edited a reply")
SendMailFrame.sendMode = "send"
w.visible = secret
w:Event("MAIL_SEND_INFO_UPDATE")
Check(#w.timers == 0, "secret composition visibility scheduled work")
w.visible = true
w:Event("MAIL_SEND_INFO_UPDATE")
w.visible = secret
w:Flush()
Check(w.subject == "", "deferred work wrote through secret composition visibility")
w.visible = true
w.name = secret
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == "", "addon triggered native validation with a restricted recipient")
w.name, w.subject = "Recipient-Realm", secret
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == secret, "addon replaced a restricted subject")
w.subject, w.items[1] = "", secret
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == "", "addon treated an unreadable attachment as public")
w:Attach(secret, secret)
w:Flush()
Check(w.subject == "", "addon used restricted attachment data")
w:Attach(("x"):rep(70), 2)
w:Flush()
Check(w.subject == ("x"):rep(64), "fixture did not truncate the native edit box")
w.items = {}
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == "", "auto subject ownership was lost after native truncation")

w.externalSubject = "Third-party subject"
w:Attach("Wool", 1)
w:Flush()
w.externalSubject, w.items = nil, {}
w:Event("MAIL_SEND_INFO_UPDATE")
w:Flush()
Check(w.subject == "Third-party subject", "addon took ownership of text applied by another handler")

w = Boot(false)
w.visible = true
w:Attach("Retail Item", 1)
w:Flush()
Check(not w.loadMail and w.writes == 0, "Retail must use its own native subject generation")
print("suite_forever_mail_subject_contract: " .. checks .. " checks passed")
