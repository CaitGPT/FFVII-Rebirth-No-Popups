-- No Popups: a start for the region boss fights (Classified Intel).
--
-- The game starts these fights from the world intel panel ("Engage Enemy", hold Y / right mouse), and the pak hides
-- that panel along with the completion banner. This puts the game's own hold-to-engage icon over Cloud while he is in
-- the boss's arena, and when the button has been held long enough it sends the hub's state trigger, as the panel
-- does: the boss comes out and the fight starts. It works the same for the first fight and for rematches.
--
-- Each boss: its Hub row (Hub.Type 10): the trigger (ActivatedStringArguments[1]), the arena (DetectorStringArg[1],
-- the location volume that shows the panel) and the flag that opens it (ActivateStoryFlagID).
local M = {}

M.BOSSES = {
    { hub = "Area_1200_Hub_7_0", boss = "Quetzalcoatl", open = "stfHubGroup_GRASA_ExBattle_Open",
      trigger = "trg1200_Hub_Open_7_0", volume = "LocationVolume_Hub_A_7_1", clear = "stfArea1200_HubEx_00_Clear" },
    { hub = "Area_1300_Hub_7_0", boss = "Junon region", open = "stfHubGroup_JUNOA_ExBattle_Open",
      trigger = "trg1300_Hub_Open_7_0", volume = "LocationVolume_Hub_B_Ex", clear = "stfArea1300_HubEx_00_Clear" },
    { hub = "Area_2200_Hub_7_1", boss = "Corel region", open = "stfHubGroup_CORLA_ExBattle_Open",
      trigger = "trg2200_Hub_Open_7_0", volume = "LocationVolume_Hub_C_7_1", clear = "stfArea2200_HubEx_00_Clear" },
    { hub = "Area_2400_Hub_7_0", boss = "Gongaga region", open = "stfHubGroup_GONGA_ExBattle_Open",
      trigger = "trg2400_Hub_Open_6_0", volume = "LocationVolume_Hub_D_Ex", clear = "stfArea2400_HubEx_00_Clear" },
    { hub = "Area_2500_Hub_7_0", boss = "Jabberwock", open = "stfHubGroup_CSMOA_ExBattle_Open",
      trigger = "trg2500_Hub_Open_7_0", volume = "LocationVolume_Hub_E_Ex", clear = "stfArea2500_HubEx_00_Clear" },
    { hub = "Area_2600_Hub_5_0", boss = "Nibel region", open = "stfHubGroup_NIBLA_ExBattle_Open",
      trigger = "trg2600_Hub_Open_Ex", volume = "LocationVolume_Hub_F_5_0", clear = "stfArea2600_HubEx_00_Clear" },
}
-- Set while the story turns world intel hubs off (Hub.ProhibitStoryFlagID).
M.PROHIBIT = "stfWorldMap_Hub_Prohibition"
-- The panel's own button: Y on a pad (Triangle), right mouse on keyboard and mouse.
M.KEYS = { "Gamepad_FaceButton_Top", "RightMouseButton" }
-- How long to hold, when the game's own value (UEndPlayerCharacterConfig.SecretEnemy_IconInputTimeMax) can't be read.
M.HOLD_DEFAULT = 1.0
-- After a start: wait this long for the fight, and after the fight this long before offering it again.
M.START_WAIT, M.AFTER_FIGHT = 20, 4

local FIELD_API = "/Script/EndGame.Default__EndFieldAPI"
local MENU_API = "/Script/EndGame.Default__EndMenuAPI"
local DB_API = "/Script/EndGame.Default__EndDataBaseAPI"
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"
local CONFIG = "/Script/EndGame.Default__EndPlayerCharacterConfig"
-- EEndMenuFieldTargetState.Hold, EEndMenuFieldTargetIconType.Triangle
local STATE_HOLD, ICON_TRIANGLE = 5, 0

M.trace = function() end

local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local cdos = {}
local function cdo(path)
    local o = cdos[path]
    if valid(o) then return o end
    o = safe(StaticFindObject, path)
    cdos[path] = valid(o) and o or nil
    return cdos[path]
end

local function flag(name)
    local db = cdo(DB_API)
    return db ~= nil and safe(function() return db:IsStoryFlag(FName(name)) end) == true
end

local function leader()
    local battle = cdo(BATTLE_API)
    local l = battle and safe(function() return battle:GetPartyLeader() end)
    return valid(l) and l or nil
end

local function controller(lead)
    local statics = cdo(STATICS)
    local c = statics and safe(function() return statics:GetPlayerController(lead, 0) end)
    return valid(c) and c or nil
end

local fkeys = {}
local function held(c)
    for _, name in ipairs(M.KEYS) do
        local key = fkeys[name]
        if not key then key = { KeyName = FName(name) }; fkeys[name] = key end
        if safe(function() return c:IsInputKeyDown(key) end) == true then return true end
    end
    return false
end

local hold_time
local function hold_seconds()
    if hold_time then return hold_time end
    local config = cdo(CONFIG)
    local t = config and safe(function() return config.SecretEnemy_IconInputTimeMax end)
    hold_time = (type(t) == "number" and t > 0.1 and t < 10) and t or M.HOLD_DEFAULT
    M.trace("hold", string.format("%.2f s%s", hold_time, (type(t) == "number") and "" or " (default)"))
    return hold_time
end

-- The arena: the location volumes whose LocationId is the hub's (the level splits one into several actors, e.g.
-- LocationVolume_Hub_A_7_1a and _1b). Their places and sizes are read once and kept while the actors stay valid
-- (they unload with their level). IsOverlappingActor reads false for them even with Cloud inside, so the test is
-- by position: within a volume's radius (its bounds are round) and height.
local volumes, last_search = {}, -100
local SEARCH_GAP = 5
local function find_volumes(now, wanted)
    local missing = {}
    for _, b in ipairs(wanted) do
        local list = volumes[b.volume]
        local ok = list ~= nil and #list > 0
        if ok then for _, entry in ipairs(list) do if not valid(entry.actor) then ok = false end end end
        if not ok then missing[b.volume] = true; volumes[b.volume] = nil end
    end
    if next(missing) == nil or now - last_search < SEARCH_GAP then return end
    last_search = now
    for _, v in ipairs(safe(FindAllOf, "EndLocationVolume") or {}) do
        if valid(v) then
            local id = safe(function() return v.LocationId:ToString() end)
            if id and missing[id] then
                local o, e = {}, {}
                safe(function() v:GetActorBounds(false, o, e, false) end)
                if type(o.X) == "number" and type(e.X) == "number" then
                    local list = volumes[id] or {}
                    list[#list + 1] = { actor = v, x = o.X, y = o.Y, z = o.Z, r = math.min(e.X, e.Y), h = e.Z }
                    volumes[id] = list
                    M.trace("volume", string.format("%s at %.0f,%.0f,%.0f radius %.0f", id, o.X, o.Y, o.Z, math.min(e.X, e.Y)))
                end
            end
        end
    end
end

local function inside(b, lead)
    local list = volumes[b.volume]
    if not list then return false end
    local p = safe(function() return lead:K2_GetActorLocation() end)
    if not p then return false end
    for _, v in ipairs(list) do
        local dx, dy = p.X - v.x, p.Y - v.y
        if dx * dx + dy * dy <= v.r * v.r and math.abs(p.Z - v.z) <= v.h then return true end
    end
    return false
end

-- The fields the tick keeps between calls.
local icon, icon_boss, gauge_since = nil, nil, nil
local waiting_until, sent_boss, saw_fight, fight_end = nil, nil, false, nil
local released = true

local function hide_icon()
    if icon then
        local menu = cdo(MENU_API)
        if menu and valid(icon) then pcall(function() menu:HideFieldTargetIcon(icon) end) end
        M.trace("icon", "hidden")
    end
    icon, icon_boss, gauge_since = nil, nil, nil
end

local function icon_place(lead)
    local p = safe(function() return lead:K2_GetActorLocation() end)
    if not p then return nil end
    return { X = p.X, Y = p.Y, Z = p.Z + 120 }
end

local function show_icon(b, lead)
    local menu, where = cdo(MENU_API), icon_place(lead)
    if not (menu and where) then return end
    icon = safe(function() return menu:ShowFieldTargetIcon(lead, where, STATE_HOLD, ICON_TRIANGLE, FName("NoPopups_" .. b.hub)) end)
    if valid(icon) then
        icon_boss = b
        pcall(function() menu:SetFieldTargetIconHoldGauge(icon, 0.0) end)
        M.trace("icon", "shown for " .. b.boss)
    else
        icon = nil
        M.trace("icon", "ShowFieldTargetIcon gave nothing")
    end
end

local function start(b)
    local field = cdo(FIELD_API)
    if not field then return false end
    local ok, err = pcall(function() field:SendStateTrigger(b.trigger) end)
    M.trace("start", b.boss .. " " .. b.trigger .. " " .. tostring(ok) .. (ok and "" or (" " .. tostring(err))))
    return ok
end

-- The boss whose arena the leader stands in, if it can be fought now.
local function current(now, lead)
    if flag(M.PROHIBIT) then return nil end
    local open = {}
    for _, b in ipairs(M.BOSSES) do if flag(b.open) then open[#open + 1] = b end end
    if #open == 0 then return nil end
    find_volumes(now, open)
    for _, b in ipairs(open) do if inside(b, lead) then return b end end
    return nil
end

-- Returns true while the icon is up (the caller ticks faster then).
function M.tick()
    local field, statics = cdo(FIELD_API), cdo(STATICS)
    local lead = leader()
    if not (field and statics and lead) then hide_icon(); return false end
    -- Real seconds since the world started (os.clock is processor time).
    local now = safe(function() return statics:GetRealTimeSeconds(lead) end)
    if type(now) ~= "number" then hide_icon(); return false end
    local in_fight = safe(function() return field:IsDuringBattle() end) == true

    -- After a start: no icon until the fight has come and gone (or never came).
    if waiting_until then
        if in_fight then saw_fight = true; fight_end = nil
        elseif saw_fight then
            fight_end = fight_end or now
            if now - fight_end >= M.AFTER_FIGHT then
                M.trace("start", sent_boss.boss .. " fight over")
                waiting_until, sent_boss, saw_fight, fight_end = nil, nil, false, nil
            end
        elseif now > waiting_until then
            M.trace("start", sent_boss.boss .. " no fight within " .. M.START_WAIT .. " s")
            waiting_until, sent_boss = nil, nil
        end
        hide_icon()
        return false
    end

    local paused = safe(function() return statics:IsGamePaused(lead) end) == true
    local free = safe(function() return field:IsEnableFieldControler(true) end)
    if in_fight or paused or free == false then hide_icon(); return false end

    local b = current(now, lead)
    if not b then hide_icon(); return false end
    local menu, c = cdo(MENU_API), controller(lead)
    if icon_boss ~= b or not valid(icon) then
        hide_icon()
        show_icon(b, lead)
        -- A hold must start in the arena: a button already down when the icon appears does not count.
        released = not (c and held(c))
    end
    if not icon then return false end

    local where = icon_place(lead)
    if where then pcall(function() menu:SetFieldTargetIconPosition(icon, where) end) end
    local down = c and held(c) or false
    if not down then released = true end
    if down and released then
        gauge_since = gauge_since or now
        local part = math.min(1, (now - gauge_since) / hold_seconds())
        pcall(function() menu:SetFieldTargetIconHoldGauge(icon, part) end)
        if part >= 1 then
            released = false
            hide_icon()
            if start(b) then
                waiting_until, sent_boss, saw_fight, fight_end = now + M.START_WAIT, b, false, nil
            end
            return false
        end
    elseif gauge_since then
        gauge_since = nil
        pcall(function() menu:SetFieldTargetIconHoldGauge(icon, 0.0) end)
    end
    return true
end

-- Called when the mod unloads or the world changes: drop the widget and the found volumes.
function M.reset()
    hide_icon()
    volumes, last_search = {}, -100
    waiting_until, sent_boss, saw_fight, fight_end = nil, nil, false, nil
end

return M
