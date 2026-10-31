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

-- > ( menu )
-- Des Hood uses the Visions hook menu (Visions-hook-menu.lua) and nothing else: the file is run as a library (getgenv().visions_menu_library) and
-- the window below is built with it. A copy in the executor's workspace is used first, the one in the repo otherwise.

local function load_menu_library()
    local ok, source = pcall(readfile, "Visions-hook-menu.lua")

    if not ok or type(source) ~= "string" or source == "" then
        ok, source = pcall(game.HttpGet, game, "https://raw.githubusercontent.com/haltorillshoot/Visions-hook/main/Visions-hook-menu.lua")
    end

    local run = ok and type(source) == "string" and loadstring(source, "=Visions-hook-menu")

    if not run then
        return nil
    end

    shared_env.visions_menu_library = true
    local library_ok, library = pcall(run)
    shared_env.visions_menu_library = nil

    return library_ok and type(library) == "table" and library or nil
end

local Library = load_menu_library()

if not Library then
    warn("[Visions hook] The Visions hook menu could not be loaded, so Des Hood has no menu.")
    return
end

pcall(Library.PlayIntro)

local Window = Library:CreateWindow({ Size = UDim2.fromOffset(650, 720), Keybind = Enum.KeyCode.RightShift })

-- the menu goes with the rest on unload (and when the script is run again)
local unload_connections = shared_env.visions_des_hood_unload

shared_env.visions_des_hood_unload = function()
    unload_connections()
    pcall(Window.Unload, Window)
end

-- > ( features )
-- Des Hood's own features go below this line, each in a tab of the window above.

-------- Settings

local Settings = Window:AddTab("Settings")
local menu_section = Settings:AddSection("Menu", "Left")

menu_section:AddDropdown({ Name = "Menu Key", Options = { "RightShift", "Insert", "K", "End" }, Default = "RightShift", Callback = function(key)
    Window:SetKeybind(Enum.KeyCode[key])
end })

menu_section:AddButton({ Name = "Unload", Callback = function()
    shared_env.visions_des_hood_unload()
end })

Window:FadeIn()

print("[Visions hook] Des Hood loaded for " .. local_player.Name)
