local _, private = ...
local suite = assert(_G.MSUFSuite, 'MSUF_Suite is required')
private.NS, private.Suite = suite, suite.Suite
-- MSUF's own media: the default look of the XP bar and the Skyriding HUD.
private.MSUF_BAR_TEXTURE = "Interface\AddOns\MidnightSimpleUnitFrames\Media\Bars\MSUF_Lucent_v2.tga"
private.MSUF_FONT = "Interface\AddOns\MidnightSimpleUnitFrames\Media\Fonts\Expressway SemiBold.ttf"
