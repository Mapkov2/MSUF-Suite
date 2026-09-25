local _, NS = ...

local ProfileIO = {
    prefix = "MSKIN1:",
    maxEncodedBytes = 1024 * 1024,
    maxDecodedBytes = 2 * 1024 * 1024,
}
NS.ProfileIO = ProfileIO

local function Codec()
    local codec = C_EncodingUtil
    if not codec or type(codec.SerializeCBOR) ~= "function"
        or type(codec.DeserializeCBOR) ~= "function"
        or type(codec.EncodeBase64) ~= "function"
        or type(codec.DecodeBase64) ~= "function" then
        return nil
    end
    return codec
end

local function CompressionMethod()
    return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
end

-- C_EncodingUtil returns nothing for input it cannot encode or decode; every
-- result is type-checked below instead of trusting it.
local function Encode(envelope)
    local codec = Codec()
    if not codec then return nil, "codec-unavailable" end
    local serialized = codec.SerializeCBOR(envelope)
    if type(serialized) ~= "string" or #serialized > ProfileIO.maxDecodedBytes then
        return nil, "serialize-failed"
    end
    local payload = serialized
    local method = CompressionMethod()
    if method and type(codec.CompressString) == "function" then
        local compressed = codec.CompressString(serialized, method)
        if type(compressed) == "string" and #compressed < #serialized then
            payload = compressed
        end
    end
    local encoded = codec.EncodeBase64(payload)
    if type(encoded) ~= "string" then return nil, "encode-failed" end
    if #encoded > ProfileIO.maxEncodedBytes then return nil, "export-too-large" end
    return ProfileIO.prefix .. encoded
end

local function Decode(text)
    if type(text) ~= "string" then return nil, "invalid-input" end
    text = text:match("^%s*(.-)%s*$") or ""
    if #text > ProfileIO.maxEncodedBytes + #ProfileIO.prefix then return nil, "import-too-large" end
    if text:sub(1, #ProfileIO.prefix) ~= ProfileIO.prefix then return nil, "invalid-prefix" end
    local codec = Codec()
    if not codec then return nil, "codec-unavailable" end
    local decoded = codec.DecodeBase64(text:sub(#ProfileIO.prefix + 1))
    if type(decoded) ~= "string" then return nil, "decode-failed" end
    local payload = decoded
    local method = CompressionMethod()
    if method and type(codec.DecompressString) == "function" then
        local inflated = codec.DecompressString(decoded, method)
        if type(inflated) == "string" then payload = inflated end
    end
    if #payload > ProfileIO.maxDecodedBytes then return nil, "import-too-large" end
    -- DecodeBase64 and DecompressString return nothing for bad input and
    -- DeserializeCBOR declares a nilable result (EncodingUtilDocumentation).
    -- TODO(in-game): confirm it returns nil rather than raising for malformed
    -- CBOR that survived both steps.
    local envelope = codec.DeserializeCBOR(payload)
    if type(envelope) ~= "table" then return nil, "deserialize-failed" end
    if (envelope.addon ~= "MapkoSkin" and envelope.addon ~= "MidnightSkin")
        or envelope.format ~= 1 then
        return nil, "incompatible"
    end
    return envelope
end

function ProfileIO.ExportProfile(name)
    name = name or NS.Database.GetActiveProfileName()
    local profile = NS.Database.GetProfile(name)
    if not profile then return nil, "missing-profile" end
    return Encode({ addon = "MapkoSkin", format = 1, kind = "profile", name = name,
        payload = NS.CopyValue(profile) })
end

function ProfileIO.ExportAll()
    local root = NS.Database.GetRoot()
    if not root then return nil, "uninitialized" end
    return Encode({ addon = "MapkoSkin", format = 1, kind = "database",
        activeProfile = root.activeProfile, payload = NS.CopyValue(root.profiles) })
end

-- Read-only staging shared with the suite's combined import. Both payloads
-- must be accepted before the suite creates either target profile.
function ProfileIO.PrepareProfile(text)
    local envelope, reason = Decode(text)
    if not envelope then return nil, reason end
    if envelope.kind ~= "profile" or type(envelope.payload) ~= "table" then
        return nil, "not-a-profile"
    end
    local profile = NS.Database.SanitizeProfile(envelope.payload)
    if not profile then return nil, "invalid-profile" end
    return profile, envelope.name
end

function ProfileIO.ImportProfile(text, targetName)
    if NS.IsCombatLocked() then return false, "combat" end
    local profile, nameOrReason = ProfileIO.PrepareProfile(text)
    if not profile then return false, nameOrReason end
    targetName = NS.Database.NormalizeProfileName(targetName or nameOrReason)
    if not targetName then return false, "invalid-name" end
    NS.Database.SetProfile(targetName, profile)
    NS.Database.SetActiveProfile(targetName)
    return true, targetName
end

function ProfileIO.ImportAll(text)
    if NS.IsCombatLocked() then return false, "combat" end
    local envelope, reason = Decode(text)
    if not envelope then return false, reason end
    if envelope.kind ~= "database" or type(envelope.payload) ~= "table" then
        return false, "not-a-database"
    end
    return NS.Database.ReplaceProfiles(envelope.payload, envelope.activeProfile)
end

return ProfileIO
