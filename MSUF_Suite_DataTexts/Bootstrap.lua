local _, private = ...
local suite = assert(_G.MSUFSuite, "MSUF_Suite is required")
private.NS, private.Suite = suite, suite.Suite
-- What every DataText shows without a value: U+2014 EM DASH, written as its
-- UTF-8 bytes so that no editor can store it in another encoding.
private.NO_VALUE = "\226\128\148"
