"""Reject broken kit behavior in memory: each mutation of PreviewKit.lua must fail its contract line."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
source = (root / "MSUF_Suite" / "Core" / "PreviewKit.lua").read_text(encoding="utf-8")
cases = [
    ("    if self.queued then return end\n    self.queued = true", "    self.queued = true",
     "requests paint on the next frame, not at once"),
    ("function Host:Request(reason)\n    if not self.active then return end", "function Host:Request(reason)",
     "a closed host holds a timer or queued work"),
    ("on = on == true and self.active == true and self.opts.animate ~= nil", "on = on == true and self.opts.animate ~= nil",
     "a closed host holds a timer or queued work"),
    ("    self:SetAnimate(false)\n    if self.handles", "    if self.handles", "closing stops the ticker and hides the frame"),
    ("    if not pool.on[index] then\n        pool.on[index] = true\n        object:Show()\n    end",
     "    pool.on[index] = true\n    object:Show()", "a warm repaint made widget calls"),
    ("local moved = drag.moving or math.abs(dx) + math.abs(dy) >= controller.threshold",
     "local moved = drag.moving or math.abs(dx) + math.abs(dy) >= 0", "a press that barely moves writes nothing"),
    ("local ok = not self:Blocked() and entry.write(x, y) ~= false", "local ok = entry.write(x, y) ~= false",
     "combat during a drag refuses the commit"),
    ("    Restore(drag)\n    if self.opts.drag then self.opts.drag(drag.entry.region, \"cancel\") end\n    self.host:Paint(\"cancel\")",
     "    Restore(drag)\n    if self.opts.drag then self.opts.drag(drag.entry.region, \"cancel\") end",
     "Cancel repaints the region from the stored value"),
    ("    if not (Readable(x) and Readable(y)) then return false end\n    return self:Commit",
     "    return self:Commit", "a secret value is never computed with"),
    ("local dx, dy = x and (x - drag.x) / scale or 0, y and (y - drag.y) / scale or 0",
     "local dx, dy = x and (x - drag.x) or 0, y and (y - drag.y) or 0", "the drag divides by the region's scale"),
    ("if IsShiftKeyDown() then return steps.shift or 10 end", "if IsShiftKeyDown() then return steps.shift or 1 end",
     "the kit's Shift step is 10"),
    ("if self:Blocked() or self:Typing() then return false end", "if self:Blocked() then return false end",
     "typing keeps the arrows"),
    ("if self.opts.dedupe and self.opts.dedupe(owner, dx, dy) then return true end", "",
     "a repeated key press is consumed once"),
    ("    if controller:Selected() == entry.region and not controller.opts.keep then controller:Select(nil) end\nend",
     "end", "hiding a region ends its drag and selection"),
    ("    region:SetScript(\"OnUpdate\", nil)\n    if drag.native", "    if drag.native",
     "release ends the follow and writes"),
    ("if handles and handles.drag and handles.drag.native then return false end", "",
     "a native drag holds the paint"),
    ("    if ok and controller.opts.moved then controller.opts.moved(entry.region) end\n", "",
     "moved hook"),
    ("    if controller:Selected() == entry.region and not controller.opts.keep then",
     "    if controller:Selected() == entry.region then", "a kept selection must outlive its region hiding"),
    ("    if opts.keydown then return opts.keydown(frame, key) end\n", "", "keydown must replace the key handler"),
    ("    if owner then return owner[self.field] or nil end\n", "", "clearing the owner's field clears the selection"),
]
failed = []
with tempfile.TemporaryDirectory() as scratch:
    tree = Path(scratch) / "MSUF_Suite" / "Core"
    tree.mkdir(parents=True)
    for old, new, message in cases:
        if source.count(old) != 1:
            failed.append("mutation anchor not found exactly once: " + old.splitlines()[0])
            continue
        (tree / "PreviewKit.lua").write_text(source.replace(old, new), encoding="utf-8")
        run = subprocess.run([lua, str(root / "tools" / "tests" / "suite_preview_kit_contract.lua"), scratch],
                             capture_output=True, text=True, errors="replace")
        if run.returncode == 0 or message not in run.stdout + run.stderr:
            failed.append("mutation survived or failed elsewhere (%s): %s" % (message, old.splitlines()[0]))
if failed:
    print("\n".join(failed))
    sys.exit(1)
print("preview kit: %d mutations rejected by the contract" % len(cases))
