-- > ( RakNet desync research )
-- A controlled desync test module, not a recorder. It does two separate things:
--
--   1. Desync (write): while enabled it overwrites one u32 field of the outgoing physics-rate packet (default id 0x1B, offset 1, value 0xFFFFFFFF, the
--      same write Visions-hook.lua's fake position makes). It is gated: it only switches on in a server that is private or on a place the local
--      account created, and only while every other player in that server is a trusted test account. It switches itself off when a player joins
--      that is not trusted, when the time limit runs out, or after repeated errors. It never writes in a public server.
--
--   2. Diagnostics (read only): test mode samples the local character at a fixed rate, shares the last few samples with the other test client
--      through the executor workspace (visions_desync/<userId>.json), and compares what this client sees of the peer against what the peer reports
--      of itself: the position gap, the delay of the replicated position, the gaps between updates, jumps. Results are kept as running totals per
--      test phase, nothing per packet is stored.
--
-- Not verified offline: what the field at offset 1 means. probe() reports what the field does on live packets (min, max, distinct values, whether
-- byte 0 equals the packet id) and the module claims nothing beyond that.

local DesyncResearch = {}
DesyncResearch.__index = DesyncResearch

-- Constants.
local DEFAULTS = {
    packetId = 0x1B,
    offset = 1,
    value = 0xFFFFFFFF,
    maxSeconds = 20,
    maxErrors = 5,
    sampleRate = 10,
    staleAfter = 0.75,
    jumpStuds = 8,
    verifyWrites = true,
    walk = false,
    trustedUserIds = {},
    exchangeFolder = "visions_desync",
}

local FIELD_WIDTH = 4
local MAX_OFFSET = 64
local RING_SIZE = 20
local MAX_EVENTS = 500
local MAX_PHASES = 16
local MAX_DISTINCT = 64
local PUBLISH_EVERY = 2
local MOVING_STUDS = 1
local WALK_STUDS = 12
local WALK_PERIOD = 2
local FAIL_REPORT_GAP = 5

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function distance(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function defaultEnvironment()
    local players = game:GetService("Players")
    local localPlayer = players.LocalPlayer
    local others = {}

    for _, player in players:GetPlayers() do
        if player ~= localPlayer then
            others[#others + 1] = player.UserId
        end
    end

    return {
        placeId = game.PlaceId,
        privateServerId = game.PrivateServerId,
        creatorId = game.CreatorId,
        creatorIsUser = game.CreatorType == Enum.CreatorType.User,
        localUserId = localPlayer.UserId,
        others = others,
    }
end

local function defaultLocalPosition()
    local character = game:GetService("Players").LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not root then
        return nil
    end

    local position = root.Position

    return position.X, position.Y, position.Z
end

local function defaultObservedPosition(userId)
    local player = game:GetService("Players"):GetPlayerByUserId(userId)
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not root then
        return nil
    end

    local position = root.Position

    return position.X, position.Y, position.Z
end

local function defaultWalker(step, origin)
    local character = game:GetService("Players").LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not humanoid or not origin then
        return
    end

    local sign = step % 2 == 0 and 1 or -1

    humanoid:MoveTo(Vector3.new(origin[1] + sign * WALK_STUDS, origin[2], origin[3]))
end

---Decide whether the write is allowed here. Pure, so it is tested without a game.
---@param env table { privateServerId, creatorId, creatorIsUser, localUserId, others }
---@param trusted table set of trusted user ids
---@return boolean ok
---@return string? reason
function DesyncResearch.evaluateGate(env, trusted)
    local private = (env.privateServerId or "") ~= ""
    local ownPlace = env.creatorIsUser == true and env.creatorId == env.localUserId

    if not private and not ownPlace then
        return false, "public server of a place you do not own"
    end

    for _, userId in env.others do
        if not trusted[userId] then
            return false, "player " .. tostring(userId) .. " is not a trusted test account"
        end
    end

    return true
end

---Create the module. Everything it needs from the game and the executor can be passed in, which is how the tests run it under lune.
---@param options table? { raknet, clock, serverTime, env, localPosition, observedPosition, walker, fs, json, notify, wait, spawn, playerAdded, heartbeat }
function DesyncResearch.new(options)
    options = options or {}

    local self = setmetatable({}, DesyncResearch)

    self.raknet = options.raknet or (getgenv and getgenv().raknet)
    self.clock = options.clock or os.clock
    self.serverTime = options.serverTime or function()
        return workspace:GetServerTimeNow()
    end
    self.env = options.env or defaultEnvironment
    self.localPosition = options.localPosition or defaultLocalPosition
    self.observedPosition = options.observedPosition or defaultObservedPosition
    self.walker = options.walker or defaultWalker
    self.notify = options.notify or function() end
    self.wait = options.wait or function(delay)
        return task.wait(delay)
    end
    self.spawn = options.spawn or function(callback)
        return task.spawn(callback)
    end
    self.fs = options.fs or (getgenv and {
        write = getgenv().writefile,
        read = getgenv().readfile,
        exists = getgenv().isfile,
        delete = getgenv().delfile,
        folder = getgenv().makefolder,
        isFolder = getgenv().isfolder,
    }) or {}
    self.json = options.json or {
        encode = function(value)
            return game:GetService("HttpService"):JSONEncode(value)
        end,
        decode = function(text)
            return game:GetService("HttpService"):JSONDecode(text)
        end,
    }
    self.playerAdded = options.playerAdded
    self.heartbeat = options.heartbeat

    self.config = {}

    for key, value in DEFAULTS do
        self.config[key] = value
    end

    self.state = "off"
    self.reason = nil
    self.role = "primary"
    self.testMode = false
    self.phase = "idle"
    self.hook = nil
    self.hookUsers = {}
    self.pendingRelease = false
    self.connections = {}
    self.generation = 0
    self.samplers = 0
    self.suite = nil

    self.errors = 0
    self.failedAt = {}
    self.packets = 0
    self.written = 0
    self.short = 0
    self.mismatch = 0
    self.rate = 0
    self.lastPacketAt = nil
    self.activeSince = nil
    self.lastSupervisedAt = 0

    self.events = {}
    self.probeData = nil
    self.phases = {}
    self.seq = 0
    self.ring = {}
    self.peer = { raw = nil, data = nil, previous = nil, lastMoveAt = nil }
    self.walkStep = 0
    self.walkOrigin = nil
    self.walkAt = 0

    return self
end

---Append to the event log. Capped so a long session cannot grow without bound.
function DesyncResearch:event(kind, detail)
    local events = self.events

    events[#events + 1] = { t = self.clock(), kind = kind, detail = detail }

    if #events > MAX_EVENTS then
        table.remove(events, 1)
    end
end

function DesyncResearch:fail(where, message)
    self.errors += 1

    -- Counted every time, reported at most once per FAIL_REPORT_GAP per place, so a fault in a 10 Hz loop cannot flood the log or the notifications.
    local now = self.clock()
    local last = self.failedAt[where]

    if last and now - last < FAIL_REPORT_GAP then
        return
    end

    self.failedAt[where] = now
    self:event("error", where .. ": " .. tostring(message))
    self.notify("desync: " .. where .. " failed", 3)
    warn("[DesyncResearch] " .. where .. ": " .. tostring(message))
end

---Validate and apply settings. Unknown keys and wrong types are ignored; numbers are clamped. Returns what was applied.
---@param settings table
---@return table applied
function DesyncResearch:setConfig(settings)
    local config = self.config
    local applied = {}

    local function number(key, low, high)
        local value = tonumber(settings[key])

        if value then
            config[key] = clamp(value, low, high)
            applied[key] = config[key]
        end
    end

    number("maxSeconds", 1, 120)
    number("maxErrors", 1, 100)
    number("sampleRate", 1, 30)
    number("staleAfter", 0.1, 5)
    number("jumpStuds", 1, 100)
    number("packetId", 0, 255)
    number("offset", 0, MAX_OFFSET)

    if settings.value ~= nil then
        local value = tonumber(settings.value)

        if value and value >= 0 and value <= 0xFFFFFFFF then
            config.value = math.floor(value)
            applied.value = config.value
        end
    end

    for _, key in { "verifyWrites", "walk" } do
        if type(settings[key]) == "boolean" then
            config[key] = settings[key]
            applied[key] = settings[key]
        end
    end

    if type(settings.trustedUserIds) == "table" then
        local ids = {}

        for _, userId in settings.trustedUserIds do
            local id = tonumber(userId)

            if id and id > 0 then
                ids[#ids + 1] = math.floor(id)
            end
        end

        config.trustedUserIds = ids
        applied.trustedUserIds = ids
    end

    if applied.packetId or applied.offset then
        self.probeData = nil
    end

    return applied
end

---Switch between "primary" and "observer", also while test mode is running.
---@param role string
function DesyncResearch:setRole(role)
    self.role = role == "observer" and "observer" or "primary"
    self.walkOrigin = nil
end

---Drop the collected totals, the probe and the event log. Counters of the running hook stay.
function DesyncResearch:clearResults()
    self.phases = {}
    self.events = {}
    self.probeData = nil
    self.lastResult = nil
    self.peer = { raw = nil, data = nil, previous = nil, lastMoveAt = nil }
end

---Parse "123, 456" into user ids.
---@param text string
---@return number[]
function DesyncResearch.parseUserIds(text)
    local ids = {}

    for token in string.gmatch(text or "", "%d+") do
        ids[#ids + 1] = tonumber(token)
    end

    return ids
end

function DesyncResearch:trustedSet()
    local set = {}

    for _, userId in self.config.trustedUserIds do
        set[userId] = true
    end

    return set
end

---The local user id, read once: the environment snapshot allocates a player list.
---@return number
function DesyncResearch:localId()
    if not self.cachedLocalId then
        self.cachedLocalId = self.env().localUserId
    end

    return self.cachedLocalId
end

---The other test account, if one is configured.
---@return number?
function DesyncResearch:peerId()
    local localUserId = self:localId()

    for _, userId in self.config.trustedUserIds do
        if userId ~= localUserId then
            return userId
        end
    end

    return nil
end

---@return boolean ok
---@return string? reason
function DesyncResearch:checkGate()
    local ok, env = pcall(self.env)

    if not ok then
        return false, "environment unreadable: " .. tostring(env)
    end

    return DesyncResearch.evaluateGate(env, self:trustedSet())
end

---Hook handling: one hook, shared by the write and the probe, registered only while one of them needs it.
function DesyncResearch:acquireHook(user)
    self.hookUsers[user] = true

    if self.hook then
        return true
    end

    local raknet = self.raknet

    if type(raknet) ~= "table" or type(raknet.add_send_hook) ~= "function" or type(raknet.remove_send_hook) ~= "function" then
        self.hookUsers[user] = nil

        return false, "raknet hooks not available on this executor"
    end

    -- A fault here must never reach the game's packet path, so every packet goes through pcall and is handed on as it came.
    local hook = function(packet)
        local ok, err = pcall(self.onPacket, self, packet)

        if not ok then
            self:fail("hook", err)

            if self.state == "active" and self.errors >= self.config.maxErrors then
                self.state = "failed"
                self.reason = "too many errors"
                self.pendingRelease = true
            end
        end
    end

    local added, err = pcall(raknet.add_send_hook, hook)

    if not added then
        self.hookUsers[user] = nil
        self:fail("add_send_hook", err)

        return false, tostring(err)
    end

    self.hook = hook
    self.pendingRelease = false
    self:event("hook_on", user)

    return true
end

function DesyncResearch:releaseHook(user)
    self.hookUsers[user] = nil

    if user == "desync" then
        self.pendingRelease = false
    end

    if not self.hook or next(self.hookUsers) ~= nil then
        return
    end

    local ok, err = pcall(self.raknet.remove_send_hook, self.hook)

    if not ok then
        self:fail("remove_send_hook", err)
    end

    self.hook = nil
    self.pendingRelease = false
    self:event("hook_off", user)
end

---Called for every outgoing packet. Everything that is not the configured id is left alone and not counted.
function DesyncResearch:onPacket(packet)
    local config = self.config

    if packet.PacketId ~= config.packetId then
        return
    end

    local buf = packet.AsBuffer

    if typeof(buf) ~= "buffer" then
        error("AsBuffer is not a buffer")
    end

    local now = self.clock()
    local size = buffer.len(buf)
    local offset = config.offset

    self.packets += 1

    if self.lastPacketAt then
        local delta = now - self.lastPacketAt

        if delta > 0 then
            self.rate = self.rate == 0 and (1 / delta) or (self.rate * 0.9 + (1 / delta) * 0.1)
        end
    end

    self.lastPacketAt = now

    if size < offset + FIELD_WIDTH then
        self.short += 1

        return
    end

    if self.testMode then
        self:probeField(buf, size, offset, config.packetId)
    end

    if self.state ~= "active" then
        return
    end

    buffer.writeu32(buf, offset, config.value)
    packet:SetData(buf)
    self.written += 1

    if config.verifyWrites and buffer.readu32(packet.AsBuffer, offset) ~= config.value then
        self.mismatch += 1
    end
end

---Aggregate what the field does on live packets. Constant memory: running min/max, a capped set of distinct values.
function DesyncResearch:probeField(buf, size, offset, id)
    local probe = self.probeData

    if not probe then
        probe = { count = 0, min = math.huge, max = -math.huge, last = 0, distinct = {}, distinctCount = 0, byte0Matches = 0, minSize = size, maxSize = size }
        self.probeData = probe
    end

    local value = buffer.readu32(buf, offset)

    probe.count += 1
    probe.last = value
    probe.min = math.min(probe.min, value)
    probe.max = math.max(probe.max, value)
    probe.minSize = math.min(probe.minSize, size)
    probe.maxSize = math.max(probe.maxSize, size)

    if buffer.readu8(buf, 0) == id then
        probe.byte0Matches += 1
    end

    if not probe.distinct[value] and probe.distinctCount < MAX_DISTINCT then
        probe.distinct[value] = true
        probe.distinctCount += 1
    end
end

---What the probe saw, for the console.
function DesyncResearch:probe()
    local probe = self.probeData

    if not probe then
        return nil
    end

    return {
        packets = probe.count,
        min = probe.min,
        max = probe.max,
        last = probe.last,
        distinct = probe.distinctCount,
        distinctCapped = probe.distinctCount >= MAX_DISTINCT,
        byte0IsId = probe.byte0Matches == probe.count,
        minSize = probe.minSize,
        maxSize = probe.maxSize,
    }
end

---Switch the write on. Fails closed: if the gate refuses or the hook cannot be installed nothing is written.
---@return boolean ok
---@return string? reason
function DesyncResearch:enable()
    if self.state == "active" then
        return true
    end

    local allowed, reason = self:checkGate()

    if not allowed then
        self.state = "blocked"
        self.reason = reason
        self:event("blocked", reason)
        self.notify("desync blocked: " .. tostring(reason), 3)

        return false, reason
    end

    local hooked, err = self:acquireHook("desync")

    if not hooked then
        self.state = "failed"
        self.reason = err

        return false, err
    end

    self.errors = 0
    self.state = "active"
    self.reason = nil
    self.activeSince = self.clock()
    self:event("enabled", "write on")

    return true
end

---Switch the write off and take the hook out if nothing else needs it.
---@param reason string?
function DesyncResearch:disable(reason)
    local wasActive = self.state == "active"

    self:releaseHook("desync")
    self.state = "off"
    self.reason = reason
    self.activeSince = nil

    if wasActive then
        self:event("disabled", reason or "requested")

        if reason then
            self.notify("desync off: " .. reason, 2)
        end
    end
end

---Supervisor: gate re-check, time limit, deferred hook release. Runs a few times a second, never per packet.
function DesyncResearch:update()
    local now = self.clock()

    if self.pendingRelease and self.state ~= "active" then
        self:releaseHook("desync")
    end

    if self.state ~= "active" then
        return
    end

    local allowed, reason = self:checkGate()

    if not allowed then
        return self:disable("gate closed: " .. tostring(reason))
    end

    if now - self.activeSince >= self.config.maxSeconds then
        self:disable("time limit reached")
    end
end

local function newBucket(label)
    return {
        label = label, n = 0, errNowSum = 0, errNowMax = 0, errLagSum = 0, errLagMax = 0, lagSum = 0, lagN = 0, lagMax = 0,
        updates = 0, gapSum = 0, gapN = 0, gapMax = 0, jumps = 0, stale = 0, peerState = "?", written = 0,
    }
end

function DesyncResearch:bucket(label)
    local bucket = self.phases[label]

    if bucket then
        return bucket
    end

    local count = 0

    for _ in self.phases do
        count += 1
    end

    if count >= MAX_PHASES then
        label = "overflow"
        bucket = self.phases[label]
    end

    if not bucket then
        bucket = newBucket(label)
        self.phases[label] = bucket
    end

    return bucket
end

function DesyncResearch:publish(now, x, y, z)
    local fs = self.fs

    if type(fs.write) ~= "function" then
        return
    end

    local userId = self:localId()

    self.seq += 1

    local ring = self.ring

    ring[#ring + 1] = { now, x, y, z }

    if #ring > RING_SIZE then
        table.remove(ring, 1)
    end

    if self.seq % PUBLISH_EVERY ~= 0 then
        return
    end

    local ok, err = pcall(function()
        if type(fs.folder) == "function" and not (type(fs.isFolder) == "function" and fs.isFolder(self.config.exchangeFolder)) then
            fs.folder(self.config.exchangeFolder)
        end

        fs.write(self.config.exchangeFolder .. "/" .. userId .. ".json", self.json.encode({
            uid = userId,
            seq = self.seq,
            phase = self.phase,
            state = self.state,
            role = self.role,
            packets = self.packets,
            written = self.written,
            samples = ring,
        }))
    end)

    if not ok then
        self:fail("publish", err)
    end
end

function DesyncResearch:readPeer(peerId)
    local fs = self.fs

    if type(fs.read) ~= "function" then
        return nil
    end

    local path = self.config.exchangeFolder .. "/" .. peerId .. ".json"

    if type(fs.exists) == "function" and not fs.exists(path) then
        return nil
    end

    local ok, raw = pcall(fs.read, path)

    if not ok or type(raw) ~= "string" or raw == "" then
        return nil
    end

    local peer = self.peer

    if raw == peer.raw then
        return peer.data
    end

    local decoded, data = pcall(self.json.decode, raw)

    if not decoded or type(data) ~= "table" or type(data.samples) ~= "table" then
        return peer.data
    end

    peer.raw = raw
    peer.data = data

    return data
end

---Compare what this client sees of the peer with what the peer reports of itself. Updates the running totals of the peer's current phase.
function DesyncResearch:compare(now, data, ox, oy, oz)
    local config = self.config
    local peer = self.peer
    local samples = data.samples
    local latest = samples[#samples]

    if not latest then
        return
    end

    local bucket = self:bucket(tostring(data.phase or "unlabelled"))

    bucket.peerState = tostring(data.state or "?")
    bucket.written = tonumber(data.written) or bucket.written

    if now - latest[1] > config.staleAfter + PUBLISH_EVERY / config.sampleRate then
        bucket.stale += 1

        return
    end

    bucket.n += 1

    local errNow = distance(ox, oy, oz, latest[2], latest[3], latest[4])

    bucket.errNowSum += errNow
    bucket.errNowMax = math.max(bucket.errNowMax, errNow)

    -- Delay of the replicated position: the age of the peer's own sample that is closest to what we see. Only meaningful while the peer moves.
    local bestDistance, bestTime = math.huge, latest[1]
    local spanMax = 0
    local first = samples[1]

    for _, sample in samples do
        local gap = distance(ox, oy, oz, sample[2], sample[3], sample[4])

        if gap < bestDistance then
            bestDistance, bestTime = gap, sample[1]
        end

        spanMax = math.max(spanMax, distance(first[2], first[3], first[4], sample[2], sample[3], sample[4]))
    end

    local moving = spanMax > MOVING_STUDS

    if moving then
        local lag = now - bestTime

        bucket.lagSum += lag
        bucket.lagN += 1
        bucket.lagMax = math.max(bucket.lagMax, lag)
        bucket.errLagSum += bestDistance
        bucket.errLagMax = math.max(bucket.errLagMax, bestDistance)
    end

    -- Update cadence and jumps of the replicated position.
    local previous = peer.previous

    if previous then
        local step = distance(ox, oy, oz, previous[1], previous[2], previous[3])

        if step > 0.01 then
            bucket.updates += 1

            if peer.lastMoveAt and moving then
                local gap = now - peer.lastMoveAt

                bucket.gapSum += gap
                bucket.gapN += 1
                bucket.gapMax = math.max(bucket.gapMax, gap)
            end

            peer.lastMoveAt = now
        end

        if step > config.jumpStuds then
            bucket.jumps += 1
        end
    else
        peer.lastMoveAt = now
        previous = { 0, 0, 0 }
        peer.previous = previous
    end

    -- Reused in place: this runs at the sample rate and should not allocate.
    previous[1], previous[2], previous[3] = ox, oy, oz
end

---One sampling step: own sample out, peer comparison in.
function DesyncResearch:step()
    local now = self.serverTime()
    local x, y, z = self.localPosition()

    if x then
        self:publish(now, x, y, z)

        if self.config.walk and self.role == "primary" then
            if not self.walkOrigin then
                self.walkOrigin = { x, y, z }
            end

            if now - self.walkAt >= WALK_PERIOD then
                self.walkAt = now
                self.walkStep += 1
                self.walker(self.walkStep, self.walkOrigin)
            end
        end
    end

    if self.role ~= "observer" then
        return
    end

    local peerId = self:peerId()

    if not peerId then
        return
    end

    local data = self:readPeer(peerId)
    local ox, oy, oz = self.observedPosition(peerId)

    if data and ox then
        self:compare(now, data, ox, oy, oz)
    end
end

---Start test mode: the sampling loop, the probe and the supervisor. Passive, allowed in any server.
---@param role string "primary" or "observer"
function DesyncResearch:startTest(role)
    if self.testMode then
        return true
    end

    local acquired, err = self:acquireHook("probe")

    if not acquired then
        self.notify("test mode: " .. tostring(err), 3)

        return false, err
    end

    self.role = role == "observer" and "observer" or "primary"
    self.testMode = true
    self.generation += 1
    self.phases = {}
    self.peer = { raw = nil, data = nil, previous = nil, lastMoveAt = nil }
    self.ring = {}
    self.walkOrigin = nil

    local generation = self.generation

    self.spawn(function()
        self.samplers += 1

        while self.testMode and self.generation == generation do
            local ok, stepErr = pcall(self.step, self)

            if not ok then
                self:fail("step", stepErr)
            end

            if self.heartbeat == nil then
                pcall(self.update, self)
            end

            self.wait(1 / self.config.sampleRate)
        end

        self.samplers -= 1
    end)

    if self.playerAdded then
        self.connections[#self.connections + 1] = self.playerAdded:Connect(function()
            if self.state == "active" then
                local allowed, reason = self:checkGate()

                if not allowed then
                    self:disable("gate closed: " .. tostring(reason))
                end
            end
        end)
    end

    if self.heartbeat then
        self.connections[#self.connections + 1] = self.heartbeat:Connect(function()
            local now = self.clock()

            if now - self.lastSupervisedAt >= 0.25 then
                self.lastSupervisedAt = now
                self:update()
            end
        end)
    end

    self:event("test_on", self.role)
    self.notify("desync test mode on (" .. self.role .. ")", 2)

    return true
end

function DesyncResearch:stopTest()
    if not self.testMode then
        return
    end

    self:cancelSuite()
    self.testMode = false
    self.generation += 1
    self.phase = "idle"

    for _, connection in self.connections do
        pcall(connection.Disconnect, connection)
    end

    self.connections = {}
    self:releaseHook("probe")

    local fs = self.fs

    if type(fs.delete) == "function" and type(fs.exists) == "function" then
        local path = self.config.exchangeFolder .. "/" .. self:localId() .. ".json"

        pcall(function()
            if fs.exists(path) then
                fs.delete(path)
            end
        end)
    end

    self:event("test_off", "stopped")
    self.notify("desync test mode off", 2)
end

function DesyncResearch:cancelSuite()
    if self.suite then
        self.suite.cancelled = true
    end
end

---Primary only: baseline with the write off, the write on, baseline again. The observer follows the phase label the primary publishes. If the gate
---refuses the write phase it is recorded as skipped and the run is marked incomplete; nothing is written.
---@param seconds number? length of each phase
---@param done function? called with the result table
function DesyncResearch:runSuite(seconds, done)
    if not self.testMode then
        return false, "start test mode first"
    end

    if self.role ~= "primary" then
        return false, "only the primary runs the suite"
    end

    if self.suite then
        return false, "a suite is already running"
    end

    seconds = clamp(tonumber(seconds) or 8, 1, self.config.maxSeconds)

    local suite = { cancelled = false }
    local result = { seconds = seconds, phases = {}, complete = true }

    self.suite = suite
    self.notify("desync test started", 2)

    self.spawn(function()
        local order = {
            { label = "baseline-before", write = false },
            { label = "desync", write = true },
            { label = "baseline-after", write = false },
        }

        for _, step in order do
            if suite.cancelled then
                result.complete = false

                break
            end

            local entry = { label = step.label, write = step.write, skipped = nil }
            local writtenBefore = self.written
            local packetsBefore = self.packets

            self.phase = step.label

            if step.write then
                local ok, reason = self:enable()

                if not ok then
                    entry.skipped = reason
                    result.complete = false
                end
            end

            if not entry.skipped then
                local deadline = self.clock() + seconds

                while self.clock() < deadline and not suite.cancelled do
                    self.wait(0.25)
                end
            end

            if step.write then
                self:disable()
            end

            entry.packets = self.packets - packetsBefore
            entry.written = self.written - writtenBefore
            result.phases[#result.phases + 1] = entry
        end

        self.phase = "idle"
        self.suite = nil
        self.lastResult = result
        self:event("suite_done", result.complete and "complete" or "incomplete")
        self.notify(result.complete and "desync test finished" or "desync test finished (incomplete)", result.complete and 2 or 3)

        if done then
            pcall(done, result)
        end
    end)

    return true
end

---Per-phase totals as plain numbers, in a fixed order.
function DesyncResearch:report()
    local out = {}

    for label, bucket in self.phases do
        out[#out + 1] = {
            phase = label,
            samples = bucket.n,
            stale = bucket.stale,
            peerState = bucket.peerState,
            peerWritten = bucket.written,
            errNowMean = bucket.n > 0 and bucket.errNowSum / bucket.n or nil,
            errNowMax = bucket.errNowMax,
            lagMean = bucket.lagN > 0 and bucket.lagSum / bucket.lagN or nil,
            lagMax = bucket.lagN > 0 and bucket.lagMax or nil,
            errAtLagMean = bucket.lagN > 0 and bucket.errLagSum / bucket.lagN or nil,
            errAtLagMax = bucket.lagN > 0 and bucket.errLagMax or nil,
            updates = bucket.updates,
            gapMean = bucket.gapN > 0 and bucket.gapSum / bucket.gapN or nil,
            gapMax = bucket.gapN > 0 and bucket.gapMax or nil,
            jumps = bucket.jumps,
        }
    end

    table.sort(out, function(a, b)
        return a.phase < b.phase
    end)

    return out
end

---Short state for the UI.
function DesyncResearch:status()
    local peerId = self:peerId()
    local data = self.peer.data

    return {
        state = self.state,
        reason = self.reason,
        testMode = self.testMode,
        role = self.role,
        phase = self.phase,
        hook = self.hook ~= nil,
        packets = self.packets,
        written = self.written,
        short = self.short,
        mismatch = self.mismatch,
        errors = self.errors,
        rate = self.rate,
        remaining = self.state == "active" and math.max(0, self.config.maxSeconds - (self.clock() - self.activeSince)) or nil,
        peerId = peerId,
        peerState = data and data.state or nil,
        peerPhase = data and data.phase or nil,
    }
end

---The two clients side by side: this client's counters and the peer's last published ones.
function DesyncResearch:compareStates()
    local mine = self:status()
    local data = self.peer.data

    return {
        mine = { state = mine.state, phase = mine.phase, role = mine.role, packets = mine.packets, written = mine.written },
        peer = data and { state = data.state, phase = data.phase, role = data.role, packets = data.packets, written = data.written } or nil,
        inSync = data ~= nil and data.phase == mine.phase,
    }
end

---One-line text for the UI and the console.
function DesyncResearch:summary()
    local status = self:status()
    local text = string.format("state=%s test=%s role=%s phase=%s packets=%d written=%d short=%d mismatch=%d errors=%d rate=%.1f/s", status.state, tostring(status.testMode), status.role, status.phase, status.packets, status.written, status.short, status.mismatch, status.errors, status.rate)

    if status.reason then
        text ..= " reason=" .. tostring(status.reason)
    end

    return text
end

---Write the phase report and the event log to the workspace.
---@return string? path
---@return string? reason
function DesyncResearch:saveResults()
    local fs = self.fs

    if type(fs.write) ~= "function" then
        return nil, "no writefile on this executor"
    end

    local path = string.format("%s/results_%d_%s.json", self.config.exchangeFolder, os.time(), self.role)

    local ok, err = pcall(function()
        if type(fs.folder) == "function" and not (type(fs.isFolder) == "function" and fs.isFolder(self.config.exchangeFolder)) then
            fs.folder(self.config.exchangeFolder)
        end

        fs.write(path, self.json.encode({
            role = self.role,
            status = self:status(),
            probe = self:probe(),
            phases = self:report(),
            suite = self.lastResult,
            events = self.events,
            trusted = #self.config.trustedUserIds,
        }))
    end)

    if not ok then
        self:fail("save", err)

        return nil, tostring(err)
    end

    self:event("saved", path)

    return path
end

---Stop everything and drop all state. Safe to call twice.
function DesyncResearch:unload()
    self:stopTest()
    self:disable()
    self:releaseHook("desync")
    self:releaseHook("probe")
    self.phases = {}
    self.events = {}
    self.ring = {}
    self.probeData = nil
end

return DesyncResearch
