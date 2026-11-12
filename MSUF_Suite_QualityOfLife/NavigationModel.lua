local _, Private = ...
local Suite = Private.Suite
local Navigation = { WAYPOINT = 1, CARD = 2, DIRECTION = 3 }
Private.Navigation, Suite.Navigation = Navigation, Navigation

function Navigation.Distance(yards, units)
    local value = units == 2 and yards * .9144 or yards
    if value >= 1000 then
        return (units == 2 and Suite.Text("%.1f km") or Suite.Text("%.1f kyd")):format(value / 1000)
    end
    return (units == 2 and Suite.Text("%d m") or Suite.Text("%d yd")):format(math.floor(value + .5))
end

-- A distance format and a travel time format as one: "%d yd · %d sec".
local joined = {}
local function Joined(distance, eta)
    local row = joined[distance]
    if not row then
        row = {}
        joined[distance] = row
    end
    local format = row[eta]
    if not format then
        format = Suite.Text("%s · %s"):format(distance, eta)
        row[eta] = format
    end
    return format
end

-- The readout is a format and its numbers, not a text: the client builds the
-- text (SetFormattedText, NavigationVisuals.lua), so a distance that changes
-- ten times a second leaves no string behind. The numbers are the ones the
-- text shows (whole yards, tenths of a kilometre), so they change only when
-- the text does, and the stamp counts those changes for the view.
function Navigation.Readout(model, config, distance, speed)
    local rounded = math.floor(distance + .5)
    local seconds = config.showETA and speed > 1 and math.floor(distance / speed + .5) or -1
    if rounded == model.rounded and seconds == model.seconds then return end
    model.rounded, model.seconds = rounded, seconds
    local format, a, b, c
    if config.showDistance then
        local metric = config.units == 2
        local value = metric and distance * .9144 or distance
        if value >= 1000 then
            format, a = metric and Suite.Text("%.1f km") or Suite.Text("%.1f kyd"), math.floor(value / 100 + .5) / 10
        else
            format, a = metric and Suite.Text("%d m") or Suite.Text("%d yd"), math.floor(value + .5)
        end
    end
    if seconds >= 0 then
        local eta, first, second = Suite.Text("%d sec"), seconds, nil
        if seconds >= 60 then eta, first, second = Suite.Text("%d min %02d sec"), math.floor(seconds / 60), seconds % 60 end
        if format then format, b, c = Joined(format, eta), first, second
        else format, a, b = eta, first, second end
    end
    if format == model.readoutFormat and a == model.readoutA and b == model.readoutB and c == model.readoutC then return end
    model.readoutFormat, model.readoutA, model.readoutB, model.readoutC = format, a, b, c
    model.readoutStamp = (model.readoutStamp or 0) + 1
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
