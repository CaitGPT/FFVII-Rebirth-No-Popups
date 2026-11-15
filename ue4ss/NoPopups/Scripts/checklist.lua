-- Give a combat assignment its objective list back.
--
-- The mod hides the world intel pop-ups, and the switch that does it also stops
-- the game building its objective panel, so this draws one. Which assignment
-- the player is in is answered by the fight itself: Chadley's research list
-- (ResearchTarget) pairs every world report with the fiend it is about, written
-- the way the battle API names a live enemy, and no fiend belongs to two
-- assignments. So the enemies on screen name the assignment, with no position
-- or map lookup. Their wording comes from the game's own text resource, so the
-- player reads it in their own language, and each objective is ticked off its
-- completion story flag.
local M = {}

local Panel = require("panel")
local ASSIGNMENTS = require("assignments")
local BY_ENEMY = require("assignments_by_enemy")

local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local TEXT_API = "/Script/EndTextResource.Default__EndTextResourceAPI"
local FLAG_API = "/Script/EndDataBase.Default__EndDataBaseDataBaseAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"
local MAX_ENEMIES = 32
-- Read on every tick: an objective is met mid-fight and the box should follow
-- at once, and three reflected flag reads cost far less than the panel's own
-- setters.
local FLAG_EVERY = 0
local TAB_KEY = "$menu_field_worldreport_header_worldreport"   -- "World Intel"

local state = {assignment = nil, view = nil, checked = 0, logged = {}, misses = {}}

local function log(message) print("[NoPopups] " .. message) end
local function log_once(key, message)
    if state.logged[key] then return end
    state.logged[key] = true
    log(message)
end

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function cdo(path)
    local object = safe(StaticFindObject, path)
    return valid(object) and object or nil
end

-- GetEnemyMembersRef fills an out array; UE4SS hands it back either as the out
-- table, a table holding one TArray, or a TArray (Battle Meters, live).
local function enemy_list(battle)
    local out = {}
    local returned = safe(function() return battle:GetEnemyMembersRef(out) end)
    local value = returned ~= nil and returned or out
    local list = {}
    local function add(item)
        local actor = item
        if type(item) == "userdata" then
            local kind = safe(function() return item:type() end)
            if kind == "RemoteUnrealParam" or kind == "LocalUnrealParam" then
                actor = safe(function() return item:get() end)
            end
        end
        if valid(actor) and #list < MAX_ENEMIES then list[#list + 1] = actor end
    end
    local function walk(array)
        safe(function() array:ForEach(function(_, element) add(element) end) end)
    end
    if type(value) == "table" then
        if #value == 1 and type(value[1]) == "userdata"
                and safe(function() return value[1]:type() end) == "TArray" then
            walk(value[1])
        else
            for _, item in ipairs(value) do add(item) end
        end
    elseif type(value) == "userdata" and safe(function() return value:type() end) == "TArray" then
        walk(value)
    end
    return list
end

local function text_of(key)
    if not key or key == "" then return nil end
    local api = cdo(TEXT_API)
    if not api then return nil end
    local value = safe(function() return api:GetTextResourceText(key, "") end)
    local shown = type(value) == "userdata" and safe(function() return value:ToString() end) or value
    if type(shown) == "string" and shown ~= "" then return shown end
    return nil
end

local function flag_set(name)
    if not name or name == "" then return false end
    local api = cdo(FLAG_API)
    if not api then return false end
    return safe(function() return api:IsStoryFlag(FName(name)) end) == true
end

-- What an enemy can be called. ResearchTarget names a fiend by its class
-- (EN2212_01_Zemzelett_RareEnd2); the battle API's own GetActorName gives the
-- placed mob instead (mobjunon_Zemzelett_Rare_001@JunonEastArea_mob_11, live
-- 2026-11-15), so the class is what the lookup needs.
local function enemy_names(battle, enemy)
    local names = {}
    local function add(value)
        if type(value) == "string" and value ~= "" then
            names[#names + 1] = value
            local bare = value:match("^(.-)_C_%d+$") or value:match("^(.-)_C$")
            if bare then names[#names + 1] = bare end
        end
    end
    add(safe(function() return enemy:GetClass():GetFName():ToString() end))
    add(safe(function() return enemy:GetFName():ToString() end))
    add(safe(function() return battle:GetActorName(enemy):ToString() end))
    return names
end

-- The assignment this fight belongs to, or nil when it is an ordinary battle.
local function assignment_in(battle)
    for _, enemy in ipairs(enemy_list(battle)) do
        local names = enemy_names(battle, enemy)
        for _, name in ipairs(names) do
            local hub = BY_ENEMY[name]
            if hub and ASSIGNMENTS[hub] then return hub, name end
        end
        local key = names[1] or "?"
        if not state.misses[key] then
            state.misses[key] = true
            log("no assignment for enemy; names seen: " .. table.concat(names, " | "))
        end
    end
    return nil
end

-- Wording is resolved once per assignment: the text resource is empty until a
-- save is loaded, so it cannot be read at start-up.
local function build_view(hub)
    local entry = ASSIGNMENTS[hub]
    local rows = {}
    for _, objective in ipairs(entry.objectives) do
        local text = text_of(objective.key)
        if text then rows[#rows + 1] = {text = text, flag = objective.flag, done = false} end
    end
    local title = text_of(entry.header)
    if not title or #rows == 0 then return nil end
    return {tab = text_of(TAB_KEY) or "World Intel", title = title, title_done = false,
            rows = rows, clear_flag = entry.clear_flag}
end

local function refresh_flags(view)
    for _, row in ipairs(view.rows) do
        local done = flag_set(row.flag)
        if done ~= row.done then
            log(string.format("objective %s: %s", done and "met" or "cleared", row.text))
        end
        row.done = done
    end
    local title_done = flag_set(view.clear_flag)
    if title_done ~= view.title_done then
        log("assignment " .. (title_done and "complete" or "not complete"))
    end
    view.title_done = title_done
end

-- Returns true while a checklist is on screen, so the caller can tick slowly
-- the rest of the time: every ExecuteInGameThread costs a Lua thread UE4SS
-- never frees (Battle Meters).
function M.tick(now, world_object)
    local battle = cdo(BATTLE_API)
    if not battle then log_once("battle_api", "battle API missing; no checklist"); return false end
    if safe(function() return battle:IsInBattle() end) ~= true then
        if state.assignment then log("checklist off: the fight ended") end
        state.assignment, state.view = nil, nil
        Panel.hide()
        return false
    end
    if not state.assignment then
        local hub, enemy = assignment_in(battle)
        if not hub then return false end
        local view = build_view(hub)
        if not view then
            log_once("view:" .. hub, "no wording yet for " .. hub)
            return false
        end
        state.assignment, state.view, state.checked = hub, view, 0
        log(string.format("checklist on: %s (%s), %d objectives", hub, enemy, #view.rows))
    end
    if now - state.checked >= FLAG_EVERY then
        state.checked = now
        refresh_flags(state.view)
    end
    if world_object == nil then log_once("no_pawn", "no controlled pawn; the panel will find the controller") end
    return Panel.show(state.view, world_object)
end

-- The controlled pawn, which is what the panel needs to reach the player
-- controller. In a battle GetPlayerPawn can come back empty, so the controller
-- is asked directly as a fallback (Battle Meters' gameplay_pawn, live). Nothing
-- here is called before a save is loaded.
local engine, controller = nil, nil
function M.world_object()
    local statics = cdo(STATICS)
    if not statics then return nil end
    if not valid(engine) then engine = safe(FindFirstOf, "GameEngine") end
    local viewport = valid(engine) and safe(function() return engine.GameViewport end)
    local pawn = nil
    if valid(viewport) then pawn = safe(function() return statics:GetPlayerPawn(viewport, 0) end) end
    if not valid(pawn) then
        -- Looked up again only when the kept one is gone: FindFirstOf walks every object.
        if not valid(controller) then controller = safe(FindFirstOf, "EndPlayerControllerBP_C") end
        pawn = valid(controller) and safe(function() return controller.Pawn end) or nil
    end
    if not valid(pawn) then return nil end
    local class = safe(function() return pawn:GetClass():GetFName():ToString() end) or ""
    if class:match("^PC%d%d%d%d_") or class:match("^VE%d%d%d%d_") then return pawn end
    return nil
end

return M
