local _, Suite = ...

Suite.AppearancePrimitives = {
    IsCombatLocked = function(event)
        if Suite.startingBeforeLockdown and not event then return Suite.IsCombatLocked() end
        return Suite.InCombat(event)
    end,
}
