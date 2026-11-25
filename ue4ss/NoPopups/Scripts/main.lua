-- No Popups: UE4SS side.
--
-- What ships (1.0.1): boss_start.lua, a start for the region boss fights (Classified Intel), whose own start is in the
-- world intel panel the pak hides. Everything else here is development work kept off in settings.txt, and its
-- modules are not in the release.
--
-- With log_widgets = 1 in settings.txt (beside this Scripts folder), every widget the game shows through
-- EndUserWidget.AddToViewportEx is written to widgets-log.txt with a time stamp, to name popups to remove.
-- The hook follows Junon Colosseum's, which runs at load every day: an empty pre-callback, the work after the call.
-- (A first version also hooked UMG.UserWidget:AddToViewport, in the pre-callback, and crashed every start-up.)

pcall(ExecuteInGameThread, function() end)

local MOD_DIR = package.path:match("([^;]*[\\/]NoPopups[\\/])[Ss]cripts[\\/]%?%.lua")
    or (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""

local function read_settings()
    local settings = { boss_start = true, boss_log = false, repair = true, log_widgets = false, probe = false,
                   probe_scan_actors = false, checklist = false, shrink = false, shrink_scale = 0.6, shrink_speed = 3.0 }
    local file = io.open(MOD_DIR .. "settings.txt", "r")
    if not file then return settings end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(%S+)")
        local on = (value == "1" or value == "true")
        if key == "boss_start" then settings.boss_start = on end
        if key == "boss_log" then settings.boss_log = on end
        if key == "repair" then settings.repair = on end
        if key == "log_widgets" then settings.log_widgets = on end
        if key == "probe" then settings.probe = on end
        if key == "probe_scan_actors" then settings.probe_scan_actors = on end
        if key == "checklist" then settings.checklist = on end
        if key == "shrink" then settings.shrink = on end
        if key == "shrink_scale" then settings.shrink_scale = tonumber(value) or settings.shrink_scale end
        if key == "shrink_speed" then settings.shrink_speed = tonumber(value) or settings.shrink_speed end
    end
    file:close()
    return settings
end

local settings = read_settings()
print(string.format("[NoPopups] loaded from %s; widget logging %s\n", MOD_DIR, settings.log_widgets and "on" or "off"))

if settings.boss_start then
    package.path = MOD_DIR .. "Scripts/?.lua;" .. package.path
    local ok, boss = pcall(require, "boss_start")
    if ok then
        if settings.boss_log then
            local log = io.open(MOD_DIR .. "boss-log.txt", "a")
            boss.trace = function(key, message)
                if not log then return end
                log:write(string.format("%s %s %s\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), key, tostring(message)))
                log:flush()
            end
            boss.trace("session", "start")
        end
        -- Registered while mods load: UE4SS adds the game-thread callback on a mod's first ExecuteInGameThread, and
        -- doing that in play can crash (Battle Meters).
        pcall(ExecuteInGameThread, function() end)
        -- Ten times a second while the icon is up (the hold gauge), otherwise twice a second.
        local busy, idle = false, 0
        LoopAsync(100, function()
            idle = idle + 1
            if busy or idle >= 5 then
                idle = 0
                ExecuteInGameThread(function()
                    local fine, shown = pcall(boss.tick)
                    if fine then busy = shown == true
                    else busy = false; boss.trace("error", tostring(shown)) end
                end)
            end
            return false
        end)
        print("[NoPopups] boss fight start on\n")
    else
        print("[NoPopups] boss_start failed to load: " .. tostring(boss) .. "\n")
    end
end
-- 1.0.3: give back crystals and quest/tutorial state that 1.0.0-1.0.2 withheld (repair.lua). Keyed on the save's own
-- state, so it does nothing on a save that was not affected. Writes repair-log.txt only when it acts.
if settings.repair then
    package.path = MOD_DIR .. "Scripts/?.lua;" .. package.path
    local ok, repair = pcall(require, "repair")
    if ok then
        local log
        repair.trace = function(key, message)
            log = log or io.open(MOD_DIR .. "repair-log.txt", "a")
            if not log then return end
            log:write(string.format("%s %s %s\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), key, tostring(message)))
            log:flush()
        end
        pcall(ExecuteInGameThread, function() end)
        LoopAsync(2000, function()
            ExecuteInGameThread(function()
                local fine, err = pcall(repair.tick)
                if not fine then repair.trace("error", tostring(err)) end
            end)
            return false
        end)
        print("[NoPopups] repair of earlier versions' missing intel rewards on\n")
    else
        print("[NoPopups] repair failed to load: " .. tostring(repair) .. "\n")
    end
end

if settings.probe then
    package.path = MOD_DIR .. "Scripts/?.lua;" .. package.path
    local ok, probe = pcall(require, "probe")
    if ok then probe.start(MOD_DIR, settings.probe_scan_actors)
    else print("[NoPopups] probe failed to load: " .. tostring(probe)) end
end

if settings.checklist then
    package.path = MOD_DIR .. "Scripts/?.lua;" .. package.path
    local ok, checklist = pcall(require, "checklist")
    if ok then
        -- Registered while mods load: UE4SS adds the game-thread callback on a mod's
        -- first ExecuteInGameThread, and doing that in play can crash (Battle Meters).
        pcall(ExecuteInGameThread, function() end)
        local idle, drawing = 0, false
        LoopAsync(200, function()
            idle = idle + 1
            -- Full rate only while the panel is up; otherwise once a second.
            if drawing or idle >= 5 then
                idle = 0
                ExecuteInGameThread(function()
                    local fine, shown = pcall(function()
                        return checklist.tick(os.time(), checklist.world_object())
                    end)
                    if fine then drawing = shown == true
                    else print("[NoPopups] checklist tick: " .. tostring(shown)) end
                end)
            end
            return false
        end)
        print("[NoPopups] combat assignment checklist on")
    else
        print("[NoPopups] checklist failed to load: " .. tostring(checklist))
    end
end

if settings.shrink then
    package.path = MOD_DIR .. "Scripts/?.lua;" .. package.path
    local ok, shrink = pcall(require, "shrink")
    if ok then
        pcall(ExecuteInGameThread, function() end)
        LoopAsync(1000, function()
            local now = os.time()
            if shrink.due(now) then
                ExecuteInGameThread(function()
                    local fine, err = pcall(function() shrink.tick(settings) end)
                    if not fine then print("[NoPopups] shrink: " .. tostring(err)) end
                end)
            end
            return false
        end)
        print(string.format("[NoPopups] notices shrunk to %.2f and run at %.1fx",
            settings.shrink_scale, settings.shrink_speed))
    else
        print("[NoPopups] shrink failed to load: " .. tostring(shrink))
    end
end

if not settings.log_widgets then return end

local log_file = io.open(MOD_DIR .. "widgets-log.txt", "a")
local function log_line(text)
    if not log_file then return end
    local now = os.time()
    log_file:write(string.format("%s %s\n", os.date("!%Y-%m-%dT%H:%M:%SZ", now), text))
    log_file:flush()
end
log_line("session start")

local ok, err = pcall(RegisterHook, "/Script/EndGame.EndUserWidget:AddToViewportEx", function() end, function(self)
    pcall(function()
        local widget = self:get()
        if widget and widget:IsValid() then
            log_line("AddToViewportEx " .. widget:GetFullName())
        end
    end)
end)
log_line((ok and "hooked" or "hook failed") .. " EndUserWidget:AddToViewportEx" .. (ok and "" or (" " .. tostring(err))))
