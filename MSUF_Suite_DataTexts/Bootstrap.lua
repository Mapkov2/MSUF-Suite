local _, private = ...
local suite = assert(_G.MSUFSuite, "MSUF_Suite is required")
private.NS, private.Suite = suite, suite.Suite
-- What every DataText shows without a value: U+2014 EM DASH, written as its
-- UTF-8 bytes so that no editor can store it in another encoding.
private.NO_VALUE = "\226\128\148"
-- The places of one DataTexts bar.
private.SLOT_COUNT = 6
-- The DataTexts module (DataTexts.lua installs it): its bars and source state.
private.DataTexts = { bars = {}, pool = {}, barIDs = {}, presentIDs = {}, due = {}, values = {},
    events = {} }
