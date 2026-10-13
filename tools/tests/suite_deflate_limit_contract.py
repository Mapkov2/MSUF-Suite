"""Differential output-count proof against Python's independent zlib decoder."""
import os
import base64
from pathlib import Path
import random
import re
import subprocess
import sys
import zlib

ROOT = Path(sys.argv[1])
LUA = os.environ.get('MSUF_LUA51', r'C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe')
rng = random.Random(17013)
cases = []
for size in (0, 1, 2, 127, 1024, 32768, 65535, 65536, 131071, 2097152, 2097153, 3145728):
    sources = [b'a' * size, (bytes(range(251)) * ((size + 250) // 251))[:size]]
    if size <= 131071:
        sources.append(rng.randbytes(size))
    for source in sources:
        for wrapper in (-15, 15):
            for level, strategy in ((0, zlib.Z_DEFAULT_STRATEGY), (1, zlib.Z_DEFAULT_STRATEGY),
                                    (9, zlib.Z_DEFAULT_STRATEGY), (6, zlib.Z_FIXED)):
                codec = zlib.compressobj(level, zlib.DEFLATED, wrapper, strategy=strategy)
                packed = codec.compress(source) + codec.flush()
                # The import boundary rejects larger input before preflight.
                if len(packed) <= 128 * 1024:
                    cases.append((packed, len(source)))
for _ in range(200):
    source = rng.randbytes(rng.randrange(1024)) * rng.randrange(1, 30)
    wrapper = rng.choice((-15, 15))
    codec = zlib.compressobj(rng.randrange(1, 10), zlib.DEFLATED, wrapper)
    packed = codec.compress(source[:10]) + codec.flush(zlib.Z_SYNC_FLUSH)
    packed += codec.compress(source[10:]) + codec.flush()
    cases.append((packed, len(source)))

# A valid zlib stream can contain a much larger valid raw DEFLATE prefix.
payload = bytearray(65379)
bomb_codec = zlib.compressobj(wbits=-15)
bomb_raw = bomb_codec.compress(b'A' * (3 * 1024 * 1024)) + bomb_codec.flush()
payload[154:154 + len(bomb_raw)] = bomb_raw
polyglot = bytes.fromhex('789c0063ff9c00') + payload + bytes.fromhex('0300') + zlib.adler32(payload).to_bytes(4, 'big')
assert len(zlib.decompress(polyglot)) == 65379
raw_size = len(zlib.decompress(polyglot, wbits=-15))
assert raw_size > 2097152
cases.append((polyglot, raw_size))

# Real supplied in-game skin exports shipped with the factories are a second
# corpus, independent of the generated zlib cases. Preserve their exact bytes.
factory_vectors = []
for name in ('ForeverFactory.lua', 'RetailSkinFactory.lua'):
    path = ROOT / 'MSUF_Suite/Core' / name
    for encoded in re.findall(r'\[\[MSKIN1:([A-Za-z0-9+/=]+)\]\]', path.read_text(encoding='utf-8')):
        packed = base64.b64decode(encoded, validate=True)
        try:
            payload = zlib.decompress(packed, wbits=-15)
        except zlib.error:
            payload = zlib.decompress(packed)
        assert len(packed) <= 128 * 1024 and len(payload) <= 2097152
        cases.append((packed, len(payload)))
        factory_vectors.append((path.name, len(packed), len(payload)))
assert len(factory_vectors) == 2, 'both client factory export vectors are required'
print('Shipped native factory vectors:', factory_vectors)

script = r'''
local root = assert(arg[1])
local NS = {}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DeflateSize.lua"))("MSUF_Suite_Skin", NS)
local limit, count = 2097152, 0
for line in io.lines() do
    local expected, hex = line:match("^(%d+):(.*)$")
    expected = assert(tonumber(expected))
    local packed = hex:gsub("..", function(byte) return string.char(tonumber(byte, 16)) end)
    local actual, reason = NS.DeflateSize(packed, limit)
    if expected > limit then
        assert(actual == nil and reason == "import-too-large", "oversized output accepted")
    else
        assert(actual == expected, "output count mismatch: " .. tostring(actual) .. "/" .. expected)
    end
    count = count + 1
end
-- The profile boundary must reject an oversized valid stream before invoking
-- the native decoder. Plain CBOR still goes straight to deserialization.
Enum = { CompressionMethod = { Deflate = 0 } }
local decompressions = 0
C_EncodingUtil = {
    DecodeBase64 = function(text) return (text:gsub("..", function(byte) return string.char(tonumber(byte, 16)) end)) end,
    DecompressString = function() decompressions = decompressions + 1; error("native inflation reached") end,
    DeserializeCBOR = function() return { addon = "MapkoSkin", format = 1, kind = "profile", payload = {} } end,
}
NS.Safety = { Dispatch = function(callback, ...) return callback(...) end }
NS.Database = { SanitizeProfile = function(profile) return profile end }
assert(loadfile((arg[3] or root) .. "/MSUF_Suite_Skin/Core/ProfileIO.lua"))("MSUF_Suite_Skin", NS)
local profile, reason = NS.ProfileIO.PrepareProfile("MSKIN1:" .. assert(arg[2]))
assert(profile == nil and reason == "import-too-large" and decompressions == 0, "native inflate was not bounded")
assert(NS.ProfileIO.PrepareProfile("MSKIN1:a0") and decompressions == 0, "plain CBOR compatibility lost")
print("DEFLATE raw/zlib/stored/fixed/dynamic/multiblock/limit cases: " .. count)
'''
# Write the transient Lua driver outside the source tree.
import tempfile
with tempfile.TemporaryDirectory(prefix='suite-deflate-') as scratch:
    driver = Path(scratch) / 'driver.lua'
    driver.write_text(script, encoding='utf-8')
    bomb = zlib.compress(b'A' * (3 * 1024 * 1024)).hex()
    data = ''.join(f'{size}:{packed.hex()}\n' for packed, size in cases)
    run = subprocess.run([LUA, str(driver), str(ROOT), bomb, sys.argv[2] if len(sys.argv) > 2 else str(ROOT)], input=data, text=True, capture_output=True)
    print(run.stdout, end='')
    if run.returncode:
        print(run.stderr, end='', file=sys.stderr)
    sys.exit(run.returncode)
