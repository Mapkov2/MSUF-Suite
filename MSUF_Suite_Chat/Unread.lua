local _, P = ...
local S = P.Suite
local C = P.Chat
local Module = C.M
local types = {}
local CHAT_TYPES = { "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "WHISPER", "BN_WHISPER" }

function C.CompileUnread(config)
    for id in pairs(types) do types[id] = nil end
    if not config.coloredUnreadTabs then return end
    for _, name in ipairs(CHAT_TYPES) do
        local info = ChatTypeInfo[name]
        if info and S.Finite(info.id) then types[info.id] = info end
    end
end

function C.ClearUnread(visual)
    visual.unreadType = nil
    if visual.unreadLine then visual.unreadLine:Hide() end
end

function C.ApplyUnread(visual, tab)
    if not Module.config.coloredUnreadTabs then
        C.ClearUnread(visual)
        return
    end
    if not visual.unreadLine then
        visual.unreadLine = C.Fill(tab, "OVERLAY")
        visual.unreadLine:SetPoint("TOPLEFT", tab, "TOPLEFT", 5, -2)
        visual.unreadLine:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -5, -2)
        visual.unreadLine:SetHeight(2)
        visual.unreadLine:Hide()
    end
end

-- AddMessage's fifth argument is the chat type ID on both clients
-- (ChatFrameOverrides.lua). Observe delivery to this exact window, after
-- Blizzard applied its filters. Never inspect text, names or native buffers.
function C.MessageUnread(frame, chatTypeID)
    if frame == ChatFrame2 or not S.Finite(chatTypeID) then return end
    local info, visual = types[chatTypeID], Module.visuals[frame]
    if not (info and visual and visual.unreadLine) then return end
    if C.TabSelected(frame, nil, C.DockSelection()) then return end
    if not (S.Finite(info.r) and S.Finite(info.g) and S.Finite(info.b)) then return end
    visual.unreadType = chatTypeID
    visual.unreadLine:SetColorTexture(info.r, info.g, info.b, 1)
    visual.unreadLine:Show()
end
