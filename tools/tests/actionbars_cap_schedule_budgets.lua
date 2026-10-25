-- Measured serial Lua 5.1 budgets; Flush.lua VM only, not live CPU.
-- Shared deadline is guarded; fresh-mark costs are reported separately.
return { iterations = 20, cases = {
    ["native/fresh-cooldown"] = { instructions = 4760, timerZero = 20, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["native/fresh-state"] = { instructions = 4600, timerZero = 20, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["native/waiting-actionbarCooldown"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["native/waiting-cooldown"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["native/waiting-unreported"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["native/waiting-usable"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["owned/fresh-cooldown"] = { instructions = 4700, timerZero = 20, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["owned/fresh-state"] = { instructions = 4600, timerZero = 20, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["owned/waiting-actionbarCooldown"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["owned/waiting-cooldown"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["owned/waiting-unreported"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
    ["owned/waiting-usable"] = { instructions = 320, timerZero = 0, timerCap = 0, clock = 20, kilobytes = 0.001 },
} }
