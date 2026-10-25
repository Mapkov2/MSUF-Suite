-- Serial real-query measurements; native order/count unchanged; no live CPU claim.
return { measured = true, iterations = 1000, allocationKB = .001, cases = {
    ["false-absent"] = { instructions = 44000 },
    ["false-hit1"] = { instructions = 7000 },
    ["false-hit2"] = { instructions = 13000 },
    ["false-hit3"] = { instructions = 19000 },
    ["false-hit4"] = { instructions = 25000 },
    ["false-hit5"] = { instructions = 31000 },
    ["false-hit6"] = { instructions = 37000 },
    ["false-hit7"] = { instructions = 43000 },
    ["nil-absent"] = { instructions = 44000 },
    ["nil-hit1"] = { instructions = 7000 },
    ["nil-hit2"] = { instructions = 13000 },
    ["nil-hit3"] = { instructions = 19000 },
    ["nil-hit4"] = { instructions = 25000 },
    ["nil-hit5"] = { instructions = 31000 },
    ["nil-hit6"] = { instructions = 37000 },
    ["nil-hit7"] = { instructions = 43000 },
} }
