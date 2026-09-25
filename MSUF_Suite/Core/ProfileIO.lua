local _, Suite = ...
local IO = { prefix = "MSUFM1:", maxBytes = 2 * 1024 * 1024 }
Suite.ProfileIO = IO

local function CodecAvailable()
    local codec = _G.C_EncodingUtil
    return type(_G.MSUF_EncodeCompactTable) == "function"
        and type(_G.MSUF_TryDecodeCompactString) == "function"
        and codec and type(codec.SerializeCBOR) == "function"
        and type(codec.DeserializeCBOR) == "function"
        and type(codec.EncodeBase64) == "function"
        and type(codec.DecodeBase64) == "function"
        and type(codec.CompressString) == "function"
        and type(codec.DecompressString) == "function"
        and Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate ~= nil
end

-- Copy only documented module settings. Runtime history, skin configuration,
-- unknown keys and sharing metadata cannot enter the module profile.
function IO.PrepareTable(profile, shared)
    local data = type(profile) == "table" and profile.suite
    if type(data) ~= "table" or data.schema ~= 1 or type(data.modules) ~= "table" then
        return nil, "Unsupported suite profile"
    end
    local result = { suite = { schema = 1, modules = {} } }
    for _, id in ipairs(Suite.SuiteOrder) do
        local source = data.modules[id]
        if source ~= nil and type(source) ~= "table" then return nil, "Invalid module settings" end
        local target = {}
        result.suite.modules[id] = target
        if source then
            for key, rule in pairs(Suite.SuiteCatalog[id].rules) do
                local value = source[key]
                if value ~= nil then
                    if type(value) ~= type(rule.default) then return nil, "Invalid module setting" end
                    if type(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
                        return nil, "Invalid module number"
                    end
                    if type(value) == "string" and #value > rule.maxLength then
                        return nil, "Module setting is too long"
                    end
                    target[key] = value
                end
            end
        end
    end
    Suite.Suite.Normalize(result)
    if shared then Suite.Suite.SanitizeImport(result) end
    return result
end

function IO.ExportProfile(name)
    local profile = Suite.Database.GetProfile(name or Suite.Database.GetActiveProfileName())
    local clean, reason = IO.PrepareTable(profile, false)
    if not clean then return nil, reason end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local encoded = _G.MSUF_EncodeCompactTable({ addon = "MSUF_Suite", format = 1, profile = clean }, "MSUF3")
    if type(encoded) ~= "string" or #encoded > IO.maxBytes then return nil, "Suite profile is too large" end
    return IO.prefix .. encoded
end

-- A module-only string carries one catalog entry and leaves every other Suite
-- module and all MSUF frame settings alone when imported.
function IO.ExportModule(id)
    if not Suite.SuiteCatalog[id] then return nil, "Unknown suite module" end
    local profile = Suite.Database.GetProfile(Suite.Database.GetActiveProfileName())
    local clean, reason = IO.PrepareTable(profile, false)
    if not clean then return nil, reason end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local encoded = _G.MSUF_EncodeCompactTable({
        addon = "MSUF_Suite", format = 2, module = id,
        settings = clean.suite.modules[id],
    }, "MSUF3")
    if type(encoded) ~= "string" or #encoded > IO.maxBytes then return nil, "Suite module profile is too large" end
    return "MSUFM2:" .. encoded
end

function IO.PrepareModuleProfile(text)
    if type(text) ~= "string" or #text > IO.maxBytes + 7 or text:sub(1, 7) ~= "MSUFM2:" then
        return nil, nil, "Invalid suite module profile"
    end
    if not CodecAvailable() then return nil, nil, "Profile codec unavailable on this client" end
    local encoded = text:sub(8)
    if encoded:sub(1, 6) ~= "MSUF3:" then return nil, nil, "Invalid suite module payload" end
    local envelope = _G.MSUF_TryDecodeCompactString(encoded)
    if type(envelope) ~= "table" or envelope.addon ~= "MSUF_Suite" or envelope.format ~= 2
        or type(envelope.module) ~= "string" or not Suite.SuiteCatalog[envelope.module]
        or type(envelope.settings) ~= "table" then
        return nil, nil, "Unsupported suite module profile"
    end
    local id = envelope.module
    local clean, reason = IO.PrepareTable({ suite = { schema = 1, modules = { [id] = envelope.settings } } }, true)
    if not clean then return nil, nil, reason end
    return id, clean.suite.modules[id]
end

function IO.PrepareProfile(text, shared)
    if type(text) ~= "string" or #text > IO.maxBytes + #IO.prefix then return nil, "Invalid suite profile" end
    if text:sub(1, #IO.prefix) ~= IO.prefix then return nil, "Invalid suite profile prefix" end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local encoded = text:sub(#IO.prefix + 1)
    if encoded:sub(1, 6) ~= "MSUF3:" then return nil, "Invalid suite profile payload" end
    local envelope = _G.MSUF_TryDecodeCompactString(encoded)
    if type(envelope) ~= "table" or envelope.addon ~= "MSUF_Suite" or envelope.format ~= 1 then
        return nil, "Unsupported suite profile"
    end
    return IO.PrepareTable(envelope.profile, shared ~= false)
end

-- Older development bundles embedded module settings in a MapkoSkin export.
-- Decode the documented envelope through MSUF's codec, then copy only modules.
-- No installed skin addon or access to its current database is needed.
function IO.PrepareLegacyProfile(text)
    if type(text) ~= "string" or #text > IO.maxBytes or text:sub(1, 7) ~= "MSKIN1:" then
        return nil, "Invalid legacy suite profile"
    end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local envelope = _G.MSUF_TryDecodeCompactString("MSUF3:" .. text:sub(8))
    if type(envelope) ~= "table" or envelope.format ~= 1 or envelope.kind ~= "profile"
        or (envelope.addon ~= "MapkoSkin" and envelope.addon ~= "MidnightSkin") then
        return nil, "Unsupported legacy suite profile"
    end
    return IO.PrepareTable(envelope.payload, true)
end
