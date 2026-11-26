-- No Popups: give back what earlier versions withheld (issue #4, 1.0.3).
--
-- Up to 1.0.2 the pak hid the "World Intel Complete" notice, and a world report's PostCompleteNotify action only runs
-- after that notice, so it never ran. 1.0.3 runs those actions before the notice instead; this repairs saves played
-- before that. Everything here is keyed on the save's own state, never on a marker of ours, so it does nothing on a
-- save that was not affected and can run on every load:
--
-- * Summon crystals. Each region's three sanctuaries (Divine Intel) feed one world state machine,
--   scg0001_Summon_<God>_ItemGet: every one of the region's crystal triggers moves it one step and the step hands out
--   the next crystal (and its ClearCheck flag; the summon materia levels up from the crystal). For each summon, while
--   fewer crystals are held than the region has sanctuaries finished, this sends one trigger and waits for the
--   crystal to arrive before it sends another. In vanilla saves the two counts are always equal (466 library saves).
--   If the crystal count reads lower than the ClearCheck flags the crystals set, the count is not trusted.
-- * Cosmo Canyon's chocobo (Chocobo Intel, WorldReport_CSMOA_02): its after-notice action told side quest 28 that the
--   chocobo was caught (trg2500_Quest28_ChocoboGetTalk3, which sets stfStory_Ch10_Quest28_isOwnChocobo). Sent again
--   while the report is finished and the flag is not.
-- * Flags whose action only showed something: the Gilgamesh finale's tutorial (stfStory_Chadlie_GILGA_Tutorial_01) and
--   the three chocobo tutorials' Manual entries. Set when their report is finished and they are not.
-- * Junon's side quest 07 (and its later copy, 10): its step 110, "capture Belle", clears when the capture hub's
--   completion trigger and then the end of the mountain chocobo tutorial (the report's after-notice action) have both
--   come, so with the notice hidden it never cleared, and each load puts the step back to waiting for a completion that
--   has already happened. Its flag (stfStory_Ch04_Quest<n>_Step110_MT_clear) is set while the step is current and the
--   capture hub (Area_1300_Hub_1_1) is complete (1.0.4).
--
-- Every repair waits until its mismatch has held for M.SETTLE checks in a row with the field playable (about a minute
-- of play), so a payout the game is still making, a crystal on its way or a tutorial still open, is never doubled.
--
-- Left alone: Chadley's call after each sanctuary, and Gilgamesh's scene after each Protorelic with the music cues
-- and party limits it starts (replaying those at an arbitrary moment could do more harm than missing them).
local M = {}

M.SUMMONS = {
    { god = "Titan", checks = { "stfMg_SUM_GRASA_ClearCheck001", "stfMg_SUM_GRASA_ClearCheck002" },
      trigger = "trg1200_SummonMinigame_Titan_GetItemTrigger_001",
      reports = { "stfWorldReport_Finish_GRASA_007", "stfWorldReport_Finish_GRASA_013", "stfWorldReport_Finish_GRASA_027" },
      crystals = { 3808, 3809, 3810 } },
    { god = "Phoenix", checks = { "stfMg_SUM_JUNOA_ClearCheck001", "stfMg_SUM_JUNOA_ClearCheck002" },
      trigger = "trg1300_SummonMinigame_Phoenix_GetItemTrigger_001",
      reports = { "stfWorldReport_Finish_JUNOA_005", "stfWorldReport_Finish_JUNOA_017", "stfWorldReport_Finish_JUNOA_023" },
      crystals = { 3811, 3812, 3813 } },
    { god = "Alexander", checks = { "stfMg_SUM_CORLA_ClearCheck001", "stfMg_SUM_CORLA_ClearCheck002" },
      trigger = "trg2200_Summon_Alexander_GetItemTrigger_001",
      reports = { "stfWorldReport_Finish_CORLA_009", "stfWorldReport_Finish_CORLA_020", "stfWorldReport_Finish_CORLA_024" },
      crystals = { 3814, 3815, 3816 } },
    { god = "Kujata", checks = { "stfMg_SUM_GONGA_ClearCheck001", "stfMg_SUM_GONGA_ClearCheck002" },
      trigger = "trg2400_Summon_Kjata_GetItemTrigger_001",
      reports = { "stfWorldReport_Finish_GONGA_004", "stfWorldReport_Finish_GONGA_015", "stfWorldReport_Finish_GONGA_019" },
      crystals = { 3817, 3818, 3819 } },
    { god = "Bahamut Arisen", checks = { "stfMg_SUM_CSMOA_ClearCheck001", "stfMg_SUM_CSMOA_ClearCheck002" },
      trigger = "trg2500_Summon_NeoBahamut_GetItemTrigger_001",
      reports = { "stfWorldReport_Finish_CSMOA_009", "stfWorldReport_Finish_CSMOA_024", "stfWorldReport_Finish_CSMOA_029" },
      crystals = { 3820, 3821, 3822 } },
    { god = "Odin", checks = { "stfMg_SUM_NIBLA_ClearCheck001", "stfMg_SUM_NIBLA_ClearCheck002" },
      trigger = "trg2600_Summon_Odin_GetItemTrigger_001",
      reports = { "stfWorldReport_Finish_NIBLA_006", "stfWorldReport_Finish_NIBLA_017", "stfWorldReport_Finish_NIBLA_022" },
      crystals = { 3823, 3824, 3825 } },
}
-- Triggers re-sent while a report is finished and the flag its action set is not.
M.TRIGGERS = {
    { name = "Cosmo Canyon chocobo, side quest 28", report = "stfWorldReport_Finish_CSMOA_002",
      flag = "stfStory_Ch10_Quest28_isOwnChocobo", trigger = "trg2500_Quest28_ChocoboGetTalk3" },
}
-- Flags set directly while a report is finished and they are not.
M.FLAGS = {
    { report = "stfWorldReport_Finish_GILGA_004", flag = "stfStory_Chadlie_GILGA_Tutorial_01" },
    { report = "stfWorldReport_Finish_JUNOA_002", flag = "stfManual_Field_Tutorial_World_0050" },
    { report = "stfWorldReport_Finish_CSMOA_002", flag = "stfManual_Field_Tutorial_World_0060" },
    { report = "stfWorldReport_Finish_NIBLA_002", flag = "stfManual_Field_Tutorial_World_0070" },
}
-- Quest steps whose flag is set while the step is current, its flag is not, and the hub it waits for is complete.
M.STEPS = {
    { name = "Junon side quest 07, capture Belle", now = "stfStory_Ch04_Quest07_Step110_AT_now",
      flag = "stfStory_Ch04_Quest07_Step110_MT_clear", hub = "stfArea1300_Hub1_01_Clear" },
    { name = "Junon side quest 10, capture the chocobo", now = "stfStory_Ch04_Quest10_Step110_AT_now",
      flag = "stfStory_Ch04_Quest10_Step110_MT_clear", hub = "stfArea1300_Hub1_01_Clear" },
}
-- Checks in a row (one every 2 s while the field is playable) a mismatch must hold before anything is done about it.
M.SETTLE = 30
-- How long a sent trigger has to show its result, how long before trying again, and how many tries per game session.
M.WAIT, M.RETRY, M.TRIES = 15, 60, 3
M.PROHIBIT = "stfWorldMap_Hub_Prohibition"

local FIELD_API = "/Script/EndGame.Default__EndFieldAPI"
local DB_API = "/Script/EndGame.Default__EndDataBaseAPI"
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"

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
local function items(uid)
    local db = cdo(DB_API)
    return db and safe(function() return db:GetItemNumBP(uid) end)
end

-- Per summon or trigger: { sent = time, before = count, tries = n, next = time }
local work = {}
local done_flags = {}
-- Per repair key: playable checks in a row its mismatch has held.
local held_for = {}
local function settled(key, wrong)
    if not wrong then held_for[key] = nil return false end
    held_for[key] = (held_for[key] or 0) + 1
    return held_for[key] >= M.SETTLE
end

local function set_flag(name)
    local db = cdo(DB_API)
    local ok = db and pcall(function() db:SetStoryFlagBP(FName(name), true) end)
    done_flags[name] = true
    M.trace("flag", name .. (ok and " set" or " (call failed)") .. " -> " .. tostring(flag(name)))
end

local function ready()
    local field, statics, battle = cdo(FIELD_API), cdo(STATICS), cdo(BATTLE_API)
    if not (field and statics and battle) then return nil end
    local lead = safe(function() return battle:GetPartyLeader() end)
    if not valid(lead) then return nil end
    local now = safe(function() return statics:GetRealTimeSeconds(lead) end)
    if type(now) ~= "number" then return nil end
    if safe(function() return field:IsDuringBattle() end) == true then return nil end
    if safe(function() return statics:IsGamePaused(lead) end) == true then return nil end
    if safe(function() return field:IsEnableFieldControler(true) end) == false then return nil end
    if flag(M.PROHIBIT) then return nil end
    return now, field, lead
end

-- A load (or any level change) gives the party a new leader object: start over then, so a save loaded again in the same
-- game session, still missing what it missed before, is repaired again.
local last_lead
local function new_load(lead)
    local address = safe(function() return lead:GetAddress() end)
    if address == nil or address == last_lead then return end
    if last_lead ~= nil then M.trace("load", "new party leader: repairs start over") end
    last_lead = address
    work, done_flags, held_for = {}, {}, {}
end

local function send(field, key, trigger, now, before)
    local w = work[key] or { tries = 0 }
    work[key] = w
    if w.tries >= M.TRIES or (w.next and now < w.next) then return end
    local ok = pcall(function() field:SendStateTrigger(trigger) end)
    w.tries, w.sent, w.before = w.tries + 1, now, before
    M.trace("send", key .. " " .. trigger .. " try " .. w.tries .. (ok and "" or " (call failed)"))
end

-- A sent trigger: true while waiting for its result.
local function waiting(key, now, count)
    local w = work[key]
    if not (w and w.sent) then return false end
    if count > w.before then
        M.trace("done", key .. " " .. w.before .. " -> " .. count)
        w.sent, w.next, w.tries = nil, nil, 0
        return false
    end
    if now - w.sent < M.WAIT then return true end
    M.trace("no-result", key .. " after " .. M.WAIT .. " s")
    w.sent, w.next = nil, now + M.RETRY
    return false
end

-- One pass; does nothing until the field is playable. Returns true while it has something in progress.
function M.tick()
    local now, field, lead = ready()
    if not now then return false end
    new_load(lead)
    local busy = false
    for _, s in ipairs(M.SUMMONS) do
        local finished, held = 0, 0
        for _, r in ipairs(s.reports) do if flag(r) then finished = finished + 1 end end
        local readable = true
        for _, uid in ipairs(s.crystals) do
            local n = items(uid)
            if type(n) ~= "number" then readable = false elseif n > 0 then held = held + 1 end
        end
        -- The crystal steps set ClearCheck001/002 too: an item count below them is a misread, so stay out.
        local checked = 0
        for _, c in ipairs(s.checks) do if flag(c) then checked = checked + 1 end end
        if readable and held < checked then
            if not work[s.god .. " misread"] then
                work[s.god .. " misread"] = true
                M.trace("skip", s.god .. ": " .. held .. " crystals read but " .. checked .. " ClearCheck flags set")
            end
            readable = false
        end
        if settled(s.god, readable and finished > held) then
            busy = true
            if not waiting(s.god, now, held) then send(field, s.god, s.trigger, now, held) end
        elseif readable and work[s.god] and work[s.god].sent then
            waiting(s.god, now, held)
        end
    end
    for _, t in ipairs(M.TRIGGERS) do
        if settled(t.name, flag(t.report) and not flag(t.flag)) then
            busy = true
            if not waiting(t.name, now, 0) then send(field, t.name, t.trigger, now, 0) end
        elseif work[t.name] and work[t.name].sent then
            waiting(t.name, now, 1)
        end
    end
    for _, f in ipairs(M.FLAGS) do
        if not done_flags[f.flag] and settled(f.flag, flag(f.report) and not flag(f.flag)) then set_flag(f.flag) end
    end
    for _, q in ipairs(M.STEPS) do
        if not done_flags[q.flag] and settled(q.flag, flag(q.now) and flag(q.hub) and not flag(q.flag)) then
            M.trace("step", q.name)
            set_flag(q.flag)
        end
    end
    return busy
end

return M
