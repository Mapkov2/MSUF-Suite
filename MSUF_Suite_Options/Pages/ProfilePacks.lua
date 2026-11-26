local _, P = ...
local Suite = P.Suite
local Extensions = Suite.Extensions
local PAGE = "suite_profilePacks"

local function Import(pack)
    if P.Combat() then return end
    P.AskText("suite.profilePack." .. pack.id, P.Tr("Name for the new profile:"), function(name)
        local ok, reason = Extensions.ImportProfile(pack.id, pack.revision, name)
        if ok then
            Suite.Print(P.Tr("Profile imported. Choose it in Profiles."))
        elseif reason then
            Suite.Print(P.Tr(reason))
        end
    end, Suite.Database.MAX_PROFILE_NAME_BYTES, Suite.Database.MAX_PROFILE_NAME_BYTES)
end

local function Build(ctx)
    if ctx.searchRows then
        P.SkinSearchRow(ctx, { pageKey = PAGE, kind = "section", label = P.Tr("Profile packs") },
            "profile_packs", P.Tr("Profile packs"))
        return
    end
    local builder = P.W.PageBuilder(ctx)
    P.LazySection(builder, "profile_packs", P.Tr("Profiles from installed addons"), true, {
        content = function(body)
            local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
            local packs = Extensions.ProfilePacks()
            local y = -12
            if #packs == 0 then
                P.Text(body, "No loaded addon has registered a profile.", 16, y, width)
                return 46
            end
            for _, pack in ipairs(packs) do
                local entry = pack
                local label = P.Text(body, "", 16, y, width - 140, nil, "section")
                local version = P.Text(body, "", 16, y - 22, width - 140)
                P.SetTranslatedText(label, entry.label)
                P.SetTranslatedText(version, P.Tr("%s · Revision %d"):format(entry.id, entry.revision))
                P.Button(ctx, body, "Import as new", width - 108, y - 2, 124, function() Import(entry) end)
                y = y - 56
            end
            return -y + 6
        end,
    })
end

P.RegisterPage({ key = PAGE, label = "Profile packs", title = "Profile packs", build = Build,
    icon = { 7, 1 }, nav = "interface", navOrder = 11, aliases = { "profiles", "presets" } })
