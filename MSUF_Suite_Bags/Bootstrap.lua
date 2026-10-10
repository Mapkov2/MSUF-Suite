local _, private = ...
local suite = assert(_G.MSUFSuite, 'MSUF_Suite is required')
private.NS, private.Suite = suite, suite.Suite

-- A Suite frame inside Blizzard's bag or bank window. On WoW Forever's
-- Gamepad UI an open bag or bank window is a panel of Blizzard's frame
-- controls manager, and SmartNavigation post-hooks CreateFrame: a frame
-- created with a parent below such a panel makes it rescan the panel in the
-- caller's execution (Blizzard_GamepadSmartNavigation/SmartNavigation.lua
-- SetupFrameHooks and UpdateParent), which from the Suite's code taints the
-- panel's navigation and the gamepad's item use. Created without a parent and
-- parented afterwards, the frame never reaches that hook (as
-- Safety.CreateChildFrame in MSUF_Suite_Skin/Core/Safety.lua). Every frame
-- below a Blizzard window comes from here, its own children included. The
-- templates used here need no parent while they load.
function private.ChildFrame(kind, parent, template)
    local frame = suite.Suite.CreateFrame(kind, nil, nil, template)
    frame:SetParent(parent)
    return frame
end
