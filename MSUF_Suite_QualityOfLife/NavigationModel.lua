local _, Private = ...
local Suite = Private.Suite
local Navigation = { WAYPOINT = 1, CARD = 2, DIRECTION = 3 }
Private.Navigation, Suite.Navigation = Navigation, Navigation

local function Duration(seconds)
    if seconds < 60 then return Suite.Text("%d sec"):format(seconds) end
    return Suite.Text("%d min %02d sec"):format(math.floor(seconds / 60), seconds % 60)
end

function Navigation.Distance(yards, units)
    local value = units == 2 and yards * .9144 or yards
    if value >= 1000 then
        return (units == 2 and Suite.Text("%.1f km") or Suite.Text("%.1f kyd")):format(value / 1000)
    end
    return (units == 2 and Suite.Text("%d m") or Suite.Text("%d yd")):format(math.floor(value + .5))
end

function Navigation.Readout(model, config, distance, speed)
    local rounded = math.floor(distance + .5)
    local seconds = config.showETA and speed > 1 and math.floor(distance / speed + .5) or -1
    if rounded == model.rounded and seconds == model.seconds then return end
    model.rounded, model.seconds = rounded, seconds
    local text = config.showDistance and Navigation.Distance(distance, config.units) or ""
    if seconds >= 0 then
        local eta = Duration(seconds)
        text = text ~= "" and Suite.Text("%s · %s"):format(text, eta) or eta
    end
    model.readout = text
end

function Navigation.Mode(model, config)
    if not model.valid or model.distance < config.hideDistance then return nil end
    if model.clamped then return config.navigator and Navigation.DIRECTION or nil end
    if config.display == 2 then return Navigation.WAYPOINT end
    if config.display == 3 then return Navigation.CARD end
    local threshold = config.nearDistance
    if model.mode == Navigation.CARD then threshold = threshold + 3 end
    return model.distance <= threshold and Navigation.CARD or Navigation.WAYPOINT
end

function Navigation.Sample(model, config, scene, distance)
    model.valid, model.clamped = scene ~= 4, scene == 3
    model.distance, model.angle, model.color = distance, -.65, config.pinColor
    model.title, model.info = Suite.Text("A place to explore"), Suite.Text("Saved waypoint · Preview")
    model.rounded = nil
    Navigation.Readout(model, config, distance, 7)
    model.mode = Navigation.Mode(model, config)
    return model
end

function Navigation.Play(config, preview)
    if not config.sound and not preview then return end
    if config.soundFile > 0 then PlaySoundFile(config.soundFile, "Master")
    else PlaySound(SOUNDKIT.MAP_PING, "Master") end
end

function Navigation.Color(config, kind)
    if kind == "complete" then return config.completeColor end
    if kind == "repeatable" then return config.repeatColor end
    if kind == "campaign" then return config.importantColor end
    return kind == "quest" and config.questColor or config.pinColor
end
