-- Preserve each contract's frame queue and expose the native cancellable handle.
return function(timer)
    function timer.NewTimer(delay, callback)
        local handle = { cancelled = false }
        function handle:Cancel() self.cancelled = true end
        local fired = false
        timer.After(delay, function()
            fired = true
            if not handle.cancelled then callback(handle) end
        end)
        -- Some older fixtures execute the emulated frame immediately.
        if not fired then return handle end
    end
end
