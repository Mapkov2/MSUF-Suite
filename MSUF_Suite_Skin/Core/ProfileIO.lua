local _, NS = ...

-- DecompressString takes no output limit and Deflate expands up to about
-- 1:1032, so the compressed payload cap bounds what an import can inflate.
-- One fully customized profile compresses to under 8 KB; the cap leaves room
-- for an "export all" of well over a dozen of them. Exports keep to the same
-- caps, so every string the skin writes can be read back.
local ProfileIO = {
    prefix = "MSKIN1:",
    maxCompressedBytes = 128 * 1024,
    maxEncodedBytes = 176 * 1024,
    maxDecodedBytes = 2 * 1024 * 1024,
}
NS.ProfileIO = ProfileIO

-- C_EncodingUtil (Retail and Forever) returns nothing for input it cannot
-- encode or decode; every result is type-checked below instead of trusting it.
local function Encode(envelope)
    local codec = C_EncodingUtil
    local serialized = codec.SerializeCBOR(envelope)
    if type(serialized) ~= "string" or #serialized > ProfileIO.maxDecodedBytes then
        return nil, "serialize-failed"
    end
    local payload = serialized
    local compressed = codec.CompressString(serialized, Enum.CompressionMethod.Deflate)
    if type(compressed) == "string" and #compressed < #serialized then
        payload = compressed
    end
    if #payload > ProfileIO.maxCompressedBytes then return nil, "export-too-large" end
    local encoded = codec.EncodeBase64(payload)
    if type(encoded) ~= "string" then return nil, "encode-failed" end
    if #encoded > ProfileIO.maxEncodedBytes then return nil, "export-too-large" end
    return ProfileIO.prefix .. encoded
end

local function Deserialize(payload)
    return C_EncodingUtil.DeserializeCBOR(payload)
end

local function Decode(text)
    if type(text) ~= "string" then return nil, "invalid-input" end
    text = text:match("^%s*(.-)%s*$") or ""
    if #text > ProfileIO.maxEncodedBytes + #ProfileIO.prefix then return nil, "import-too-large" end
    if text:sub(1, #ProfileIO.prefix) ~= ProfileIO.prefix then return nil, "invalid-prefix" end
    local codec = C_EncodingUtil
    local decoded = codec.DecodeBase64(text:sub(#ProfileIO.prefix + 1))
    if type(decoded) ~= "string" then return nil, "decode-failed" end
    if #decoded > ProfileIO.maxCompressedBytes then return nil, "import-too-large" end
    local payload = decoded
    local inflated = codec.DecompressString(decoded, Enum.CompressionMethod.Deflate)
    if type(inflated) == "string" then payload = inflated end
    if #payload > ProfileIO.maxDecodedBytes then return nil, "import-too-large" end
    -- DeserializeCBOR declares a nilable result (EncodingUtilDocumentation).
    -- It runs as its own boundary: should it raise for malformed CBOR, the
    -- error is reported and the import fails like one it returned nil for.
    local envelope = NS.Safety.Dispatch(Deserialize, payload)
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

-- The first maxBytes bytes of text without a cut-off UTF-8 sequence.
local function LeadingBytes(text, maxBytes)
    text = text:sub(1, maxBytes)
    local last = #text
    local start = last
    while start > 0 and text:byte(start) >= 128 and text:byte(start) < 192 do
        start = start - 1
    end
    local lead = start > 0 and text:byte(start) or 0
    local size = lead >= 240 and 4 or lead >= 224 and 3 or lead >= 192 and 2 or 1
    if start > 0 and last - start + 1 < size then text = text:sub(1, start - 1) end
    return text
end

-- name, or "name (2)", "name (3)" ... for the first one no profile uses.
local function FreeName(name)
    if not NS.Database.GetProfile(name) then return name end
    local limit = #NS.Database.GetProfileNames() + 1
    for number = 2, limit + 1 do
        local suffix = " (" .. number .. ")"
        local candidate = NS.Database.NormalizeProfileName(
            LeadingBytes(name, NS.Database.maxProfileNameBytes - #suffix) .. suffix)
        if candidate and not NS.Database.GetProfile(candidate) then return candidate end
    end
    return nil
end
ProfileIO.FreeName = FreeName

-- An import never replaces a profile on its own. Without a target name it
-- lands under the exported name, or the first free "name (n)" when that one
-- is taken. A target name that is taken is refused with "profile-exists"
-- (and the normalized name) until the caller confirms the replacement with
-- replace == true.
function ProfileIO.ImportProfile(text, targetName, replace)
    if NS.IsCombatLocked() then return false, "combat" end
    local profile, nameOrReason = ProfileIO.PrepareProfile(text)
    if not profile then return false, nameOrReason end
    local chosen = targetName ~= nil
    targetName = NS.Database.NormalizeProfileName(targetName or nameOrReason)
    if not targetName then return false, "invalid-name" end
    if NS.Database.GetProfile(targetName) and replace ~= true then
        if chosen then return false, "profile-exists", targetName end
        targetName = FreeName(targetName)
        if not targetName then return false, "invalid-name" end
    end
    local stored, reason = NS.Database.SetProfile(targetName, profile)
    if not stored then return false, reason end
    return NS.Database.SetActiveProfile(targetName)
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
