"""Offline checks of ue4ss/NoPopups/Scripts/repair.lua with a mocked game.

    pip install lupa
    python tools/test_repair.py [repair.lua]
"""
import sys
from lupa import LuaRuntime

SRC = sys.argv[1] if len(sys.argv) > 1 else str(__import__("pathlib").Path(__file__).resolve().parent.parent / "ue4ss" / "NoPopups" / "Scripts" / "repair.lua")

MOCK = r"""
flags, inv, sent, set_calls, now = {}, {}, {}, {}, 0
local function obj(t) t.IsValid = function() return true end return t end
local lead = obj({})
local db = obj({
  IsStoryFlag = function(self, n) return flags[n] == true end,
  SetStoryFlagBP = function(self, n, v) flags[n] = v; set_calls[#set_calls + 1] = n end,
  GetItemNumBP = function(self, uid) return inv[uid] or 0 end,
})
local field = obj({
  IsDuringBattle = function() return false end,
  IsEnableFieldControler = function() return true end,
  SendStateTrigger = function(self, t) sent[#sent + 1] = t end,
})
local battle = obj({ GetPartyLeader = function() return lead end })
local statics = obj({
  GetRealTimeSeconds = function() return now end,
  IsGamePaused = function() return paused == true end,
})
local map = {
  ["/Script/EndGame.Default__EndFieldAPI"] = field,
  ["/Script/EndGame.Default__EndDataBaseAPI"] = db,
  ["/Script/EndGame.Default__EndBattleAPI"] = battle,
  ["/Script/Engine.Default__GameplayStatics"] = statics,
}
function StaticFindObject(p) return map[p] end
function FName(s) return s end
function tick_n(M, n) for i = 1, n do now = now + 2; M.tick() end end
"""


def fresh():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    M = lua.execute(open(SRC, encoding="utf-8").read())
    return lua, M


def count(t):
    return len(list(t.values()))


fails = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        fails.append(what)


# 1. A save stuck at quest 07 step 110: the flag is set after M.SETTLE playable checks, not before.
lua, M = fresh()
g = lua.globals()
for f in ("stfStory_Ch04_Quest07_Step110_AT_now", "stfArea1300_Hub1_01_Clear"):
    g.flags[f] = True
lua.eval("tick_n")(M, M.SETTLE - 1)
check(not g.flags["stfStory_Ch04_Quest07_Step110_MT_clear"], "stuck quest 07: nothing before the settle time")
lua.eval("tick_n")(M, 1)
check(g.flags["stfStory_Ch04_Quest07_Step110_MT_clear"] is True, "stuck quest 07: step 110 flag set after the settle time")
check(count(g.set_calls) == 1, "stuck quest 07: exactly one flag set")
lua.eval("tick_n")(M, 100)
check(count(g.set_calls) == 1, "stuck quest 07: nothing more later")

# 2. The game's own sequence: hub complete, step current, flag set by the game 20 checks later. Nothing done.
lua, M = fresh()
g = lua.globals()
g.flags["stfStory_Ch04_Quest07_Step110_AT_now"] = True
g.flags["stfArea1300_Hub1_01_Clear"] = True
g.flags["stfWorldReport_Finish_JUNOA_002"] = True
lua.eval("tick_n")(M, 20)
g.flags["stfStory_Ch04_Quest07_Step110_MT_clear"] = True
g.flags["stfManual_Field_Tutorial_World_0050"] = True
lua.eval("tick_n")(M, 200)
check(count(g.set_calls) == 0, "live capture: no flag set while the game finishes it itself")

# 3. Paused checks (an open tutorial) do not count towards the settle time.
lua, M = fresh()
g = lua.globals()
g.flags["stfStory_Ch04_Quest07_Step110_AT_now"] = True
g.flags["stfArea1300_Hub1_01_Clear"] = True
g.paused = True
lua.eval("tick_n")(M, 200)
check(count(g.set_calls) == 0, "paused: nothing done")
g.paused = False
lua.eval("tick_n")(M, 3)
g.flags["stfStory_Ch04_Quest07_Step110_MT_clear"] = True
lua.eval("tick_n")(M, 100)
check(count(g.set_calls) == 0, "tutorial closed after a long pause: the game's own flag, nothing from us")

# 4. A crystal arriving 10 checks after the sanctuary finishes: no trigger sent.
lua, M = fresh()
g = lua.globals()
g.flags["stfWorldReport_Finish_GRASA_007"] = True
lua.eval("tick_n")(M, 10)
g.inv[3808] = 1
g.flags["stfMg_SUM_GRASA_ClearCheck001"] = True
lua.eval("tick_n")(M, 100)
check(count(g.sent) == 0, "live sanctuary: no trigger while the crystal is on its way")

# 5. A save missing its crystal: one trigger after the settle time, then done when it arrives.
lua, M = fresh()
g = lua.globals()
g.flags["stfWorldReport_Finish_GRASA_007"] = True
lua.eval("tick_n")(M, M.SETTLE - 1)
check(count(g.sent) == 0, "missing crystal: nothing before the settle time")
lua.eval("tick_n")(M, 1)
check(count(g.sent) == 1 and g.sent[1] == "trg1200_SummonMinigame_Titan_GetItemTrigger_001",
      "missing crystal: one trigger after the settle time")
g.inv[3808] = 1
lua.eval("tick_n")(M, 100)
check(count(g.sent) == 1, "missing crystal: no second trigger once it arrived")

# 6. A save that is not affected: nothing at all.
lua, M = fresh()
g = lua.globals()
for f in ("stfWorldReport_Finish_GRASA_007", "stfMg_SUM_GRASA_ClearCheck001", "stfStory_Ch04_Quest07_Step110_MT_clear",
          "stfArea1300_Hub1_01_Clear", "stfWorldReport_Finish_JUNOA_002", "stfManual_Field_Tutorial_World_0050"):
    g.flags[f] = True
g.inv[3808] = 1
lua.eval("tick_n")(M, 300)
check(count(g.sent) == 0 and count(g.set_calls) == 0, "unaffected save: nothing sent or set")

print("FAILED" if fails else "all repair checks pass")
sys.exit(1 if fails else 0)
