local _, NS = ...

-- RFC 1951 size preflight: count literals and backreferences without building
-- the output string. The native decoder still validates checksums and data.
-- Both raw DEFLATE and RFC 1950 zlib envelopes are accepted.
local floor = math.floor
local POW = {}
for i = 0, 16 do POW[i] = 2 ^ i end

local function Bits(reader, count)
    while reader.bits < count do
        if reader.pos > reader.last then return nil end
        reader.value = reader.value + reader.text:byte(reader.pos) * POW[reader.bits]
        reader.pos, reader.bits = reader.pos + 1, reader.bits + 8
    end
    local value = reader.value % POW[count]
    reader.value, reader.bits = floor(reader.value / POW[count]), reader.bits - count
    return value
end

local function Tree(lengths, first, last)
    local counts, symbols, offsets = {}, {}, {}
    for i = 0, 15 do counts[i] = 0 end
    for i = first, last do
        local length = lengths[i]
        if length == nil or length > 15 then return nil end
        counts[length] = counts[length] + 1
    end
    local left, offset = 1, 1
    for length = 1, 15 do
        left = left * 2 - counts[length]
        if left < 0 then return nil end
        offsets[length] = offset
        offset = offset + counts[length]
    end
    for i = first, last do
        local length = lengths[i]
        if length > 0 then
            local index = offsets[length]
            symbols[index], offsets[length] = i - first, index + 1
        end
    end
    return { counts = counts, symbols = symbols }
end

local function Symbol(reader, tree)
    local code, first, index = 0, 0, 1
    for length = 1, 15 do
        local bit = Bits(reader, 1)
        if bit == nil then return nil end
        code = code + bit
        local count = tree.counts[length]
        if code >= first and code - first < count then return tree.symbols[index + code - first] end
        index, first, code = index + count, (first + count) * 2, code * 2
    end
end

local fixedLiterals, fixedDistances
local function FixedTrees()
    if not fixedLiterals then
        local lengths, distances = {}, {}
        for i = 0, 287 do lengths[i] = i <= 143 and 8 or i <= 255 and 9 or i <= 279 and 7 or 8 end
        for i = 0, 31 do distances[i] = 5 end
        fixedLiterals, fixedDistances = Tree(lengths, 0, 287), Tree(distances, 0, 31)
    end
    return fixedLiterals, fixedDistances
end

local ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }
local function CodeLengths(reader, tree, count)
    local lengths, index = {}, 0
    while index < count do
        local value = Symbol(reader, tree)
        if value == nil then return nil end
        local repeats = 1
        if value > 15 then
            local extra = Bits(reader, value == 16 and 2 or value == 17 and 3 or 7)
            if extra == nil or value == 16 and index == 0 then return nil end
            repeats = extra + (value == 18 and 11 or 3)
            value = value == 16 and lengths[index - 1] or 0
        end
        if index + repeats > count then return nil end
        for _ = 1, repeats do
            lengths[index], index = value, index + 1
        end
    end
    return lengths
end

local function DynamicTrees(reader)
    local literals, distances, codes = Bits(reader, 5), Bits(reader, 5), Bits(reader, 4)
    if codes == nil or literals == nil or distances == nil or literals > 29 then return nil end
    literals, distances, codes = literals + 257, distances + 1, codes + 4
    local lengths = {}
    for i = 0, 18 do lengths[i] = 0 end
    for i = 1, codes do
        lengths[ORDER[i]] = Bits(reader, 3)
        if lengths[ORDER[i]] == nil then return nil end
    end
    local tree = Tree(lengths, 0, 18)
    if not tree then return nil end
    lengths = CodeLengths(reader, tree, literals + distances)
    if not lengths or lengths[256] == 0 then return nil end
    return Tree(lengths, 0, literals - 1), Tree(lengths, literals, literals + distances - 1)
end

local LENGTH = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27,
    31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LENGTH_BITS = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2,
    2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DISTANCE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
    193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DISTANCE_BITS = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6,
    6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }

local function CompressedBlock(reader, literals, distances, size, limit)
    while true do
        local symbol = Symbol(reader, literals)
        if symbol == nil or symbol > 285 then return nil, "invalid-deflate" end
        if symbol == 256 then return size end
        if symbol < 256 then
            size = size + 1
        else
            local index = symbol - 256
            local extra = Bits(reader, LENGTH_BITS[index])
            local distance = Symbol(reader, distances)
            if extra == nil or distance == nil or distance > 29 then return nil, "invalid-deflate" end
            local offset = Bits(reader, DISTANCE_BITS[distance + 1])
            if offset == nil or DISTANCE[distance + 1] + offset > size then return nil, "invalid-deflate" end
            size = size + LENGTH[index] + extra
        end
        if size > limit then return nil, "import-too-large" end
    end
end

local function StoredBlock(reader, size, limit)
    reader.value, reader.bits = 0, 0
    local length, inverse = Bits(reader, 16), Bits(reader, 16)
    if inverse == nil or length == nil or length + inverse ~= 65535 then return nil, "invalid-deflate" end
    if reader.pos + length - 1 > reader.last then return nil, "invalid-deflate" end
    size, reader.pos = size + length, reader.pos + length
    if size > limit then return nil, "import-too-large" end
    return size
end

local function Measure(text, limit, first, last)
    local reader = { text = text, pos = first, last = last, bits = 0, value = 0 }
    local size, final = 0, 0
    while final == 0 do
        final = Bits(reader, 1)
        local kind = Bits(reader, 2)
        if final == nil or kind == nil or kind == 3 then return nil, "invalid-deflate" end
        local reason
        if kind == 0 then
            size, reason = StoredBlock(reader, size, limit)
        else
            local literals, distances
            if kind == 1 then literals, distances = FixedTrees() else literals, distances = DynamicTrees(reader) end
            if not literals or not distances then return nil, "invalid-deflate" end
            size, reason = CompressedBlock(reader, literals, distances, size, limit)
        end
        if not size then return nil, reason end
    end
    -- A native decoder may accept trailing bytes after the final block.
    return size
end

function NS.DeflateSize(text, limit)
    local raw, reason = Measure(text, limit, 1, #text)
    if reason == "import-too-large" then return nil, reason end
    local cmf, flags = text:byte(1, 2)
    if flags and cmf % 16 == 8 and floor(cmf / 16) <= 7 and (cmf * 256 + flags) % 31 == 0
        and floor(flags / 32) % 2 == 0 and #text >= 6 then
        local wrapped, why = Measure(text, limit, 3, #text - 4)
        if why == "import-too-large" then return nil, why end
        if wrapped then return math.max(raw or 0, wrapped) end
    end
    return raw, reason
end
