-- Measured by measure-02/02-measure.log using the actual candidate Paint.lua.
-- 1000 calls per hot case; VM limits are the exact observed product-only counts.
-- Every observed hot allocation minimum was 0 KiB (minimum of two GC-stopped runs).
-- 0.001 KiB allows at most one byte of count resolution across all 1000 calls;
-- it is smaller than one allocated Lua object and does not permit per-call objects.
-- Native feedback/curve call vectors are asserted independently by the contract.
return {
    iterations = 1000,
    cases = {
        ["off-idle"] = { instructions = 8000, kilobytes = 0.001, configReads = 0 },
        ["off-cleanup"] = { instructions = 16000, kilobytes = 0.001, configReads = 0 },
        ["alpha-zero"] = { instructions = 27000, kilobytes = 0.001, configReads = 0 },
        ["alpha-near-full"] = { instructions = 27000, kilobytes = 0.001, configReads = 0 },
        ["both-zero"] = { instructions = 30000, kilobytes = 0.001, configReads = 0 },
        ["both-near-full"] = { instructions = 30000, kilobytes = 0.001, configReads = 0 },
        ["desat-active"] = { instructions = 26000, kilobytes = 0.001, configReads = 0 },
        ["alpha-active"] = { instructions = 27000, kilobytes = 0.001, configReads = 0 },
        ["both-active"] = { instructions = 30000, kilobytes = 0.001, configReads = 0 },
        ["desat-ready"] = { instructions = 26000, kilobytes = 0.001, configReads = 0 },
        ["alpha-ready"] = { instructions = 27000, kilobytes = 0.001, configReads = 0 },
        ["both-ready"] = { instructions = 30000, kilobytes = 0.001, configReads = 0 },
        ["desat-inactive"] = { instructions = 14000, kilobytes = 0.001, configReads = 0 },
        ["alpha-inactive"] = { instructions = 15000, kilobytes = 0.001, configReads = 0 },
        ["both-inactive"] = { instructions = 14000, kilobytes = 0.001, configReads = 0 },
        ["desat-missing"] = { instructions = 20000, kilobytes = 0.001, configReads = 0 },
        ["alpha-missing"] = { instructions = 21000, kilobytes = 0.001, configReads = 0 },
        ["both-missing"] = { instructions = 20000, kilobytes = 0.001, configReads = 0 },
        ["desat-secret"] = { instructions = 26000, kilobytes = 0.001, configReads = 0 },
        ["alpha-secret"] = { instructions = 27000, kilobytes = 0.001, configReads = 0 },
        ["both-secret"] = { instructions = 30000, kilobytes = 0.001, configReads = 0 },
    },
    coldCases = {
        ["unchanged-opacity"] = { instructions = 23 },
        ["changed-opacity"] = { instructions = 35 },
        ["same-opacity-desat-on"] = { instructions = 21 },
        ["same-opacity-desat-off"] = { instructions = 23 },
        ["full-opacity-boundary"] = { instructions = 35 },
    },
}
