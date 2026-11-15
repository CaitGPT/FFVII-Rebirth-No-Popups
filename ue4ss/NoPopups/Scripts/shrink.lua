-- Make the world intel notice small and quick instead of removing it.
--
-- The notice is worth keeping: it carries the objective checklist the game
-- draws top left, which ticks as the fight goes. What is not worth keeping is
-- the pause - a completed combat assignment holds the player still for about
-- twelve seconds (measured 2026-11-15, Junon Fiend Intel 2). The banner and the
-- Results panel are both EndUserWidgets whose life is driven by their own
-- animations, so this scales them down and runs those animations fast.
--
-- Nothing here presses a button or changes game state; it only resizes a widget
-- and changes animation playback speed.
local M = {}

local BANNER = "EventProgress_01_C"
local RESULTS = "MissionResult_C"
local ANIMATIONS = {"In", "Out", "Shift", "Complete_Out", "Failed_Out", "Failed_Shift"}

local seen = {}

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end

local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

local function touch(widget, label, scale, speed)
    local key = safe(function() return widget:GetAddress() end)
    if key == nil or seen[key] then return false end
    seen[key] = true
    local applied = {}
    if scale and scale > 0 and scale ~= 1.0 then
        if safe(function() widget:SetRenderScale({X = scale, Y = scale}) end) ~= nil
                or safe(function() return widget:IsValid() end) then
            applied[#applied + 1] = string.format("scale %.2f", scale)
        end
    end
    if speed and speed > 1.0 then
        local sped = 0
        for _, name in ipairs(ANIMATIONS) do
            if safe(function() widget:SetPlaybackSpeedByName(FName(name), speed) end) ~= nil then
                sped = sped + 1
            end
        end
        applied[#applied + 1] = string.format("%d animations at %.1fx", sped, speed)
    end
    print(string.format("[NoPopups] %s: %s", label, table.concat(applied, ", ")))
    return true
end

-- FindFirstOf walks every object, so the search is only run when a notice is
-- plausible: while a fight is on, just after one, and otherwise now and then
-- (a Lifespring's notice comes with no fight at all).
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local AFTER_BATTLE_SECONDS = 25
local IDLE_EVERY = 5
local last_battle, idle = -1000, 0

function M.due(now)
    local battle = safe(StaticFindObject, BATTLE_API)
    local fighting = valid(battle) and safe(function() return battle:IsInBattle() end) == true
    if fighting then last_battle = now end
    if fighting or now - last_battle <= AFTER_BATTLE_SECONDS then return true end
    idle = idle + 1
    if idle >= IDLE_EVERY then idle = 0 return true end
    return false
end

-- Called on the game thread. Cheap when nothing is up: two class lookups.
function M.tick(settings)
    for label, class in pairs({banner = BANNER, results = RESULTS}) do
        local widget = safe(FindFirstOf, class)
        if valid(widget) then
            touch(widget, label, settings.shrink_scale, settings.shrink_speed)
        end
    end
    -- Forget widgets that have gone, so the next notice is handled too.
    if next(seen) ~= nil then
        local live = {}
        for _, class in ipairs({BANNER, RESULTS}) do
            local widget = safe(FindFirstOf, class)
            local key = valid(widget) and safe(function() return widget:GetAddress() end) or nil
            if key then live[key] = true end
        end
        for key in pairs(seen) do
            if not live[key] then seen[key] = nil end
        end
    end
end

return M
