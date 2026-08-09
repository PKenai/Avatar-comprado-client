# -*- coding: utf-8 -*-
import io

BASE = "C:/Users/imfis/Desktop/Avatar-Compraado-server/data/"

def patch_bytes(path, replacements):
    with open(path, "rb") as f:
        data = f.read()
    for old, new in replacements:
        old_b = old.encode("latin-1") if isinstance(old, str) else old
        new_b = new.encode("latin-1") if isinstance(new, str) else new
        if old_b not in data:
            print("NOT FOUND in {}: {}".format(path, old[:80].replace("\n", "\\n")))
        data = data.replace(old_b, new_b)
    with open(path, "wb") as f:
        f.write(data)
    print("patched:", path)

# --- login.lua ---
login = BASE + "creaturescripts/scripts/loginLogout/login.lua"
patch_bytes(login, [
    # remove dofile 153
    ('dofile(getDataDir().."lib/isoled/153-npcTaskDaily.lua")\n', ''),
    # remove getDailysByTime function
    ('''function getDailysByTime(cid)
--    local canDoAgain = checkDelayIsFree(cid)
--    if canDoAgain.state then
--\t\treturn 0 
--\tend 
local total = 0
local storages = {"TimeDailyUm", "TimeDailyDois", "TimeDailyTres", "TimeDailyQuatro"}
for i = 1, #storages do 
\tif os.time() < getPlayerStorageValue(cid, storages[i]) then 
\t\ttotal = total+1
\tend
end 
return total
end

''', ''),
    # remove daily reset block
    ('''\tif getPlayerStorageValue(cid, "getCompletedDaily"..getDayID()) == -1 then 
\t\tif getStorage("GlobalSaveDays") ~= getPlayerStorageValue(cid, "lastGlobalSaveLogin") then 
\t\t\tsetPlayerStorageValue(cid, "lastGlobalSaveLogin", getStorage("GlobalSaveDays"))
\t\t\tsetPlayerStorageValue(cid, "getCompletedDaily"..getDayID(), 0)
\t\t\tsetPlayerStorageValue(cid, "dailyTaskColdown", os.time())
\t\t\tlocal storagesTimes = {"TimeDailyUm", "TimeDailyDois", "TimeDailyTres", "TimeDailyQuatro"}
\t\t\tfor i = 1, #storagesTimes do 
\t\t\t\tsetPlayerStorageValue(cid, storagesTimes[i], 0)
\t\t\tend 
\t\telse
\t\t\tsetPlayerStorageValue(cid, "getCompletedDaily"..getDayID(), getDailysByTime(cid))
\t\tend
\t\tsetPlayerStorageValue(cid, "isInDailyTask", 0)
\tend 
''', ''),
])

# --- tasksKill.lua ---
kill = BASE + "creaturescripts/scripts/tasksKill.lua"
patch_bytes(kill, [
    ('dofile(getDataDir().."lib/isoled/153-npcTaskDaily.lua")\n', ''),
    # remove daily kill block (between the gate/supreme abadeer section and the general task section)
    ('''    if getDailyCourse(cid) < 4 and getPlayerStorageValue(cid, "isInDailyTask") == 1 then
      local infos = getDailyTaskInfos(cid)
      if monsterName == infos.monster:lower() then
       -- if not getPlayerParty(cid) then
          local currentCount = addDailyMonsterCount(cid)
          local number = (infos.count-currentCount)

          if number > 0 then
          --  doPlayerSendCancel(cid, getLangString(cid, ""..(getDailyCourse(cid)+1).."\u00aa Daily Task: "..(number).." "..infos.monster.."(s) left to kill.", ""..(getDailyCourse(cid)+1).."\u00aa Task Di\u00e1ria: Falta matar "..(number).." "..infos.monster.."(s)."))
            doPlayerSendTextMessage(cid, MESSAGE_STATUS_CONSOLE_ORANGE, getLangString(cid, ""..(getDailyCourse(cid)+1).."\u00aa Daily Task: "..(number).." "..infos.monster.."(s) left to kill.", ""..(getDailyCourse(cid)+1).."\u00aa Task Di\u00e1ria: Falta matar "..(number).." "..infos.monster.."(s)."))
      return true
       elseif number == 0 then
        doPlayerSendTextMessage(cid, MESSAGE_STATUS_CONSOLE_ORANGE, getLangString(cid, ""..(getDailyCourse(cid)+1).."\u00aa Daily Task: Finished!", ""..(getDailyCourse(cid)+1).."\u00aa Task Di\u00e1ria: Completada!"))
      return true
          end
       -- end
      end
    end

''', ''),
])

# --- globalevents/scripts/init.lua ---
ge = BASE + "globalevents/scripts/init.lua"
patch_bytes(ge, [
    ('dofile(getDataDir().."lib/isoled/153-npcTaskDaily.lua")\n', ''),
    ('randomizeDailyTasks()\n', ''),
])

# --- talkactions/scripts/tasks.lua ---
tasks = BASE + "talkactions/scripts/tasks.lua"
patch_bytes(tasks, [
    ('dofile(getDataDir().."lib/isoled/153-npcTaskDaily.lua")\n', ''),
    ('doShowTextDialog(cid, 18157, getDailyTaskList(cid).."\\n\\n ".. getAdvancedTaskList(cid))',
     'doShowTextDialog(cid, 18157, getAdvancedTaskList(cid))'),
])

# --- npc/lib/npcGen.lua ---
npgen = BASE + "npc/lib/npcGen.lua"
patch_bytes(npgen, [
    ('dofile(getDataDir().."lib/isoled/153-npcTaskDaily.lua")\n', ''),
])

# --- npc/scripts/itemMissions.lua ---
im = BASE + "npc/scripts/itemMissions.lua"
patch_bytes(im, [
    ('''\tif tabela.dailyTasks and getPlayerDailysCompleted(cid) < tabela.dailyTasks then 
\t\treturn false
\tend 
''', ''),
])

# --- npc/scripts/poi.lua ---
poi = BASE + "npc/scripts/poi.lua"
patch_bytes(poi, [
    ('    dailyTasks = 5,\n', ''),
])

# --- lib/250-Item Task.lua (remove dailyTasks field from each entry) ---
it = BASE + "lib/250-Item Task.lua"
with open(it, "rb") as f:
    data = f.read()
new_data = data.replace(b"dailyTasks = 0, ", b"")
count = data.count(b"dailyTasks = 0, ")
with open(it, "wb") as f:
    f.write(new_data)
print("patched:", it, "removed", count, "dailyTasks fields")
