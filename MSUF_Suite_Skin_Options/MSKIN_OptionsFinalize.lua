local _, Private = ...
local NS, O = Private.NS, Private.Options

NS.OptionsReady = type(O.Open) == "function" and type(O.BuildWindow) == "function"
