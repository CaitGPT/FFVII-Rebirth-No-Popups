-- No Popups: UE4SS side.
--
-- With log_widgets = 1 in settings.txt (beside this Scripts folder), every widget the game shows through
-- EndUserWidget.AddToViewportEx is written to widgets-log.txt with a time stamp, to name popups to remove.
-- The hook follows Junon Colosseum's, which runs at load every day: an empty pre-callback, the work after the call.
-- (A first version also hooked UMG.UserWidget:AddToViewport, in the pre-callback, and crashed every start-up.)

pcall(ExecuteInGameThread, function() end)

local MOD_DIR = package.path:match("([^;]*[\\/]NoPopups[\\/])[Ss]cripts[\\/]%?%.lua")
    or (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""

local function read_settings()
    local settings = { log_widgets = false }
    local file = io.open(MOD_DIR .. "settings.txt", "r")
    if not file then return settings end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(%S+)")
        if key == "log_widgets" then settings.log_widgets = (value == "1" or value == "true") end
    end
    file:close()
    return settings
end

local settings = read_settings()
print(string.format("[NoPopups] loaded from %s; widget logging %s\n", MOD_DIR, settings.log_widgets and "on" or "off"))
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
