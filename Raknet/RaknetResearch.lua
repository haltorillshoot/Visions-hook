-- > ( RakNet research )
-- A passive recorder for outgoing RakNet packets. It registers one send hook through raknet.add_send_hook, writes down what each packet looks like
-- (id, size, timing, a short hex preview, whether the buffer is long enough for the offsets other code reads) and hands every packet on untouched:
-- the hook never calls packet:SetData, so nothing it sees is changed. Controlled "before and after" tests only run on simulated packets
-- (RaknetResearch:simulate), never on live traffic.
--
-- Recordings are written through the luau-toolkit serializer (luaukit/Ser.lua) when it is in the workspace, to dumps/raknet/<session>.json.
-- Without the toolkit the recording stays in memory and a warning says so.
--
-- Not verified: what packet id 0x1B means. Visions-hook.lua writes four 0xFF bytes at offset 1 of it; this module only records that the buffer
-- is long enough for that write (see OFFSET_CHECKS) and counts the packets, it does not claim a layout.

local RaknetResearch = {}
RaknetResearch.__index = RaknetResearch

-- Constants.
local DEFAULTS = {
    maxRecords = 2000,
    hexBytes = 16,
    sessionName = "raknet",
}

-- Offsets other code in the repo reads or writes, as { offset, width in bytes }. Used only to say whether a buffer could hold them.
local OFFSET_CHECKS = {
    { name = "u32@1", offset = 1, width = 4 },
}

local function hexPreview(buf, size, count)
    local parts = {}
    local last = math.min(size, count)

    for index = 0, last - 1 do
        parts[#parts + 1] = string.format("%02X", buffer.readu8(buf, index))
    end

    return table.concat(parts, " ")
end

local function validate(size)
    local result = {}

    for _, check in OFFSET_CHECKS do
        result[check.name] = size >= check.offset + check.width
    end

    return result
end

---Create a recorder. Everything it needs from the outside can be passed in, which is how the tests run it without an executor.
---@param options table? { raknet, clock, ser, notify, maxRecords, hexBytes, sessionName }
function RaknetResearch.new(options)
    options = options or {}

    local self = setmetatable({}, RaknetResearch)

    self.raknet = options.raknet or (getgenv and getgenv().raknet)
    self.clock = options.clock or os.clock
    self.ser = options.ser
    self.notify = options.notify or function() end
    self.maxRecords = options.maxRecords or DEFAULTS.maxRecords
    self.hexBytes = options.hexBytes or DEFAULTS.hexBytes
    self.sessionName = options.sessionName or DEFAULTS.sessionName

    self.hook = nil
    self.recording = false
    self.logging = false
    self.filter = nil
    self.records = {}
    self.events = {}
    self.counts = {}
    self.errors = 0
    self.dropped = 0
    self.seen = 0
    self.startedAt = nil
    self.lastAt = nil
    self.lastPerId = {}

    return self
end

---Append to the event log (hook activation, errors, saves). Capped so a long session cannot grow without bound.
function RaknetResearch:event(kind, detail)
    local events = self.events

    events[#events + 1] = { t = self.clock(), kind = kind, detail = detail }

    if #events > 500 then
        table.remove(events, 1)
    end
end

function RaknetResearch:fail(where, message)
    self.errors += 1
    self:event("error", where .. ": " .. tostring(message))
    self.notify("raknet research: " .. where .. " failed", 2)
    warn("[RaknetResearch] " .. where .. ": " .. tostring(message))
end

---Record one packet. Never writes to the packet.
---@param packet table anything with PacketId and AsBuffer
function RaknetResearch:capture(packet)
    local id = packet.PacketId

    self.seen += 1

    if self.filter and not self.filter[id] then
        return
    end

    local now = self.clock()
    local buf = packet.AsBuffer
    local size = typeof(buf) == "buffer" and buffer.len(buf) or -1

    local record = {
        index = self.seen,
        id = id,
        t = now - self.startedAt,
        gap = self.lastAt and (now - self.lastAt) or 0,
        gapSameId = self.lastPerId[id] and (now - self.lastPerId[id]) or nil,
        size = size,
        valid = size >= 0 and validate(size) or nil,
        hex = size > 0 and hexPreview(buf, size, self.hexBytes) or "",
    }

    self.lastAt = now
    self.lastPerId[id] = now
    self.counts[id] = (self.counts[id] or 0) + 1

    local records = self.records

    records[#records + 1] = record

    if #records > self.maxRecords then
        table.remove(records, 1)
        self.dropped += 1
    end

    if self.logging then
        print(string.format("[RaknetResearch] #%d id=0x%02X size=%d gap=%.1fms %s", record.index, id, size, record.gap * 1000, record.hex))
    end
end

---Start recording. Registers exactly one hook; calling it again while recording does nothing.
---@return boolean ok
---@return string? reason
function RaknetResearch:start()
    if self.recording then
        return true
    end

    local raknet = self.raknet

    if type(raknet) ~= "table" or type(raknet.add_send_hook) ~= "function" or type(raknet.remove_send_hook) ~= "function" then
        self:fail("start", "raknet.add_send_hook / remove_send_hook not available")
        return false, "raknet hooks not available on this executor"
    end

    self.startedAt = self.clock()
    self.lastAt = nil
    self.lastPerId = {}

    -- A fault in the recorder must never reach the game's packet path, so every packet goes through pcall and is always handed on as it came.
    self.hook = function(packet)
        local ok, err = pcall(self.capture, self, packet)

        if not ok then
            self:fail("capture", err)
        end
    end

    local ok, err = pcall(raknet.add_send_hook, self.hook)

    if not ok then
        self.hook = nil
        self:fail("add_send_hook", err)
        return false, tostring(err)
    end

    self.recording = true
    self:event("hook_on", "send hook registered")

    return true
end

---Stop recording and remove the hook.
function RaknetResearch:stop()
    if not self.recording then
        return true
    end

    local ok, err = pcall(self.raknet.remove_send_hook, self.hook)

    if not ok then
        self:fail("remove_send_hook", err)
    end

    self.hook = nil
    self.recording = false
    self:event("hook_off", "send hook removed")

    return ok
end

---Only record these packet ids. Pass nil or an empty list to record everything.
---@param ids number[]?
function RaknetResearch:setFilter(ids)
    if not ids or #ids == 0 then
        self.filter = nil
        return
    end

    local filter = {}

    for _, id in ids do
        filter[id] = true
    end

    self.filter = filter
end

---Parse "1B, 0x10 ff" style text into ids. Hex without a prefix is accepted because packet ids are normally written that way.
---@param text string
---@return number[]
function RaknetResearch.parseIds(text)
    local ids = {}

    for token in string.gmatch(text or "", "[%w]+") do
        local value = tonumber(token, 16) or tonumber(token)

        if value and value >= 0 and value <= 255 then
            ids[#ids + 1] = value
        end
    end

    return ids
end

function RaknetResearch:setLogging(enabled)
    self.logging = enabled == true
end

function RaknetResearch:clear()
    self.records = {}
    self.counts = {}
    self.dropped = 0
    self.seen = 0
    self.lastAt = nil
    self.lastPerId = {}
    self.startedAt = self.recording and self.clock() or nil
    self:event("clear", "recording cleared")
end

---Short state for the UI.
function RaknetResearch:status()
    local lines = {}

    for id, count in self.counts do
        lines[#lines + 1] = { id = id, count = count }
    end

    table.sort(lines, function(a, b)
        return a.id < b.id
    end)

    return {
        recording = self.recording,
        logging = self.logging,
        stored = #self.records,
        seen = self.seen,
        dropped = self.dropped,
        errors = self.errors,
        counts = lines,
    }
end

---One line per packet id, for a quick look in the console.
function RaknetResearch:summary()
    local status = self:status()
    local out = { string.format("recording=%s seen=%d stored=%d dropped=%d errors=%d", tostring(status.recording), status.seen, status.stored, status.dropped, status.errors) }

    for _, line in status.counts do
        out[#out + 1] = string.format("  0x%02X x%d", line.id, line.count)
    end

    return table.concat(out, "\n")
end

---Run a transformation on a copy of a simulated packet and record the before and after. This is the only place buffers are written, and it only
---ever sees buffers it made itself.
---@param id number
---@param bytes number[] contents of the simulated packet
---@param transform function? receives the copy, may write to it
function RaknetResearch:simulate(id, bytes, transform)
    local size = #bytes
    local before = buffer.create(size)

    for index, value in bytes do
        buffer.writeu8(before, index - 1, value)
    end

    local after = buffer.create(size)

    buffer.copy(after, 0, before, 0, size)

    local ok, err = true, nil

    if transform then
        ok, err = pcall(transform, after)
    end

    local result = {
        id = id,
        size = size,
        ok = ok,
        error = err and tostring(err) or nil,
        before = hexPreview(before, size, size),
        after = hexPreview(after, size, size),
        valid = validate(size),
        simulated = true,
    }

    self.events[#self.events + 1] = { t = self.clock(), kind = "simulation", detail = result }

    return result
end

---Write the recording to disk through the toolkit serializer.
---@return string? path
---@return string? reason
function RaknetResearch:save()
    local ser = self.ser

    if not ser then
        self:event("save_skipped", "luau-toolkit Ser.lua not loaded")
        return nil, "luau-toolkit Ser.lua not available, recording kept in memory"
    end

    local path = string.format("dumps/raknet/%s_%d.json", self.sessionName, os.time())

    local ok, bytes, err = pcall(ser.write, path, {
        status = self:status(),
        records = self.records,
        events = self.events,
    })

    if not ok or not bytes then
        self:fail("save", ok and err or bytes)
        return nil, tostring(ok and err or bytes)
    end

    self:event("saved", path)

    return path
end

---Stop and drop everything. Safe to call twice.
function RaknetResearch:unload()
    self:stop()
    self.records = {}
    self.events = {}
    self.counts = {}
end

return RaknetResearch
