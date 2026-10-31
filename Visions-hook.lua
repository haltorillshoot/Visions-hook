-- > (wait game load)

if not game:IsLoaded() then game.Loaded:Wait() end

-- > ( Des Hood )
-- Visions hook lives in Des-Hood/Des-Hood.lua now, and only runs in Des Hood. This file hands over to it: a copy in the executor's workspace
-- (Des-Hood.lua) is used first, the one in the repo otherwise.
if game.PlaceId ~= 82613047987648 then
    warn("[Visions hook] Visions hook only runs in Des Hood (place 82613047987648); this is place " .. tostring(game.PlaceId) .. ".")
    return
end

local ok, source = pcall(readfile, "Des-Hood.lua")

if not ok or type(source) ~= "string" or source == "" then
    ok, source = pcall(game.HttpGet, game, "https://raw.githubusercontent.com/haltorillshoot/Visions-hook/main/Des-Hood/Des-Hood.lua")
end

local run = ok and type(source) == "string" and loadstring(source, "=Des-Hood")

if run then
    run()
else
    warn("[Visions hook] The Des Hood part could not be loaded.")
end
