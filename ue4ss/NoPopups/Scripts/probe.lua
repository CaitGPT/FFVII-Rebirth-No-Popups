-- What the game offers a mod during a combat assignment, asked once in game.
--
-- Four questions, because the answers decide how the checklist is drawn:
--   1. Can a mod resolve a text key ($menu_...) to the words the player reads?
--   2. Can it read an objective's completion story flag?
--   3. With the pop-ups off, what does the game still build when an assignment runs?
--   4. Can it find a hub's path-guide point actor, to tell which assignment the
--      player is standing in?
-- Writes probe-log.txt beside this folder; sends no input and changes nothing.
local M = {}

local log_file = nil
local function log(text)
    if log_file then
        log_file:write(os.date("!%H:%M:%S ") .. text .. "\n")
        log_file:flush()
    end
    print("[NoPopups probe] " .. text .. "\n")
end

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil, value
end

local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

local function find(path)
    local object = safe(StaticFindObject, path)
    return valid(object) and object or nil
end

-- 1. the text resource API, whose package name we only know from the header dump
local TEXT_API = {
    "/Script/EndTextResource.Default__EndTextResourceAPI",
    "/Script/EndGame.Default__EndTextResourceAPI",
    "/Script/EndDataBase.Default__EndTextResourceAPI",
}
local KEYS = {
    "$menu_WorldReport_JUNOA_13_Title",
    "$menu_WorldReport_Condition_020",
    "$menu_BattleMission_02_Condition",
}

local function probe_text()
    for _, path in ipairs(TEXT_API) do
        local api = find(path)
        if api then
            log("text API found: " .. path)
            for _, key in ipairs(KEYS) do
                local ok, value = pcall(function() return api:GetTextResourceText(key, "") end)
                local shown = tostring(value)
                if ok and type(value) == "userdata" then
                    local got, text = pcall(function() return value:ToString() end)
                    if got then shown = tostring(text) end
                end
                log(string.format("  GetTextResourceText(%q) -> ok=%s %s", key, tostring(ok), shown))
            end
            return true
        end
    end
    log("text API: none of the candidate paths resolved")
    return false
end

-- 2. story flags: the Junon Fiend Intel 2 objectives, its visit and clear flags
local FLAG_API = {
    "/Script/EndDataBase.Default__EndDataBaseDataBaseAPI",
    "/Script/EndGame.Default__EndDataBaseDataBaseAPI",
}
-- Every combat-assignment flag, so that whatever the game sets when a fight
-- starts shows up as a change. The checklist itself will watch three.
local ok_flags, FLAGS = pcall(require, "probe_flags")
if not ok_flags then
    FLAGS = {"stfWorldReport_Visit_JUNOA_013", "stfWorldReport_Finish_JUNOA_013",
             "stfBattleMission_JUNOA_2_01clear", "stfBattleMission_JUNOA_2_02clear",
             "stfBattleMission_JUNOA_2_03clear"}
end

local flag_api = nil
local function probe_flags(first)
    if not flag_api then
        for _, path in ipairs(FLAG_API) do
            flag_api = find(path)
            if flag_api then log("flag API found: " .. path) break end
        end
        if not flag_api then log("flag API: none of the candidate paths resolved") return end
    end
    local line, errors = {}, 0
    for _, flag in ipairs(FLAGS) do
        local ok, value = pcall(function() return flag_api:IsStoryFlag(FName(flag)) end)
        if not ok then errors = errors + 1
        elseif value then line[#line + 1] = (flag:gsub("^stf", "")) end
    end
    if errors > 0 then line[#line + 1] = string.format("(%d unreadable)", errors) end
    local now = table.concat(line, " ")
    if first or now ~= M.last_flags then
        log(string.format("%s %d of %d set: %s", first and "flags:" or "flags changed,",
            #line, #FLAGS, now))
        M.last_flags = now
    end
end

-- 4. a hub's path-guide point: if the actor is loaded, its position tells us
-- which assignment the player is standing in without any baked coordinates.
local POINTS = {"Area_1300_Hub_3_2"}   -- Junon Fiend Intel 2

-- One sweep of every actor, and only when asked: a full scan freezes a frame
-- (live 2026-11-04, the Piko catch scans), so it is never on by default.
local function probe_points()
    for _, name in ipairs(POINTS) do
        local actors = safe(FindAllOf, "Actor") or {}
        local found = 0
        for _, actor in ipairs(actors) do
            local full = safe(function() return actor:GetFullName() end) or ""
            if full:find(name, 1, true) then
                found = found + 1
                if found <= 3 then
                    local at = safe(function() return actor:K2_GetActorLocation() end)
                    log(string.format("  actor %s at %s", full:sub(1, 120),
                        at and string.format("%.0f,%.0f,%.0f", at.X, at.Y, at.Z) or "?"))
                end
            end
        end
        log(string.format("actors matching %q: %d", name, found))
    end
end

function M.start(mod_dir, scan_actors)
    log_file = io.open(mod_dir .. "probe-log.txt", "a")
    log("probe start")
    local done_once = false
    LoopAsync(3000, function()
        ExecuteInGameThread(function()
            if not done_once then
                done_once = true
                probe_text()
                probe_flags(true)
                if scan_actors then probe_points() end
            else
                probe_flags(false)
            end
        end)
        return false
    end)
end

return M
