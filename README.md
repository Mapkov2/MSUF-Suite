# MSUF Suite

**Version 1.0 Alpha 1** is a public test build of the Suite modules for WoW Retail and WoW Forever. The Suite is packaged separately but currently requires [Midnight Simple Unit Frames](https://github.com/Mapkov2/MidnightSimpleUnitFrames).

## Install

1. Install the MSUF build for your WoW client. WoW Forever testers should use the current MSUF Classic beta.
2. Download the Suite alpha ZIP from this repository's Releases page.
3. Extract the `MSUF_Suite*` folders directly into that client's `Interface/AddOns` folder. There should be no extra wrapper folder around them.
4. Enable MSUF and the desired Suite modules in the AddOns list, then open the MSUF options with `/msuf`.

The ZIP contains the Suite core, its optional modules, and the Suite-owned Skinning module. Your existing SavedVariables are not part of the ZIP.

## Testing

Please report the WoW client and build, the MSUF and Suite versions, steps to reproduce, any Lua error text, and a screenshot when the issue is visual. Open an [issue](https://github.com/Mapkov2/MSUF-Suite/issues) for Suite problems. For MSUF core problems, use the [MSUF issue tracker](https://github.com/Mapkov2/MidnightSimpleUnitFrames/issues).

This alpha passed the repository's offline Suite contracts for Retail and WoW Forever. It still needs live client, combat, and visual testing.

## Copyright

Copyright (c) 2026 Mapko. All rights reserved. See [LICENSE.txt](LICENSE.txt). Bundled third-party components retain their own terms; the Skinning module lists them in [`MSUF_Suite_Skin/THIRD_PARTY_NOTICES.txt`](MSUF_Suite_Skin/THIRD_PARTY_NOTICES.txt).
