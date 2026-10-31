-- > ( Des Hood )
-- The Des Hood part of Visions hook. It only runs in Des Hood (https://www.roblox.com/games/82613047987648/Des-Hood): started anywhere else it
-- says so and stops, so nothing made for this game ever runs in another one. Visions-hook.lua hands over to this file when it is started in Des
-- Hood, and it can also be run on its own.

local DES_HOOD_PLACE = 82613047987648

if game.PlaceId ~= DES_HOOD_PLACE then
    warn("[Visions hook] The Des Hood part only runs in Des Hood (place " .. DES_HOOD_PLACE .. "); this is place " .. tostring(game.PlaceId) .. ".")
    return
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- > ( single instance )
-- Running it again unloads the copy that is already running first, so loops and connections never stack up.

local shared_env = getgenv()

if type(shared_env.visions_des_hood_unload) == "function" then
    pcall(shared_env.visions_des_hood_unload)
end

local connections = {}

local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

shared_env.visions_des_hood_unload = function()
    for _, connection in connections do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(connections)
end

-- > ( services )

local players_service = cloneref(game:GetService("Players"))
local local_player = players_service.LocalPlayer

-- > ( features )
-- Des Hood's own features go below this line.

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Visions hook",
        Text = "Des Hood loaded",
        Duration = 4,
    })
end)

print("[Visions hook] Des Hood loaded for " .. local_player.Name)
