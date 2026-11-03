-- Runs under lune with a mock raknet table and simulated packets; no executor and no live traffic:
--   lune run Raknet/tests/desync_research.spec.luau
local task = require("@lune/task")
local DesyncResearch = require("../DesyncResearch")

local passed, failed = 0, 0

local function check(name, condition, detail)
    if condition then
        passed += 1
    else
        failed += 1
        print("FAIL", name, detail or "")
    end
end

local function mockRaknet()
    local mock = { hooks = {}, adds = 0, removes = 0 }

    function mock.add_send_hook(hook)
        mock.adds += 1
        table.insert(mock.hooks, hook)
    end

    function mock.remove_send_hook(hook)
        mock.removes += 1
        local index = table.find(mock.hooks, hook)
        assert(index, "hook not registered")
        table.remove(mock.hooks, index)
    end

    -- Sends a simulated packet through every registered hook and returns it with the bytes it ended up with.
    function mock.send(id, bytes)
        local buf = buffer.create(#bytes)
        for index, value in bytes do
            buffer.writeu8(buf, index - 1, value)
        end
        local packet = { PacketId = id, AsBuffer = buf, setCalls = 0 }
        function packet:SetData(data)
            self.setCalls += 1
            self.AsBuffer = data
        end
        for _, hook in mock.hooks do
            hook(packet)
        end
        return packet
    end

    return mock
end

local function hex(packet)
    local out = {}
    for index = 0, buffer.len(packet.AsBuffer) - 1 do
        out[#out + 1] = string.format("%02X", buffer.readu8(packet.AsBuffer, index))
    end
    return table.concat(out, " ")
end

local clockNow = 1000
local function clock()
    return clockNow
end

local function make(env, extra)
    local raknet = mockRaknet()
    local options = {
        raknet = raknet,
        clock = clock,
        serverTime = clock,
        env = function()
            return env
        end,
        localPosition = function()
            return 0, 0, 0
        end,
        observedPosition = function()
            return nil
        end,
        notify = function() end,
        spawn = task.spawn,
        wait = function(dt)
            clockNow += dt or 0.03
            task.wait()
        end,
    }
    for key, value in extra or {} do
        options[key] = value
    end
    local module = DesyncResearch.new(options)
    return module, raknet
end

local PRIVATE = { privateServerId = "abc", creatorId = 1, creatorIsUser = false, localUserId = 100, others = { 200 } }
local PUBLIC = { privateServerId = "", creatorId = 1, creatorIsUser = false, localUserId = 100, others = { 200 } }
local PACKET = { 0x1B, 1, 2, 3, 4, 9, 9, 9 }

-- gate
do
    local trusted = { [200] = true }
    check("public blocked", select(1, DesyncResearch.evaluateGate(PUBLIC, trusted)) == false)
    check("private with trusted peer allowed", select(1, DesyncResearch.evaluateGate(PRIVATE, trusted)) == true)
    check("private with untrusted blocked", select(1, DesyncResearch.evaluateGate(PRIVATE, {})) == false)
    check("private alone allowed", select(1, DesyncResearch.evaluateGate({ privateServerId = "x", localUserId = 1, others = {} }, {})) == true)
    check("own place allowed", select(1, DesyncResearch.evaluateGate({ privateServerId = "", creatorId = 100, creatorIsUser = true, localUserId = 100, others = {} }, {})) == true)
    check("group place with same id not own", select(1, DesyncResearch.evaluateGate({ privateServerId = "", creatorId = 100, creatorIsUser = false, localUserId = 100, others = {} }, {})) == false)
    check("nil private id blocked", select(1, DesyncResearch.evaluateGate({ localUserId = 1, others = {} }, {})) == false)
end

-- public server: enable refuses, nothing hooked, nothing written
do
    local module, raknet = make(PUBLIC)
    module:setConfig({ trustedUserIds = { 200 } })
    local ok, reason = module:enable()
    check("public enable refused", ok == false and reason ~= nil and module.state == "blocked")
    check("public: no hook", #raknet.hooks == 0 and raknet.adds == 0)
    module:startTest("primary")
    local packet = raknet.send(0x1B, PACKET)
    check("public: packet untouched", hex(packet) == "1B 01 02 03 04 09 09 09" and packet.setCalls == 0)
    module:unload()
end

-- private server: the write
do
    local module, raknet = make(PRIVATE)
    module:setConfig({ trustedUserIds = { 200 } })
    check("enable ok", module:enable())
    module:enable()
    check("one hook after double enable", #raknet.hooks == 1 and raknet.adds == 1)

    local packet = raknet.send(0x1B, PACKET)
    check("field written, rest untouched", hex(packet) == "1B FF FF FF FF 09 09 09", hex(packet))
    check("SetData once", packet.setCalls == 1)

    local other = raknet.send(0x10, { 0x10, 1, 2, 3, 4, 9, 9, 9 })
    check("other id untouched", hex(other) == "10 01 02 03 04 09 09 09" and other.setCalls == 0, hex(other))

    local short = raknet.send(0x1B, { 0x1B, 1, 2, 3 })
    check("short packet skipped", hex(short) == "1B 01 02 03" and short.setCalls == 0 and module.short == 1)
    check("counters", module.written == 1 and module.packets == 2 and module.mismatch == 0, module:summary())

    module:disable()
    module:disable()
    check("hook removed once", #raknet.hooks == 0 and raknet.removes == 1)
    local after = raknet.send(0x1B, PACKET)
    check("untouched after disable", after.setCalls == 0 and module.state == "off")
    module:unload()
end

-- gate closes mid-run, time limit
do
    local env = { privateServerId = "abc", localUserId = 100, others = { 200 } }
    local module, raknet = make(env)
    module:setConfig({ trustedUserIds = { 200 }, maxSeconds = 5 })
    module:enable()
    env.others = { 200, 300 }
    module:update()
    check("untrusted joiner disables", module.state == "off" and #raknet.hooks == 0 and (module.reason or ""):find("gate closed") ~= nil, tostring(module.reason))
    check("no write after", raknet.send(0x1B, PACKET).setCalls == 0)

    env.others = { 200 }
    module:enable()
    clockNow += 6
    module:update()
    check("time limit disables", module.state == "off" and module.reason == "time limit reached", tostring(module.reason))
    module:unload()
end

-- errors: a broken packet never escapes the hook, repeated errors stop the write
do
    local module, raknet = make(PRIVATE)
    module:setConfig({ trustedUserIds = { 200 }, maxErrors = 3 })
    module:enable()
    local broken = { PacketId = 0x1B, AsBuffer = "not a buffer", SetData = function() end }
    local thrown = false
    for _ = 1, 3 do
        local ok = pcall(raknet.hooks[1], broken)
        thrown = thrown or not ok
    end
    check("hook never throws", not thrown)
    check("errors counted, write stopped", module.errors == 3 and module.state == "failed" and module.pendingRelease)
    check("no write while failed", raknet.send(0x1B, PACKET).setCalls == 0)
    module:update()
    check("deferred release", #raknet.hooks == 0)
    check("re-enable resets", module:enable() and module.errors == 0 and module.state == "active")
    module:unload()
end

-- a failed write with test mode still running keeps the probe hook and does not retry the release forever
do
    local module, raknet = make(PRIVATE)
    module:setConfig({ trustedUserIds = { 200 }, maxErrors = 1 })
    module:startTest("primary")
    module:enable()
    pcall(raknet.hooks[1], { PacketId = 0x1B, AsBuffer = "not a buffer", SetData = function() end })
    check("failed with probe running", module.state == "failed" and module.pendingRelease)
    module:update()
    check("probe hook kept, release flag cleared", #raknet.hooks == 1 and not module.pendingRelease and raknet.removes == 0)
    module:unload()
    check("then released", #raknet.hooks == 0)
end

-- fails closed without raknet, and when add_send_hook throws
do
    local module = make(PRIVATE, { raknet = {} })
    module:setConfig({ trustedUserIds = { 200 } })
    local ok, reason = module:enable()
    check("no raknet fails closed", ok == false and module.state == "failed" and reason ~= nil)

    local throwing = mockRaknet()
    throwing.add_send_hook = function()
        error("boom")
    end
    local second = make(PRIVATE, { raknet = throwing })
    second:setConfig({ trustedUserIds = { 200 } })
    local ok2 = second:enable()
    check("add_send_hook error fails closed", ok2 == false and second.state == "failed" and second.hook == nil)
end

-- config validation
do
    local module = make(PRIVATE)
    local applied = module:setConfig({ maxSeconds = 9999, sampleRate = -3, packetId = "27", offset = 1000, value = -1, verifyWrites = "yes", jumpStuds = "x", junk = 1, trustedUserIds = { "5", 0, -2, "x", 7.9 } })
    check("clamped", module.config.maxSeconds == 120 and module.config.sampleRate == 1 and module.config.packetId == 27 and module.config.offset == 64, tostring(module.config.offset))
    check("bad value ignored", module.config.value == 0xFFFFFFFF and applied.value == nil)
    check("bad types ignored", module.config.verifyWrites == true and module.config.jumpStuds == 8 and applied.junk == nil)
    check("trusted ids", #module.config.trustedUserIds == 2 and module.config.trustedUserIds[1] == 5 and module.config.trustedUserIds[2] == 7, #module.config.trustedUserIds)
    check("parseUserIds", #DesyncResearch.parseUserIds("12, 34;x 56") == 3)
end

-- probe
do
    local module, raknet = make(PRIVATE)
    module:startTest("primary")
    raknet.send(0x1B, { 0x1B, 1, 0, 0, 0, 5 })
    raknet.send(0x1B, { 0x1B, 9, 0, 0, 0, 5, 6 })
    raknet.send(0x1B, { 0x1B, 9, 0, 0, 0, 5, 6 })
    raknet.send(0x42, { 0x42, 77, 0, 0, 0 })
    local probe = module:probe()
    check("probe values", probe and probe.packets == 3 and probe.min == 1 and probe.max == 9 and probe.distinct == 2, probe and probe.distinct)
    check("probe byte0 and sizes", probe.byte0IsId and probe.minSize == 6 and probe.maxSize == 7)
    module:stopTest()
    check("probe hook released", #raknet.hooks == 0)
    module:unload()
end

-- comparison between two clients over a shared fake workspace
local function sharedFs()
    local files = {}
    return {
        files = files,
        write = function(path, data)
            files[path] = data
        end,
        read = function(path)
            return files[path]
        end,
        exists = function(path)
            return files[path] ~= nil
        end,
        delete = function(path)
            files[path] = nil
        end,
        folder = function() end,
        isFolder = function()
            return true
        end,
    }
end

local json = {
    encode = function(value)
        return require("@lune/serde").encode("json", value)
    end,
    decode = function(text)
        return require("@lune/serde").decode("json", text)
    end,
}

local function twoClients(truthPosition, observedPosition)
    local fs = sharedFs()
    local primary = make({ privateServerId = "abc", localUserId = 100, others = { 200 } }, {
        fs = fs,
        json = json,
        localPosition = function()
            return truthPosition()
        end,
    })
    local observer = make({ privateServerId = "abc", localUserId = 200, others = { 100 } }, {
        fs = fs,
        json = json,
        localPosition = function()
            return 0, 0, 0
        end,
        observedPosition = function()
            return observedPosition()
        end,
    })
    primary:setConfig({ trustedUserIds = { 100, 200 }, sampleRate = 10 })
    observer:setConfig({ trustedUserIds = { 100, 200 }, sampleRate = 10 })
    return primary, observer, fs
end

-- stationary and consistent: no error, no jumps
do
    local primary, observer = twoClients(function()
        return 5, 3, 5
    end, function()
        return 5, 3, 5
    end)
    primary:startTest("primary")
    observer:startTest("observer")
    for _ = 1, 40 do
        primary:step()
        observer:step()
        clockNow += 0.1
    end
    local report = observer:report()
    check("stationary: one phase", #report == 1, #report)
    check("stationary: zero error", report[1] and report[1].errNowMax < 1e-6 and report[1].jumps == 0 and report[1].samples > 20, report[1] and report[1].samples)
    check("stationary: peer id", observer:peerId() == 100 and primary:peerId() == 200)
    check("stationary: states compared", observer:compareStates().peer ~= nil)
    primary:unload()
    observer:unload()
end

-- moving peer seen 0.2 s late: delay is measured, error at that delay stays small
do
    local t = 0
    local truth = function()
        return t * 10, 0, 0
    end
    local seen = function()
        return (t - 0.2) * 10, 0, 0
    end
    local primary, observer = twoClients(truth, seen)
    primary:startTest("primary")
    observer:startTest("observer")
    primary.phase = "baseline-before"
    for _ = 1, 60 do
        t = clockNow - 1000
        primary:step()
        observer:step()
        clockNow += 0.1
    end
    local row = observer:report()[1]
    check("lag measured", row and row.lagMean and math.abs(row.lagMean - 0.2) < 0.11, row and row.lagMean)
    check("error at lag small", row and row.errAtLagMean < 1.1, row and row.errAtLagMean)
    check("phase label follows primary", row and row.phase == "baseline-before")
    primary:unload()
    observer:unload()
end

-- desync phase: the observed position freezes while the primary moves, then snaps back
do
    local t = 0
    local frozen = nil
    local primary, observer = twoClients(function()
        return t * 10, 0, 0
    end, function()
        if primary_phase == "desync" then
            return frozen or 0, 0, 0
        end
        return t * 10, 0, 0
    end)
    local phaseRef = { value = "baseline-before" }
    primary_phase = nil
    primary:startTest("primary")
    observer:startTest("observer")
    local function run(label, seconds)
        primary.phase = label
        primary_phase = label
        for _ = 1, seconds * 10 do
            t = clockNow - 1000
            if label == "desync" and not frozen then
                frozen = t * 10
            end
            primary:step()
            observer:step()
            clockNow += 0.1
        end
    end
    run("baseline-before", 5)
    run("desync", 5)
    frozen = nil
    run("baseline-after", 5)
    local rows = {}
    for _, row in observer:report() do
        rows[row.phase] = row
    end
    check("three phases reported", rows["baseline-before"] and rows["desync"] and rows["baseline-after"])
    check("desync error grows", rows["desync"].errNowMax > 20 and rows["baseline-before"].errNowMax < 5, rows["desync"].errNowMax)
    check("baseline error stays small", rows["baseline-after"].errNowMax < 20, rows["baseline-after"].errNowMax)
    primary:unload()
    observer:unload()
end

-- stale peer data is counted, not compared
do
    local primary, observer = twoClients(function()
        return 0, 0, 0
    end, function()
        return 0, 0, 0
    end)
    primary:startTest("primary")
    observer:startTest("observer")
    for _ = 1, 4 do
        primary:step()
        observer:step()
        clockNow += 0.1
    end
    clockNow += 10
    for _ = 1, 3 do
        observer:step()
        clockNow += 0.1
    end
    local row = observer:report()[1]
    check("stale counted", row and row.stale == 3, row and row.stale)
    primary:unload()
    observer:unload()
end

-- unconfigured peer and a missing workspace do not break stepping
do
    local module = make(PRIVATE, { fs = {} })
    module:startTest("observer")
    local ok = pcall(module.step, module)
    check("step without fs or peer", ok)
    module:unload()
end

-- suite in a public server: write phase skipped, nothing written, run marked incomplete
do
    local module, raknet = make(PUBLIC, { localPosition = function()
        return 0, 0, 0
    end })
    module:setConfig({ trustedUserIds = { 200 } })
    module:startTest("primary")
    local result
    local started = module:runSuite(1, function(r)
        result = r
    end)
    check("suite started", started)
    while not result do
        raknet.send(0x1B, PACKET)
        task.wait()
    end
    check("suite incomplete", result.complete == false and result.phases[2].skipped ~= nil and result.phases[2].written == 0)
    check("suite wrote nothing", module.written == 0)
    check("suite released", module.suite == nil and module.state ~= "active")
    module:unload()
end

-- suite in a private server: written only in the desync phase
do
    local module, raknet = make(PRIVATE, { localPosition = function()
        return 0, 0, 0
    end })
    module:setConfig({ trustedUserIds = { 200 } })
    module:startTest("primary")
    local result
    module:runSuite(1, function(r)
        result = r
    end)
    local phaseWrites = {}
    while not result do
        local packet = raknet.send(0x1B, PACKET)
        phaseWrites[module.phase] = (phaseWrites[module.phase] or 0) + (packet.setCalls or 0)
        task.wait()
    end
    check("suite complete", result.complete == true and #result.phases == 3)
    check("written only while desync", (phaseWrites["baseline-before"] or 0) == 0 and (phaseWrites["baseline-after"] or 0) == 0 and (phaseWrites["desync"] or 0) > 0, tostring(phaseWrites["desync"]))
    check("suite counts match", result.phases[2].written > 0 and result.phases[1].written == 0 and result.phases[3].written == 0)
    check("write off afterwards", module.state == "off")
    check("only primary runs suite", select(1, make(PRIVATE):runSuite(1)) == false)
    module:unload()
end

-- save
do
    local fs = sharedFs()
    local module = make(PRIVATE, { fs = fs, json = json })
    local path = module:saveResults()
    check("results saved", path ~= nil and fs.files[path] ~= nil)
    check("no fs reports why", select(2, make(PRIVATE, { fs = {} }):saveResults()) ~= nil)
end

-- cleanup and leaks: the structures that could grow stay bounded and empty after unload, memory does not climb across batches
do
    local module, raknet = make(PRIVATE)
    module:setConfig({ trustedUserIds = { 200 } })

    local function cycles(count)
        for _ = 1, count do
            module:startTest("primary")
            module:enable()
            raknet.send(0x1B, PACKET)
            module:stopTest()
            module:disable()
            task.wait()
        end
    end

    cycles(500)
    local first = collectgarbage("count")
    cycles(500)
    local second = collectgarbage("count")
    module:unload()
    task.wait()
    check("sampler threads all exited", module.samplers == 0, module.samplers)
    check("no hooks left", #raknet.hooks == 0 and raknet.adds == raknet.removes, raknet.adds .. "/" .. raknet.removes)
    check("no connections left", #module.connections == 0)
    check("state clean", module.state == "off" and not module.testMode and module.hook == nil and next(module.hookUsers) == nil)
    check("event log capped", #module.events <= 500)
    check("no growth across batches", second - first < 1024, second - first)
    module:unload()
    check("unload twice", #raknet.hooks == 0)
end

-- overhead of the hook per packet (informational, loose bound)
do
    local module, raknet = make(PRIVATE)
    module:setConfig({ trustedUserIds = { 200 } })
    module:enable()
    local hook = raknet.hooks[1]
    local packet = { PacketId = 0x1B, AsBuffer = buffer.create(32), SetData = function() end }
    local count = 200000
    local start = os.clock()
    for _ = 1, count do
        hook(packet)
    end
    local micros = (os.clock() - start) / count * 1e6
    local skipStart = os.clock()
    local other = { PacketId = 0x10, AsBuffer = packet.AsBuffer, SetData = packet.SetData }
    for _ = 1, count do
        hook(other)
    end
    local skipMicros = (os.clock() - skipStart) / count * 1e6
    print(string.format("hook cost: write %.2f us/packet, other id %.2f us/packet", micros, skipMicros))
    check("overhead bounded", micros < 20, micros)
    module:unload()
end

print(string.format("desync_research: %d passed, %d failed", passed, failed))

if failed > 0 then
    error("tests failed")
end
