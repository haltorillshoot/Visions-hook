-- Runs under lune with a mock raknet table; no executor and no live traffic:
--   lune run Raknet/tests/raknet_research.spec.luau
local RaknetResearch = require("../RaknetResearch")

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

    -- Sends a simulated packet through every registered hook; returns the packet so tests can check it was not touched.
    function mock.send(id, bytes)
        local buf = buffer.create(#bytes)
        for index, value in bytes do
            buffer.writeu8(buf, index - 1, value)
        end
        local packet = { PacketId = id, AsBuffer = buf, setCalls = 0 }
        function packet:SetData()
            self.setCalls += 1
        end
        for _, hook in mock.hooks do
            hook(packet)
        end
        return packet
    end

    return mock
end

local function fakeClock()
    local now = 100
    return function()
        return now
    end, function(delta)
        now += delta
    end
end

-- hook registration and cleanup
do
    local raknet = mockRaknet()
    local rec = RaknetResearch.new({ raknet = raknet })
    check("start ok", rec:start())
    rec:start()
    check("one hook after double start", #raknet.hooks == 1 and raknet.adds == 1)
    rec:stop()
    rec:stop()
    check("hook removed once", #raknet.hooks == 0 and raknet.removes == 1)
    rec:start()
    rec:unload()
    check("unload removes hook", #raknet.hooks == 0)
end

-- missing raknet fails closed
do
    local rec = RaknetResearch.new({ raknet = {} })
    local ok, reason = rec:start()
    check("fails without hooks", ok == false and reason ~= nil and not rec.recording and rec.errors == 1)
end

-- identification, sizes, validation, timing, never writes
do
    local raknet = mockRaknet()
    local clock, advance = fakeClock()
    local rec = RaknetResearch.new({ raknet = raknet, clock = clock })
    rec:start()

    local first = raknet.send(0x1B, { 0x1B, 1, 2, 3, 4, 5 })
    advance(0.010)
    raknet.send(0x1B, { 0x1B, 9 })
    advance(0.005)
    raknet.send(0x10, { 0x10, 7, 7, 7, 7 })

    local records = rec.records
    check("three records", #records == 3)
    check("ids", records[1].id == 0x1B and records[3].id == 0x10)
    check("sizes", records[1].size == 6 and records[2].size == 2 and records[3].size == 5)
    check("valid long", records[1].valid["u32@1"] == true)
    check("valid short", records[2].valid["u32@1"] == false)
    check("hex", records[1].hex == "1B 01 02 03 04 05", records[1].hex)
    check("gap", math.abs(records[2].gap - 0.010) < 1e-9 and math.abs(records[3].gap - 0.005) < 1e-9)
    check("gap same id", math.abs(records[2].gapSameId - 0.010) < 1e-9 and records[3].gapSameId == nil)
    check("ordering", records[1].index < records[2].index and records[2].index < records[3].index)
    check("timestamps", math.abs(records[3].t - 0.015) < 1e-9)
    check("packet untouched", first.setCalls == 0 and buffer.readu8(first.AsBuffer, 1) == 1)
    check("counts", rec.counts[0x1B] == 2 and rec.counts[0x10] == 1)
    rec:stop()
end

-- filtering, ring cap, errors do not escape the hook
do
    local raknet = mockRaknet()
    local rec = RaknetResearch.new({ raknet = raknet, maxRecords = 3 })
    rec:start()
    rec:setFilter(RaknetResearch.parseIds("1B, 0x10"))
    check("parseIds", #RaknetResearch.parseIds("1B, 0x10 zz 999") == 2)
    raknet.send(0x05, { 5 })
    for _ = 1, 5 do
        raknet.send(0x1B, { 0x1B, 0, 0, 0, 0 })
    end
    check("filter skips others", rec.counts[0x05] == nil and rec.seen == 6)
    check("ring cap", #rec.records == 3 and rec.dropped == 2)

    local ok = pcall(raknet.hooks[1], { PacketId = 0x1B, AsBuffer = nil })
    check("bad packet does not throw", ok)
    local ok2 = pcall(raknet.hooks[1], setmetatable({}, { __index = function() error("boom") end }))
    check("hostile packet does not throw", ok2 and rec.errors >= 1)
    rec:setFilter(nil)
    check("filter cleared", rec.filter == nil)
    rec:clear()
    check("clear", #rec.records == 0 and rec.seen == 0)
    rec:unload()
end

-- simulated before / after
do
    local rec = RaknetResearch.new({ raknet = mockRaknet() })
    local result = rec:simulate(0x1B, { 0x1B, 1, 2, 3, 4, 5 }, function(buf)
        buffer.writeu32(buf, 1, 0xFFFFFFFF)
    end)
    check("sim before", result.before == "1B 01 02 03 04 05", result.before)
    check("sim after", result.after == "1B FF FF FF FF 05", result.after)
    local short = rec:simulate(0x1B, { 0x1B, 1 }, function(buf)
        buffer.writeu32(buf, 1, 0xFFFFFFFF)
    end)
    check("sim out of range is caught", short.ok == false and short.before == "1B 01")
end

-- saving through a serializer
do
    local written
    local rec = RaknetResearch.new({
        raknet = mockRaknet(),
        ser = {
            write = function(path, data)
                written = { path = path, data = data }
                return 123
            end,
        },
    })
    local path = rec:save()
    check("save path", path ~= nil and written and written.path:match("^dumps/raknet/") ~= nil)
    check("save payload", written.data.status and written.data.records and written.data.events)

    local bare = RaknetResearch.new({ raknet = mockRaknet() })
    local none, reason = bare:save()
    check("save without toolkit", none == nil and reason ~= nil)
end

-- overhead: a capture should be far below a frame
do
    local raknet = mockRaknet()
    local rec = RaknetResearch.new({ raknet = raknet, maxRecords = 100 })
    rec:start()
    local bytes = { 0x1B, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
    local started = os.clock()
    for _ = 1, 10000 do
        raknet.send(0x1B, bytes)
    end
    local perPacket = (os.clock() - started) / 10000 * 1e6
    print(string.format("overhead: %.1f us per packet (includes building the mock packet)", perPacket))
    check("overhead below 100us", perPacket < 100)
    rec:unload()
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
    error("tests failed")
end
