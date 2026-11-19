local _, Suite = ...
if not Suite.Client.isForever then return end

-- On Forever the native attachment subject is generated only when C.O.D.
-- is enabled. Restore the subject in the other branch after native mail work.
local function AttachmentSubject()
    local hasUnresolvedItem
    for index = 1, ATTACHMENTS_MAX_SEND do
        local attached = HasSendMailItem(index)
        if Suite.IsSecret(attached) then return end
        if attached then
            local name, _, _, count = GetSendMailItem(index)
            name = Suite.PublicText(name)
            if name and Suite.Finite(count) then
                if count > 1 then return name .. " (" .. count .. ")" end
                return name
            end
            hasUnresolvedItem = true
        end
    end
    if not hasUnresolvedItem then return "" end
end

local function Observe()
    local mail, compose = _G.MailFrame, _G.SendMailFrame
    local subject, recipient = _G.SendMailSubjectEditBox, _G.SendMailNameEditBox
    local forbidden = Suite.Safety.IsForbidden
    if not (mail and compose and subject and recipient and Suite.Finite(ATTACHMENTS_MAX_SEND)) then return end
    if forbidden(mail) or forbidden(compose) or forbidden(subject) then return end

    local function ComposeVisible()
        if forbidden(compose) then return false end
        local visible = compose:IsVisible()
        return Suite.Public(visible) and visible == true
    end

    local pending, queued, userEdited, automaticSubject
    local function Reset()
        pending, userEdited, automaticSubject = nil, nil, nil
    end

    local function Refresh()
        queued = nil
        if not pending then return end
        pending = nil
        if userEdited or Suite.InCombat() or not ComposeVisible() then return end
        local mode, cod = compose.sendMode, C_Mail.IsCODEnabled()
        if not Suite.Public(mode) or mode ~= "send" or not Suite.Public(cod) or cod ~= false then return end
        if forbidden(subject) then return end
        local text = subject:GetText()
        if not Suite.Public(text) or type(text) ~= "string" then return end
        if text ~= "" and text ~= automaticSubject then return end
        local nextSubject = AttachmentSubject()
        if nextSubject == nil or nextSubject == text then return end
        local mailPending = C_Mail.IsCommandPending()
        if not Suite.Public(mailPending) or mailPending ~= false then return end
        -- The edit box's native OnTextChanged reads the recipient to validate
        -- the draft. Leave that path alone when the value is unreadable.
        if forbidden(recipient) or not Suite.Public(recipient:GetText()) then return end
        subject:SetText(nextSubject)
        -- The box may truncate long names. A different subject supplied by
        -- another handler does not belong to us.
        local written = Suite.PublicText(subject:GetText())
        automaticSubject = written and nextSubject:sub(1, #written) == written and written or nil
    end

    local function Queue()
        if userEdited or not ComposeVisible() then return end
        pending = true
        if queued then return end
        queued = true
        C_Timer.After(0, Refresh)
    end

    subject:HookScript("OnTextChanged", function(_, userInput)
        if Suite.Public(userInput) and userInput == true then userEdited = true end
    end)
    mail:HookScript("OnHide", Reset)
    mail:HookScript("OnEvent", function(_, event)
        if event == "MAIL_SEND_SUCCESS" then Reset()
        elseif event == "MAIL_SEND_INFO_UPDATE" or event == "MAIL_UNLOCK_SEND_ITEMS"
            or event == "MAIL_SUCCESS" or event == "MAIL_FAILED" then Queue() end
    end)
    compose:HookScript("OnShow", Queue)
    Queue()
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_MailFrame", Observe)
