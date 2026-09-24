-- Shared by the suite contract tests (not a test itself). Files load in TOC
-- order, so the tests follow load-order changes without their own file lists.
local Support = {}

function Support.TocFiles(root, addon, flavor)
    local path = root .. "/" .. addon .. "/" .. addon .. "_" .. (flavor or "Mainline") .. ".toc"
    local toc = assert(io.open(path, "rb"), "missing " .. path)
    local text = toc:read("*a"):gsub("\r", "")
    toc:close()
    local files = {}
    for line in text:gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    return files
end

-- Loads the addon's Lua files up to and including `through` (for example
-- "Core/Suite.lua"). Files listed in `skip` are left out.
function Support.Load(root, addon, namespace, through, skip, flavor)
    local reached = through == nil
    for _, file in ipairs(Support.TocFiles(root, addon, flavor)) do
        if file:match("%.lua$") and not (skip and skip[file]) then
            assert(loadfile(root .. "/" .. addon .. "/" .. file))(addon, namespace)
        end
        if file == through then reached = true; break end
    end
    assert(reached, tostring(through) .. " is not listed in the " .. addon .. " TOC")
    return namespace
end

return Support
