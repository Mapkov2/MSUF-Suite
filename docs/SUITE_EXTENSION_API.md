# MSUF Suite extensions

Declare `MSUF_Suite` as a dependency in your addon's TOC. `MSUFSuite.API.Extensions` has its own version, currently `1`.

```lua
local api = MSUFSuite.API.Extensions
if not api or api.version ~= 1 then return end

local provider = api.Register("ExampleAddon", function(kind, identity)
    if kind == "Item" and identity == 6948 then
        return "My collection", "Collected"
    end
end)
if not provider then return end

provider.PublishDataText("My collection", "24 items", 134414)
provider.SetSetting("includeCollected", false)
```

- Register once with your addon's TOC directory name. Omit the callback if you only publish a data text. Register returns a handle or nil if that ID is already in use.
- Tooltip providers return one label and value. Suite calls them when its tooltip details are enabled, outside combat. Units are supplied as a unit token. Items and spells are supplied as a public ID. Return nil to skip the row. Keep the callback read-only. Suite disables a failing callback for the session.
- Publish data text when your value changes. Choose the publication from a data bar's Broker source list. Pass a public text label, a public text value and, optionally, a texture path or file ID. The API coalesces changes to running data bars.
- GetSetting and SetSetting read or write the active profile's plugin state. Values can be a boolean, finite number, or up to 240 bytes of text. SetSetting accepts nil to delete a key, up to 32 keys per provider, and runs outside combat. This state lives with the local profile.
- The retired RegisterProfile method returns false for compatibility with existing v1 callers.
- Unregister() withdraws its tooltip callback and data text. Local plugin state is kept for the next registration.
