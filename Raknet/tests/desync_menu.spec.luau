-- Runs the real "Raknet desync test" block of Visions-hook.lua against a fake menu library and a mock game, under lune:
--   lune run Raknet/tests/desync_menu.spec.luau
-- Nothing here touches Roblox or an executor; the packets are simulated.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local task = require("@lune/task")

local passed, failed = 0, 0

local function check(name, condition, detail)
    if condition then
        passed += 1
    else
        failed += 1
        print("FAIL", name, detail or "")
    end
end

local menuSource = fs.readFile("Visions-hook.lua")
local startMarker = "\t-- Raknet desync test: a gated desync research module"
local endMarker = '\trows.antiReport = Other:AddLabel("Anti Report")'
local startAt = string.find(menuSource, startMarker, 1, true)
local endAt = string.find(menuSource, endMarker, 1, true)

check("block found", startAt ~= nil and endAt ~= nil and startAt < endAt)

local blockSource = string.sub(menuSource, startAt, endAt - 1)
local moduleSource = fs.readFile("Raknet/DesyncResearch.lua")

-- fake library -----------------------------------------------------------------------------------------------------------
local controls = { toggles = {}, buttons = {}, sliders = {}, inputs = {}, dropdowns = {}, labels = {} }

local function newLabel(name)
    local label = { name = name, text = name }

    function label:ToolTip()
        return self
    end

    function label:SetText(text)
        self.text = text
    end

    function label:AddLabel(childName)
        local child = newLabel(childName)
        controls.labels[childName] = child
        return child
    end

    function label:AddOption()
        return newLabel("option")
    end

    function label:AddToggle(config)
        local item = { value = config.Default and true or false }
        function item:GetValue()
            return self.value
        end
        function item:SetValue(value)
            self.value = value and true or false
            config.Callback(self.value)
        end
        controls.toggles[config.Flag] = item
        return item
    end

    function label:AddSlider(config)
        local item = { value = config.Default }
        function item:SetValue(value)
            self.value = value
            config.Callback(value)
        end
        controls.sliders[config.Flag] = item
        return item
    end

    function label:AddDropdown(config)
        local item = { value = config.Default }
        function item:SetValue(value)
            self.value = value
            config.Callback(value)
        end
        controls.dropdowns[config.Flag] = item
        return item
    end

    function label:AddTextInput(config)
        local item = { value = config.Default }
        function item:SetValue(value)
            self.value = value
            config.Callback(value)
        end
        controls.inputs[config.Flag] = item
        return item
    end

    function label:AddButton(config)
        controls.buttons[config.Name] = config
        return {}
    end

    return label
end

-- mock game ----------------------------------------------------------------------------------------------------------------
local function newSignal()
    local signal = { connections = {} }
    function signal:Connect(callback)
        local connection = { callback = callback, connected = true }
        function connection:Disconnect()
            self.connected = false
            local index = table.find(signal.connections, self)
            if index then
                table.remove(signal.connections, index)
            end
        end
        table.insert(self.connections, connection)
        return connection
    end
    function signal:Fire(...)
        for _, connection in table.clone(self.connections) do
            connection.callback(...)
        end
    end
    return signal
end

local world = { privateServerId = "", others = {} }
local heartbeat = newSignal()
local playerAdded = newSignal()
local files = {}
local notifications = {}
local printed = {}

local players = {
    LocalPlayer = {
        UserId = 100,
        Character = {
            FindFirstChild = function()
                return { Position = { X = 0, Y = 3, Z = 0 } }
            end,
        },
    },
    PlayerAdded = playerAdded,
    GetPlayers = function(self)
        local list = { self.LocalPlayer }
        for _, userId in world.others do
            table.insert(list, { UserId = userId })
        end
        return list
    end,
    GetPlayerByUserId = function()
        return nil
    end,
}

local services = {
    Players = players,
    RunService = { Heartbeat = heartbeat },
    HttpService = {
        JSONEncode = function(_, value)
            return serde.encode("json", value)
        end,
        JSONDecode = function(_, text)
            return serde.decode("json", text)
        end,
    },
}

local game = setmetatable({}, {
    __index = function(_, key)
        if key == "PlaceId" then
            return 1
        elseif key == "PrivateServerId" then
            return world.privateServerId
        elseif key == "CreatorId" then
            return 42
        elseif key == "CreatorType" then
            return "Group"
        elseif key == "GetService" then
            return function(_, name)
                return services[name]
            end
        elseif key == "HttpGet" then
            return function()
                error("HttpGet must not be needed when the workspace copy exists")
            end
        end
        return nil
    end,
})

-- mock raknet
local raknet = { hooks = {}, adds = 0, removes = 0 }
function raknet.add_send_hook(hook)
    raknet.adds += 1
    table.insert(raknet.hooks, hook)
end
function raknet.remove_send_hook(hook)
    raknet.removes += 1
    local index = table.find(raknet.hooks, hook)
    assert(index, "hook not registered")
    table.remove(raknet.hooks, index)
end
local function sendPacket()
    local buf = buffer.create(8)
    buffer.writeu8(buf, 0, 0x1B)
    local packet = { PacketId = 0x1B, AsBuffer = buf, setCalls = 0 }
    function packet:SetData(data)
        self.setCalls += 1
        self.AsBuffer = data
    end
    for _, hook in raknet.hooks do
        hook(packet)
    end
    return packet
end

local environment = {
    game = game,
    workspace = { GetServerTimeNow = function()
        return os.clock()
    end },
    Enum = { CreatorType = { User = "User", Group = "Group" } },
    typeof = function(value)
        return type(value)
    end,
    task = task,
    getgenv = function()
        return {
            raknet = raknet,
            writefile = function(path, data)
                files[path] = data
            end,
            readfile = function(path)
                return files[path]
            end,
            isfile = function(path)
                return files[path] ~= nil
            end,
            delfile = function(path)
                files[path] = nil
            end,
            makefolder = function() end,
            isfolder = function()
                return true
            end,
        }
    end,
    readfile = function(path)
        if path == "DesyncResearch.lua" then
            return moduleSource
        end
        error("no such file " .. path)
    end,
    print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do
            parts[index] = tostring((select(index, ...)))
        end
        table.insert(printed, table.concat(parts, " "))
    end,
    menu = {
        new_notification = function(text, kind)
            table.insert(notifications, { text = text, kind = kind })
        end,
    },
    rows = {},
    Other = newLabel("Other"),
    Players = players,
    Session = { Alive = true, Cleanups = {} },
    addBindableToggle = function(label, _, config)
        return label:AddToggle(config)
    end,
}

environment.loadstring = function(source, name)
    local ok, chunk = pcall(luau.load, source, { debugName = name, environment = environment, injectGlobals = true })
    return ok and chunk or nil
end

-- the block, wrapped so it can run on its own
local runner = luau.load("return function()\n" .. blockSource .. "\nend", { debugName = "desync_block", environment = environment, injectGlobals = true })
check("block compiles", type(runner) == "function")

local session = environment.Session
local rows = environment.rows

runner()()

local function lastNotification()
    local last = notifications[#notifications]
    return last and last.text or ""
end

local function waitUntil(condition, seconds)
    local deadline = os.clock() + seconds
    while os.clock() < deadline do
        if condition() then
            return true
        end
        task.wait(0.05)
    end
    return condition()
end

-- heartbeat driver
local driving = true
task.spawn(function()
    while driving do
        heartbeat:Fire()
        task.wait(0.05)
    end
end)

check("rows created", rows.raknetDesync and rows.raknetDesyncStatus and rows.raknetDesyncSync)
check("flags created", controls.toggles.raknet_desync and controls.toggles.raknet_desync_test and controls.dropdowns.raknet_desync_role and controls.inputs.raknet_desync_trusted and controls.sliders.raknet_desync_limit)
check("buttons created", controls.buttons["Run Test Suite (Primary)"] and controls.buttons["Diagnostics (Console)"] and controls.buttons["Compare Clients (Console)"] and controls.buttons["Save Results"])
check("nothing hooked before use", #raknet.hooks == 0 and raknet.adds == 0)

-- public server: the desync toggle is refused and put back, nothing is written
controls.inputs.raknet_desync_trusted:SetValue("100, 200")
controls.toggles.raknet_desync:SetValue(true)
check("public: toggle put back", controls.toggles.raknet_desync:GetValue() == false)
check("public: reason notified", lastNotification():find("Raknet Desync") ~= nil and lastNotification():find("public server") ~= nil, lastNotification())
check("public: no hook", #raknet.hooks == 0)
check("public: status row", waitUntil(function()
    return rows.raknetDesyncStatus.text:find("blocked") ~= nil
end, 2), rows.raknetDesyncStatus.text)

-- test mode is passive and works in a public server
controls.toggles.raknet_desync_test:SetValue(true)
check("test mode on", controls.toggles.raknet_desync_test:GetValue() == true and #raknet.hooks == 1)
local publicPacket = sendPacket()
check("public + test mode: packet untouched", publicPacket.setCalls == 0)
check("clients row waits for peer", waitUntil(function()
    return rows.raknetDesyncSync.text:find("waiting") ~= nil
end, 2), rows.raknetDesyncSync.text)

-- private server with a trusted peer: the write works, the time limit switches it off and the toggle follows
world.privateServerId = "vip"
world.others = { 200 }
controls.sliders.raknet_desync_limit:SetValue(1)
controls.toggles.raknet_desync:SetValue(true)
check("private: toggle stays on", controls.toggles.raknet_desync:GetValue() == true)
local written = sendPacket()
check("private: packet written", written.setCalls == 1 and buffer.readu32(written.AsBuffer, 1) == 0xFFFFFFFF)
check("private: status row active", waitUntil(function()
    return rows.raknetDesyncStatus.text:find("active") ~= nil
end, 2), rows.raknetDesyncStatus.text)
check("time limit turns it off", waitUntil(function()
    return controls.toggles.raknet_desync:GetValue() == false
end, 4))
check("write stopped", sendPacket().setCalls == 0)
check("hook kept for test mode only", #raknet.hooks == 1)

-- an untrusted player joins mid-run
controls.sliders.raknet_desync_limit:SetValue(20)
controls.toggles.raknet_desync:SetValue(true)
check("rearmed", sendPacket().setCalls == 1)
table.insert(world.others, 999)
playerAdded:Fire({ UserId = 999 })
check("untrusted joiner stops the write at once", sendPacket().setCalls == 0)
check("toggle follows", waitUntil(function()
    return controls.toggles.raknet_desync:GetValue() == false
end, 2))
world.others = { 200 }

-- suite
controls.sliders.raknet_desync_phase:SetValue(2)
controls.buttons["Run Test Suite (Primary)"].Callback()
check("suite finishes", waitUntil(function()
    sendPacket()
    for _, line in printed do
        if line:find("suite complete") or line:find("suite INCOMPLETE") then
            return true
        end
    end
    return false
end, 12))
local suiteLines = table.concat(printed, "\n")
check("suite complete", suiteLines:find("suite complete") ~= nil, suiteLines)
-- The suite prints the module's own per-phase counters (taken around each phase), so this does not depend on the status row's refresh
local writesByPhase = {}
for label, packets, writes in string.gmatch(suiteLines, "suite ([%w%-]+): packets=(%d+) written=(%d+)") do
    writesByPhase[label] = { packets = tonumber(packets), written = tonumber(writes) }
end
check("write only in the desync phase", writesByPhase["baseline-before"] and writesByPhase["baseline-before"].written == 0 and writesByPhase["baseline-after"].written == 0 and writesByPhase["desync"].written > 0 and writesByPhase["baseline-before"].packets > 0, suiteLines)
check("finish notified", (function()
    for _, entry in notifications do
        if entry.text:find("desync test finished") then
            return true
        end
    end
    return false
end)())

-- diagnostics and results
controls.buttons["Diagnostics (Console)"].Callback()
controls.buttons["Compare Clients (Console)"].Callback()
controls.buttons["Status"].Callback()
local output = table.concat(printed, "\n")
check("diagnostics printed", output:find("field probe") ~= nil and output:find("this client:") ~= nil, output:sub(-600))
controls.buttons["Save Results"].Callback()
check("results file written", (function()
    for path in files do
        if path:find("results_") then
            return true
        end
    end
    return false
end)())
controls.buttons["Clear Results"].Callback()

-- turning things off and unloading
controls.toggles.raknet_desync_test:SetValue(false)
check("test mode off releases the hook", #raknet.hooks == 0 and controls.toggles.raknet_desync_test:GetValue() == false)

controls.toggles.raknet_desync_test:SetValue(true)
controls.toggles.raknet_desync:SetValue(true)
check("on again", #raknet.hooks == 1 and sendPacket().setCalls == 1)
session.Alive = false
for _, cleanup in session.Cleanups do
    cleanup()
end
check("unload removes the hook", #raknet.hooks == 0 and raknet.adds == raknet.removes, raknet.adds .. "/" .. raknet.removes)
check("unload removes the exchange file", (function()
    for path in files do
        if path:find("100.json") then
            return false
        end
    end
    return true
end)())
check("heartbeat connections gone", #heartbeat.connections == 0 and #playerAdded.connections == 0)

driving = false
task.wait(0.2)

print(string.format("desync_menu: %d passed, %d failed", passed, failed))

if failed > 0 then
    error("tests failed")
end
