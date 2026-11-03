-- Vanta: a modular HvH script for Da Hood on the Priv9 UI.
-- Layout: Util -> Settings -> Players -> Target -> Resolver -> Aim -> Body -> Follow -> VoidSpam -> AutoFire -> Ragebot -> Menu.
-- Every module reads its settings live from the UI flags, so a loaded config takes effect without any extra wiring, and each module cleans up after
-- itself when its toggle goes off or the script unloads. One Heartbeat driver (Ragebot) steps the modules in a fixed order; only Body ever moves the
-- character, and it asks Void Spam first and Follow second, so the two can never fight over the character.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local environment = getgenv()

if environment.Vanta and environment.Vanta.unload then
	pcall(environment.Vanta.unload)
end

-- Services.
local playersService = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local statsService = game:GetService("Stats")

-- Constants.
local VOID_DISTANCE = 9e5
local MAX_REAL_SPEED = 80
local HISTORY_SECONDS = 3
local LIBRARY_URL = "https://raw.githubusercontent.com/i77lhm/Libraries/refs/heads/main/Priv9/Library.lua"

local localPlayer = playersService.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = localPlayer:GetMouse()

---@module Util
local Util = {}

---Small connection and task bag. Everything a module creates goes in one so unloading is a single call.
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ tasks = {} }, Maid)
end

---Keep a connection, function or instance for cleaning later.
---@param task any
function Maid:give(task)
	self.tasks[#self.tasks + 1] = task
	return task
end

function Maid:clean()
	local tasks = self.tasks
	self.tasks = {}

	for _, task in tasks do
		local kind = typeof(task)

		if kind == "RBXScriptConnection" then
			task:Disconnect()
		elseif kind == "function" then
			pcall(task)
		elseif kind == "Instance" then
			task:Destroy()
		end
	end
end

Util.Maid = Maid

---True for a position that is out in the void rather than on the map.
---@param position Vector3
function Util.inVoid(position)
	local magnitude = position.Magnitude

	return magnitude ~= magnitude or magnitude >= VOID_DISTANCE
end

---Round-trip time in seconds.
function Util.ping()
	local ok, value = pcall(function()
		return statsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)

	return ok and value / 1000 or 0.05
end

---Safe flag read: the Priv9 library keeps every control's value in library.flags.
local library, notifications
local function flag(name, fallback)
	local value = library and library.flags[name]

	if value == nil then
		return fallback
	end

	return value
end

---Whether a dropdown (single or multi) has the item selected.
local function picked(name, item, fallback)
	local value = flag(name, fallback)

	if type(value) == "table" then
		return table.find(value, item) ~= nil
	end

	return value == item
end

---@module Hooks
---One metamethod hook per kind for the whole session. A hook cannot be removed, and a new one on every load stacked a layer on every instance index, call and
---write (a client that was reloaded many times slowed down and then dropped). So the first load installs a thin hook that calls whatever handler is set
---for that metamethod, and later loads, and unloading, only change the handler. An empty handler passes straight through.
local Hooks = {}

---@param metamethod string "__index", "__newindex" or "__namecall"
---@param handler function? (original, ...) -> ...; nil passes through
function Hooks.set(metamethod, handler)
	local registry = environment.VantaHooks

	if not registry then
		registry = {}
		environment.VantaHooks = registry
	end

	local entry = registry[metamethod]

	if not entry and handler == nil then
		return
	end

	if not entry then
		entry = {}
		registry[metamethod] = entry

		local original
		original = hookmetamethod(game, metamethod, newcclosure(function(...)
			local handle = entry.handler

			if handle then
				return handle(original, ...)
			end

			return original(...)
		end))
	end

	entry.handler = handler
end

---@module Players
local Players = {}

---@param player Player
function Players.root(player)
	local character = player and player.Character

	return character and character:FindFirstChild("HumanoidRootPart")
end

---Da Hood keeps the real state in BodyEffects; Humanoid.Health stays above 0 until the character is removed.
---@param player Player
---@return string? phase "respawning", "loading", "protected" or nil when the player can be hit
function Players.phase(player)
	local character = player.Character

	if not character then
		return "respawning"
	end

	local effects = character:FindFirstChild("BodyEffects")
	local dead = effects and effects:FindFirstChild("Dead")
	local sdeath = effects and effects:FindFirstChild("SDeath")

	if (dead and dead.Value) or (sdeath and sdeath.Value) then
		return "respawning"
	end

	if not effects or not character:FindFirstChild("HumanoidRootPart") or not character:FindFirstChild("FULLY_LOADED_CHAR") then
		return "loading"
	end

	if character:FindFirstChild("ForceField") or character:FindFirstChild("FORCEFIELD") then
		return "protected"
	end

	return nil
end

---@param player Player
function Players.knocked(player)
	local character = player.Character
	local effects = character and character:FindFirstChild("BodyEffects")
	local value = effects and effects:FindFirstChild("K.O")

	return value ~= nil and value.Value == true
end

---Health as a fraction for target selection.
---@param player Player
function Players.health(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	return humanoid and humanoid.Health or math.huge
end

---@module Status
---A friendly / neutral / enemy mark for every other player, kept between sessions in the workspace file `Vanta/statuses.json` (by user id). Target
---selection, ESP colours, Auto Stomp, Safe Purchasing and the legit features read it through `Status.get`. Auto rules can mark friends and crew mates
---friendly and the friends of an enemy enemy.
local Status = { values = {}, loaded = false, autoAt = 0 }

local STATUS_FILE = "Vanta/statuses.json"

function Status.load()
	Status.loaded = true

	local ok, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(readfile(STATUS_FILE))
	end)

	if ok and type(decoded) == "table" then
		for id, value in decoded do
			Status.values[tonumber(id) or id] = value
		end
	end
end

local function saveStatuses()
	pcall(function()
		if not isfolder("Vanta") then
			makefolder("Vanta")
		end

		local plain = {}

		for id, value in Status.values do
			plain[tostring(id)] = value
		end

		writefile(STATUS_FILE, game:GetService("HttpService"):JSONEncode(plain))
	end)
end

---@param player Player
---@return string "neutral", "friendly" or "enemy"
function Status.get(player)
	return Status.values[player.UserId] or "neutral"
end

---@param player Player
---@param value string
function Status.set(player, value)
	if value == "neutral" then
		Status.values[player.UserId] = nil
	else
		Status.values[player.UserId] = value
	end

	saveStatuses()
end

local function crewOf(player)
	local folder = player:FindFirstChild("DataFolder")
	local info = folder and folder:FindFirstChild("Information")
	local crew = info and info:FindFirstChild("Crew")

	return crew and crew.Value ~= "" and crew.Value or nil
end

---Marks players by the rules that are on; runs every few seconds.
function Status.auto(now)
	if now - Status.autoAt < 3 then
		return
	end

	Status.autoAt = now

	local myCrew = crewOf(localPlayer)

	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer then
			local current = Status.get(player)

			if flag("status_friends", false) and current == "neutral" then
				local ok, friends = pcall(player.IsFriendsWith, player, localPlayer.UserId)

				if ok and friends then
					Status.set(player, "friendly")

					continue
				end
			end

			if flag("status_crew", false) and current == "neutral" and myCrew and crewOf(player) == myCrew then
				Status.set(player, "friendly")

				continue
			end

			if flag("status_enemy_friends", false) and current == "neutral" then
				for _, other in playersService:GetPlayers() do
					if other ~= player and other ~= localPlayer and Status.get(other) == "enemy" then
						local ok, friends = pcall(player.IsFriendsWith, player, other.UserId)

						if ok and friends then
							Status.set(player, "enemy")

							break
						end
					end
				end
			end
		end
	end
end

---@module Target
---One selected target for every module. Nothing else keeps its own copy of "who we are shooting at".
local Target = {
	player = nil,
	character = nil,
	changed = {}, -- callbacks(newPlayer)
}

local function setTarget(player)
	if Target.player == player and (player == nil or Target.character == player.Character) then
		return
	end

	Target.player = player
	Target.character = player and player.Character or nil

	for _, callback in Target.changed do
		task.spawn(callback, player)
	end
end

---Whether a player can be picked as a target right now.
---@param player Player
function Target.eligible(player)
	if player == localPlayer or not Players.root(player) then
		return false
	end

	local phase = Players.phase(player)

	if phase == "respawning" or phase == "loading" then
		return false
	end

	if not picked("target_statuses", Status.get(player), { "neutral", "enemy" }) then
		return false
	end

	if phase == "protected" and picked("target_ignore_if", "protected", { "in void", "protected", "knocked" }) then
		return false
	end

	if Players.knocked(player) and picked("target_ignore_if", "knocked", { "in void", "protected", "knocked" }) then
		return false
	end

	return true
end

local function pick()
	local mode = flag("target_priority", "closest to mouse")
	local myRoot = Players.root(localPlayer)
	local mouseLocation = userInputService:GetMouseLocation()
	local fov = flag("target_fov", 180)
	local maxDistance = flag("target_distance", 1000)
	local best, bestScore = nil, math.huge

	for _, player in playersService:GetPlayers() do
		if not Target.eligible(player) then
			continue
		end

		local root = Players.root(player)
		local position = root.Position
		local score = nil

		if Util.inVoid(position) and picked("target_ignore_if", "in void", { "in void", "protected", "knocked" }) then
			continue
		end

		if myRoot and not Util.inVoid(position) and (position - myRoot.Position).Magnitude > maxDistance then
			continue
		end

		if mode == "closest to mouse" then
			local screen, onScreen = camera:WorldToViewportPoint(position)

			if not onScreen then
				continue
			end

			score = (Vector2.new(screen.X, screen.Y) - mouseLocation).Magnitude

			if score > fov then
				continue
			end
		elseif mode == "closest to character" then
			score = myRoot and (position - myRoot.Position).Magnitude or math.huge
		elseif mode == "lowest health" then
			score = Players.health(player)
		else
			score = math.random()
		end

		if score < bestScore then
			best, bestScore = player, score
		end
	end

	return best
end

---The target key: the first press selects a target, the next one clears it.
function Target.toggle()
	if Target.player then
		setTarget(nil)
		return false
	end

	setTarget(pick())

	return Target.player ~= nil
end

function Target.clear()
	setTarget(nil)
end

Target.set = setTarget

local lastAutoPick = 0

---Keeps the target honest every frame: left the game, respawned, died or got knocked.
function Target.step(now)
	local player = Target.player

	if player then
		local gone = player.Parent ~= playersService
		local drop = false

		if not gone then
			local root = Players.root(player)

			-- the conditions the Untarget When list names; Auto Stomp keeps a knocked target so it can be finished
			drop = (picked("target_untarget_when", "dead", { "dead" }) and Players.phase(player) == "respawning")
				or (picked("target_untarget_when", "knocked", { "dead" }) and Players.knocked(player) and not flag("autostomp_enabled", false))
				or (picked("target_untarget_when", "flung", { "dead" }) and root ~= nil and root.AssemblyLinearVelocity.Magnitude > 250)
		end

		if gone or drop then
			setTarget(nil)
		elseif player.Character ~= Target.character then
			-- a new character: same player, fresh state for everything that tracks it
			Target.character = player.Character

			for _, callback in Target.changed do
				task.spawn(callback, player)
			end
		end
	end

	if not Target.player and flag("target_automatic", false) and now - lastAutoPick >= flag("target_cooldown", 0.25) then
		lastAutoPick = now
		setTarget(pick())
	end
end

---@module Resolver
---Works out where a target really is. A target that hops between spots (void spam, desync) shows up at its true place far more often than at any one
---fake one, so the spots seen on the map over the last moments are binned into a grid and the busiest bin wins. A target that moves like a player is
---simply where it shows, plus a short lead.
local Resolver = {
	samples = {},
	lastMap = nil,
	lastMapAt = 0,
	confidence = 0,
	source = "none",
	jumpedAt = nil :: number?,
	clusteredAt = -1,
	cluster = nil :: Vector3?,
	clusterShare = 0,
	velocity = Vector3.zero,
	spots = {},
	weightedAt = nil :: number?,
}

function Resolver.reset()
	table.clear(Resolver.samples)
	Resolver.lastMap = nil
	Resolver.lastMapAt = 0
	Resolver.confidence = 0
	Resolver.source = "none"
	Resolver.jumpedAt = nil
	Resolver.clusteredAt = -1
	Resolver.cluster = nil
	Resolver.clusterShare = 0
	Resolver.spots = {}
	Resolver.weightedAt = nil
end

---Record where the target shows this frame.
---@param position Vector3
---@param now number
function Resolver.record(position, now)
	local samples = Resolver.samples

	samples[#samples + 1] = { position = position, time = now }

	-- drop what is older than the history window, in one pass from the front
	local keepFrom = 1

	while keepFrom < #samples and now - samples[keepFrom].time > HISTORY_SECONDS do
		keepFrom += 1
	end

	if keepFrom > 1 then
		table.move(samples, keepFrom, #samples, 1)

		for index = #samples - keepFrom + 2, #samples do
			samples[index] = nil
		end
	end

	if not Util.inVoid(position) then
		Resolver.lastMap = position
		Resolver.lastMapAt = now
	end
end

---The map sightings of the last `window` seconds.
local function recentMap(now, window)
	local found = {}

	for index = #Resolver.samples, 1, -1 do
		local sample = Resolver.samples[index]

		if now - sample.time > window then
			break
		end

		if not Util.inVoid(sample.position) then
			found[#found + 1] = sample.position
		end
	end

	return found
end

---The centre of the busiest grid bin (with its neighbours) among the points, and how big a share of them sits there.
local function busiestCluster(points, radius)
	local bins, bestKey, bestCount = {}, nil, 0

	for _, point in points do
		local key = Vector3.new(math.floor(point.X / radius), math.floor(point.Y / radius), math.floor(point.Z / radius))
		local bin = bins[key]

		if not bin then
			bin = { count = 0, sum = Vector3.zero }
			bins[key] = bin
		end

		bin.count += 1
		bin.sum += point
	end

	for key, bin in bins do
		local count = bin.count

		-- the neighbouring bins count too, so a cluster that straddles a bin edge is not split in two
		for x = -1, 1 do
			for y = -1, 1 do
				for z = -1, 1 do
					if x ~= 0 or y ~= 0 or z ~= 0 then
						local neighbour = bins[key + Vector3.new(x, y, z)]
						count += neighbour and neighbour.count or 0
					end
				end
			end
		end

		if count > bestCount then
			bestKey, bestCount = key, count
		end
	end

	if not bestKey then
		return nil, 0
	end

	local sum, total = Vector3.zero, 0

	for x = -1, 1 do
		for y = -1, 1 do
			for z = -1, 1 do
				local bin = bins[bestKey + Vector3.new(x, y, z)]

				if bin then
					sum += bin.sum
					total += bin.count
				end
			end
		end
	end

	return sum / total, total / #points
end

---Velocity over the last tenth of a second of map sightings.
local function measuredVelocity()
	local samples = Resolver.samples
	local newest = samples[#samples]

	if not newest or Util.inVoid(newest.position) then
		return Vector3.zero
	end

	for index = #samples - 1, 1, -1 do
		local older = samples[index]
		local span = newest.time - older.time

		if span >= 0.1 then
			if Util.inVoid(older.position) then
				return Vector3.zero
			end

			return (newest.position - older.position) / span
		end
	end

	return Vector3.zero
end

---The busiest cluster of recent map sightings (or, for a short while, the last map spot). Cached for a twentieth of a second: the clustering is the
---one expensive step.
local function clusterAnswer(now, radius, window)
	if now - Resolver.clusteredAt >= 0.05 then
		Resolver.clusteredAt = now

		local points = recentMap(now, window)

		Resolver.cluster, Resolver.clusterShare = nil, 0

		if #points >= 3 then
			Resolver.cluster, Resolver.clusterShare = busiestCluster(points, radius)
		end
	end

	if Resolver.cluster then
		return Resolver.cluster, Resolver.clusterShare, "cluster"
	end

	-- nothing to cluster on yet: the last place it stood on the map, for a short while only
	if Resolver.lastMap and now - Resolver.lastMapAt < flag("resolver_hold", 1.5) then
		return Resolver.lastMap, 0.3, "held"
	end

	return nil, 0, "none"
end

---Every spot the target is seen at gets a weight. Spots within the merge radius fold into one that moves toward the newest sighting (Lerp), weights fade
---at the Forget Rate (two and a half times as fast for spots away from where the target is now), and a spot seen on the map is held while the target
---sits in the far void. A map sighting adds Normal Position Trust, a void sighting Void Trust, both scaled down for a far target (Distance Penalty).
---The spot with the best score (weight times how often it was seen) wins once it passes Accuracy.
local function weightedAnswer(position, now)
	local spots = Resolver.spots
	local elapsed = Resolver.weightedAt and math.min(now - Resolver.weightedAt, 0.25) or 0
	local inVoid = Util.inVoid(position)
	local mine = Players.root(localPlayer)
	local distance = mine and not inVoid and (mine.Position - position).Magnitude or 0
	local distanceFactor = inVoid and 1 or math.clamp(1 - distance / 100 * flag("resolver_penalty", 2) * 0.01, 0.25, 1)
	local radius = flag("resolver_radius", 12) * 3
	local mergeRadius = radius

	Resolver.weightedAt = now

	if inVoid then
		-- out there a position is only kept to a few studs (32-bit floats), so spots merge within four of those steps
		local far = math.max(math.abs(position.X), math.abs(position.Y), math.abs(position.Z))

		mergeRadius = math.max(radius, 2 ^ (math.floor(math.log(far, 2)) - 23) * 4)
	end

	local forget = flag("resolver_forget", 80) / 20
	local accuracy = 1 + 0.6525 * ((flag("resolver_accuracy", 76.82) - 50) / 50)
	local lerp = math.clamp(flag("resolver_lerp", 10), 10, 100) / 100

	for index = #spots, 1, -1 do
		local spot = spots[index]
		local held = inVoid and spot.seenMap and now - spot.seenMap < 1.25

		if not held then
			spot.weight -= elapsed * forget * ((spot.position - position).Magnitude > mergeRadius and 2.5 or 1)
		end

		if spot.weight < 0.1 then
			table.remove(spots, index)
		end
	end

	local add = (inVoid and flag("resolver_void_trust", 0.2) or flag("resolver_trust", 1.5)) * distanceFactor
	local merged = false

	for _, spot in spots do
		if (spot.position - position).Magnitude <= mergeRadius then
			spot.position = spot.position:Lerp(position, lerp)
			spot.weight = math.clamp(spot.weight + add, -1, 18)
			spot.count += 1
			spot.seenMap = (not inVoid) and now or spot.seenMap
			merged = true

			break
		end
	end

	if not merged then
		spots[#spots + 1] = { position = position, weight = add, count = 1, seenMap = (not inVoid) and now or nil }

		-- a forget rate of 0 never lets a spot go: the list is kept to the 48 best
		if #spots > 48 then
			local worst, worstWeight = nil, math.huge

			for index, spot in spots do
				if spot.weight < worstWeight then
					worst, worstWeight = index, spot.weight
				end
			end

			table.remove(spots, worst)
		end
	end

	local best, bestScore = nil, 0

	for _, spot in spots do
		local score = spot.weight * math.clamp(spot.count * 0.25, 1, 3)

		if score > bestScore then
			best, bestScore = spot, score
		end
	end

	local confidence = best and math.clamp(bestScore / (accuracy * 2), 0, 1) or 0

	if best and bestScore > accuracy then
		return best.position, confidence
	end

	return nil, confidence
end

---@param now number
---@return Vector3? aim, number confidence
function Resolver.aim(now)
	local samples = Resolver.samples
	local newest = samples[#samples]

	if not newest then
		return nil, 0
	end

	local mode = flag("resolver_mode", "adaptive")
	local shows = newest.position
	local onMap = not Util.inVoid(shows)
	local velocity = measuredVelocity()

	Resolver.velocity = velocity

	-- a step between two sightings that no player could walk marks the target as a faker for a moment
	local previous = samples[#samples - 1]

	if previous and onMap and not Util.inVoid(previous.position) then
		local dt = math.max(newest.time - previous.time, 1 / 240)

		if (newest.position - previous.position).Magnitude / dt > MAX_REAL_SPEED * 2 then
			Resolver.jumpedAt = now
		end
	end

	local faking = velocity.Magnitude > MAX_REAL_SPEED or (Resolver.jumpedAt ~= nil and now - Resolver.jumpedAt < 0.75)

	-- On the map the cluster radius gets Out Of Void Bonus on top, so a target that stands on the map is forgiven more than one that hops
	local radius = flag("resolver_radius", 12) + (onMap and flag("resolver_map_bonus", 5) or 0)
	local window = flag("resolver_window", 1.5)

	-- a normal mover: where it shows plus the distance it covers while the shot is on its way
	local function direct()
		if not onMap then
			Resolver.source, Resolver.confidence = "none", 0

			return nil, 0
		end

		local lead = velocity * (Util.ping() + 0.04) * (flag("resolver_lead", 100) / 100)

		if lead.Magnitude > 30 then
			lead = lead.Unit * 30
		end

		Resolver.source, Resolver.confidence = "direct", 1

		return shows + Vector3.new(lead.X, 0, lead.Z), 1
	end

	if mode == "off" then
		return direct()
	end

	-- A target that moves like a player (on the map, not faster than anyone runs, no jump in the last moments) is where it shows: a resolved spot
	-- would only lag behind it. Only the weighted history still takes the sighting in.
	if onMap and not faking then
		if mode == "weighted" or mode == "hybrid" then
			weightedAnswer(shows, now)
		end

		return direct()
	end

	if mode == "cluster" or (mode == "adaptive" and (not onMap or faking)) then
		local position, share, source = clusterAnswer(now, radius, window)

		Resolver.source, Resolver.confidence = source, share

		return position, share
	end

	if mode == "weighted" or mode == "hybrid" then
		-- the weighted history is kept up to date every frame, whichever answer is used
		local weighted, weightedSure = weightedAnswer(shows, now)

		if mode == "hybrid" then
			local cluster, clusterSure = clusterAnswer(now, radius, window)

			if cluster and weighted then
				if (cluster - weighted).Magnitude <= radius then
					local total = clusterSure + weightedSure

					Resolver.source = "hybrid"
					Resolver.confidence = math.min(1, math.max(clusterSure, weightedSure) + 0.2 * math.min(clusterSure, weightedSure))

					return total > 0 and cluster:Lerp(weighted, weightedSure / total) or cluster, Resolver.confidence
				end

				-- they disagree: the surer one wins, the cluster on a tie
				if weightedSure > clusterSure then
					Resolver.source, Resolver.confidence = "weighted", weightedSure

					return weighted, weightedSure
				end

				Resolver.source, Resolver.confidence = "cluster", clusterSure

				return cluster, clusterSure
			end

			if cluster then
				Resolver.source, Resolver.confidence = "cluster", clusterSure

				return cluster, clusterSure
			end
		end

		if weighted then
			Resolver.source, Resolver.confidence = "weighted", weightedSure

			return weighted, weightedSure
		end

		-- nothing resolved: a target that moves like a player is where it shows
		if not faking then
			return direct()
		end

		Resolver.source, Resolver.confidence = "none", 0

		return nil, 0
	end

	-- adaptive, normal mover
	return direct()
end

---@module Aim
---Silent aim for the game's own gun scripts: while an aim is set, the mouse's Hit and Target read as the aim position for scripts other than ours.
local Aim = { position = nil, part = nil, expires = 0, active = true, hooked = false }

function Aim.set(position, part, now, duration)
	Aim.position, Aim.part, Aim.expires = position, part, now + (duration or 0.15)
end

function Aim.clear()
	Aim.position, Aim.part, Aim.expires = nil, nil, 0
end

function Aim.install()
	Hooks.set("__index", function(original, self, key)
		if Aim.active and Aim.position and self == mouse and not checkcaller() then
			if os.clock() > Aim.expires then
				Aim.clear()
			elseif key == "Hit" then
				return CFrame.new(Aim.position)
			elseif key == "Target" and Aim.part then
				return Aim.part
			end
		end

		return original(self, key)
	end)
end

---@module Body
---The one place that moves the character. The modules above it return the CFrame they want for this frame; Body applies the first answer on Heartbeat
---(after the physics step, before replication) and puts the real CFrame back before the frame is drawn, so the camera and the player's own control are
---not disturbed.
local Body = {
	providers = {}, -- ordered { name, want(now) -> CFrame? }
	real = nil,
	applied = false,
	appliedAt = 0,
	spot = nil,
	spotAt = 0,
	lastMap = nil :: CFrame?,
}

function Body.addProvider(name, want)
	Body.providers[#Body.providers + 1] = { name = name, want = want }
end

local function bodyRoot()
	local character = localPlayer.Character

	return character and character:FindFirstChild("HumanoidRootPart")
end

---Called on Heartbeat.
function Body.apply(now)
	local root = bodyRoot()

	if not root or Body.applied then
		return
	end

	if not Util.inVoid(root.Position) then
		Body.lastMap = root.CFrame
	end

	for _, provider in Body.providers do
		local cframe = provider.want(now)

		if cframe then
			Body.real = { cframe = root.CFrame, velocity = root.AssemblyLinearVelocity }
			Body.applied = true

			-- a new place the server has to catch up with: shots wait for it (see Body.settled)
			if not Body.spot or (Body.spot - cframe.Position).Magnitude > 4 then
				Body.spotAt = now
			end

			Body.spot = cframe.Position
			root.CFrame = cframe
			root.AssemblyLinearVelocity = Vector3.zero

			return
		end
	end

	Body.spot = nil
end

---Called before the frame is drawn.
function Body.restore()
	if not Body.applied then
		return
	end

	Body.applied = false

	local root = bodyRoot()

	if root and Body.real then
		root.CFrame = Body.real.cframe
		root.AssemblyLinearVelocity = Body.real.velocity
	end

	Body.real = nil
end

---Whether the server has had the body at its current spot long enough for a shot from there to count.
function Body.settled(now)
	return Body.spot ~= nil and now - Body.spotAt >= Util.ping() + 0.04
end

---@module Follow
local Follow = { healing = false, held = nil :: Vector3?, heldAt = 0, heldStyle = "", aim = nil :: Vector3? }

local function ringOffset(angle, distance)
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local POLYGON_SIDES = { triangle = 3, square = 4, pentagon = 5, hexagon = 6, decagon = 10 }

---A point on the chosen shape round the target, `phase` being how far round it is (0 to 1).
local function shapeOffset(shape, phase, radius)
	local sides = POLYGON_SIDES[shape]

	if sides then
		-- along the straight edges between the corners
		local scaled = phase * sides
		local corner = math.floor(scaled)
		local along = scaled - corner
		local from = ringOffset(corner / sides * math.pi * 2, radius)
		local to = ringOffset((corner + 1) / sides * math.pi * 2, radius)

		return from:Lerp(to, along)
	end

	if shape == "heart" then
		local t = phase * math.pi * 2
		local x = 16 * math.sin(t) ^ 3
		local z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)

		return Vector3.new(x, 0, z) * (radius / 16)
	end

	return ringOffset(phase * math.pi * 2, radius)
end

---Follow's reasons to stand still.
local function followStopped(player)
	if picked("follow_stop_if", "target knocked", { "no gun equipped", "target knocked", "reloading" }) and player and Players.knocked(player) then
		return true
	end

	local character = localPlayer.Character

	if picked("follow_stop_if", "no gun equipped", { "no gun equipped", "target knocked", "reloading" }) and character then
		local tool = character:FindFirstChildOfClass("Tool")

		if not (tool and tool:FindFirstChild("Ammo")) then
			return true
		end
	end

	if picked("follow_stop_if", "reloading", { "no gun equipped", "target knocked", "reloading" }) and character then
		local effects = character:FindFirstChild("BodyEffects")
		local reload = effects and effects:FindFirstChild("Reload")

		if reload and reload.Value == true then
			return true
		end
	end

	return false
end

---Where the body goes for a given aim position, in the chosen style. Shared with Void Spam so a window out of the void uses the same place.
---@param aim Vector3
---@param now number
---@return CFrame
function Follow.cframeFor(aim, now)
	-- Lead: where the target will be by the time the body has been taken there (its speed times Lead Time, at most 60 studs)
	if flag("follow_lead", true) then
		local lead = Resolver.velocity * (flag("follow_lead_time", 80) / 1000)

		if lead.Magnitude > 60 then
			lead = lead.Unit * 60
		end

		aim += Vector3.new(lead.X, 0, lead.Z)
	end

	local style = flag("follow_style", "orbit")
	local shape = flag("follow_shape", "circle")
	local distance = flag("follow_distance", 15)
	local height = flag("follow_height", 0)
	local low, high = flag("follow_sky_min", 10), flag("follow_sky_max", 20)
	local reposition = flag("follow_reposition", 0.05)
	local offset

	if style == "orbit" then
		offset = shapeOffset(shape, (now * flag("follow_speed", 75) / 100) % 1, distance) + Vector3.new(0, height, 0)
	elseif style == "zigzag" then
		local side = math.floor(now * flag("follow_zigzag_speed", 35) / 5) % 2 == 0 and 1 or -1

		offset = Vector3.new(side * distance, flag("follow_zigzag_height", 3), 0)
	else
		-- the styles that hop to a new place keep it for `reposition` seconds (the server has the body about a tenth of a second late)
		if not Follow.held or now - Follow.heldAt >= reposition or Follow.heldStyle ~= style then
			local angle = math.random() * math.pi * 2

			if style == "random" then
				Follow.held = Vector3.new(math.random(-distance, distance), math.random(-distance, distance), math.random(-distance, distance))
			elseif style == "above" then
				Follow.held = Vector3.new(0, low + (high - low) * math.random(), 0)
			elseif style == "strafe above" then
				Follow.held = shapeOffset(shape, math.random(), distance) + Vector3.new(0, height + low + (high - low) * math.random(), 0)
			else
				-- "teleport": a random place round the target between Teleport Min and Teleport Max studs out, up to 5 studs over it
				local near = flag("follow_teleport_min", 2)
				local far = math.max(flag("follow_teleport_max", 17), near)

				Follow.held = ringOffset(angle, near + (far - near) * math.random()) + Vector3.new(0, math.random() * 5, 0)
			end

			Follow.heldAt, Follow.heldStyle = now, style
		end

		offset = Follow.held
	end

	return CFrame.lookAt(aim + offset, aim)
end

---Body provider: the follow's own place, whenever it is on and there is somewhere to go.
function Follow.want(now)
	if not flag("ragebot_enabled", false) or not flag("follow_enabled", false) or not Target.player then
		Follow.held = nil

		return nil
	end

	local aim = Follow.aim

	if not aim then
		return nil
	end

	if Util.inVoid(aim) and not flag("follow_into_void", true) then
		return nil
	end

	if localPlayer.Character and Players.knocked(localPlayer) then
		return nil
	end

	if followStopped(Target.player) then
		return nil
	end

	-- Stop Following While Healing
	if Follow.healing and flag("shop_heal_stop_follow", false) then
		return nil
	end

	return Follow.cframeFor(aim, now)
end

---@module VoidSpam
---Cycles the body between the void and short windows at the target. A window only opens when a gun can shoot in it, because every moment out of the void
---is a moment the target can shoot back; if no gun is ready for IDLE_WINDOW seconds a window opens anyway so the cycle can never stop shooting.
local VoidSpam = { phase = "void", phaseAt = 0, spot = nil, idleSince = 0, baitUntil = 0, baitAt = 0, baitCFrame = nil :: CFrame?, targetVoidAt = nil :: number?, deepSpot = nil :: CFrame?, deepFor = nil :: Instance? }

local IDLE_WINDOW = 2.5

local function randomVoidSpot()
	local range = 4e8

	return CFrame.new(math.random(-range, range), math.random(1e5, range), math.random(-range, range))
end

---One spot far out along a random direction, kept for the whole life (Deep Distance million studs): the body hardly moves there.
local function deepVoidSpot()
	if not VoidSpam.deepSpot or VoidSpam.deepFor ~= localPlayer.Character then
		local far = flag("voidspam_deep", 100) * 1e6
		local angle = math.random() * math.pi * 2

		VoidSpam.deepSpot = CFrame.new(math.cos(angle) * far, far * 0.5, math.sin(angle) * far)
		VoidSpam.deepFor = localPlayer.Character
	end

	return VoidSpam.deepSpot
end

local function voidSpot()
	if flag("voidspam_type", "random") == "deep" then
		return deepVoidSpot()
	end

	return randomVoidSpot()
end

---True when another player's gun reaches the spot (a bait visit there would be shot at).
local function coveredByOthers(spot)
	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer and player ~= Target.player and not Players.knocked(player) then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local tool = character and character:FindFirstChildOfClass("Tool")
			local range = tool and tool:FindFirstChild("Range")

			if root and range and (root.Position - spot).Magnitude <= range.Value + 15 then
				return true
			end
		end
	end

	return false
end

---Bait: a short visit to a spot on the map every Bait Cooldown, Bait Time long, so a target that follows the body comes after it. A visit is skipped when
---another player's gun covers the spot or the body is below 40% health.
local function baitSpot(now)
	if now < VoidSpam.baitUntil and VoidSpam.baitCFrame then
		if flag("voidspam_bait_freeze", false) then
			return VoidSpam.baitCFrame
		end

		local jitter = flag("voidspam_offset", 3)

		return VoidSpam.baitCFrame + Vector3.new(math.random(-jitter, jitter), math.random(-jitter, jitter), math.random(-jitter, jitter))
	end

	if now - VoidSpam.baitAt < flag("voidspam_bait_cooldown", 0.5) then
		return nil
	end

	VoidSpam.baitAt = now

	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health < humanoid.MaxHealth * 0.4 then
		return nil
	end

	local spot

	if flag("voidspam_bait_spot", "random") == "where you stood" and Body.lastMap then
		spot = Body.lastMap
	else
		local range = flag("voidspam_bait_distance", 250)

		spot = CFrame.new(math.random(-range, range), math.random(-200, 200), math.random(-range, range))
	end

	if coveredByOthers(spot.Position) then
		return nil
	end

	VoidSpam.baitCFrame = spot
	VoidSpam.baitUntil = now + flag("voidspam_bait_time", 0.03)

	return spot
end

function VoidSpam.reset()
	VoidSpam.phase, VoidSpam.phaseAt, VoidSpam.spot, VoidSpam.idleSince = "void", 0, nil, 0
	VoidSpam.baitUntil, VoidSpam.baitAt, VoidSpam.baitCFrame = 0, 0, nil
	VoidSpam.targetVoidAt = nil
end

---Set by AutoFire: whether any gun in hand could fire right now.
VoidSpam.gunReady = function()
	return true
end

---Force When: reasons to be out of reach whatever else is going on.
local function voidForced()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if picked("voidspam_force_when", "reloading", {}) and character then
		local effects = character:FindFirstChild("BodyEffects")
		local reload = effects and effects:FindFirstChild("Reload")

		if reload and reload.Value == true then
			return true
		end
	end

	if picked("voidspam_force_when", "tabbed out", {}) and not isrbxactive() then
		return true
	end

	return picked("voidspam_force_when", "not full health", {}) and humanoid ~= nil and humanoid.Health < humanoid.MaxHealth
end

function VoidSpam.want(now)
	if not flag("ragebot_enabled", false) then
		VoidSpam.reset()

		return nil
	end

	local forced = voidForced()

	-- with the spam off, a forced hide is just a hide; with it on, Stop If Forced decides whether the windows go on
	if forced and (not flag("voidspam_enabled", false) or flag("voidspam_stop_forced", false)) then
		VoidSpam.spot = VoidSpam.spot or voidSpot()

		return VoidSpam.spot
	end

	if not flag("voidspam_enabled", false) then
		VoidSpam.reset()

		return nil
	end

	local aim = Follow.aim
	local valid = Target.player ~= nil and aim ~= nil

	if not valid then
		-- nobody to shoot at: stay hidden while waiting (a respawning target is waited for), otherwise leave the body alone
		if flag("voidspam_hide_waiting", true) and Target.player then
			VoidSpam.spot = VoidSpam.spot or voidSpot()

			return VoidSpam.spot
		end

		VoidSpam.reset()

		return nil
	end

	local targetHiding = Util.inVoid(aim)

	if targetHiding then
		VoidSpam.targetVoidAt = now
	end

	-- Out With Target: the target has just come out of the void onto the map, so the body goes onto it and stays for a moment
	if flag("voidspam_out_with_target", true) and not targetHiding and VoidSpam.targetVoidAt and now - VoidSpam.targetVoidAt < 1.5 then
		VoidSpam.phase, VoidSpam.phaseAt, VoidSpam.spot = "window", now, nil

		return Follow.cframeFor(aim, now)
	end

	local settle = Util.ping() + 0.04
	local windowTime = math.max(flag("voidspam_window", 0.12), settle + 0.08)
	local voidTime = flag("voidspam_void", 0.35)
	local elapsed = now - VoidSpam.phaseAt

	if VoidSpam.phase == "void" then
		-- Hide While Target Hides: nothing can be shot at a target in the void, so no window is opened for it
		if elapsed >= voidTime and not (targetHiding and flag("voidspam_hide_with_target", true)) then
			if VoidSpam.gunReady() or elapsed >= IDLE_WINDOW then
				VoidSpam.phase, VoidSpam.phaseAt, VoidSpam.spot = "window", now, nil
			end
		end
	elseif elapsed >= windowTime then
		VoidSpam.phase, VoidSpam.phaseAt, VoidSpam.spot = "void", now, nil
	end

	if VoidSpam.phase == "window" then
		local place = Follow.cframeFor(aim, now)
		local jitter = flag("voidspam_offset", 3)

		-- Offset: a little random movement on the window's place so the body is not a still target
		return place + Vector3.new(math.random(-jitter, jitter), math.random(-jitter, jitter), math.random(-jitter, jitter))
	end

	if flag("voidspam_type", "random") == "bait" then
		local visit = baitSpot(now)

		if visit then
			return visit
		end
	end

	VoidSpam.spot = VoidSpam.spot or voidSpot()

	return VoidSpam.spot
end

---@module AutoFire
---Fires the guns through the game's own tools: the gun is equipped, the aim is set for its script, and the tool is activated. Each gun keeps its own
---cooldown and ammo; a shotgun is never fired from or at the void (the server turns those calls away and counts them against its SecurityTolerance).
local AutoFire = { lastShot = {}, lastEquip = 0, lastReload = {}, current = nil, lastTool = nil :: Instance?, lastSent = 0, lastUnequip = 0 }

local function mainEvent()
	return replicatedStorage:FindFirstChild("MainEvent")
end

local function gunInfo(tool)
	local ammo = tool:FindFirstChild("Ammo")
	local range = tool:FindFirstChild("Range")
	local cooldown = tool:FindFirstChild("ShootingCooldown")

	if not (ammo and range and tool:FindFirstChild("Handle")) then
		return nil
	end

	return {
		tool = tool,
		ammo = ammo.Value,
		range = range.Value,
		cooldown = cooldown and cooldown.Value or 0.1,
		shotgun = tool:GetAttribute("SecurityTolerance") ~= nil,
	}
end

---Every gun the player has, equipped or in the backpack.
local function allGuns()
	local guns = {}
	local character = localPlayer.Character
	local backpack = localPlayer:FindFirstChild("Backpack")

	for _, container in { character, backpack } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") then
					local info = gunInfo(tool)

					if info then
						guns[#guns + 1] = info
					end
				end
			end
		end
	end

	return guns
end

local function gunReadyAt(info, now, aim, myPosition)
	if info.ammo <= 0 then
		return false
	end

	if now - (AutoFire.lastShot[info.tool] or 0) < info.cooldown + 0.02 then
		return false
	end

	if (aim - myPosition).Magnitude > info.range then
		return false
	end

	if info.shotgun and (Util.inVoid(aim) or Util.inVoid(myPosition)) then
		return false
	end

	return true
end

---Whether anything could shoot at the current aim; Void Spam uses it to decide when a window is worth opening.
function AutoFire.anyReady()
	local aim = Follow.aim

	if not aim or Util.inVoid(aim) then
		return false
	end

	local now = os.clock()
	-- (the follow's own place is not worked out here: that would move its held spot; it stands about Distance from the aim)
	local position = aim + Vector3.new(flag("follow_distance", 15), 0, 0)

	for _, info in allGuns() do
		if gunReadyAt(info, now, aim, position) then
			return true
		end
	end

	return false
end

---Empty guns are reloaded while the body is hidden, one request per gun at a time.
local function reloadEmpty(now, guns)
	local event = mainEvent()

	if not event then
		return
	end

	for _, info in guns do
		if info.ammo <= 0 and now - (AutoFire.lastReload[info.tool] or 0) > 1.2 then
			AutoFire.lastReload[info.tool] = now
			event:FireServer("Reload", info.tool)

			return
		end
	end
end

---Auto Equip: the gun to use, from the Guns list in its order (the Double-Barrel first when Prioritize DB is on), among the guns that are loaded and reach.
function AutoFire.preferred(guns, now, aim, position)
	if not flag("autoequip_enabled", false) then
		return nil
	end

	local order = flag("autoequip_guns", { "rifle", "double-barrel sg", "flintlock", "revolver" })
	local best, bestRank = nil, math.huge

	for _, info in guns do
		if gunReadyAt(info, now, aim, position) then
			local name = info.tool.Name:sub(2, -2):lower()
			local rank = table.find(order, name)

			if flag("autoequip_db", false) and name == "double-barrel sg" then
				rank = 0
			end

			if rank and rank < bestRank then
				best, bestRank = info, rank
			end
		end
	end

	return best
end

---Unequip When: the tool goes back in the bag when there is no target, or it is knocked or dead.
function AutoFire.equipStep(now)
	if not flag("autoequip_enabled", false) or now - AutoFire.lastUnequip < 0.5 then
		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or not character:FindFirstChildOfClass("Tool") then
		return
	end

	local player = Target.player
	local drop = (picked("autoequip_unequip", "no target", {}) and player == nil)
		or (player ~= nil and picked("autoequip_unequip", "target knocked", {}) and Players.knocked(player))
		or (player ~= nil and picked("autoequip_unequip", "target dead", {}) and Players.phase(player) == "respawning")

	if drop then
		AutoFire.lastUnequip = now
		humanoid:UnequipTools()
	end
end

function AutoFire.step(now)
	if not flag("autofire_enabled", false) then
		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local aim = Follow.aim

	if not humanoid or humanoid.Health <= 0 or Players.knocked(localPlayer) then
		return
	end

	local guns = allGuns()

	if flag("autofire_reload", true) and (VoidSpam.phase == "void" or not flag("voidspam_enabled", false)) then
		reloadEmpty(now, guns)
	end

	if not aim or not Target.player or Util.inVoid(aim) then
		return
	end

	-- a shot from the void is thrown away, and one from a spot the server has not caught up with yet is refused
	if flag("voidspam_enabled", false) and VoidSpam.phase ~= "window" then
		return
	end

	if Body.spot and not Body.settled(now) then
		return
	end

	local position = Body.spot or (Players.root(localPlayer) and Players.root(localPlayer).Position)

	if not position or Util.inVoid(position) then
		return
	end

	local chosen = nil

	for _, info in guns do
		if gunReadyAt(info, now, aim, position) then
			if not chosen or info.cooldown > chosen.cooldown then
				-- the slow guns go first: a fast one would otherwise always arrive first and starve them
				chosen = info
			end
		end
	end

	chosen = AutoFire.preferred(guns, now, aim, position) or chosen

	if not chosen then
		return
	end

	-- Gun Gap: a different gun waits this long after the last one sent (the server takes about one shot per short window across all the guns)
	if AutoFire.lastTool and AutoFire.lastTool ~= chosen.tool and now - AutoFire.lastSent < flag("autofire_gap", 40) / 1000 then
		return
	end

	if chosen.tool.Parent ~= character then
		if now - AutoFire.lastEquip >= 0.15 then
			AutoFire.lastEquip = now
			humanoid:EquipTool(chosen.tool)
		end

		return
	end

	-- Hitboxes: the head when it is ticked (it wins over the others), otherwise the torso for body, arms and legs
	local root = Target.character and Target.character:FindFirstChild(picked("autofire_hitbox", "head", { "head" }) and "Head" or "HumanoidRootPart")

	Aim.set(aim, root, now, 0.2)
	AutoFire.lastShot[chosen.tool] = now
	AutoFire.lastTool, AutoFire.lastSent = chosen.tool, now
	chosen.tool:Activate()
end

---@module AutoStomp
---Finishes a knocked target: the body stands over its torso and asks the server to stomp. Asked before Follow and Void Spam, so a knocked target is
---stomped instead of followed.
local AutoStomp = { lastStomp = 0 }

local STOMP_OFFSET = Vector3.new(0, 3, 0)

---The knocked player to finish: the target when it is knocked, otherwise the nearest knocked player whose status is one Auto Stomp was told to take.
function AutoStomp.pick()
	local target = Target.player

	if target and Players.knocked(target) then
		return target
	end

	local mine = Players.root(localPlayer)

	if not mine then
		return nil
	end

	local best, bestDistance = nil, flag("autostomp_range", 300)

	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer and Players.knocked(player) and Players.phase(player) ~= "respawning"
			and picked("autostomp_statuses", Status.get(player), { "neutral", "enemy" }) then
			local root = Players.root(player)

			if root and not Util.inVoid(root.Position) then
				local distance = (root.Position - mine.Position).Magnitude

				if distance < bestDistance then
					best, bestDistance = player, distance
				end
			end
		end
	end

	return best
end

function AutoStomp.want(now)
	if not flag("ragebot_enabled", false) or not flag("autostomp_enabled", false) then
		return nil
	end

	local player = AutoStomp.pick()
	local character = player and player.Character

	if not character then
		return nil
	end

	-- a target that has died (or is loading again) has nothing left to stomp
	if flag("autostomp_stop_dead", true) and Players.phase(player) == "respawning" then
		return nil
	end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")

	-- a body that is being carried or flung cannot be stomped
	if not torso or character:FindFirstChild("GRABBING_CONSTRAINT") or torso.AssemblyLinearVelocity.Magnitude > 100 then
		return nil
	end

	if Util.inVoid(torso.Position) or Players.knocked(localPlayer) then
		return nil
	end

	if now - AutoStomp.lastStomp >= 0.05 then
		local event = mainEvent()

		if event then
			AutoStomp.lastStomp = now
			event:FireServer("Stomp")
		end
	end

	return CFrame.new(torso.Position + STOMP_OFFSET)
end

---@module Visuals
---Drawing-library visuals: the FOV circle, a tracer to the aim, a ring round the target, and the camera on the target. Objects are created when a
---feature is switched on and removed when it goes off, never every frame.
local Visuals = { objects = {}, ringSegments = 24, cameraSwapped = false }

local function drawing(kind, key, properties)
	local object = Visuals.objects[key]

	if not object then
		object = Drawing.new(kind)
		Visuals.objects[key] = object
	end

	for name, value in properties do
		object[name] = value
	end

	return object
end

local function removeDrawing(key)
	local object = Visuals.objects[key]

	if object then
		object:Remove()
		Visuals.objects[key] = nil
	end
end

local function pickerColor(name, fallback)
	local picker = flag(name)

	if type(picker) == "table" and picker.Color then
		return picker.Color, 1 - (picker.Transparency or 0)
	end

	return fallback, 1
end

function Visuals.clear()
	for key in Visuals.objects do
		removeDrawing(key)
	end

	if Visuals.cameraSwapped then
		Visuals.cameraSwapped = false

		local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function Visuals.render()
	local enabled = flag("ragebot_enabled", false)
	local viewport = camera.ViewportSize
	local mouseLocation = userInputService:GetMouseLocation()
	local aim = Follow.aim
	local player = Target.player

	-- FOV circle
	if enabled and flag("fov_show", false) then
		local colour, opacity = pickerColor("fov_color", Color3.fromRGB(255, 255, 255))
		local activeColour, activeOpacity = pickerColor("fov_active_color", Color3.fromRGB(255, 80, 80))
		local active = player ~= nil
		local fovPosition = mouseLocation

		-- Follow Target: the circle is drawn on the target instead of the mouse
		if flag("fov_follow", false) and aim and not Util.inVoid(aim) then
			local point, onScreen = camera:WorldToViewportPoint(aim)

			if onScreen and point.Z > 0 then
				fovPosition = Vector2.new(point.X, point.Y)
			end
		end

		if flag("fov_outline", false) then
			drawing("Circle", "fovback", {
				Visible = true,
				Position = fovPosition,
				Radius = flag("target_fov", 180),
				Thickness = 3,
				NumSides = 64,
				Filled = false,
				Color = pickerColor(active and "fov_active_outline" or "fov_outline_color", Color3.new(0, 0, 0)),
				Transparency = 1,
			})
		else
			removeDrawing("fovback")
		end

		drawing("Circle", "fov", {
			Visible = true,
			Position = fovPosition,
			Radius = flag("target_fov", 180),
			Thickness = 1,
			NumSides = 64,
			Filled = false,
			Color = active and activeColour or colour,
			Transparency = active and activeOpacity or opacity,
		})
	else
		removeDrawing("fov")
		removeDrawing("fovback")
	end

	-- Aim assist FOV circle (drawn whether or not the ragebot is on)
	if flag("aimassist_enabled", false) and flag("aimassist_show_fov", false) then
		local colour, opacity = pickerColor("aimassist_fov_color", Color3.fromRGB(255, 255, 255))

		drawing("Circle", "aafov", {
			Visible = true,
			Position = mouseLocation,
			Radius = flag("aimassist_fov", 120),
			Thickness = 1,
			NumSides = 64,
			Filled = false,
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("aafov")
	end

	if flag("silent_enabled", false) and flag("silent_show_fov", false) then
		local colour, opacity = pickerColor("silent_fov_color", Color3.fromRGB(180, 180, 255))

		drawing("Circle", "safov", {
			Visible = true,
			Position = mouseLocation,
			Radius = flag("silent_fov", 120),
			Thickness = 1,
			NumSides = 64,
			Filled = false,
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("safov")
	end

	-- Tracer
	if enabled and flag("tracer_show", false) and aim and not Util.inVoid(aim) then
		-- End Point: the aim position, or the head, torso or feet of the target
		local endPoint = aim
		local targetCharacter = player and player.Character
		local endName = flag("tracer_end", "aim")

		if targetCharacter and endName ~= "aim" then
			local part = targetCharacter:FindFirstChild(endName == "head" and "Head" or "HumanoidRootPart")

			if part and not Util.inVoid(part.Position) then
				endPoint = part.Position + (endName == "feet" and Vector3.new(0, -3, 0) or Vector3.zero)
			end
		end

		local screen, onScreen = camera:WorldToViewportPoint(endPoint)
		local colour, opacity = pickerColor("tracer_color", Color3.fromRGB(255, 255, 255))
		local origin = flag("tracer_origin", "bottom")
		local from = origin == "mouse" and mouseLocation or origin == "center" and viewport / 2 or Vector2.new(viewport.X / 2, viewport.Y)

		if flag("tracer_outline", false) then
			drawing("Line", "tracerback", {
				Visible = onScreen,
				From = from,
				To = Vector2.new(screen.X, screen.Y),
				Thickness = flag("tracer_thickness", 1) + 2,
				Color = pickerColor("tracer_outline_color", Color3.new(0, 0, 0)),
				Transparency = 1,
			})
		else
			removeDrawing("tracerback")
		end

		drawing("Line", "tracer", {
			Visible = onScreen,
			From = from,
			To = Vector2.new(screen.X, screen.Y),
			Thickness = flag("tracer_thickness", 1),
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("tracer")
		removeDrawing("tracerback")
	end

	-- 3D ring round the target's feet
	if enabled and flag("circle_show", false) and aim and not Util.inVoid(aim) then
		local colour, opacity = pickerColor("circle_color", Color3.fromRGB(180, 120, 255))
		local radius = flag("circle_radius", 4)
		local spin = os.clock() * 1.5
		local previous

		for index = 0, Visuals.ringSegments do
			local angle = spin + index / Visuals.ringSegments * math.pi * 2
			local point, onScreen = camera:WorldToViewportPoint(aim + Vector3.new(math.cos(angle) * radius, -3, math.sin(angle) * radius))
			local current = Vector2.new(point.X, point.Y)

			if previous then
				drawing("Line", "ring" .. index, {
					Visible = onScreen and point.Z > 0,
					From = previous,
					To = current,
					Thickness = 1,
					Color = colour,
					Transparency = opacity,
				})
			end

			previous = current
		end
	else
		for index = 0, Visuals.ringSegments do
			removeDrawing("ring" .. index)
		end
	end

	-- where the follow is taking the body
	if enabled and flag("follow_visualize", false) and Body.spot and not Util.inVoid(Body.spot) then
		local point, onScreen = camera:WorldToViewportPoint(Body.spot)
		local colour, opacity = pickerColor("follow_visualize_color", Color3.fromRGB(120, 200, 255))

		drawing("Circle", "followspot", {
			Visible = onScreen and point.Z > 0,
			Position = Vector2.new(point.X, point.Y),
			Radius = 6,
			Thickness = 2,
			NumSides = 24,
			Filled = false,
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("followspot")
	end

	-- information panel
	if enabled and flag("info_panel", false) and player then
		local targetCharacter = player.Character
		local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
		local effects = targetCharacter and targetCharacter:FindFirstChild("BodyEffects")
		local armor = effects and effects:FindFirstChild("Armor")
		local tool = targetCharacter and targetCharacter:FindFirstChildOfClass("Tool")
		local mine = Players.root(localPlayer)
		local root = Players.root(player)
		local lines = {
			string.format("%s (%s)", player.Name, Status.get(player)),
			targetHumanoid and string.format("health %d/%d", targetHumanoid.Health, targetHumanoid.MaxHealth) or "health ?",
			string.format("armor %d", armor and armor.Value or 0),
			(mine and root and not Util.inVoid(root.Position)) and string.format("distance %d", (mine.Position - root.Position).Magnitude) or "distance ?",
			string.format("tool %s", tool and tool.Name or "none"),
			string.format("aim %s %.2f", Resolver.source, Resolver.confidence),
		}

		drawing("Text", "info", {
			Visible = true,
			Text = table.concat(lines, "\n"),
			Position = Vector2.new(20, viewport.Y * 0.4),
			Size = 14,
			Outline = true,
			Font = Drawing.Fonts and Drawing.Fonts.UI or 0,
			Color = pickerColor("info_color", Color3.fromRGB(255, 255, 255)),
		})
	else
		removeDrawing("info")
	end

	-- the camera on the target
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")

	if enabled and flag("view_target", false) and humanoid and not (flag("view_stop_knocked", false) and Players.knocked(player)) then
		camera.CameraSubject = humanoid
		Visuals.cameraSwapped = true
	elseif Visuals.cameraSwapped then
		Visuals.cameraSwapped = false

		local own = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

		if own then
			camera.CameraSubject = own
		end
	end
end

---@module Shop
---Buying through the game's own shop parts. Every item is a part in Workspace.Ignored.Shop named like `5 [Rifle Ammo] - $281` with a Head and a
---ClickDetector; a purchase stands the body at the part and clicks until the cash drops. The cheapest of the many copies of an item is used.
---Purchases go one at a time. A refused one is not asked again at once (the wait doubles from 0.5 s up to 8 s), and a purchase can be held back while
---other players stand near the shop. The auto buys (armor, ammo, heal, mask, loadout) only ask this module for items; none of them moves the body.
local Shop = {
	armorAt = 0,
	items = {},
	names = {},
	queue = {},
	current = nil,
	bought = 0,
	failures = {},
	blockedUntil = {},
	heldTool = nil,
	autoAt = 0,
	healAt = 0,
	popcorn = nil,
}

local MAX_BACKOFF = 8

local function dataFolder()
	return localPlayer:FindFirstChild("DataFolder")
end

---Cash on hand.
function Shop.cash()
	local folder = dataFolder()
	local currency = folder and folder:FindFirstChild("Currency")

	return currency and currency.Value or 0
end

---Reads the shop parts once; the cheapest copy of each item is kept.
function Shop.scan()
	table.clear(Shop.items)
	table.clear(Shop.names)

	local ignored = workspace:FindFirstChild("Ignored")
	local folder = ignored and ignored:FindFirstChild("Shop")

	if not folder then
		return 0
	end

	for _, part in folder:GetChildren() do
		local packs, name, price = part.Name:lower():match("^(%d*)%s*%[(.-)%]%s*[%-%=]%s*%$(%d+)")
		price = tonumber(price)

		if name and price and price > 0 then
			local head = part:FindFirstChild("Head")
			local detector = part:FindFirstChildOfClass("ClickDetector")

			if head and detector then
				local known = Shop.items[name]

				if not known or price < known.price then
					Shop.items[name] = { name = name, price = price, head = head, detector = detector, packSize = tonumber(packs) }
				end
			end
		end
	end

	for name in Shop.items do
		Shop.names[#Shop.names + 1] = name
	end

	table.sort(Shop.names)

	return #Shop.names
end

local function notify(text)
	if flag("shop_notify", true) and notifications then
		notifications:create_notification({ name = text })
	end
end

---Ask for an item. `packs` is how many times to click (ammo packs); returns false when the item is unknown, already waiting or backing off.
---@param name string lower case item name, e.g. "rifle ammo" or "high-medium armor"
---@param packs number?
function Shop.request(name, packs)
	local item = Shop.items[name]

	if not item or (packs and packs <= 0) then
		return false
	end

	if Shop.current and Shop.current.item == item then
		return false
	end

	for _, queued in Shop.queue do
		if queued.item == item then
			return false
		end
	end

	if os.clock() < (Shop.blockedUntil[name] or 0) then
		return false
	end

	Shop.queue[#Shop.queue + 1] = { item = item, packs = packs or 1 }

	return true
end

---True while a purchase is running (other modules leave the body alone then).
function Shop.busy()
	return Shop.current ~= nil
end

---Whether another player stands near the shop part, for Safe Purchasing.
local function shopWatched(position)
	local radius = flag("shop_safe_distance", 50)
	for _, player in playersService:GetPlayers() do
		local avoided = (player == Target.player and picked("shop_safe_avoid", "target", { "target" })) or picked("shop_safe_avoid", Status.get(player), { "target" })

		if player ~= localPlayer and avoided and not Players.knocked(player) then
			local root = Players.root(player)

			if root and (root.Position - position).Magnitude < radius then
				return true
			end
		end
	end

	return false
end

local function finish(success)
	local current = Shop.current

	Shop.current = nil

	if not current then
		return
	end

	local name = current.item.name

	if success then
		Shop.failures[name] = nil
		-- a short breather: the item takes a moment to show up in the bag, and asking again at once bought a second mask in testing
		Shop.blockedUntil[name] = os.clock() + 1.5
		notify("bought " .. name)
	else
		local failures = (Shop.failures[name] or 0) + 1

		Shop.failures[name] = failures
		Shop.blockedUntil[name] = os.clock() + math.min(0.5 * 2 ^ (failures - 1), MAX_BACKOFF)
		notify("could not buy " .. name)
	end

	-- back to where the character was
	local root = Players.root(localPlayer)
	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

	if root and humanoid and humanoid.Health > 0 and current.origin then
		root.CFrame = current.origin
		root.AssemblyLinearVelocity = Vector3.zero
	end

	-- the gun that was in hand goes back
	local held = Shop.heldTool
	Shop.heldTool = nil

	if held and held.Parent == localPlayer:FindFirstChild("Backpack") and humanoid then
		humanoid:EquipTool(held)
	end
end

---Where the body stands for a purchase: beside the part, a few studs out (measured: a click from 8.8 studs below it was refused, one from 3 studs
---beside it was sold; the detector reaches 9).
local function shopSpot(item)
	return CFrame.new(item.head.Position + Vector3.new(0, 0, 3))
end

---Runs after the body has moved, so the click happens with the body at the shop.
function Shop.step(now)
	local current = Shop.current

	if not current then
		local nextRequest = table.remove(Shop.queue, 1)
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if not nextRequest or not humanoid or humanoid.Health <= 0 or Players.knocked(localPlayer) then
			return
		end

		-- a pack of ammo is refused while a reload runs: ask again later
		local effects = character:FindFirstChild("BodyEffects")
		local reload = effects and effects:FindFirstChild("Reload")

		if nextRequest.item.name:find("ammo") and reload and reload.Value == true then
			return
		end

		if flag("shop_safe", false) and shopWatched(nextRequest.item.head.Position) then
			Shop.blockedUntil[nextRequest.item.name] = now + 1
			notify("held " .. nextRequest.item.name .. " (safe purchasing)")

			return
		end

		local held = character:FindFirstChildOfClass("Tool")

		if held and not nextRequest.item.name:find("armor") then
			Shop.heldTool = held
			humanoid:UnequipTools()
		end

		local root = Players.root(localPlayer)

		if not root then
			return
		end

		Shop.current = {
			item = nextRequest.item,
			packs = nextRequest.packs,
			startedAt = now,
			startBought = Shop.bought,
			origin = root.CFrame,
		}

		return
	end

	-- The character is held at the shop for the whole purchase, not just for a frame: the server only sells to a player it has standing there, and
	-- a spot that is put back before every frame never reached it.
	local root = Players.root(localPlayer)

	if root then
		root.CFrame = shopSpot(current.item)
		root.AssemblyLinearVelocity = Vector3.zero
	end

	local done = Shop.bought - current.startBought
	local timeout = Util.ping() * 2 + current.packs * 0.36 + 0.3

	if done >= current.packs then
		finish(true)
	elseif now - current.startedAt > timeout then
		finish(done > 0)
	else
		fireclickdetector(current.item.detector)
	end
end

---Counts every drop in the cash as one purchase.
function Shop.watchCash(maid)
	local folder = dataFolder()
	local currency = folder and folder:FindFirstChild("Currency")

	if not currency then
		return
	end

	local last = currency.Value

	maid:give(currency:GetPropertyChangedSignal("Value"):Connect(function()
		if currency.Value < last then
			Shop.bought += 1
		end

		last = currency.Value
	end))
end

---@param name string
local function ownsTool(name)
	local character = localPlayer.Character
	local backpack = localPlayer:FindFirstChild("Backpack")

	for _, container in { character, backpack } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool.Name:lower() == "[" .. name .. "]" then
					return tool
				end
			end
		end
	end

	return nil
end

local function armorValue()
	local character = localPlayer.Character
	local effects = character and character:FindFirstChild("BodyEffects")
	local armor = effects and effects:FindFirstChild("Armor")

	return armor and armor.Value or nil
end

local function heal(now, humanoid, spare)
	local fraction = flag("shop_heal_below", 50) / 100

	if humanoid.Health / humanoid.MaxHealth >= fraction then
		-- healed: the food goes back in the bag
		if Shop.popcorn and Shop.popcorn.Parent == localPlayer.Character then
			Shop.popcorn.Parent = localPlayer:FindFirstChild("Backpack")
		end

		Shop.popcorn = nil
		Follow.healing = false

		return
	end

	local food = ownsTool("popcorn")

	if not food then
		if spare then
			Shop.request("popcorn")
		end

		return
	end

	Shop.popcorn = food
	Follow.healing = true

	if food.Parent ~= localPlayer.Character then
		humanoid:EquipTool(food)

		return
	end

	if now - Shop.healAt >= flag("shop_heal_cooldown", 0.3) then
		Shop.healAt = now
		food:Activate()
	end
end

---Disable When: the ammo, mask and loadout buys wait while one of the chosen conditions holds (armor and heal never wait).
function Shop.paused()
	local player = Target.player

	return (picked("shop_pause_when", "target selected", {}) and player ~= nil)
		or (picked("shop_pause_when", "target alive", {}) and player ~= nil and Players.phase(player) ~= "respawning" and not Players.knocked(player))
end

---The auto buys, checked four times a second.
function Shop.auto(now)
	if now - Shop.autoAt < 0.25 or Shop.current then
		return
	end

	Shop.autoAt = now

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 or Players.knocked(localPlayer) then
		return
	end

	local spare = Shop.cash() > flag("shop_keep_cash", 5000)

	if flag("shop_armor", false) then
		local armor = armorValue()

		if armor and armor < flag("shop_armor_below", 52) and spare and now - Shop.armorAt >= flag("shop_armor_cooldown", 0.05) then
			Shop.armorAt = now
			Shop.request("high-medium armor")
		end
	end

	if flag("shop_ammo", false) and #Shop.queue == 0 and not Shop.paused() then
		local folder = dataFolder()
		local inventory = folder and folder:FindFirstChild("Inventory")

		for _, info in allGuns() do
			local record = inventory and inventory:FindFirstChild(info.tool.Name)
			local maxAmmo = info.tool:FindFirstChild("MaxAmmo")

			if record and maxAmmo and maxAmmo.Value > 0 then
				local clips = math.floor((tonumber(record.Value) or 0) / maxAmmo.Value)

				if clips < flag("shop_ammo_clips", 2) + 1 and spare then
					Shop.request(info.tool.Name:sub(2, -2):lower() .. " ammo", flag("shop_ammo_packs", 1))
				end
			end
		end
	end

	if flag("shop_heal", false) then
		heal(now, humanoid, spare)
	else
		Follow.healing = false
	end

	if flag("shop_mask", false) and not character:FindFirstChild("In-gameMask") and not Shop.paused() then
		local mask = ownsTool("mask")

		if mask then
			if mask.Parent ~= character then
				humanoid:EquipTool(mask)
			else
				mask:Activate()
			end
		elseif spare then
			Shop.request("ninja mask")
		end
	end

	if flag("shop_loadout", false) and not Shop.paused() then
		local wanted = flag("shop_loadout_guns", { "rifle" })

		for _, gun in type(wanted) == "table" and wanted or { wanted } do
			local tool = ownsTool(gun)

			if not tool then
				Shop.request(gun)
			else
				-- the gun is owned: top it up when the reserve is below one magazine
				local folder = dataFolder()
				local inventory = folder and folder:FindFirstChild("Inventory")
				local record = inventory and inventory:FindFirstChild(tool.Name)
				local maxAmmo = tool:FindFirstChild("MaxAmmo")

				if record and maxAmmo and (tonumber(record.Value) or 0) < maxAmmo.Value then
					Shop.request(gun .. " ammo", flag("shop_loadout_packs", 5))
				end
			end
		end
	end
end

---@module AntiStomp
---While the character is knocked it is kept out of reach, so there is nothing for anyone to stomp. (Visions-hook also kills the character on purpose;
---this does not: the character just stands in the void until it gets up or dies.)
local AntiStomp = { spot = nil, back = nil :: CFrame? }

function AntiStomp.want()
	if not flag("antistomp_enabled", false) or not Players.knocked(localPlayer) then
		AntiStomp.spot = nil

		return nil
	end

	-- where the character stood when it was knocked, for Teleport Back after the respawn (never a void spot)
	AntiStomp.back = AntiStomp.back or Body.lastMap

	AntiStomp.spot = AntiStomp.spot or CFrame.new(math.random(-1e8, 1e8), 5e7, math.random(-1e8, 1e8))

	return AntiStomp.spot
end

---@module QuickDraw
---Holding a knife or nothing: takes out the gun that reaches the target when it comes in range, and puts the knife back after.
local QuickDraw = { back = nil, drawn = nil, lastSeen = 0, lastEquip = 0 }

function QuickDraw.step(now)
	if not flag("quickdraw_enabled", false) then
		QuickDraw.back, QuickDraw.drawn = nil, nil

		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local aim = Follow.aim

	if not humanoid or humanoid.Health <= 0 or not character then
		return
	end

	local held = character:FindFirstChildOfClass("Tool")
	local heldIsGun = held and held:FindFirstChild("Ammo") ~= nil
	local myPosition = Body.spot or (Players.root(localPlayer) and Players.root(localPlayer).Position)

	if aim and myPosition and not Util.inVoid(aim) and not heldIsGun and now - QuickDraw.lastEquip > 0.2 then
		local best, bestRange = nil, math.huge

		for _, info in allGuns() do
			if info.ammo > 0 and picked("quickdraw_guns", info.tool.Name:sub(2, -2):lower(), { "rifle", "double-barrel sg", "flintlock", "revolver" })
				and (aim - myPosition).Magnitude <= info.range and info.range < bestRange then
				best, bestRange = info.tool, info.range
			end
		end

		if best then
			QuickDraw.back = held
			QuickDraw.drawn = best
			QuickDraw.lastSeen = now
			QuickDraw.lastEquip = now
			humanoid:EquipTool(best)
		end

		return
	end

	-- the target is out of every drawn gun's reach for a second: the knife (or empty hands) comes back
	if QuickDraw.drawn and heldIsGun then
		local info = gunInfo(held)

		if aim and myPosition and info and (aim - myPosition).Magnitude <= info.range then
			QuickDraw.lastSeen = now
		elseif now - QuickDraw.lastSeen > 1 then
			local back = QuickDraw.back

			QuickDraw.drawn, QuickDraw.back = nil, nil
			QuickDraw.lastEquip = now

			if back and back.Parent == localPlayer:FindFirstChild("Backpack") then
				humanoid:EquipTool(back)
			else
				humanoid:UnequipTools()
			end
		end
	end
end

---@module AdStrafe
---Taps A and D in turn while there is a target, so the character sidesteps like a player would.
local AdStrafe = { held = nil, switchedAt = 0 }

local virtualInput = nil

local function sendKey(down, key)
	if not virtualInput then
		local ok, service = pcall(game.GetService, game, "VirtualInputManager")

		virtualInput = ok and service or false
	end

	if virtualInput then
		pcall(virtualInput.SendKeyEvent, virtualInput, down, key, false, game)
	end
end

function AdStrafe.release()
	if AdStrafe.held then
		sendKey(false, AdStrafe.held)
		AdStrafe.held = nil
	end
end

function AdStrafe.step(now)
	local active = flag("adstrafe_enabled", false) and Target.player ~= nil and not Players.knocked(localPlayer)
		and userInputService:GetFocusedTextBox() == nil

	if not active then
		AdStrafe.release()

		return
	end

	if AdStrafe.held == nil or now - AdStrafe.switchedAt >= flag("adstrafe_interval", 0.22) then
		local nextKey = AdStrafe.held == Enum.KeyCode.A and Enum.KeyCode.D or Enum.KeyCode.A

		AdStrafe.release()
		AdStrafe.held = nextKey
		AdStrafe.switchedAt = now
		sendKey(true, nextKey)
	end
end

---@module FullAuto
---Hold the left mouse button to keep shooting the gun in your hands. Speed is a share of the gun's own fire rate; it never goes past the gun's cooldown,
---which the server enforces.
local FullAuto = { lastShot = 0 }

function FullAuto.step(now)
	if not flag("fullauto_enabled", false) or not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or userInputService:GetFocusedTextBox() then
		return
	end

	local character = localPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local info = tool and gunInfo(tool)

	if not info or info.ammo <= 0 then
		return
	end

	local share = math.clamp(flag("fullauto_speed", 100), 1, 100) / 100
	local interval = (info.cooldown + 0.015) / share

	if now - FullAuto.lastShot >= interval then
		FullAuto.lastShot = now
		tool:Activate()
	end
end

---@module Bounty
---Da Hood shows the one bounty there is on every poster in Workspace.MAP.BountyPosters (Texts.PlayerName, a SurfaceGui TextLabel; blank while nobody has one).
---Anti Bounty: your name on the posters, and you leave the server. Auto Bounty: whoever is on the posters becomes the target, and the features needed to
---hunt them are switched on; once nobody here has the bounty, what it switched on goes back off.
local Bounty = { turnedOn = {}, hunted = nil, left = false, checkedAt = 0 }

local BOUNTY_FLAGS = { "ragebot_enabled", "follow_enabled", "autofire_enabled", "autostomp_enabled", "autofire_reload" }

local function setFlag(name, value)
	local setter = library and library.config_flags[name]

	if setter then
		setter(value)
	end
end

---The player named on the first poster that has a name.
local function bountyPlayer()
	local map = workspace:FindFirstChild("MAP")
	local posters = map and map:FindFirstChild("BountyPosters")

	for _, poster in posters and posters:GetChildren() or {} do
		local texts = poster:FindFirstChild("Texts")
		local holder = texts and texts:FindFirstChild("PlayerName")
		local gui = holder and holder:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		local name = label and label.Text

		if name and name ~= "" then
			return playersService:FindFirstChild(name), name
		end
	end

	return nil, nil
end

Bounty.read = bountyPlayer

function Bounty.release()
	for name in Bounty.turnedOn do
		setFlag(name, false)
	end

	Bounty.turnedOn = {}

	if Bounty.hunted and Target.player == Bounty.hunted then
		Target.clear()
	end

	Bounty.hunted = nil
end

function Bounty.step(now)
	if now - Bounty.checkedAt < 0.5 then
		return
	end

	Bounty.checkedAt = now

	local player, name = bountyPlayer()

	if flag("antibounty_enabled", false) and player == localPlayer and not Bounty.left then
		Bounty.left = true

		if notifications then
			notifications:create_notification({ name = "anti bounty: a bounty is on you, leaving" })
		end

		pcall(localPlayer.Kick, localPlayer, "Anti Bounty: a bounty was put on you, so you left the server.")

		return
	end

	if not flag("autobounty_enabled", false) or not player or player == localPlayer then
		if next(Bounty.turnedOn) or Bounty.hunted then
			Bounty.release()
		end

		return
	end

	for _, flagName in BOUNTY_FLAGS do
		if flag(flagName, false) ~= true then
			setFlag(flagName, true)
			Bounty.turnedOn[flagName] = true
		end
	end

	if Bounty.hunted ~= player then
		Bounty.hunted = player

		if notifications then
			notifications:create_notification({ name = "auto bounty: going after " .. name })
		end
	end

	if Target.player ~= player then
		Target.set(player)
	end
end

---@module Esp
---Drawing-library player ESP: box, name, distance, tool, health bar and text, armor bar. Drawings exist only for players that are on screen and the feature
---is on; they are removed when it goes off, when the player leaves, and on unload.
local Esp = { players = {}, MAX_ARMOR = 130 }

local ESP_PARTS = { "box", "name", "distance", "tool", "healthBack", "healthBar", "healthText", "armorBack", "armorBar" }

local function espDrawing(entry, key, kind)
	local object = entry[key]

	if not object then
		object = Drawing.new(kind)
		entry[key] = object
	end

	return object
end

local function hideEntry(entry)
	for _, key in ESP_PARTS do
		if entry[key] then
			entry[key].Visible = false
		end
	end
end

---The colour flag for a player: the target colour, else the friendly or enemy colour, else the normal one.
local function espColour(player, isTarget)
	if isTarget then
		return pickerColor("esp_target_color", Color3.fromRGB(255, 80, 80))
	end

	local status = Status.get(player)

	if status == "friendly" then
		return pickerColor("esp_friendly_color", Color3.fromRGB(80, 255, 120))
	elseif status == "enemy" then
		return pickerColor("esp_enemy_color", Color3.fromRGB(255, 160, 60))
	end

	return pickerColor("esp_color", Color3.fromRGB(255, 255, 255))
end

local function hideCham(entry)
	if entry.cham then
		entry.cham.Enabled = false
	end
end

---Chams (a fill) and Highlight (an outline) are one Highlight object; it is drawn through walls unless Behind Walls is off.
local function updateCham(entry, player, character, isTarget)
	local fill, outline = flag("esp_chams", false), flag("esp_highlight", false)

	if not (fill or outline) then
		hideCham(entry)

		return
	end

	local cham = entry.cham

	if not cham or cham.Adornee ~= character then
		if cham then
			cham:Destroy()
		end

		cham = Instance.new("Highlight")
		cham.Parent = game:GetService("CoreGui")
		entry.cham = cham
	end

	cham.Adornee = character
	cham.Enabled = true
	cham.DepthMode = flag("esp_chams_walls", true) and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
	cham.FillColor = espColour(player, isTarget)
	cham.FillTransparency = fill and flag("esp_chams_transparency", 0.5) or 1
	cham.OutlineColor = pickerColor("esp_highlight_color", Color3.new(1, 1, 1))
	cham.OutlineTransparency = outline and 0 or 1
end

local function destroyEntry(player)
	local entry = Esp.players[player]

	if not entry then
		return
	end

	if entry.cham then
		entry.cham:Destroy()
	end

	for _, key in ESP_PARTS do
		if entry[key] then
			entry[key]:Remove()
		end
	end

	Esp.players[player] = nil
end

function Esp.clear()
	for player in Esp.players do
		destroyEntry(player)
	end
end

---Draws one player. Returns false when nothing could be drawn (no character, in the void, off screen).
---@param player Player
function Esp.draw(player)
	local entry = Esp.players[player]

	if not entry then
		entry = {}
		Esp.players[player] = entry
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not (root and head and humanoid) or Util.inVoid(root.Position) then
		hideEntry(entry)
		hideCham(entry)

		return false
	end

	updateCham(entry, player, character, player == Target.player)

	local top = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
	local bottom = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

	if top.Z <= 0 or bottom.Z <= 0 then
		hideEntry(entry)

		return false
	end

	local height = math.max(bottom.Y - top.Y, 4)
	local width = height * 0.55
	local left = top.X - width / 2
	local isTarget = player == Target.player
	local mainColour = espColour(player, isTarget)
	local font = Drawing.Fonts and Drawing.Fonts.UI or 0
	local textY = top.Y - 15

	if flag("esp_box", true) then
		local box = espDrawing(entry, "box", "Square")

		box.Visible = true
		box.Position = Vector2.new(left, top.Y)
		box.Size = Vector2.new(width, height)
		box.Color = mainColour
		box.Thickness = 1
		box.Filled = false
	elseif entry.box then
		entry.box.Visible = false
	end

	if flag("esp_name", true) then
		local label = espDrawing(entry, "name", "Text")

		label.Visible = true
		label.Text = flag("esp_display_name", true) and player.DisplayName or player.Name
		label.Position = Vector2.new(top.X, textY)
		label.Size = 13
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = mainColour
	elseif entry.name then
		entry.name.Visible = false
	end

	local belowY = bottom.Y + 2

	if flag("esp_distance", false) then
		local mine = Players.root(localPlayer)
		local studs = mine and (mine.Position - root.Position).Magnitude or 0
		local label = espDrawing(entry, "distance", "Text")
		local metres = flag("esp_unit", "studs") == "metres"

		label.Visible = true
		label.Text = metres and string.format("%dm", studs * 0.28) or string.format("%d st", studs)
		label.Position = Vector2.new(top.X, belowY)
		label.Size = 12
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = mainColour
		belowY += 13
	elseif entry.distance then
		entry.distance.Visible = false
	end

	if flag("esp_tool", false) then
		local tool = character:FindFirstChildOfClass("Tool")
		local label = espDrawing(entry, "tool", "Text")
		local text = tool and tool.Name or ""

		label.Visible = text ~= ""
		label.Text = flag("esp_tool_upper", false) and text:upper() or text
		label.Position = Vector2.new(top.X, belowY)
		label.Size = 12
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = mainColour
	elseif entry.tool then
		entry.tool.Visible = false
	end

	local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)

	if flag("esp_health_bar", true) then
		local x = left - 4
		local back = espDrawing(entry, "healthBack", "Line")
		local bar = espDrawing(entry, "healthBar", "Line")

		back.Visible = true
		back.From, back.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y)
		back.Thickness = 3
		back.Color = Color3.new(0, 0, 0)

		bar.Visible = fraction > 0
		bar.From, bar.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y + height * (1 - fraction))
		bar.Thickness = 1
		bar.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 90), fraction)
	else
		if entry.healthBack then entry.healthBack.Visible = false end
		if entry.healthBar then entry.healthBar.Visible = false end
	end

	if flag("esp_health_text", false) and not (flag("esp_health_hide_full", true) and fraction >= 1) then
		local label = espDrawing(entry, "healthText", "Text")

		label.Visible = true
		label.Text = tostring(math.floor(humanoid.Health))
		label.Position = Vector2.new(left - 14, top.Y + height * (1 - fraction))
		label.Size = 11
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = Color3.new(1, 1, 1)
	elseif entry.healthText then
		entry.healthText.Visible = false
	end

	local effects = character:FindFirstChild("BodyEffects")
	local armor = effects and effects:FindFirstChild("Armor")
	local armorValue = armor and armor.Value or 0

	if flag("esp_armor_bar", false) and not (flag("esp_armor_hide_none", true) and armorValue <= 0) then
		local x = left + width + 4
		local armorFraction = math.clamp(armorValue / Esp.MAX_ARMOR, 0, 1)
		local back = espDrawing(entry, "armorBack", "Line")
		local bar = espDrawing(entry, "armorBar", "Line")

		back.Visible = true
		back.From, back.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y)
		back.Thickness = 3
		back.Color = Color3.new(0, 0, 0)

		bar.Visible = armorFraction > 0
		bar.From, bar.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y + height * (1 - armorFraction))
		bar.Thickness = 1
		bar.Color = Color3.fromRGB(70, 140, 255)
	else
		if entry.armorBack then entry.armorBack.Visible = false end
		if entry.armorBar then entry.armorBar.Visible = false end
	end

	return true
end

function Esp.render()
	if not flag("esp_enabled", false) then
		if next(Esp.players) then
			Esp.clear()
		end

		return
	end

	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer then
			if (flag("esp_only_target", false) and player ~= Target.player)
				or not picked("esp_statuses", Status.get(player), { "neutral", "friendly", "enemy" }) then
				destroyEntry(player)
			else
				Esp.draw(player)
			end
		end
	end

	-- players that left
	for player in Esp.players do
		if player.Parent ~= playersService then
			destroyEntry(player)
		end
	end
end

---@module Legit
---The legit bot: aim assist (moves your view toward a target while a key is held), silent aim (answers the game's own gun script with a position near the
---target while you shoot) and the triggerbot (clicks when the crosshair is on a player). The three share one way to find a player, `Legit.best`,
---which reads its FOV, distance, hitbox and visibility settings from the prefix of the feature that asks ("aimassist" or "silent"); the ignore options
---are shared. None of them sends anything to the server except the shot your own gun script makes.
local Legit = { target = nil, targetSince = 0, silentRoll = true, silentWasDown = false }

local function legitPart(character, prefix)
	local hitbox = flag(prefix .. "_hitbox", "head")

	if hitbox == "head" then
		return character:FindFirstChild("Head")
	elseif hitbox == "chest" then
		return character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function visibleFrom(origin, part, character, prefix)
	if not flag(prefix .. "_visible", true) then
		return true
	end

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character, character }

	return workspace:Raycast(origin, part.Position - origin, params) == nil
end

---Whether a player is one the legit features may use right now.
local function legitUsable(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if player == localPlayer or not humanoid or humanoid.Health <= 0 or Players.phase(player) == "respawning" then
		return false
	end

	if not picked("legit_statuses", Status.get(player), { "neutral", "enemy" }) then
		return false
	end

	if flag("legit_ignore_knocked", true) and Players.knocked(player) then
		return false
	end

	if flag("legit_ignore_protected", true) and Players.phase(player) == "protected" then
		return false
	end

	return true
end

---Is this player inside the feature's FOV circle, range and line of sight? Returns the part to aim at.
local function inReach(player, prefix, mouseLocation)
	local part = legitPart(player.Character, prefix)

	if not part or Util.inVoid(part.Position) or (part.Position - camera.CFrame.Position).Magnitude > flag(prefix .. "_distance", 500) then
		return nil
	end

	local screen, onScreen = camera:WorldToViewportPoint(part.Position)

	if not onScreen or (Vector2.new(screen.X, screen.Y) - mouseLocation).Magnitude > flag(prefix .. "_fov", 120) then
		return nil
	end

	if not visibleFrom(camera.CFrame.Position, part, player.Character, prefix) then
		return nil
	end

	return part, (Vector2.new(screen.X, screen.Y) - mouseLocation).Magnitude
end

---The usable player closest to the mouse inside the feature's FOV.
---@param prefix string "aimassist" or "silent"
function Legit.best(prefix)
	local mouseLocation = userInputService:GetMouseLocation()
	local best, bestPart, bestScore = nil, nil, math.huge

	for _, player in playersService:GetPlayers() do
		if legitUsable(player) then
			local part, distance = inReach(player, prefix, mouseLocation)

			if part and distance < bestScore then
				best, bestPart, bestScore = player, part, distance
			end
		end
	end

	return best, bestPart
end

---Keeps the current player for `Target swap cooldown` seconds before a better one is taken (the aim does not jump between players).
local function stickyBest(prefix, now)
	local current = Legit.target

	if current and current.Parent == playersService and legitUsable(current) and now - Legit.targetSince < flag("legit_swap_cooldown", 0) then
		local part = inReach(current, prefix, userInputService:GetMouseLocation())

		if part then
			return current, part
		end
	end

	local player, part = Legit.best(prefix)

	if player ~= Legit.target then
		Legit.target, Legit.targetSince = player, now
	end

	return player, part
end

---@module AimAssist
local AimAssist = {}

function AimAssist.step()
	local bind = flag("aimassist_key")

	if not flag("aimassist_enabled", false) or type(bind) ~= "table" or not bind.active or userInputService:GetFocusedTextBox() then
		return
	end

	local _, part = stickyBest("aimassist", os.clock())

	if not part then
		return
	end

	local horizontal = math.max(flag("aimassist_h_smooth", 6), 1)
	local vertical = math.max(flag("aimassist_v_smooth", 6), 1)

	if flag("aimassist_method", "camera") == "mouse" then
		local screen = camera:WorldToViewportPoint(part.Position)
		local delta = Vector2.new(screen.X, screen.Y) - userInputService:GetMouseLocation()

		mousemoverel(delta.X / horizontal, delta.Y / vertical)

		return
	end

	local cframe = camera.CFrame
	local wanted = (part.Position - cframe.Position).Unit
	local currentYaw = math.atan2(-cframe.LookVector.X, -cframe.LookVector.Z)
	local currentPitch = math.asin(cframe.LookVector.Y)
	local wantedYaw = math.atan2(-wanted.X, -wanted.Z)
	local wantedPitch = math.asin(wanted.Y)
	local yawDelta = (wantedYaw - currentYaw + math.pi) % (math.pi * 2) - math.pi
	local pitch = math.clamp(currentPitch + (wantedPitch - currentPitch) / vertical, -1.45, 1.45)

	camera.CFrame = CFrame.new(cframe.Position) * CFrame.fromOrientation(pitch, currentYaw + yawDelta / horizontal, 0)
end

---@module SilentAim
---While the left mouse button is held, the game's gun script is answered with a position on the best player inside the silent FOV, as long as that
---position is within Max Curve degrees of where the mouse is pointing. Redirect Chance is rolled once per press. The ragebot's own shots are left alone.
local SilentAim = {}

function SilentAim.step(now)
	if not flag("silent_enabled", false) then
		return
	end

	local down = userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and userInputService:GetFocusedTextBox() == nil

	if down and not Legit.silentWasDown then
		Legit.silentRoll = math.random() * 100 < flag("silent_chance", 100)
	end

	Legit.silentWasDown = down

	if not down or not Legit.silentRoll or (Aim.position and now < Aim.expires) then
		return
	end

	local _, part = Legit.best("silent")

	if not part then
		return
	end

	local mouseLocation = userInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local toward = (part.Position - ray.Origin)
	local angle = math.deg(math.acos(math.clamp(ray.Direction:Dot(toward.Unit), -1, 1)))

	if angle > flag("silent_curve", 30) then
		return
	end

	local position = part.Position

	if flag("silent_flat", false) then
		-- Dont Curve Vertically: the height stays where the mouse is pointing, only the sideways part is moved
		local along = toward.Magnitude
		local ahead = ray.Origin + ray.Direction * along

		position = Vector3.new(position.X, ahead.Y, position.Z)
	end

	Aim.set(position, part, now, 0.1)
end

---@module Triggerbot
---Clicks (activates the gun in hand) when the mouse is over a usable player's chosen hitbox: it must stay over the same part for Hover Time, clicks are
---Cooldown apart and wait Delay (and are dropped if the mouse left by then), and the check itself runs every Refresh Rate seconds.
local Triggerbot = { checkedAt = 0, lastPart = nil, hoverSince = 0, lastClick = 0, pending = false }

local TORSO_PARTS = { UpperTorso = true, LowerTorso = true, HumanoidRootPart = true, Torso = true }
local ARM_PARTS = { LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true, LeftHand = true, RightHand = true, ["Left Arm"] = true, ["Right Arm"] = true }
local LEG_PARTS = { LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true, LeftFoot = true, RightFoot = true, ["Left Leg"] = true, ["Right Leg"] = true }

local function hitboxWanted(partName)
	if partName == "Head" then
		return picked("trigger_hitboxes", "head", { "head", "body" })
	elseif TORSO_PARTS[partName] then
		return picked("trigger_hitboxes", "body", { "head", "body" })
	elseif ARM_PARTS[partName] then
		return picked("trigger_hitboxes", "arms", { "head", "body" })
	elseif LEG_PARTS[partName] then
		return picked("trigger_hitboxes", "legs", { "head", "body" })
	end

	return false
end

function Triggerbot.step(now)
	if not flag("trigger_enabled", false) then
		Triggerbot.lastPart = nil

		return
	end

	if now - Triggerbot.checkedAt < flag("trigger_refresh", 0) then
		return
	end

	Triggerbot.checkedAt = now

	local character = localPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local info = tool and gunInfo(tool)

	if not info or info.ammo <= 0 or userInputService:GetFocusedTextBox() then
		Triggerbot.lastPart = nil

		return
	end

	local mouseLocation = userInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local maxDistance = flag("trigger_distance", 0)

	maxDistance = maxDistance == 0 and info.range or maxDistance

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * maxDistance, params)
	local part = result and result.Instance
	local model = part and part:FindFirstAncestorOfClass("Model")
	local player = model and playersService:GetPlayerFromCharacter(model)

	if not (part and player and legitUsable(player) and hitboxWanted(part.Name)) then
		Triggerbot.lastPart = nil

		return
	end

	if Triggerbot.lastPart ~= part then
		Triggerbot.hoverSince = now
	end

	Triggerbot.lastPart = part

	if Triggerbot.pending or now - Triggerbot.lastClick < flag("trigger_cooldown", 0) or now - Triggerbot.hoverSince < flag("trigger_hover", 0) then
		return
	end

	Triggerbot.pending = true

	task.delay(flag("trigger_delay", 0), function()
		Triggerbot.pending = false

		-- the mouse left the target while the click waited
		if Triggerbot.lastPart ~= part or not flag("trigger_enabled", false) then
			return
		end

		local current = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Tool")

		if current then
			Triggerbot.lastClick = os.clock()
			current:Activate()
		end
	end)
end

---@module Movement
---Your own character's movement: extra speed, flight, noclip, jump power, anti sit. It changes the character on your client; where the server does not
---agree, the server wins. Runs before the Body step, so the position Body saves as "real" already includes the movement.
local Movement = { flying = false, jumpDefault = nil, noclipParts = {}, jumpValue = nil, humanoid = nil, hooked = false, active = true, pushScale = 1, pushUntil = 0, pushPart = nil :: Instance?, pushPosition = nil :: Vector3?, pushVelocity = Vector3.zero, pushSettled = 0, tripHumanoid = nil :: Instance? }

---Da Hood's own script writes JumpPower back every frame (measured: 50, 120 and 50 again within one frame), so a plain write never lasts. While Jump Power is on,
---the writes the game makes to your humanoid's JumpPower are given the chosen value instead; nothing else is touched.
function Movement.installHook()
	Hooks.set("__newindex", function(original, self, key, value)
		if Movement.active and self == Movement.humanoid and not checkcaller() then
			if key == "JumpPower" then
				if Movement.jumpValue then
					return original(self, key, Movement.jumpValue)
				end

				-- the game sets JumpPower to 0 for its jump cooldown
				if flag("move_no_jump_cooldown", false) and value == 0 then
					return
				end
			elseif key == "WalkSpeed" then
				if flag("move_lock_walk", false) then
					return
				end

				if flag("move_no_slow", false) and type(value) == "number" and value < 16 then
					return original(self, key, 16)
				end
			end
		end

		return original(self, key, value)
	end)
end

local function movementParts()
	local character = localPlayer.Character

	return character, character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

function Movement.step(dt)
	local character, humanoid, root = movementParts()

	if not (character and humanoid and root) or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()

	-- Pushback guard: when one frame carries the body backwards, against the way it was going, by more than 24 studs and more than 8 frames of that
	-- travel, speed and flight drop to a quarter for 10 seconds. It stands aside while Vanta itself moves the body and for a moment after a respawn.
	if Movement.pushScale < 1 and now >= Movement.pushUntil then
		Movement.pushScale = 1
	end

	if flag("move_pushback", true) and (flag("move_speed", false) or flag("move_flight", false)) then
		if Body.spot or Shop.busy() or root ~= Movement.pushPart then
			Movement.pushPart, Movement.pushPosition, Movement.pushSettled = root, nil, now + 1.5
		else
			local position, lastPosition, lastVelocity = root.Position, Movement.pushPosition, Movement.pushVelocity

			Movement.pushPosition, Movement.pushVelocity = position, root.AssemblyLinearVelocity

			if lastPosition and now >= Movement.pushSettled and lastVelocity.Magnitude >= 1 then
				local back = -(position - lastPosition):Dot(lastVelocity.Unit)

				if back > math.max(24, lastVelocity.Magnitude * math.max(dt, 1 / 60) * 8) then
					Movement.pushScale = math.max(Movement.pushScale * 0.25, 1 / 64)
					Movement.pushUntil = now + 10

					if notifications then
						notifications:create_notification({ name = string.format("pushed back %d studs: speed slowed to %d%% for 10s", back, Movement.pushScale * 100) })
					end
				end
			end
		end
	end

	local flightOn = flag("move_flight", false) and not Players.knocked(localPlayer)

	if flightOn and userInputService:GetFocusedTextBox() == nil then
		local look = camera.CFrame
		local direction = Vector3.zero

		if userInputService:IsKeyDown(Enum.KeyCode.W) then direction += look.LookVector end
		if userInputService:IsKeyDown(Enum.KeyCode.S) then direction -= look.LookVector end
		if userInputService:IsKeyDown(Enum.KeyCode.D) then direction += look.RightVector end
		if userInputService:IsKeyDown(Enum.KeyCode.A) then direction -= look.RightVector end
		if userInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
		if userInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.yAxis end

		root.AssemblyLinearVelocity = direction.Magnitude > 0 and direction.Unit * flag("move_flight_speed", 60) * Movement.pushScale or Vector3.zero
		Movement.flying = true
	elseif Movement.flying then
		Movement.flying = false
		root.AssemblyLinearVelocity = Vector3.zero
	end

	-- extra speed: the character is moved along its walking direction on top of the normal walk
	if flag("move_speed", false) and not flightOn and humanoid.MoveDirection.Magnitude > 0 then
		root.CFrame += humanoid.MoveDirection * flag("move_speed_value", 20) * Movement.pushScale * dt
	end

	Movement.humanoid = humanoid

	if flag("move_jump", false) then
		Movement.jumpDefault = Movement.jumpDefault or { humanoid.UseJumpPower, humanoid.JumpPower }
		Movement.jumpValue = flag("move_jump_power", 70)
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Movement.jumpValue
	elseif Movement.jumpDefault then
		Movement.jumpValue = nil
		humanoid.UseJumpPower, humanoid.JumpPower = Movement.jumpDefault[1], Movement.jumpDefault[2]
		Movement.jumpDefault = nil
	end

	if flag("move_antisit", false) then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

		if humanoid.Sit then
			humanoid.Sit = false
		end
	end

	-- anti trip: the character cannot fall over
	if flag("move_antitrip", false) then
		if Movement.tripHumanoid ~= humanoid then
			Movement.tripHumanoid = humanoid
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		end
	elseif Movement.tripHumanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		Movement.tripHumanoid = nil
	end

	-- face target: the character looks at the target (the spinbot, when on, turns it instead)
	if flag("face_target", false) and not flag("move_spin", false) and Target.player and Follow.aim and not Util.inVoid(Follow.aim) then
		local flat = Vector3.new(Follow.aim.X, root.Position.Y, Follow.aim.Z)

		humanoid.AutoRotate = false
		Movement.facing = true

		if (flat - root.Position).Magnitude > 0.5 then
			root.CFrame = CFrame.lookAt(root.Position, flat)
		end
	elseif Movement.facing then
		Movement.facing = false
		humanoid.AutoRotate = true
	end

	-- spinbot: the character turns on the spot
	if flag("move_spin", false) then
		humanoid.AutoRotate = false
		root.CFrame *= CFrame.Angles(0, flag("move_spin_speed", 50) / 3 * math.min(dt, 1 / 30), 0)
		Movement.spinning = true
	elseif Movement.spinning then
		Movement.spinning = false
		humanoid.AutoRotate = true
	end
end

---Noclip is applied on the physics step, before the character collides.
function Movement.stepped()
	if not flag("move_noclip", false) then
		return
	end

	local character = localPlayer.Character

	if not character then
		return
	end

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
			Movement.noclipParts[part] = true
		end
	end
end

function Movement.restore()
	Movement.jumpValue = nil
	Movement.pushScale = 1

	local _, current = movementParts()

	if current then
		if Movement.tripHumanoid then
			current:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		end

		if Movement.spinning or Movement.facing then
			current.AutoRotate = true
		end
	end

	Movement.tripHumanoid, Movement.spinning, Movement.facing = nil, false, false
	Movement.active = false

	for part in Movement.noclipParts do
		if part.Parent then
			part.CanCollide = true
		end
	end

	Movement.noclipParts = {}

	local _, humanoid, root = movementParts()

	if humanoid and Movement.jumpDefault then
		humanoid.UseJumpPower, humanoid.JumpPower = Movement.jumpDefault[1], Movement.jumpDefault[2]
	end

	if root and Movement.flying then
		root.AssemblyLinearVelocity = Vector3.zero
	end

	Movement.jumpDefault, Movement.flying = nil, false
end

---@module Utility
---Anti AFK (answers the idle kick the way a player moving would), rejoin (back into this same server), the watermark switch.
local Utility = {}

function Utility.antiAfk()
	local ok, service = pcall(game.GetService, game, "VirtualUser")

	if not ok then
		return
	end

	service:CaptureController()
	service:ClickButton2(Vector2.new())
end

function Utility.rejoin()
	local teleport = game:GetService("TeleportService")

	if #playersService:GetPlayers() <= 1 then
		teleport:Teleport(game.PlaceId, localPlayer)
	else
		teleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
	end
end

---@module Feedback
---What you see and hear when you shoot. The game's own shot call is watched (read only, passed straight on) to learn where each shot was sent from and to; a drop
---in another player's health shortly after, close to where the shot was sent, counts as the hit. Every effect is a short-lived object with a life time,
---updated by one RenderStepped step and removed when it expires, when its toggle goes off, and on unload.
local Feedback = {
	shots = {},
	effects = {},
	health = {},
	sounds = {},
	hooked = false,
	active = true,
	overlay = nil,
	lastShotAt = 0,
}

local SOUND_NAMES = { "neverlose", "primordial", "sparkle", "mc bow", "break", "skeet", "rust", "agpa1", "agpa2", "Beep1", "bubble", "copperbell", "cowbell", "huhh", "quake" }
local SOUND_URL = "https://raw.githubusercontent.com/haltorillshoot/Visions-hook/main/assets/neverlose%20recode/assets/"

local function guiParent()
	local ok, hidden = pcall(function()
		return gethui()
	end)

	return ok and hidden or game:GetService("CoreGui")
end

---Adds a timed effect. `step(age, life)` returns false when it is done early; `destroy()` frees what it made.
local function addEffect(life, step, destroy)
	Feedback.effects[#Feedback.effects + 1] = { born = os.clock(), life = life, step = step, destroy = destroy }
end

local function newLine()
	local line = Drawing.new("Line")

	line.Visible = true

	return line
end

local function colourFor(name, lethalName, lethal)
	local colour = pickerColor(lethal and lethalName or name, lethal and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 255, 255))

	return colour
end

---Frees every effect (unload, or a toggle going off clears only its own kind through `kind`).
function Feedback.clear()
	for _, effect in Feedback.effects do
		effect.destroy()
	end

	table.clear(Feedback.effects)

	if Feedback.overlay then
		Feedback.overlay.Parent:Destroy()
		Feedback.overlay = nil
	end
end

function Feedback.render()
	local now = os.clock()
	local index = 1

	while index <= #Feedback.effects do
		local effect = Feedback.effects[index]
		local age = now - effect.born

		if age >= effect.life or effect.step(age, effect.life) == false then
			effect.destroy()
			table.remove(Feedback.effects, index)
		else
			index += 1
		end
	end
end

-- Individual effects ------------------------------------------------------------------------------------------------------------------------

local function marker2d(lethal)
	local colour = colourFor("fb_marker2d_color", "fb_marker2d_lethal", lethal)
	local thickness = flag("fb_marker2d_thickness", 2)
	local lines = { newLine(), newLine(), newLine(), newLine() }
	local signs = { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) }

	addEffect(flag("fb_marker2d_life", 0.4), function(age, life)
		local centre = camera.ViewportSize / 2
		local spread = 3 + age / life * 4

		for index, line in lines do
			line.From = centre + signs[index] * spread
			line.To = centre + signs[index] * (spread + 6)
			line.Thickness = thickness
			line.Color = colour
			line.Transparency = 1 - age / life
		end
	end, function()
		for _, line in lines do
			line:Remove()
		end
	end)
end

local function marker3d(position, lethal)
	local colour = colourFor("fb_marker3d_color", "fb_marker3d_lethal", lethal)
	local thickness = flag("fb_marker3d_thickness", 2)
	local lines = { newLine(), newLine(), newLine(), newLine() }
	local signs = { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) }

	addEffect(flag("fb_marker3d_life", 0.6), function(age, life)
		local point, onScreen = camera:WorldToViewportPoint(position)
		local centre = Vector2.new(point.X, point.Y)
		local visible = onScreen and point.Z > 0

		for index, line in lines do
			line.Visible = visible
			line.From = centre + signs[index] * 3
			line.To = centre + signs[index] * 10
			line.Thickness = thickness
			line.Color = colour
			line.Transparency = 1 - age / life
		end
	end, function()
		for _, line in lines do
			line:Remove()
		end
	end)
end

local function damageNumber(position, damage, lethal)
	local text = Drawing.new("Text")

	text.Visible = true
	text.Text = tostring(math.floor(damage + 0.5))
	text.Size = flag("fb_damage_size", 18)
	text.Center = true
	text.Outline = true
	text.Font = Drawing.Fonts and Drawing.Fonts.UI or 0
	text.Color = colourFor("fb_damage_color", "fb_damage_lethal", lethal)

	addEffect(flag("fb_damage_life", 1), function(age, life)
		local point, onScreen = camera:WorldToViewportPoint(position + Vector3.new(0, 1.5 + age * 3, 0))

		text.Visible = onScreen and point.Z > 0
		text.Position = Vector2.new(point.X, point.Y)
		text.Transparency = 1 - age / life
	end, function()
		text:Remove()
	end)
end

local function hitOverlay(lethal)
	if not Feedback.overlay then
		local gui = Instance.new("ScreenGui")

		gui.Name = ""
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10
		gui.Parent = guiParent()

		local frame = Instance.new("Frame")

		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Parent = gui
		Feedback.overlay = frame
	end

	local frame = Feedback.overlay
	local colour = colourFor("fb_overlay_color", "fb_overlay_lethal", lethal)

	frame.BackgroundColor3 = colour

	addEffect(flag("fb_overlay_life", 0.35), function(age, life)
		frame.BackgroundTransparency = 0.65 + 0.35 * (age / life)
	end, function()
		frame.BackgroundTransparency = 1
	end)
end

local function hitChams(character, lethal)
	if not character then
		return
	end

	if flag("fb_chams_last_only", true) then
		for _, effect in Feedback.effects do
			if effect.kind == "chams" then
				effect.born = -math.huge
			end
		end
	end

	local highlight = Instance.new("Highlight")

	highlight.Adornee = character
	highlight.FillColor = colourFor("fb_chams_color", "fb_chams_lethal", lethal)
	highlight.OutlineColor = highlight.FillColor
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = guiParent()

	addEffect(flag("fb_chams_life", 0.5), function(age, life)
		highlight.FillTransparency = 0.3 + 0.7 * (age / life)
		highlight.OutlineTransparency = age / life
	end, function()
		highlight:Destroy()
	end)

	Feedback.effects[#Feedback.effects].kind = "chams"
end

local function hitParticles(position, lethal)
	local anchor = Instance.new("Part")

	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")

	emitter.Enabled = false
	emitter.Color = ColorSequence.new(colourFor("fb_particle_color", "fb_particle_lethal", lethal))
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.4, 0)
	emitter.LightEmission = 1
	emitter.Parent = anchor
	emitter:Emit(flag("fb_particle_count", 20))

	addEffect(1.2, function() end, function()
		anchor:Destroy()
	end)
end

local function hitSkeleton(character)
	if not character then
		return
	end

	local colour = pickerColor("fb_skeleton_color", Color3.fromRGB(255, 255, 255))
	local thickness = flag("fb_skeleton_thickness", 1)
	local joints = {}

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			joints[#joints + 1] = { descendant.Part0, descendant.Part1, newLine() }
		end
	end

	addEffect(flag("fb_skeleton_life", 0.6), function(age, life)
		for _, joint in joints do
			local from, fromOn = camera:WorldToViewportPoint(joint[1].Position)
			local to, toOn = camera:WorldToViewportPoint(joint[2].Position)
			local line = joint[3]

			line.Visible = fromOn and toOn and from.Z > 0 and to.Z > 0
			line.From, line.To = Vector2.new(from.X, from.Y), Vector2.new(to.X, to.Y)
			line.Thickness = thickness
			line.Color = colour
			line.Transparency = 1 - age / life
		end
	end, function()
		for _, joint in joints do
			joint[3]:Remove()
		end
	end)
end

local function bulletTracer(origin, hit)
	local colour = pickerColor("fb_tracer_color", Color3.fromRGB(255, 255, 255))
	local line = newLine()

	addEffect(flag("fb_tracer_life", 0.5), function(age, life)
		local from, fromOn = camera:WorldToViewportPoint(origin)
		local to, toOn = camera:WorldToViewportPoint(hit)

		line.Visible = (fromOn or toOn) and (from.Z > 0 or to.Z > 0)
		line.From, line.To = Vector2.new(from.X, from.Y), Vector2.new(to.X, to.Y)
		line.Thickness = flag("fb_tracer_thickness", 1)
		line.Color = colour
		line.Transparency = 1 - age / life
	end, function()
		line:Remove()
	end)
end

local function bulletImpact(hit)
	local ball = Instance.new("Part")

	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = pickerColor("fb_impact_color", Color3.fromRGB(255, 200, 80))
	ball.Size = Vector3.one * 0.8
	ball.Position = hit
	ball.Parent = workspace

	addEffect(flag("fb_impact_life", 0.8), function(age, life)
		ball.Transparency = age / life
	end, function()
		ball:Destroy()
	end)
end

-- Hit sound ----------------------------------------------------------------------------------------------------------------------------------

---Downloads the chosen sound from the repository once (kept in the workspace folder `Vanta/sounds`) and returns an asset id for it.
---@param name string
function Feedback.soundId(name)
	if Feedback.sounds[name] then
		return Feedback.sounds[name]
	end

	local ok, id = pcall(function()
		if not isfolder("Vanta") then
			makefolder("Vanta")
		end

		if not isfolder("Vanta/sounds") then
			makefolder("Vanta/sounds")
		end

		local path = "Vanta/sounds/" .. name .. ".ogg"

		if not isfile(path) then
			writefile(path, game:HttpGet(SOUND_URL .. name:gsub(" ", "%%20") .. ".ogg"))
		end

		return getcustomasset(path)
	end)

	if ok and id then
		Feedback.sounds[name] = id

		return id
	end

	return nil
end

local function hitSound()
	local id = Feedback.soundId(flag("fb_sound_name", "neverlose"))

	if not id then
		return
	end

	local sound = Instance.new("Sound")

	sound.SoundId = id
	sound.Volume = flag("fb_sound_volume", 1)
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 5)
end

-- Events -------------------------------------------------------------------------------------------------------------------------------------

---A confirmed hit: runs every effect that is on.
---@param position Vector3 where the shot was sent to
---@param character Model? the player hit
---@param damage number
---@param lethal boolean
function Feedback.hit(position, character, damage, lethal)
	if flag("fb_marker2d", false) then marker2d(lethal) end
	if flag("fb_marker3d", false) then marker3d(position, lethal) end
	if flag("fb_damage", false) then damageNumber(position, damage, lethal) end
	if flag("fb_overlay", false) then hitOverlay(lethal) end
	if flag("fb_chams", false) then hitChams(character, lethal) end
	if flag("fb_particle", false) then hitParticles(position, lethal) end
	if flag("fb_skeleton", false) then hitSkeleton(character) end
	if flag("fb_sound", false) then hitSound() end

	if flag("fb_notify_hits", false) and notifications then
		notifications:create_notification({ name = string.format("hit %s for %d", character and character.Name or "?", damage) })
	end
end

---A shot sent to the server. Pellets of one shotgun shot arrive together and count as one.
function Feedback.shot(tool, origin, hit)
	local now = os.clock()
	local last = Feedback.shots[#Feedback.shots]

	if last and last.tool == tool and now - last.at < 0.05 then
		return
	end

	local entry = { at = now, tool = tool, origin = origin, hit = hit, confirmed = false }

	Feedback.shots[#Feedback.shots + 1] = entry

	if #Feedback.shots > 8 then
		table.remove(Feedback.shots, 1)
	end

	if flag("fb_tracer", false) then bulletTracer(origin, hit) end
	if flag("fb_impact", false) then bulletImpact(hit) end

	if flag("fb_notify_miss", false) and notifications then
		task.delay(0.4 + Util.ping(), function()
			if not entry.confirmed then
				notifications:create_notification({ name = "shot: no hit" })
			end
		end)
	end
end

---Which recent shot does a health drop at `position` belong to?
local function matchShot(position)
	local now = os.clock()

	for index = #Feedback.shots, 1, -1 do
		local entry = Feedback.shots[index]

		if now - entry.at > 0.6 + Util.ping() then
			break
		end

		if not entry.confirmed and (entry.hit - position).Magnitude < 30 then
			return entry
		end
	end

	return nil
end

local function watchPlayer(player, maid)
	local function watchCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 5)

		if not humanoid then
			return
		end

		Feedback.health[humanoid] = humanoid.Health

		maid:give(humanoid.HealthChanged:Connect(function(health)
			local before = Feedback.health[humanoid] or health

			Feedback.health[humanoid] = health

			if before - health < 0.5 then
				return
			end

			local root = character:FindFirstChild("HumanoidRootPart")
			local entry = root and matchShot(root.Position)

			if entry then
				entry.confirmed = true
				Feedback.hit(entry.hit, character, before - health, health <= 5 or Players.knocked(player))
			end
		end))
	end

	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	maid:give(player.CharacterAdded:Connect(watchCharacter))
end

---Starts watching: other players' health, and the game's shot call.
---@param maid table
function Feedback.start(maid)
	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer then
			watchPlayer(player, maid)
		end
	end

	maid:give(playersService.PlayerAdded:Connect(function(player)
		watchPlayer(player, maid)
	end))

	Hooks.set("__namecall", function(original, self, ...)
		if Feedback.active and getnamecallmethod() == "FireServer" and not checkcaller() then
			local kind, handle, origin, hit = ...

			if kind == "ShootGun" and typeof(origin) == "Vector3" and typeof(hit) == "Vector3" then
				pcall(Feedback.shot, typeof(handle) == "Instance" and handle.Parent or nil, origin, hit)
			end
		end

		return original(self, ...)
	end)

	maid:give(function()
		Feedback.active = false
		Feedback.clear()
	end)
end

---@module World
---Local world settings: time, ambient, atmosphere, colour correction, weather, skybox, lighting technology, blur, chat, game crosshair, 3D rendering.
---Nothing here is sent to the server. Each setting keeps what it replaced and puts it back when its toggle goes off or the script unloads. The game
---changes some of these values on its own, so the ones that are on are written again every frame.
local World = { saved = {}, made = {}, weather = nil :: Part?, lastTech = nil :: string?, chatHidden = nil :: boolean?, cursorHidden = nil :: boolean?, renderOff = nil :: boolean?, active = true }

local lighting = game:GetService("Lighting")
local starterGui = game:GetService("StarterGui")

local SKIES = {
	["stormy"] = { Up = "http://www.roblox.com/asset/?id=18703232671", Bk = "http://www.roblox.com/asset/?id=18703245834", Lf = "http://www.roblox.com/asset/?id=18703237556", Dn = "http://www.roblox.com/asset/?id=18703243349", Ft = "http://www.roblox.com/asset/?id=18703240532", Rt = "http://www.roblox.com/asset/?id=18703235430" },
	["blue space"] = { Lf = "rbxassetid://15536114370", Up = "rbxassetid://15536117282", Rt = "rbxassetid://15536118762", Ft = "rbxassetid://15536116141", Dn = "rbxassetid://15536112543", Bk = "rbxassetid://15536110634" },
	["pink"] = { Up = "rbxassetid://12216108877", Lf = "rbxassetid://12216110170", Rt = "rbxassetid://12216110471", Ft = "rbxassetid://12216109489", Bk = "rbxassetid://12216109205", Dn = "rbxassetid://12216109875" },
	["black storm"] = { Lf = "rbxassetid://15502507918", Up = "rbxassetid://15502511911", Rt = "rbxassetid://15502509398", Ft = "rbxassetid://15502510289", Dn = "rbxassetid://15502508460", Bk = "rbxassetid://15502511288" },
	["realistic"] = { Up = "rbxassetid://653719321", Dn = "rbxassetid://653718790", Lf = "rbxassetid://653719190", Ft = "rbxassetid://653719067", Rt = "rbxassetid://653718931", Bk = "rbxassetid://653719502" },
}

local SKY_NAMES = { "stormy", "blue space", "pink", "black storm", "realistic" }

---Remember the first value of a property so it can be put back.
local function remember(object, property)
	World.saved[object] = World.saved[object] or {}

	if World.saved[object][property] == nil then
		World.saved[object][property] = object[property]
	end
end

---Writes a property, remembering what it was.
local function setProperty(object, property, value)
	remember(object, property)

	if object[property] ~= value then
		object[property] = value
	end
end

---An effect or sky made by Vanta, created only while the feature is on.
local function made(key, make)
	local object = World.made[key]

	if not object or not object.Parent then
		object = make()
		World.made[key] = object
	end

	return object
end

local function dropMade(key)
	if World.made[key] then
		World.made[key]:Destroy()
		World.made[key] = nil
	end
end

local function colourOf(name, fallback)
	local picked = pickerColor(name, fallback)

	return picked
end

function World.step()
	-- time of day
	if flag("world_time", false) then
		setProperty(lighting, "ClockTime", flag("world_time_value", 12))
	end

	-- ambient
	if flag("world_ambient", false) then
		setProperty(lighting, "Ambient", colourOf("world_ambient_color", Color3.fromRGB(120, 120, 140)))
		setProperty(lighting, "OutdoorAmbient", colourOf("world_outdoor_color", Color3.fromRGB(140, 140, 160)))
	end

	-- lighting technology (the property is not scriptable, so it is written through the reflection library)
	if flag("world_technology", false) then
		local wanted = flag("world_technology_value", "future")
		local technology = wanted == "shadowmap" and Enum.Technology.ShadowMap or wanted == "voxel" and Enum.Technology.Voxel or Enum.Technology.Future

		if World.lastTech ~= wanted or lighting.Technology ~= technology then
			World.lastTech = wanted

			if World.saved[lighting] == nil or World.saved[lighting].Technology == nil then
				World.saved[lighting] = World.saved[lighting] or {}
				World.saved[lighting].Technology = lighting.Technology
			end

			pcall(sethiddenproperty, lighting, "Technology", technology)
		end
	end

	-- atmosphere: the game's own is changed when there is one
	if flag("world_atmosphere", false) then
		local atmosphere = lighting:FindFirstChildOfClass("Atmosphere") or made("atmosphere", function()
			local created = Instance.new("Atmosphere")

			created.Parent = lighting

			return created
		end)

		setProperty(atmosphere, "Color", colourOf("world_atmosphere_color", Color3.fromRGB(199, 199, 199)))
		setProperty(atmosphere, "Decay", colourOf("world_atmosphere_decay", Color3.fromRGB(106, 112, 125)))
		setProperty(atmosphere, "Haze", flag("world_atmosphere_haze", 1))
		setProperty(atmosphere, "Glare", flag("world_atmosphere_glare", 0))
		setProperty(atmosphere, "Offset", flag("world_atmosphere_offset", 0))
		setProperty(atmosphere, "Density", flag("world_atmosphere_density", 0.3))
	end

	-- saturation, contrast and tint through one colour correction effect
	if flag("world_colour", false) then
		local correction = made("colour", function()
			local effect = Instance.new("ColorCorrectionEffect")

			effect.Parent = lighting

			return effect
		end)

		correction.Saturation = flag("world_saturation", 0)
		correction.Contrast = flag("world_contrast", 0)
		correction.TintColor = colourOf("world_tint", Color3.new(1, 1, 1))
	else
		dropMade("colour")
	end

	-- blur
	if flag("world_blur", false) then
		made("blur", function()
			local effect = Instance.new("BlurEffect")

			effect.Parent = lighting

			return effect
		end).Size = flag("world_blur_size", 6)
	else
		dropMade("blur")
	end

	-- skybox
	local skyName = flag("world_sky_name", "stormy")

	if flag("world_sky", false) and SKIES[skyName] then
		local sky = lighting:FindFirstChildOfClass("Sky") or made("sky", function()
			local created = Instance.new("Sky")

			created.Parent = lighting

			return created
		end)

		for face, id in SKIES[skyName] do
			setProperty(sky, "Skybox" .. face, id)
		end
	end

	-- weather: a patch of particles that follows the camera
	if flag("world_weather", false) then
		local kind = flag("world_weather_type", "rain")
		local patch = World.weather

		if not patch or not patch.Parent or patch:GetAttribute("kind") ~= kind then
			if patch then
				patch:Destroy()
			end

			patch = Instance.new("Part")
			patch.Anchored = true
			patch.CanCollide = false
			patch.CanQuery = false
			patch.CanTouch = false
			patch.Transparency = 1
			patch.Size = Vector3.new(80, 1, 80)
			patch:SetAttribute("kind", kind)

			local emitter = Instance.new("ParticleEmitter")

			emitter.EmissionDirection = Enum.NormalId.Bottom
			emitter.Lifetime = NumberRange.new(2, 3)
			emitter.Speed = NumberRange.new(kind == "rain" and 70 or 12)
			emitter.SpreadAngle = Vector2.new(kind == "rain" and 2 or 25, 0)
			emitter.Size = NumberSequence.new(kind == "rain" and 0.12 or 0.25)
			emitter.Transparency = NumberSequence.new(0.2)
			emitter.Parent = patch
			patch.Parent = camera
			World.weather = patch
		end

		local emitter = patch:FindFirstChildOfClass("ParticleEmitter")

		emitter.Rate = flag("world_weather_rate", 300)
		emitter.Color = ColorSequence.new(colourOf("world_weather_color", kind == "rain" and Color3.fromRGB(170, 190, 255) or Color3.new(1, 1, 1)))
		patch.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
	elseif World.weather then
		World.weather:Destroy()
		World.weather = nil
	end

	-- chat window, game crosshair, 3D rendering
	if flag("world_hide_chat", false) ~= World.chatHidden then
		World.chatHidden = flag("world_hide_chat", false)
		pcall(starterGui.SetCoreGuiEnabled, starterGui, Enum.CoreGuiType.Chat, not World.chatHidden)
	end

	if flag("world_hide_cursor", false) ~= World.cursorHidden then
		World.cursorHidden = flag("world_hide_cursor", false)
		userInputService.MouseIconEnabled = not World.cursorHidden
	end

	if flag("world_no_render", false) ~= World.renderOff then
		World.renderOff = flag("world_no_render", false)
		pcall(runService.Set3dRenderingEnabled, runService, not World.renderOff)
	end

	-- switched-off settings go back to what the game had
	if not flag("world_time", false) then
		World.putBack(lighting, "ClockTime")
	end

	if not flag("world_ambient", false) then
		World.putBack(lighting, "Ambient")
		World.putBack(lighting, "OutdoorAmbient")
	end
end

---Puts one property back to what it was before Vanta changed it.
function World.putBack(object, property)
	local saved = World.saved[object]

	if saved and saved[property] ~= nil then
		object[property] = saved[property]
		saved[property] = nil
	end
end

---Everything off: properties restored, made objects removed.
function World.restore()
	for object, properties in World.saved do
		if object.Parent then
			for property, value in properties do
				if property == "Technology" then
					pcall(sethiddenproperty, object, "Technology", value)
				else
					pcall(function()
						object[property] = value
					end)
				end
			end
		end
	end

	World.saved = {}

	for key in World.made do
		dropMade(key)
	end

	if World.weather then
		World.weather:Destroy()
		World.weather = nil
	end

	if World.chatHidden then
		pcall(starterGui.SetCoreGuiEnabled, starterGui, Enum.CoreGuiType.Chat, true)
	end

	if World.cursorHidden then
		userInputService.MouseIconEnabled = true
	end

	if World.renderOff then
		pcall(runService.Set3dRenderingEnabled, runService, true)
	end

	World.chatHidden, World.cursorHidden, World.renderOff, World.lastTech = nil, nil, nil, nil
end

---@module Crosshair
---A Drawing crosshair at the centre of the screen (or on the target), with an optional state panel under it.
local Crosshair = { objects = {}, angle = 0 }

local function crosshairLine(index)
	local line = Crosshair.objects[index]

	if not line then
		line = Drawing.new("Line")
		Crosshair.objects[index] = line
	end

	return line
end

function Crosshair.clear()
	for _, object in Crosshair.objects do
		object:Remove()
	end

	Crosshair.objects = {}
end

function Crosshair.render(dt)
	local panel = flag("crosshair_panel", false)

	if not flag("crosshair_enabled", false) and not panel then
		if next(Crosshair.objects) then
			Crosshair.clear()
		end

		return
	end

	local centre = camera.ViewportSize / 2

	if flag("crosshair_follow", false) and Follow.aim and not Util.inVoid(Follow.aim) then
		local point, onScreen = camera:WorldToViewportPoint(Follow.aim)

		if onScreen and point.Z > 0 then
			centre = Vector2.new(point.X, point.Y)
		end
	end

	local hasTarget = Target.player ~= nil

	if flag("crosshair_enabled", false) then
		local size = flag("crosshair_size", 8)
		local gap = flag("crosshair_gap", 4)
		local thickness = flag("crosshair_thickness", 1)
		local colour = pickerColor(hasTarget and "crosshair_target_color" or "crosshair_color", hasTarget and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255))
		local outline = pickerColor("crosshair_outline", Color3.new(0, 0, 0))

		Crosshair.angle += dt * math.rad(flag("crosshair_spin", 0))

		for index = 0, 3 do
			local direction = Vector2.new(math.cos(Crosshair.angle + index * math.pi / 2), math.sin(Crosshair.angle + index * math.pi / 2))
			local from, to = centre + direction * gap, centre + direction * (gap + size)
			local back = crosshairLine("back" .. index)
			local front = crosshairLine("front" .. index)

			back.Visible, back.From, back.To, back.Thickness, back.Color = true, from, to, thickness + 2, outline
			front.Visible, front.From, front.To, front.Thickness, front.Color = true, from, to, thickness, colour
		end
	else
		for index = 0, 3 do
			local back, front = Crosshair.objects["back" .. index], Crosshair.objects["front" .. index]

			if back then back.Visible = false end
			if front then front.Visible = false end
		end
	end

	if panel then
		local text = Crosshair.objects.panel

		if not text then
			text = Drawing.new("Text")
			Crosshair.objects.panel = text
		end

		local state = Shop.busy() and "shopping" or (flag("voidspam_enabled", false) and ("void spam: " .. VoidSpam.phase))
			or (flag("follow_enabled", false) and hasTarget and "following") or (hasTarget and "targeting") or "idle"

		text.Visible = true
		text.Text = state .. (hasTarget and (" - " .. Target.player.Name) or "")
		text.Position = Vector2.new(centre.X, centre.Y + flag("crosshair_size", 8) + 22)
		text.Size = 13
		text.Center = true
		text.Outline = true
		text.Font = Drawing.Fonts and Drawing.Fonts.UI or 0
		text.Color = pickerColor("crosshair_panel_color", Color3.fromRGB(255, 255, 255))
	elseif Crosshair.objects.panel then
		Crosshair.objects.panel:Remove()
		Crosshair.objects.panel = nil
	end
end

---@module LocalChar
---Your own character: a highlight, a material, a hat, an aura and a rainbow on the tool in hand. Local to your screen.
local LocalChar = { highlight = nil, hat = nil, aura = nil, tool = nil, materials = {}, hue = 0 }

local function dropObject(key)
	if LocalChar[key] then
		LocalChar[key]:Destroy()
		LocalChar[key] = nil
	end
end

function LocalChar.restore()
	dropObject("highlight")
	dropObject("hat")
	dropObject("aura")
	dropObject("tool")

	for part, original in LocalChar.materials do
		if part.Parent then
			part.Material = original
		end
	end

	LocalChar.materials = {}
end

function LocalChar.step(dt)
	local character = localPlayer.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (character and head and root) then
		return
	end

	-- highlight
	if flag("char_highlight", false) then
		if not LocalChar.highlight or LocalChar.highlight.Adornee ~= character then
			dropObject("highlight")
			LocalChar.highlight = Instance.new("Highlight")
			LocalChar.highlight.Parent = game:GetService("CoreGui")
		end

		LocalChar.highlight.Adornee = character
		LocalChar.highlight.FillColor = pickerColor("char_highlight_fill", Color3.fromRGB(180, 120, 255))
		LocalChar.highlight.OutlineColor = pickerColor("char_highlight_outline", Color3.new(1, 1, 1))
		LocalChar.highlight.FillTransparency = flag("char_highlight_fill_transparency", 0.6)
	else
		dropObject("highlight")
	end

	-- material
	if flag("char_material", false) then
		local material = Enum.Material[flag("char_material_value", "ForceField")]

		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				LocalChar.materials[part] = LocalChar.materials[part] or part.Material
				part.Material = material
			end
		end
	elseif next(LocalChar.materials) then
		for part, original in LocalChar.materials do
			if part.Parent then
				part.Material = original
			end
		end

		LocalChar.materials = {}
	end

	-- china hat: a cone on the head
	if flag("char_hat", false) then
		if not LocalChar.hat or not LocalChar.hat.Parent then
			dropObject("hat")

			local hat = Instance.new("Part")
			local mesh = Instance.new("SpecialMesh")

			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = "rbxassetid://1033714"
			mesh.Parent = hat
			hat.Anchored = true
			hat.CanCollide = false
			hat.CanQuery = false
			hat.CanTouch = false
			hat.Material = Enum.Material.Neon
			hat.Size = Vector3.one
			hat.Parent = camera
			LocalChar.hat = hat
		end

		local scale = flag("char_hat_scale", 1.6)

		LocalChar.hat.Color = pickerColor("char_hat_color", Color3.fromRGB(255, 120, 200))
		LocalChar.hat.Mesh.Scale = Vector3.new(scale * 1.2, scale * 0.45, scale * 1.2)
		LocalChar.hat.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.9 + scale * 0.1, 0))
	else
		dropObject("hat")
	end

	-- particle aura
	if flag("char_aura", false) then
		if not LocalChar.aura or LocalChar.aura.Parent ~= root then
			dropObject("aura")
			LocalChar.aura = Instance.new("ParticleEmitter")
			LocalChar.aura.Rate = 25
			LocalChar.aura.Lifetime = NumberRange.new(0.8, 1.4)
			LocalChar.aura.Speed = NumberRange.new(1, 3)
			LocalChar.aura.SpreadAngle = Vector2.new(180, 180)
			LocalChar.aura.Size = NumberSequence.new(0.35, 0)
			LocalChar.aura.LightEmission = 1
			LocalChar.aura.Parent = root
		end

		LocalChar.aura.Color = ColorSequence.new(pickerColor("char_aura_color", Color3.fromRGB(120, 200, 255)))
	else
		dropObject("aura")
	end

	-- rainbow on the tool in hand
	local tool = character:FindFirstChildOfClass("Tool")

	if flag("char_rainbow", false) and tool then
		LocalChar.hue = (LocalChar.hue + dt * flag("char_rainbow_speed", 0.4)) % 1

		if not LocalChar.tool or LocalChar.tool.Adornee ~= tool then
			dropObject("tool")
			LocalChar.tool = Instance.new("Highlight")
			LocalChar.tool.Parent = game:GetService("CoreGui")
			LocalChar.tool.Adornee = tool
		end

		LocalChar.tool.FillColor = Color3.fromHSV(LocalChar.hue, 1, 1)
		LocalChar.tool.OutlineColor = Color3.fromHSV((LocalChar.hue + 0.5) % 1, 1, 1)
		LocalChar.tool.FillTransparency = flag("char_rainbow_transparency", 0.3)
	else
		dropObject("tool")
	end
end

---@module Misc
---Small things on your own client: hide other players' nametags, play an animation on your character, lift the camera zoom limit.
---Each one remembers what it changed and puts it back.
local Misc = { nametags = {}, animation = nil, track = nil, animationId = nil, zoomSaved = nil }

local EMOTES = {
	["sleep"] = "rbxassetid://10714360343",
	["floss"] = "rbxassetid://10714340543",
	["hype"] = "rbxassetid://10714369624",
	["china dance"] = "rbxassetid://112134517351163",
	["aura idle"] = "rbxassetid://131556235813350",
	["headless basketball"] = "rbxassetid://71379317586292",
	["aura farming"] = "rbxassetid://119737281881349",
	["sturdy"] = "rbxassetid://95578613077512",
	["ramge"] = "rbxassetid://104322051945322",
}

local EMOTE_NAMES = { "sleep", "floss", "hype", "china dance", "aura idle", "headless basketball", "aura farming", "sturdy", "ramge", "custom" }

local function restoreNametags()
	for humanoid, original in Misc.nametags do
		if humanoid.Parent then
			humanoid.DisplayDistanceType, humanoid.HealthDisplayType = original[1], original[2]
		end
	end

	Misc.nametags = {}
end

local function stopAnimation()
	if Misc.track then
		Misc.track:Stop()
		Misc.track = nil
	end

	if Misc.animation then
		Misc.animation:Destroy()
		Misc.animation = nil
	end

	Misc.animationId = nil
end

function Misc.restore()
	restoreNametags()
	stopAnimation()

	if Misc.zoomSaved then
		localPlayer.CameraMaxZoomDistance = Misc.zoomSaved
		Misc.zoomSaved = nil
	end
end

function Misc.step()
	-- nametags of the other players
	if flag("misc_hide_nametags", false) then
		for _, player in playersService:GetPlayers() do
			local humanoid = player ~= localPlayer and player.Character and player.Character:FindFirstChildOfClass("Humanoid")

			if humanoid then
				Misc.nametags[humanoid] = Misc.nametags[humanoid] or { humanoid.DisplayDistanceType, humanoid.HealthDisplayType }
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end
		end
	elseif next(Misc.nametags) then
		restoreNametags()
	end

	-- camera zoom limit
	if flag("misc_zoom", false) then
		Misc.zoomSaved = Misc.zoomSaved or localPlayer.CameraMaxZoomDistance
		localPlayer.CameraMaxZoomDistance = 9e9
	elseif Misc.zoomSaved then
		localPlayer.CameraMaxZoomDistance = Misc.zoomSaved
		Misc.zoomSaved = nil
	end

	-- animation player: loaded again when the animation or the character changes
	if flag("misc_anim", false) then
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local name = flag("misc_anim_name", "sleep")
		local id = name == "custom" and ("rbxassetid://" .. tostring(flag("misc_anim_id", "15609995579"))) or EMOTES[name]

		if animator and id and (Misc.animationId ~= id or not Misc.track or Misc.track.Parent == nil) then
			stopAnimation()

			local animation = Instance.new("Animation")

			animation.AnimationId = id
			Misc.animation = animation
			Misc.animationId = id

			local ok, track = pcall(animator.LoadAnimation, animator, animation)

			if ok and track then
				track.Looped = true
				track:Play()
				Misc.track = track
			end
		end
	elseif Misc.track or Misc.animation then
		stopAnimation()
	end
end

---@module Skins
---Gun and bat skins on your own client. ReplicatedStorage.SkinModules (a module returning, per gun, every skin with the mesh to use and where it sits) is
---read, and a chosen skin is put on the gun by hiding its mesh and welding the skin's mesh in its place; the skin's shoot sound and particles are taken
---from ReplicatedStorage.SkinAssets when it has them. Other players see the gun as it is. Choices are kept in `Vanta/skins.json` and applied again whenever
---a tool is added to the backpack or the character.
local Skins = { choices = {}, states = setmetatable({}, { __mode = "k" }), data = nil, guns = {} }

local SKIN_FILE = "Vanta/skins.json"

local function skinModules()
	return game:GetService("ReplicatedStorage"):FindFirstChild("SkinModules")
end

function Skins.load()
	local modules = skinModules()

	if modules then
		local ok, data = pcall(require, modules)

		Skins.data = ok and type(data) == "table" and data or nil
	end

	local ok, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(readfile(SKIN_FILE))
	end)

	if ok and type(decoded) == "table" then
		Skins.choices = decoded
	end
end

local function saveChoices()
	pcall(function()
		if not isfolder("Vanta") then
			makefolder("Vanta")
		end

		writefile(SKIN_FILE, game:GetService("HttpService"):JSONEncode(Skins.choices))
	end)
end

---The weapons that can be skinned: guns that have a model in SkinModules, and the bat.
function Skins.weapons()
	local list = {}
	local modules = skinModules()
	local models = modules and modules:FindFirstChild("GunModels")

	if Skins.data and models then
		for name in Skins.data do
			if type(name) == "string" and models:FindFirstChild(name) and name ~= "[Knife]" then
				list[#list + 1] = name
			end
		end
	end

	if modules and modules:FindFirstChild("Bats") then
		list[#list + 1] = "[Bat]"
	end

	table.sort(list)

	return #list > 0 and list or { "none" }
end

---Skin names for a weapon, "default" first.
function Skins.skinsFor(weapon)
	local list = {}

	if weapon == "[Bat]" then
		local bats = skinModules() and skinModules():FindFirstChild("Bats")

		for _, skin in bats and bats:GetChildren() or {} do
			list[#list + 1] = skin.Name
		end
	elseif Skins.data and Skins.data[weapon] then
		for name in Skins.data[weapon] do
			list[#list + 1] = tostring(name)
		end
	end

	table.sort(list)
	table.insert(list, 1, "default")

	return list
end

local function stateOf(tool, mesh)
	local state = Skins.states[tool]

	if not state then
		state = { mesh = mesh, transparency = mesh.Transparency, texture = mesh.TextureID, clones = {}, added = {}, removed = {}, sound = nil }
		Skins.states[tool] = state
	end

	return state
end

---Puts a tool back to the game's own look.
function Skins.reset(tool)
	local state = Skins.states[tool]

	if not state then
		return
	end

	Skins.states[tool] = nil

	for _, clone in state.clones do
		clone:Destroy()
	end

	if state.mesh and state.mesh.Parent then
		state.mesh.Transparency = state.transparency
		pcall(function()
			state.mesh.TextureID = state.texture
		end)
	end

	local handle = tool:FindFirstChild("Handle")

	if handle then
		local shoot = handle:FindFirstChild("ShootSound")

		if shoot and state.sound then
			shoot.SoundId = state.sound
		end

		if state.skinAttribute ~= nil then
			handle:SetAttribute("SkinName", state.skinAttribute or nil)
		end

		for _, emitter in state.added do
			emitter:Destroy()
		end

		for _, emitter in state.removed do
			emitter.Parent = handle
		end
	end
end

---Applies the chosen skin of a tool (or leaves it at the game's look).
function Skins.apply(tool)
	Skins.reset(tool)

	local choice = Skins.choices[tool.Name]

	if not flag("skins_enabled", false) or not choice or choice == "default" then
		return
	end

	local mesh = tool:FindFirstChildOfClass("MeshPart")
	local modules = skinModules()

	if not mesh or not modules then
		return
	end

	if tool.Name == "[Bat]" then
		local bats = modules:FindFirstChild("Bats")
		local source = bats and bats:FindFirstChild(choice)

		if not source then
			return
		end

		local state = stateOf(tool, mesh)
		local clone = source:Clone()

		clone.Name = "VantaSkin"
		clone.CFrame = mesh.CFrame
		clone.Parent = tool

		local weld = Instance.new("Weld")

		weld.Part0, weld.Part1 = clone, mesh
		weld.Parent = clone
		mesh.Transparency = 1
		state.clones[#state.clones + 1] = clone

		return
	end

	local info = Skins.data and Skins.data[tool.Name] and Skins.data[tool.Name][choice]

	if not info then
		return
	end

	local state = stateOf(tool, mesh)

	if typeof(info.TextureID) == "Instance" then
		local clone = info.TextureID:Clone()

		clone.Name = "VantaSkin"
		clone.CFrame = mesh.CFrame
		clone.Parent = tool

		local weld = Instance.new("Weld")

		weld.Part0, weld.Part1 = clone, mesh
		weld.C0 = info.CFrame:Inverse()
		weld.Parent = clone
		mesh.Transparency = 1
		state.clones[#state.clones + 1] = clone
	else
		mesh.TextureID = tostring(info.TextureID)
		mesh.Transparency = 0
	end

	local handle = tool:FindFirstChild("Handle")

	if not handle then
		return
	end

	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("SkinAssets")
	local shoot = handle:FindFirstChild("ShootSound")
	local sounds = assets and assets:FindFirstChild("GunShootSounds")
	local gunSounds = sounds and sounds:FindFirstChild(tool.Name)
	local soundValue = gunSounds and gunSounds:FindFirstChild(choice)

	if shoot and soundValue then
		state.sound = state.sound or shoot.SoundId
		shoot.SoundId = soundValue.Value
	end

	local particles = assets and assets:FindFirstChild("GunHandleParticle")
	local source = particles and particles:FindFirstChild(choice)
	local emitter = source and source:FindFirstChildOfClass("ParticleEmitter")

	if emitter then
		-- the emitters that were there are parked, so the default look can bring them back
		for _, existing in handle:GetChildren() do
			if existing:IsA("ParticleEmitter") then
				state.removed[#state.removed + 1] = existing
				existing.Parent = nil
			end
		end

		local added = emitter:Clone()

		added.Parent = handle
		state.added[#state.added + 1] = added
	end

	state.skinAttribute = handle:GetAttribute("SkinName") or false
	handle:SetAttribute("SkinName", choice)
end

---Chooses (or clears) a weapon's skin, remembers it and applies it to the tools that exist.
function Skins.choose(weapon, skin)
	Skins.choices[weapon] = (skin ~= nil and skin ~= "default") and skin or nil
	saveChoices()
	Skins.refresh(weapon)
end

---Applies the choices again to every tool with this name (every tool when none is given).
function Skins.refresh(weapon)
	local character = localPlayer.Character
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")

	for _, holder in { character, backpack } do
		if holder then
			for _, tool in holder:GetChildren() do
				if tool:IsA("Tool") and (weapon == nil or tool.Name == weapon) then
					Skins.apply(tool)
				end
			end
		end
	end
end

---Applies skins to tools as they appear, and takes every skin off on unload.
function Skins.start(maid)
	local function watch(holder)
		if not holder then
			return
		end

		maid:give(holder.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				task.delay(0.15, function()
					if child.Parent then
						Skins.apply(child)
					end
				end)
			end
		end))
	end

	watch(localPlayer:FindFirstChildOfClass("Backpack"))
	watch(localPlayer.Character)

	maid:give(localPlayer.CharacterAdded:Connect(function(character)
		watch(character)
		task.delay(1, Skins.refresh)
	end))

	task.defer(Skins.refresh)

	maid:give(function()
		for tool in pairs(Skins.states) do
			Skins.reset(tool)
		end
	end)
end

---@module Inventory
---The hotbar layout. The game saves a hotbar layout as the setting "HotbarLayout" ({slot number = tool name, food as "FOOD"}) sent with MainEvent
---"UpdateSingleSetting", and its hotbar arranges itself by it on every spawn. This module works that layout out from the nine slots picked here and sends
---that same setting, only when it differs from the saved one and at most every 1.5 seconds (the game's own Save Layout button waits one second). No tool is
---moved on your side. The original also moves the tools that have no slot out of the hotbar through the hotbar script's internals; that is not done here.
local Inventory = { sentAt = 0, pending = false, lastLayout = nil }

local KNOWN_TOOLS = {
	"[Double-Barrel SG]", "[Revolver]", "[TacticalShotgun]", "[AUG]", "[Rifle]", "[Flintlock]", "[Shotgun]", "[Drum-Shotgun]", "[SMG]", "[Silencer]",
	"[SilencerAR]", "[AK47]", "[AR]", "[LMG]", "[P90]", "[Glock]", "[RPG]", "[GrenadeLauncher]", "[Flamethrower]", "[Taser]", "[Knife]", "[Bat]",
	"[Pitchfork]", "[Shovel]", "[StopSign]", "[Pepper Spray]", "[Grenade]", "[Flashbang]",
}

local DEFAULT_SLOTS = { "[Double-Barrel SG]", "[Revolver]", "[TacticalShotgun]", "[AUG]", "[Rifle]", "[Flintlock]", "None", "None", "None" }

---The slot choices: None, the known tools and whatever else is owned right now.
function Inventory.choices()
	local list = { "None" }

	for _, name in KNOWN_TOOLS do
		list[#list + 1] = name
	end

	local backpack = localPlayer:FindFirstChildOfClass("Backpack")

	for _, tool in backpack and backpack:GetChildren() or {} do
		if tool:IsA("Tool") and not table.find(list, tool.Name) then
			list[#list + 1] = tool.Name
		end
	end

	return list
end

local function slotName(tool)
	if tool:FindFirstChild("Eat") or tool:FindFirstChild("Drink") or tool.Name == "[Lettuce]" then
		return "FOOD"
	end

	return tool.Name
end

---The layout for the slots picked, as {["1"] = name, ...}. A slot whose tool is not owned is left out, and every name is used once.
function Inventory.layout()
	local tools = {}

	for _, holder in { localPlayer:FindFirstChildOfClass("Backpack"), localPlayer.Character } do
		for _, tool in holder and holder:GetChildren() or {} do
			if tool:IsA("Tool") then
				tools[#tools + 1] = tool
			end
		end
	end

	local layout, named, used = {}, {}, {}

	for slot = 1, 9 do
		local wanted = flag("sorter_slot_" .. slot, DEFAULT_SLOTS[slot])

		if wanted and wanted ~= "None" then
			for _, tool in tools do
				if not used[tool] and tool.Name == wanted then
					used[tool] = true

					local name = slotName(tool)

					if not named[name] then
						named[name] = true
						layout[tostring(slot)] = name
					end

					break
				end
			end
		end
	end

	return layout
end

---Is this layout the one the server already has?
local function sameAsSaved(layout)
	local http = game:GetService("HttpService")
	local ok, saved = pcall(http.JSONDecode, http, localPlayer:GetAttribute("HotbarLayout") or "[]")

	if not ok or type(saved) ~= "table" then
		return false
	end

	local byKey = {}

	for key, value in saved do
		byKey[tostring(key)] = tostring(value)
	end

	for key, value in layout do
		if byKey[key] ~= value then
			return false
		end
	end

	for key in byKey do
		if layout[key] == nil then
			return false
		end
	end

	return true
end

---Works the layout out and sends it when it is new. `manual` (Sort Now) ignores the auto switch.
---@return string result what happened, for the notification
function Inventory.sort(manual)
	if not manual and not flag("sorter_enabled", false) then
		return "off"
	end

	local layout = Inventory.layout()

	if next(layout) == nil then
		return "no slot picked or no matching tool"
	end

	if sameAsSaved(layout) then
		return "already saved"
	end

	local wait = 1.5 - (os.clock() - Inventory.sentAt)

	if wait > 0 then
		if not Inventory.pending then
			Inventory.pending = true

			task.delay(wait, function()
				Inventory.pending = false
				Inventory.sort(manual)
			end)
		end

		return "waiting"
	end

	local event = game:GetService("ReplicatedStorage"):FindFirstChild("MainEvent")

	if not event then
		return "no MainEvent"
	end

	Inventory.sentAt = os.clock()
	Inventory.lastLayout = layout
	event:FireServer("UpdateSingleSetting", "HotbarLayout", game:GetService("HttpService"):JSONEncode(layout))

	return "sent"
end

---Auto Sorter: sorts when the backpack changes and after a respawn.
function Inventory.start(maid)
	local token = 0

	local function request()
		if not flag("sorter_enabled", false) then
			return
		end

		token += 1

		local mine = token

		task.delay(0.6, function()
			if mine == token then
				Inventory.sort(false)
			end
		end)
	end

	local function watch(backpack)
		if backpack then
			maid:give(backpack.ChildAdded:Connect(request))
			maid:give(backpack.ChildRemoved:Connect(request))
		end
	end

	watch(localPlayer:FindFirstChildOfClass("Backpack"))

	maid:give(localPlayer.CharacterAdded:Connect(function()
		task.wait(1)
		watch(localPlayer:FindFirstChildOfClass("Backpack"))
		request()
	end))
end


---@module Ragebot
---The driver: one Heartbeat step, one PreRender step, same order every frame.
local Ragebot = { maid = Maid.new() }

function Ragebot.start()
	Aim.install()
	Movement.installHook()

	Target.changed[#Target.changed + 1] = function(player)
		Resolver.reset()
		VoidSpam.reset()
		Follow.held = nil
		Follow.aim = nil

		if flag("notify_target", true) and notifications then
			notifications:create_notification({ name = player and ("target: " .. player.Name) or "target cleared" })
		end
	end

	Body.addProvider("antistomp", AntiStomp.want)
	Body.addProvider("autostomp", AutoStomp.want)
	Body.addProvider("voidspam", VoidSpam.want)
	Body.addProvider("follow", Follow.want)
	VoidSpam.gunReady = AutoFire.anyReady

	Shop.watchCash(Ragebot.maid)

	Ragebot.maid:give(localPlayer.CharacterAdded:Connect(function(character)
		local back = AntiStomp.back

		AntiStomp.back = nil

		if back and flag("antistomp_back", false) and flag("antistomp_enabled", false) then
			task.spawn(function()
				local root = character:WaitForChild("HumanoidRootPart", 5)

				for _ = 1, 3 do
					task.wait()

					if root and root.Parent then
						root.CFrame = back
					end
				end
			end)
		end
	end))
	Status.load()
	Skins.start(Ragebot.maid)
	Inventory.start(Ragebot.maid)
	Ragebot.maid:give(AdStrafe.release)
	Ragebot.maid:give(Bounty.release)

	Ragebot.maid:give(runService.Heartbeat:Connect(function(dt)
		local now = os.clock()

		-- before the body step, so the position it saves as "real" already includes the movement
		Movement.step(dt)

		-- the features that need no target: the statuses, the shop, the bounty watch and the held-trigger full auto
		Status.auto(now)
		Shop.auto(now)
		Bounty.step(now)
		FullAuto.step(now)

		if not flag("ragebot_enabled", false) then
			Follow.aim = nil
			AdStrafe.release()

			if not Shop.busy() then
				Body.apply(now)
			end

			Shop.step(now)

			return
		end

		Target.step(now)

		local root = Target.player and Players.root(Target.player)

		if root then
			Resolver.record(root.Position, now)

			local aim = Resolver.aim(now)

			Follow.aim = aim
		else
			Follow.aim = nil
		end

		-- the body goes first so the gun script reads the spot the server will have it at when the tool is activated
		-- a purchase holds the character at the shop; nothing else moves it until the purchase is done
		if not Shop.busy() then
			Body.apply(now)
		end

		Shop.step(now)

		if not Shop.busy() then
			AutoFire.step(now)
			AutoFire.equipStep(now)
			QuickDraw.step(now)
		end

		AdStrafe.step(now)
	end))

	Ragebot.maid:give(runService.PreRender:Connect(Body.restore))
	Ragebot.maid:give(runService.RenderStepped:Connect(Visuals.render))
	Ragebot.maid:give(runService.RenderStepped:Connect(Esp.render))
	Ragebot.maid:give(runService.RenderStepped:Connect(World.step))
	Ragebot.maid:give(runService.RenderStepped:Connect(Misc.step))
	Ragebot.maid:give(Misc.restore)
	Ragebot.maid:give(runService.RenderStepped:Connect(Crosshair.render))
	Ragebot.maid:give(runService.RenderStepped:Connect(LocalChar.step))
	Ragebot.maid:give(World.restore)
	Ragebot.maid:give(Crosshair.clear)
	Ragebot.maid:give(LocalChar.restore)
	Ragebot.maid:give(runService.RenderStepped:Connect(Feedback.render))
	Feedback.start(Ragebot.maid)
	Ragebot.maid:give(runService.RenderStepped:Connect(AimAssist.step))
	Ragebot.maid:give(runService.RenderStepped:Connect(function()
		local now = os.clock()

		SilentAim.step(now)
		Triggerbot.step(now)
	end))
	Ragebot.maid:give(runService.Stepped:Connect(Movement.stepped))
	Ragebot.maid:give(Esp.clear)
	Ragebot.maid:give(Movement.restore)
	Ragebot.maid:give(localPlayer.Idled:Connect(function()
		if flag("utility_antiafk", false) then
			Utility.antiAfk()
		end
	end))
	Ragebot.maid:give(Visuals.clear)

	Ragebot.maid:give(userInputService.InputBegan:Connect(function(input, processed)
		local bind = library.flags["target_key"]

		if processed or not flag("ragebot_enabled", false) or type(bind) ~= "table" then
			return
		end

		if input.KeyCode == bind.key then
			Target.toggle()
		end
	end))

	Ragebot.maid:give(playersService.PlayerRemoving:Connect(function(player)
		if player == Target.player then
			Target.clear()
		end
	end))
end

function Ragebot.stop()
	Body.restore()
	Aim.active = false
	Aim.clear()

	-- the hooks stay installed (they cannot be removed) but no longer do anything
	Hooks.set("__index", nil)
	Hooks.set("__newindex", nil)
	Hooks.set("__namecall", nil)
	Ragebot.maid:clean()
end

-- Menu: the Priv9 window and every control, wired to the flags the modules read.
local chunk = assert(loadstring(game:HttpGet(LIBRARY_URL)), "could not compile the Priv9 library")
library, notifications = chunk()

local window = library:window({ name = "vanta" })

notifications:create_notification({ name = "loading vanta..." })

local function unload()
	Ragebot.stop()
	Resolver.reset()
	Target.clear()
	environment.Vanta = nil

	if library then
		library:unload_menu()
	end
end

-- The menu is built inside a function: the main chunk is close to the limit of 200 local variables.
local function buildMenu()
	local rage = window:tab({ name = "rage" })
	local ragebotColumn = rage:column({})
	local mainSection = ragebotColumn:section({ name = "ragebot" })
	mainSection:toggle({ name = "enabled", flag = "ragebot_enabled" })
	mainSection:keybind({ name = "target key", flag = "target_key", key = Enum.KeyCode.E, mode = "Hold" })
	mainSection:toggle({ name = "automatic target", flag = "target_automatic" })
	mainSection:toggle({ name = "notify target changes", flag = "notify_target", default = true })

	local targetSection = ragebotColumn:section({ name = "target selection" })
	targetSection:dropdown({ name = "priority", flag = "target_priority", items = { "closest to mouse", "closest to character", "lowest health", "random" }, default = "closest to mouse" })
	targetSection:slider({ name = "fov", flag = "target_fov", min = 10, max = 1000, default = 180, interval = 1, suffix = "px" })
	targetSection:slider({ name = "max distance", flag = "target_distance", min = 50, max = 3000, default = 1000, interval = 10, suffix = " st" })
	targetSection:slider({ name = "automatic cooldown", flag = "target_cooldown", min = 0.05, max = 2, default = 0.25, interval = 0.05, suffix = "s" })
	targetSection:dropdown({ name = "ignore if", flag = "target_ignore_if", items = { "in void", "protected", "knocked" }, default = { "in void", "protected", "knocked" }, multi = true })
	targetSection:dropdown({ name = "target statuses", flag = "target_statuses", items = { "neutral", "friendly", "enemy" }, default = { "neutral", "enemy" }, multi = true })
	targetSection:dropdown({ name = "untarget when", flag = "target_untarget_when", items = { "dead", "knocked", "flung" }, default = { "dead" }, multi = true })

	local stompSection = ragebotColumn:section({ name = "auto stomp" })
	stompSection:toggle({ name = "enabled", flag = "autostomp_enabled" })
	stompSection:toggle({ name = "stop when target dead", flag = "autostomp_stop_dead", default = true })
	stompSection:dropdown({ name = "target statuses", flag = "autostomp_statuses", items = { "neutral", "friendly", "enemy" }, default = { "neutral", "enemy" }, multi = true })
	stompSection:slider({ name = "range", flag = "autostomp_range", min = 20, max = 1000, default = 300, interval = 10, suffix = " st" })

	local fireColumn = rage:column({})
	local fireSection = fireColumn:section({ name = "auto fire" })
	fireSection:toggle({ name = "enabled", flag = "autofire_enabled" })
	fireSection:dropdown({ name = "hitboxes", flag = "autofire_hitbox", items = { "head", "body", "arms", "legs" }, default = { "head" }, multi = true })
	fireSection:toggle({ name = "full auto (hold mouse)", flag = "fullauto_enabled" })
	fireSection:slider({ name = "full auto speed", flag = "fullauto_speed", min = 1, max = 100, default = 100, interval = 1, suffix = "%" })
	fireSection:toggle({ name = "quick draw", flag = "quickdraw_enabled" })
	fireSection:dropdown({ name = "quick draw guns", flag = "quickdraw_guns", items = { "rifle", "double-barrel sg", "flintlock", "revolver", "tacticalshotgun", "shotgun", "smg", "glock" }, default = { "rifle", "double-barrel sg", "flintlock", "revolver" }, multi = true })
	fireSection:toggle({ name = "a/d strafe", flag = "adstrafe_enabled" })
	fireSection:slider({ name = "a/d interval", flag = "adstrafe_interval", min = 0.05, max = 1, default = 0.22, interval = 0.01, suffix = "s" })
	fireSection:toggle({ name = "auto reload", flag = "autofire_reload", default = true })
	fireSection:toggle({ name = "auto equip", flag = "autoequip_enabled" })
	fireSection:dropdown({ name = "equip order", flag = "autoequip_guns", items = { "rifle", "double-barrel sg", "flintlock", "revolver", "tacticalshotgun", "shotgun", "smg", "glock" }, default = { "rifle", "double-barrel sg", "flintlock", "revolver" }, multi = true })
	fireSection:toggle({ name = "prioritize double-barrel", flag = "autoequip_db" })
	fireSection:dropdown({ name = "unequip when", flag = "autoequip_unequip", items = { "no target", "target knocked", "target dead" }, default = {}, multi = true })
	fireSection:slider({ name = "gun gap", flag = "autofire_gap", min = 0, max = 300, default = 40, interval = 5, suffix = "ms" })

	local resolverSection = fireColumn:section({ name = "resolver" })
	resolverSection:dropdown({ name = "mode", flag = "resolver_mode", items = { "off", "cluster", "adaptive", "weighted", "hybrid" }, default = "adaptive" })
	resolverSection:slider({ name = "out of void bonus", flag = "resolver_map_bonus", min = 0, max = 12, default = 5, interval = 0.5, suffix = " st" })
	resolverSection:slider({ name = "normal position trust", flag = "resolver_trust", min = 0.1, max = 5, default = 1.5, interval = 0.05, suffix = "" })
	resolverSection:slider({ name = "void trust", flag = "resolver_void_trust", min = 0.1, max = 5, default = 0.2, interval = 0.05, suffix = "" })
	resolverSection:slider({ name = "forget rate", flag = "resolver_forget", min = 0, max = 1000, default = 80, interval = 5, suffix = "%" })
	resolverSection:slider({ name = "accuracy", flag = "resolver_accuracy", min = 5, max = 110, default = 76.82, interval = 0.5, suffix = "%" })
	resolverSection:slider({ name = "distance penalty", flag = "resolver_penalty", min = 0, max = 5, default = 2, interval = 0.1, suffix = "x" })
	resolverSection:slider({ name = "lerp when close", flag = "resolver_lerp", min = 10, max = 100, default = 10, interval = 1, suffix = "%" })
	resolverSection:slider({ name = "cluster radius", flag = "resolver_radius", min = 2, max = 60, default = 12, interval = 1, suffix = " st" })
	resolverSection:slider({ name = "history window", flag = "resolver_window", min = 0.25, max = 3, default = 1.5, interval = 0.05, suffix = "s" })
	resolverSection:slider({ name = "hold last spot", flag = "resolver_hold", min = 0, max = 4, default = 1.5, interval = 0.1, suffix = "s" })
	resolverSection:slider({ name = "lead", flag = "resolver_lead", min = 0, max = 200, default = 100, interval = 5, suffix = "%" })

	local move = window:tab({ name = "movement" })
	local followColumn = move:column({})
	local followSection = followColumn:section({ name = "follow target" })
	followSection:toggle({ name = "enabled", flag = "follow_enabled" })
	followSection:dropdown({ name = "style", flag = "follow_style", items = { "orbit", "random", "above", "strafe above", "teleport", "zigzag" }, default = "orbit" })
	followSection:slider({ name = "distance", flag = "follow_distance", min = 2, max = 200, default = 15, interval = 1, suffix = " st" })
	followSection:slider({ name = "height", flag = "follow_height", min = -100, max = 100, default = 0, interval = 1, suffix = " st" })
	followSection:slider({ name = "orbit speed", flag = "follow_speed", min = 1, max = 100, default = 75, interval = 1, suffix = "%" })
	followSection:slider({ name = "reposition every", flag = "follow_reposition", min = 0, max = 2, default = 0.05, interval = 0.01, suffix = "s" })
	followSection:toggle({ name = "follow into void", flag = "follow_into_void", default = true })
	followSection:dropdown({ name = "stop if", flag = "follow_stop_if", items = { "no gun equipped", "target knocked", "reloading" }, default = { "no gun equipped", "target knocked", "reloading" }, multi = true })
	followSection:toggle({ name = "lead", flag = "follow_lead", default = true })
	followSection:slider({ name = "lead time", flag = "follow_lead_time", min = 0, max = 300, default = 80, interval = 5, suffix = "ms" })
	followSection:dropdown({ name = "orbit shape", flag = "follow_shape", items = { "circle", "square", "triangle", "pentagon", "hexagon", "decagon", "heart" }, default = "circle" })

	local skySection = followColumn:section({ name = "above settings" })
	skySection:slider({ name = "height min", flag = "follow_sky_min", min = 1, max = 100, default = 10, interval = 1, suffix = " st" })
	skySection:slider({ name = "height max", flag = "follow_sky_max", min = 2, max = 200, default = 20, interval = 1, suffix = " st" })
	skySection:slider({ name = "zig zag height", flag = "follow_zigzag_height", min = -50, max = 50, default = 3, interval = 1, suffix = " st" })
	skySection:slider({ name = "zig zag speed", flag = "follow_zigzag_speed", min = 1, max = 100, default = 35, interval = 1, suffix = "x" })
	skySection:slider({ name = "teleport min", flag = "follow_teleport_min", min = 1, max = 100, default = 2, interval = 1, suffix = " st" })
	skySection:slider({ name = "teleport max", flag = "follow_teleport_max", min = 2, max = 200, default = 17, interval = 1, suffix = " st" })

	local characterColumn = move:column({})
	local characterSection = characterColumn:section({ name = "character" })
	characterSection:toggle({ name = "speed", flag = "move_speed" })
	characterSection:slider({ name = "speed value", flag = "move_speed_value", min = 1, max = 100, default = 20, interval = 1, suffix = " st/s" })
	characterSection:toggle({ name = "flight", flag = "move_flight" })
	characterSection:slider({ name = "flight speed", flag = "move_flight_speed", min = 10, max = 200, default = 60, interval = 1, suffix = " st/s" })
	characterSection:toggle({ name = "noclip", flag = "move_noclip" })
	characterSection:toggle({ name = "jump power", flag = "move_jump" })
	characterSection:slider({ name = "jump power value", flag = "move_jump_power", min = 10, max = 300, default = 70, interval = 1, suffix = "" })
	characterSection:toggle({ name = "anti sit", flag = "move_antisit" })
	characterSection:toggle({ name = "anti trip", flag = "move_antitrip" })
	characterSection:toggle({ name = "lock walk speed", flag = "move_lock_walk" })
	characterSection:toggle({ name = "remove slowdowns", flag = "move_no_slow" })
	characterSection:toggle({ name = "remove jump cooldown", flag = "move_no_jump_cooldown" })
	characterSection:toggle({ name = "pushback guard", flag = "move_pushback", default = true })
	characterSection:toggle({ name = "face target", flag = "face_target" })
	characterSection:toggle({ name = "spinbot", flag = "move_spin" })
	characterSection:slider({ name = "spin speed", flag = "move_spin_speed", min = 1, max = 100, default = 50, interval = 1, suffix = "%" })

	local voidColumn = move:column({})
	local voidSection = voidColumn:section({ name = "void spam" })
	voidSection:toggle({ name = "enabled", flag = "voidspam_enabled" })
	voidSection:slider({ name = "void time", flag = "voidspam_void", min = 0.05, max = 1.5, default = 0.35, interval = 0.01, suffix = "s" })
	voidSection:slider({ name = "window time", flag = "voidspam_window", min = 0.05, max = 0.6, default = 0.12, interval = 0.01, suffix = "s" })
	voidSection:toggle({ name = "hide while waiting", flag = "voidspam_hide_waiting", default = true })
	voidSection:dropdown({ name = "force when", flag = "voidspam_force_when", items = { "reloading", "tabbed out", "not full health" }, default = {}, multi = true })
	voidSection:toggle({ name = "stop if forced", flag = "voidspam_stop_forced" })
	voidSection:toggle({ name = "out with target", flag = "voidspam_out_with_target", default = true })
	voidSection:toggle({ name = "hide while target hides", flag = "voidspam_hide_with_target", default = true })
	voidSection:dropdown({ name = "type", flag = "voidspam_type", items = { "random", "deep", "bait" }, default = "random" })
	voidSection:slider({ name = "deep distance", flag = "voidspam_deep", min = 1, max = 1000, default = 100, interval = 1, suffix = "m st" })
	voidSection:slider({ name = "offset", flag = "voidspam_offset", min = 0, max = 30, default = 3, interval = 1, suffix = " st" })

	local baitSection = voidColumn:section({ name = "bait" })
	baitSection:slider({ name = "bait distance", flag = "voidspam_bait_distance", min = 200, max = 2500, default = 250, interval = 10, suffix = " st" })
	baitSection:slider({ name = "bait cooldown", flag = "voidspam_bait_cooldown", min = 0.01, max = 1.5, default = 0.5, interval = 0.01, suffix = "s" })
	baitSection:slider({ name = "bait time", flag = "voidspam_bait_time", min = 0.01, max = 1, default = 0.03, interval = 0.01, suffix = "s" })
	baitSection:toggle({ name = "bait freeze", flag = "voidspam_bait_freeze" })
	baitSection:dropdown({ name = "bait spot", flag = "voidspam_bait_spot", items = { "random", "where you stood" }, default = "random" })

	local visuals = window:tab({ name = "visuals" })
	local visualsColumn = visuals:column({})
	local fovSection = visualsColumn:section({ name = "fov circle" })
	fovSection:toggle({ name = "show", flag = "fov_show" })
	fovSection:colorpicker({ name = "colour", flag = "fov_color", color = Color3.fromRGB(255, 255, 255) })
	fovSection:colorpicker({ name = "active colour", flag = "fov_active_color", color = Color3.fromRGB(255, 80, 80) })
	fovSection:toggle({ name = "follow target", flag = "fov_follow" })
	fovSection:toggle({ name = "outline", flag = "fov_outline" })
	fovSection:colorpicker({ name = "outline colour", flag = "fov_outline_color", color = Color3.new(0, 0, 0) })
	fovSection:colorpicker({ name = "active outline", flag = "fov_active_outline", color = Color3.new(0, 0, 0) })

	local tracerSection = visualsColumn:section({ name = "tracer" })
	tracerSection:toggle({ name = "show", flag = "tracer_show" })
	tracerSection:colorpicker({ name = "colour", flag = "tracer_color", color = Color3.fromRGB(255, 255, 255) })
	tracerSection:slider({ name = "thickness", flag = "tracer_thickness", min = 1, max = 5, default = 1, interval = 1, suffix = "px" })
	tracerSection:dropdown({ name = "origin", flag = "tracer_origin", items = { "bottom", "center", "mouse" }, default = "bottom" })
	tracerSection:dropdown({ name = "end point", flag = "tracer_end", items = { "aim", "head", "torso", "feet" }, default = "aim" })
	tracerSection:toggle({ name = "outline", flag = "tracer_outline" })
	tracerSection:colorpicker({ name = "outline colour", flag = "tracer_outline_color", color = Color3.new(0, 0, 0) })

	local targetVisualColumn = visuals:column({})
	local circleSection = targetVisualColumn:section({ name = "target circle" })
	circleSection:toggle({ name = "show", flag = "circle_show" })
	circleSection:colorpicker({ name = "colour", flag = "circle_color", color = Color3.fromRGB(180, 120, 255) })
	circleSection:slider({ name = "radius", flag = "circle_radius", min = 1, max = 20, default = 4, interval = 0.5, suffix = " st" })

	local cameraSection = targetVisualColumn:section({ name = "camera" })
	cameraSection:toggle({ name = "view target", flag = "view_target" })
	cameraSection:toggle({ name = "stop when knocked", flag = "view_stop_knocked" })
	cameraSection:toggle({ name = "information panel", flag = "info_panel" })
	cameraSection:colorpicker({ name = "panel colour", flag = "info_color", color = Color3.fromRGB(255, 255, 255) })

	local followVisualSection = targetVisualColumn:section({ name = "follow spot" })
	followVisualSection:toggle({ name = "visualize", flag = "follow_visualize" })
	followVisualSection:colorpicker({ name = "colour", flag = "follow_visualize_color", color = Color3.fromRGB(120, 200, 255) })

	-- the shop parts are read before the menu is built so the manual purchase list can name them
	Shop.scan()

	local shopTab = window:tab({ name = "shop" })
	local shopColumn = shopTab:column({})
	local purchaseSection = shopColumn:section({ name = "purchasing" })
	purchaseSection:toggle({ name = "safe purchasing", flag = "shop_safe" })
	purchaseSection:dropdown({ name = "avoid", flag = "shop_safe_avoid", items = { "target", "neutral", "friendly", "enemy" }, default = { "target" }, multi = true })
	purchaseSection:slider({ name = "avoid within", flag = "shop_safe_distance", min = 10, max = 200, default = 50, interval = 1, suffix = " st" })
	purchaseSection:slider({ name = "keep cash", flag = "shop_keep_cash", min = 0, max = 50000, default = 5000, interval = 100, suffix = "$" })
	purchaseSection:toggle({ name = "notifications", flag = "shop_notify", default = true })
	purchaseSection:dropdown({ name = "pause ammo, mask and loadout when", flag = "shop_pause_when", items = { "target selected", "target alive" }, default = {}, multi = true })
	purchaseSection:dropdown({ name = "item", flag = "shop_manual_item", items = #Shop.names > 0 and Shop.names or { "none" }, default = Shop.items["popcorn"] and "popcorn" or nil, scrolling = true })
	purchaseSection:button({ name = "buy item", callback = function()
		local chosen = flag("shop_manual_item")

		if type(chosen) == "string" and not Shop.request(chosen) then
			notifications:create_notification({ name = "cannot buy " .. chosen .. " right now" })
		end
	end })

	local autoSection = shopColumn:section({ name = "auto armor" })
	autoSection:toggle({ name = "enabled", flag = "shop_armor" })
	autoSection:slider({ name = "buy if below", flag = "shop_armor_below", min = 1, max = 200, default = 52, interval = 1, suffix = "" })
	autoSection:slider({ name = "try cooldown", flag = "shop_armor_cooldown", min = 0.05, max = 5, default = 0.05, interval = 0.05, suffix = "s" })

	local ammoSection = shopColumn:section({ name = "auto ammo" })
	ammoSection:toggle({ name = "enabled", flag = "shop_ammo" })
	ammoSection:slider({ name = "minimum clips", flag = "shop_ammo_clips", min = 0, max = 10, default = 2, interval = 1, suffix = "" })
	ammoSection:slider({ name = "packs per purchase", flag = "shop_ammo_packs", min = 1, max = 20, default = 1, interval = 1, suffix = "" })

	local shopColumn2 = shopTab:column({})
	local healSection = shopColumn2:section({ name = "auto heal" })
	healSection:toggle({ name = "enabled", flag = "shop_heal" })
	healSection:slider({ name = "heal below", flag = "shop_heal_below", min = 1, max = 100, default = 50, interval = 1, suffix = "%" })
	healSection:slider({ name = "eat every", flag = "shop_heal_cooldown", min = 0.05, max = 1, default = 0.3, interval = 0.05, suffix = "s" })
	healSection:toggle({ name = "stop following while healing", flag = "shop_heal_stop_follow" })

	local maskSection = shopColumn2:section({ name = "auto mask" })
	maskSection:toggle({ name = "enabled", flag = "shop_mask" })

	local loadoutSection = shopColumn2:section({ name = "auto loadout" })
	loadoutSection:toggle({ name = "enabled", flag = "shop_loadout" })
	loadoutSection:dropdown({ name = "guns", flag = "shop_loadout_guns", items = { "rifle", "double-barrel sg", "flintlock", "revolver", "tacticalshotgun", "shotgun", "smg", "glock", "silencer", "knife" }, default = { "rifle" }, multi = true })
	loadoutSection:slider({ name = "ammo packs", flag = "shop_loadout_packs", min = 0, max = 20, default = 5, interval = 1, suffix = "" })


	local espColumn = visuals:column({})
	local espSection = espColumn:section({ name = "player esp" })
	espSection:toggle({ name = "enabled", flag = "esp_enabled" })
	espSection:toggle({ name = "only target", flag = "esp_only_target" })
	espSection:dropdown({ name = "render statuses", flag = "esp_statuses", items = { "neutral", "friendly", "enemy" }, default = { "neutral", "friendly", "enemy" }, multi = true })
	espSection:toggle({ name = "box", flag = "esp_box", default = true })
	espSection:toggle({ name = "name", flag = "esp_name", default = true })
	espSection:toggle({ name = "use display name", flag = "esp_display_name", default = true })
	espSection:toggle({ name = "distance", flag = "esp_distance" })
	espSection:dropdown({ name = "unit", flag = "esp_unit", items = { "studs", "metres" }, default = "studs" })
	espSection:toggle({ name = "tool text", flag = "esp_tool" })
	espSection:toggle({ name = "uppercase tool", flag = "esp_tool_upper" })
	espSection:toggle({ name = "health bar", flag = "esp_health_bar", default = true })
	espSection:toggle({ name = "health text", flag = "esp_health_text" })
	espSection:toggle({ name = "hide health text if full", flag = "esp_health_hide_full", default = true })
	espSection:toggle({ name = "armor bar", flag = "esp_armor_bar" })
	espSection:toggle({ name = "hide armor bar if none", flag = "esp_armor_hide_none", default = true })
	espSection:colorpicker({ name = "colour", flag = "esp_color", color = Color3.fromRGB(255, 255, 255) })
	espSection:colorpicker({ name = "target colour", flag = "esp_target_color", color = Color3.fromRGB(255, 80, 80) })
	espSection:colorpicker({ name = "friendly colour", flag = "esp_friendly_color", color = Color3.fromRGB(80, 255, 120) })
	espSection:colorpicker({ name = "enemy colour", flag = "esp_enemy_color", color = Color3.fromRGB(255, 160, 60) })
	espSection:toggle({ name = "chams", flag = "esp_chams" })
	espSection:slider({ name = "chams transparency", flag = "esp_chams_transparency", min = 0, max = 1, default = 0.5, interval = 0.05, suffix = "" })
	espSection:toggle({ name = "chams behind walls", flag = "esp_chams_walls", default = true })
	espSection:toggle({ name = "highlight outline", flag = "esp_highlight" })
	espSection:colorpicker({ name = "outline colour", flag = "esp_highlight_color", color = Color3.new(1, 1, 1) })

	local legit = window:tab({ name = "legit" })
	local legitColumn = legit:column({})
	local aimSection = legitColumn:section({ name = "aim assist" })
	aimSection:toggle({ name = "enabled", flag = "aimassist_enabled" })
	aimSection:keybind({ name = "aim key", flag = "aimassist_key", key = Enum.KeyCode.Q, mode = "Hold" })
	aimSection:dropdown({ name = "method", flag = "aimassist_method", items = { "camera", "mouse" }, default = "camera" })
	aimSection:dropdown({ name = "hitbox", flag = "aimassist_hitbox", items = { "head", "chest", "root" }, default = "head" })
	aimSection:slider({ name = "field of view", flag = "aimassist_fov", min = 10, max = 800, default = 120, interval = 1, suffix = "px" })
	aimSection:slider({ name = "max distance", flag = "aimassist_distance", min = 50, max = 3000, default = 500, interval = 10, suffix = " st" })
	aimSection:slider({ name = "horizontal smoothing", flag = "aimassist_h_smooth", min = 1, max = 50, default = 6, interval = 1, suffix = "" })
	aimSection:slider({ name = "vertical smoothing", flag = "aimassist_v_smooth", min = 1, max = 50, default = 6, interval = 1, suffix = "" })
	aimSection:toggle({ name = "visible only", flag = "aimassist_visible", default = true })
	aimSection:slider({ name = "target swap cooldown", flag = "legit_swap_cooldown", min = 0, max = 2, default = 0, interval = 0.05, suffix = "s" })
	aimSection:toggle({ name = "show fov", flag = "aimassist_show_fov" })
	aimSection:colorpicker({ name = "fov colour", flag = "aimassist_fov_color", color = Color3.fromRGB(255, 255, 255) })

	local hits = window:tab({ name = "hits" })
	local hitsColumn = hits:column({})
	local markerSection = hitsColumn:section({ name = "hit markers" })
	markerSection:toggle({ name = "2d hit marker", flag = "fb_marker2d" })
	markerSection:slider({ name = "2d lifetime", flag = "fb_marker2d_life", min = 0.1, max = 2, default = 0.4, interval = 0.05, suffix = "s" })
	markerSection:slider({ name = "2d thickness", flag = "fb_marker2d_thickness", min = 1, max = 5, default = 2, interval = 1, suffix = "px" })
	markerSection:colorpicker({ name = "2d colour", flag = "fb_marker2d_color", color = Color3.fromRGB(255, 255, 255) })
	markerSection:colorpicker({ name = "2d lethal colour", flag = "fb_marker2d_lethal", color = Color3.fromRGB(255, 60, 60) })
	markerSection:toggle({ name = "3d hit marker", flag = "fb_marker3d" })
	markerSection:slider({ name = "3d lifetime", flag = "fb_marker3d_life", min = 0.1, max = 3, default = 0.6, interval = 0.05, suffix = "s" })
	markerSection:slider({ name = "3d thickness", flag = "fb_marker3d_thickness", min = 1, max = 5, default = 2, interval = 1, suffix = "px" })
	markerSection:colorpicker({ name = "3d colour", flag = "fb_marker3d_color", color = Color3.fromRGB(255, 255, 255) })
	markerSection:colorpicker({ name = "3d lethal colour", flag = "fb_marker3d_lethal", color = Color3.fromRGB(255, 60, 60) })

	local damageSection = hitsColumn:section({ name = "damage number" })
	damageSection:toggle({ name = "enabled", flag = "fb_damage" })
	damageSection:slider({ name = "lifetime", flag = "fb_damage_life", min = 0.2, max = 3, default = 1, interval = 0.05, suffix = "s" })
	damageSection:slider({ name = "size", flag = "fb_damage_size", min = 10, max = 40, default = 18, interval = 1, suffix = "px" })
	damageSection:colorpicker({ name = "colour", flag = "fb_damage_color", color = Color3.fromRGB(255, 255, 255) })
	damageSection:colorpicker({ name = "lethal colour", flag = "fb_damage_lethal", color = Color3.fromRGB(255, 60, 60) })

	local soundSection = hitsColumn:section({ name = "hit sound" })
	soundSection:toggle({ name = "enabled", flag = "fb_sound" })
	soundSection:dropdown({ name = "sound", flag = "fb_sound_name", items = SOUND_NAMES, default = "neverlose", scrolling = true })
	soundSection:slider({ name = "volume", flag = "fb_sound_volume", min = 0, max = 5, default = 1, interval = 0.1, suffix = "" })

	local hitsColumn2 = hits:column({})
	local overlaySection = hitsColumn2:section({ name = "hit overlay" })
	overlaySection:toggle({ name = "enabled", flag = "fb_overlay" })
	overlaySection:slider({ name = "lifetime", flag = "fb_overlay_life", min = 0.1, max = 2, default = 0.35, interval = 0.05, suffix = "s" })
	overlaySection:colorpicker({ name = "colour", flag = "fb_overlay_color", color = Color3.fromRGB(255, 255, 255) })
	overlaySection:colorpicker({ name = "lethal colour", flag = "fb_overlay_lethal", color = Color3.fromRGB(255, 60, 60) })

	local chamsSection = hitsColumn2:section({ name = "hit chams" })
	chamsSection:toggle({ name = "enabled", flag = "fb_chams" })
	chamsSection:toggle({ name = "only last hit", flag = "fb_chams_last_only", default = true })
	chamsSection:slider({ name = "lifetime", flag = "fb_chams_life", min = 0.1, max = 3, default = 0.5, interval = 0.05, suffix = "s" })
	chamsSection:colorpicker({ name = "colour", flag = "fb_chams_color", color = Color3.fromRGB(255, 255, 255) })
	chamsSection:colorpicker({ name = "lethal colour", flag = "fb_chams_lethal", color = Color3.fromRGB(255, 60, 60) })

	local particleSection = hitsColumn2:section({ name = "hit particle" })
	particleSection:toggle({ name = "enabled", flag = "fb_particle" })
	particleSection:slider({ name = "amount", flag = "fb_particle_count", min = 1, max = 100, default = 20, interval = 1, suffix = "" })
	particleSection:colorpicker({ name = "colour", flag = "fb_particle_color", color = Color3.fromRGB(255, 255, 255) })
	particleSection:colorpicker({ name = "lethal colour", flag = "fb_particle_lethal", color = Color3.fromRGB(255, 60, 60) })

	local skeletonSection = hitsColumn2:section({ name = "hit skeleton" })
	skeletonSection:toggle({ name = "enabled", flag = "fb_skeleton" })
	skeletonSection:slider({ name = "lifetime", flag = "fb_skeleton_life", min = 0.1, max = 3, default = 0.6, interval = 0.05, suffix = "s" })
	skeletonSection:slider({ name = "thickness", flag = "fb_skeleton_thickness", min = 1, max = 5, default = 1, interval = 1, suffix = "px" })
	skeletonSection:colorpicker({ name = "colour", flag = "fb_skeleton_color", color = Color3.fromRGB(255, 255, 255) })

	local hitsColumn3 = hits:column({})
	local tracerSection2 = hitsColumn3:section({ name = "bullet tracers" })
	tracerSection2:toggle({ name = "local tracers", flag = "fb_tracer" })
	tracerSection2:slider({ name = "lifetime", flag = "fb_tracer_life", min = 0.1, max = 3, default = 0.5, interval = 0.05, suffix = "s" })
	tracerSection2:slider({ name = "thickness", flag = "fb_tracer_thickness", min = 1, max = 5, default = 1, interval = 1, suffix = "px" })
	tracerSection2:colorpicker({ name = "colour", flag = "fb_tracer_color", color = Color3.fromRGB(255, 255, 255) })

	local impactSection = hitsColumn3:section({ name = "bullet impacts" })
	impactSection:toggle({ name = "local impacts", flag = "fb_impact" })
	impactSection:slider({ name = "lifetime", flag = "fb_impact_life", min = 0.1, max = 3, default = 0.8, interval = 0.05, suffix = "s" })
	impactSection:colorpicker({ name = "colour", flag = "fb_impact_color", color = Color3.fromRGB(255, 200, 80) })

	local notifySection = hitsColumn3:section({ name = "shot notifications" })
	notifySection:toggle({ name = "notify hits", flag = "fb_notify_hits" })
	notifySection:toggle({ name = "notify shots with no hit", flag = "fb_notify_miss" })

	local legitColumn2 = legit:column({})
	local sharedSection = legitColumn2:section({ name = "shared" })
	sharedSection:dropdown({ name = "target statuses", flag = "legit_statuses", items = { "neutral", "friendly", "enemy" }, default = { "neutral", "enemy" }, multi = true })
	sharedSection:toggle({ name = "ignore knocked", flag = "legit_ignore_knocked", default = true })
	sharedSection:toggle({ name = "ignore spawn protected", flag = "legit_ignore_protected", default = true })

	local silentSection = legitColumn2:section({ name = "silent aim" })
	silentSection:toggle({ name = "enabled", flag = "silent_enabled" })
	silentSection:dropdown({ name = "hitbox", flag = "silent_hitbox", items = { "head", "chest", "root" }, default = "head" })
	silentSection:slider({ name = "field of view", flag = "silent_fov", min = 10, max = 800, default = 120, interval = 1, suffix = "px" })
	silentSection:slider({ name = "max distance", flag = "silent_distance", min = 50, max = 3000, default = 500, interval = 10, suffix = " st" })
	silentSection:slider({ name = "max curve", flag = "silent_curve", min = 1, max = 90, default = 30, interval = 1, suffix = "deg" })
	silentSection:toggle({ name = "dont curve vertically", flag = "silent_flat" })
	silentSection:slider({ name = "redirect chance", flag = "silent_chance", min = 0, max = 100, default = 100, interval = 1, suffix = "%" })
	silentSection:toggle({ name = "visible only", flag = "silent_visible", default = true })
	silentSection:toggle({ name = "show fov", flag = "silent_show_fov" })
	silentSection:colorpicker({ name = "fov colour", flag = "silent_fov_color", color = Color3.fromRGB(180, 180, 255) })

	local triggerSection = legitColumn2:section({ name = "triggerbot" })
	triggerSection:toggle({ name = "enabled", flag = "trigger_enabled" })
	triggerSection:dropdown({ name = "hitboxes", flag = "trigger_hitboxes", items = { "head", "body", "arms", "legs" }, default = { "head", "body" }, multi = true })
	triggerSection:slider({ name = "max distance (0 = gun range)", flag = "trigger_distance", min = 0, max = 2500, default = 0, interval = 10, suffix = " st" })
	triggerSection:slider({ name = "refresh rate", flag = "trigger_refresh", min = 0, max = 0.5, default = 0, interval = 0.01, suffix = "s" })
	triggerSection:slider({ name = "hover time", flag = "trigger_hover", min = 0, max = 0.3, default = 0, interval = 0.01, suffix = "s" })
	triggerSection:slider({ name = "cooldown", flag = "trigger_cooldown", min = 0, max = 1, default = 0, interval = 0.01, suffix = "s" })
	triggerSection:slider({ name = "delay", flag = "trigger_delay", min = 0, max = 0.5, default = 0, interval = 0.01, suffix = "s" })

	local world = window:tab({ name = "world" })
	local worldColumn = world:column({})
	local timeSection = worldColumn:section({ name = "time and light" })
	timeSection:toggle({ name = "world time", flag = "world_time" })
	timeSection:slider({ name = "clock time", flag = "world_time_value", min = 0, max = 24, default = 12, interval = 0.1, suffix = "h" })
	timeSection:toggle({ name = "ambient", flag = "world_ambient" })
	timeSection:colorpicker({ name = "indoor colour", flag = "world_ambient_color", color = Color3.fromRGB(120, 120, 140) })
	timeSection:colorpicker({ name = "outdoor colour", flag = "world_outdoor_color", color = Color3.fromRGB(140, 140, 160) })
	timeSection:toggle({ name = "lighting mode", flag = "world_technology" })
	timeSection:dropdown({ name = "mode", flag = "world_technology_value", items = { "voxel", "shadowmap", "future" }, default = "future" })

	local atmosphereSection = worldColumn:section({ name = "atmosphere" })
	atmosphereSection:toggle({ name = "enabled", flag = "world_atmosphere" })
	atmosphereSection:colorpicker({ name = "colour", flag = "world_atmosphere_color", color = Color3.fromRGB(199, 199, 199) })
	atmosphereSection:colorpicker({ name = "decay", flag = "world_atmosphere_decay", color = Color3.fromRGB(106, 112, 125) })
	atmosphereSection:slider({ name = "haze", flag = "world_atmosphere_haze", min = 0, max = 10, default = 1, interval = 0.1, suffix = "" })
	atmosphereSection:slider({ name = "glare", flag = "world_atmosphere_glare", min = 0, max = 10, default = 0, interval = 0.1, suffix = "" })
	atmosphereSection:slider({ name = "offset", flag = "world_atmosphere_offset", min = 0, max = 1, default = 0, interval = 0.05, suffix = "" })
	atmosphereSection:slider({ name = "density", flag = "world_atmosphere_density", min = 0, max = 1, default = 0.3, interval = 0.01, suffix = "" })

	local worldColumn2 = world:column({})
	local colourSection = worldColumn2:section({ name = "colour and blur" })
	colourSection:toggle({ name = "colour correction", flag = "world_colour" })
	colourSection:slider({ name = "saturation", flag = "world_saturation", min = -1, max = 3, default = 0, interval = 0.05, suffix = "" })
	colourSection:slider({ name = "contrast", flag = "world_contrast", min = -1, max = 2, default = 0, interval = 0.05, suffix = "" })
	colourSection:colorpicker({ name = "tint", flag = "world_tint", color = Color3.new(1, 1, 1) })
	colourSection:toggle({ name = "blur", flag = "world_blur" })
	colourSection:slider({ name = "blur size", flag = "world_blur_size", min = 0, max = 30, default = 6, interval = 1, suffix = "" })

	local worldSkySection = worldColumn2:section({ name = "sky and weather" })
	worldSkySection:toggle({ name = "skybox", flag = "world_sky" })
	worldSkySection:dropdown({ name = "sky", flag = "world_sky_name", items = SKY_NAMES, default = "stormy" })
	worldSkySection:toggle({ name = "weather", flag = "world_weather" })
	worldSkySection:dropdown({ name = "type", flag = "world_weather_type", items = { "rain", "snow" }, default = "rain" })
	worldSkySection:slider({ name = "rate", flag = "world_weather_rate", min = 20, max = 1500, default = 300, interval = 10, suffix = "" })
	worldSkySection:colorpicker({ name = "colour", flag = "world_weather_color", color = Color3.fromRGB(170, 190, 255) })

	local worldColumn3 = world:column({})
	local screenSection = worldColumn3:section({ name = "screen" })
	screenSection:toggle({ name = "hide chat", flag = "world_hide_chat" })
	screenSection:toggle({ name = "hide cursor icon", flag = "world_hide_cursor" })
	screenSection:toggle({ name = "disable 3d rendering", flag = "world_no_render" })

	local hud = window:tab({ name = "hud" })
	local hudColumn = hud:column({})
	local crosshairSection = hudColumn:section({ name = "crosshair" })
	crosshairSection:toggle({ name = "enabled", flag = "crosshair_enabled" })
	crosshairSection:toggle({ name = "follow target", flag = "crosshair_follow" })
	crosshairSection:slider({ name = "line size", flag = "crosshair_size", min = 2, max = 40, default = 8, interval = 1, suffix = "px" })
	crosshairSection:slider({ name = "gap size", flag = "crosshair_gap", min = 0, max = 30, default = 4, interval = 1, suffix = "px" })
	crosshairSection:slider({ name = "line thickness", flag = "crosshair_thickness", min = 1, max = 6, default = 1, interval = 1, suffix = "px" })
	crosshairSection:slider({ name = "rotation", flag = "crosshair_spin", min = 0, max = 720, default = 0, interval = 10, suffix = "deg/s" })
	crosshairSection:colorpicker({ name = "colour", flag = "crosshair_color", color = Color3.fromRGB(255, 255, 255) })
	crosshairSection:colorpicker({ name = "target colour", flag = "crosshair_target_color", color = Color3.fromRGB(255, 80, 80) })
	crosshairSection:colorpicker({ name = "outline colour", flag = "crosshair_outline", color = Color3.new(0, 0, 0) })

	local panelSection = hudColumn:section({ name = "state panel" })
	panelSection:toggle({ name = "show panel", flag = "crosshair_panel" })
	panelSection:colorpicker({ name = "colour", flag = "crosshair_panel_color", color = Color3.fromRGB(255, 255, 255) })

	local characterTab = window:tab({ name = "character" })
	local charColumn = characterTab:column({})
	local charHighlightSection = charColumn:section({ name = "highlight and material" })
	charHighlightSection:toggle({ name = "character highlight", flag = "char_highlight" })
	charHighlightSection:colorpicker({ name = "fill colour", flag = "char_highlight_fill", color = Color3.fromRGB(180, 120, 255) })
	charHighlightSection:colorpicker({ name = "outline colour", flag = "char_highlight_outline", color = Color3.new(1, 1, 1) })
	charHighlightSection:slider({ name = "fill transparency", flag = "char_highlight_fill_transparency", min = 0, max = 1, default = 0.6, interval = 0.05, suffix = "" })
	charHighlightSection:toggle({ name = "character material", flag = "char_material" })
	charHighlightSection:dropdown({ name = "material", flag = "char_material_value", items = { "ForceField", "Neon", "Glass", "Metal", "Plastic", "SmoothPlastic" }, default = "ForceField" })

	local charColumn2 = characterTab:column({})
	local hatSection = charColumn2:section({ name = "china hat" })
	hatSection:toggle({ name = "enabled", flag = "char_hat" })
	hatSection:colorpicker({ name = "colour", flag = "char_hat_color", color = Color3.fromRGB(255, 120, 200) })
	hatSection:slider({ name = "scale", flag = "char_hat_scale", min = 0.5, max = 4, default = 1.6, interval = 0.1, suffix = "" })

	local auraSection = charColumn2:section({ name = "particle aura" })
	auraSection:toggle({ name = "enabled", flag = "char_aura" })
	auraSection:colorpicker({ name = "colour", flag = "char_aura_color", color = Color3.fromRGB(120, 200, 255) })

	local rainbowSection = charColumn2:section({ name = "rainbow tool" })
	rainbowSection:toggle({ name = "enabled", flag = "char_rainbow" })
	rainbowSection:slider({ name = "speed", flag = "char_rainbow_speed", min = 0.05, max = 3, default = 0.4, interval = 0.05, suffix = "" })
	rainbowSection:slider({ name = "transparency", flag = "char_rainbow_transparency", min = 0, max = 1, default = 0.3, interval = 0.05, suffix = "" })

	local playersTab = window:tab({ name = "players" })
	local playersColumn = playersTab:column({})
	local playersSection = playersColumn:section({ name = "player list" })

	local function otherNames()
		local names = {}

		for _, player in playersService:GetPlayers() do
			if player ~= localPlayer then
				names[#names + 1] = player.Name
			end
		end

		table.sort(names)

		return #names > 0 and names or { "none" }
	end

	local playerDropdown = playersSection:dropdown({ name = "player", flag = "status_player", items = otherNames(), default = otherNames()[1], scrolling = true })

	playersSection:dropdown({ name = "status", flag = "status_value", items = { "neutral", "friendly", "enemy" }, default = "neutral" })
	playersSection:button({ name = "apply status", callback = function()
		local chosen = playersService:FindFirstChild(tostring(flag("status_player")))

		if chosen and chosen ~= localPlayer then
			Status.set(chosen, flag("status_value", "neutral"))
			notifications:create_notification({ name = chosen.Name .. " is " .. flag("status_value", "neutral") })
		end
	end })
	playersSection:button({ name = "show status", callback = function()
		local chosen = playersService:FindFirstChild(tostring(flag("status_player")))

		if chosen then
			notifications:create_notification({ name = chosen.Name .. " is " .. Status.get(chosen) })
		end
	end })
	playersSection:button({ name = "set as target", callback = function()
		local chosen = playersService:FindFirstChild(tostring(flag("status_player")))

		if chosen and chosen ~= localPlayer then
			Target.set(chosen)
		end
	end })
	playersSection:button({ name = "refresh list", callback = function()
		playerDropdown.refresh_options(otherNames())
	end })

	local autoStatusSection = playersTab:column({}):section({ name = "automatic statuses" })

	autoStatusSection:toggle({ name = "friends are friendly", flag = "status_friends" })
	autoStatusSection:toggle({ name = "crew mates are friendly", flag = "status_crew" })
	autoStatusSection:toggle({ name = "friends of an enemy are enemies", flag = "status_enemy_friends" })

	-- the skin list is read before the menu names it
	Skins.load()

	local skinsTab = window:tab({ name = "skins" })
	local skinsColumn = skinsTab:column({})
	local skinSection = skinsColumn:section({ name = "skin changer" })
	local skinDropdown

	skinSection:toggle({ name = "enabled", flag = "skins_enabled", callback = function()
		Skins.refresh()
	end })

	local weaponList = Skins.weapons()

	skinSection:dropdown({ name = "weapon", flag = "skins_weapon", items = weaponList, default = weaponList[1], scrolling = true, callback = function(weapon)
		if skinDropdown and type(weapon) == "string" then
			skinDropdown.refresh_options(Skins.skinsFor(weapon))
			pcall(skinDropdown.set, Skins.choices[weapon] or "default")
		end
	end })
	skinDropdown = skinSection:dropdown({ name = "skin", flag = "skins_skin", items = Skins.skinsFor(weaponList[1]), default = Skins.choices[weaponList[1]] or "default", scrolling = true })
	skinSection:button({ name = "apply skin to weapon", callback = function()
		local weapon, skin = flag("skins_weapon"), flag("skins_skin")

		if type(weapon) == "string" and type(skin) == "string" then
			Skins.choose(weapon, skin)
			notifications:create_notification({ name = weapon .. ": " .. skin })
		end
	end })
	skinSection:button({ name = "reset this weapon", callback = function()
		local weapon = flag("skins_weapon")

		if type(weapon) == "string" then
			Skins.choose(weapon, nil)
			notifications:create_notification({ name = weapon .. ": default" })
		end
	end })
	skinSection:button({ name = "refresh all skins", callback = function()
		Skins.refresh()
	end })

	local inventoryColumn = skinsTab:column({})
	local sorterSection = inventoryColumn:section({ name = "auto sorter" })
	local slotDropdowns = {}

	sorterSection:toggle({ name = "enabled", flag = "sorter_enabled" })

	for slot = 1, 9 do
		slotDropdowns[slot] = sorterSection:dropdown({ name = "slot " .. slot, flag = "sorter_slot_" .. slot, items = Inventory.choices(), default = DEFAULT_SLOTS[slot], scrolling = true })
	end

	sorterSection:button({ name = "sort now", callback = function()
		notifications:create_notification({ name = "sorter: " .. Inventory.sort(true) })
	end })
	sorterSection:button({ name = "refresh tool list", callback = function()
		for _, dropdown in slotDropdowns do
			dropdown.refresh_options(Inventory.choices())
		end
	end })

	local misc = window:tab({ name = "misc" })
	local miscColumn = misc:column({})
	local miscSection = miscColumn:section({ name = "script" })
	local utilitySection = miscColumn:section({ name = "utility" })
	utilitySection:toggle({ name = "anti bounty", flag = "antibounty_enabled" })
	utilitySection:toggle({ name = "auto bounty", flag = "autobounty_enabled" })
	utilitySection:toggle({ name = "anti stomp", flag = "antistomp_enabled" })
	utilitySection:toggle({ name = "anti stomp teleport back", flag = "antistomp_back" })
	utilitySection:toggle({ name = "anti afk", flag = "utility_antiafk" })
	utilitySection:toggle({ name = "hide player nametags", flag = "misc_hide_nametags" })
	utilitySection:toggle({ name = "unlock camera distance", flag = "misc_zoom" })
	utilitySection:toggle({ name = "animation player", flag = "misc_anim" })
	utilitySection:dropdown({ name = "animation", flag = "misc_anim_name", items = EMOTE_NAMES, default = "sleep", scrolling = true })
	utilitySection:textbox({ name = "custom asset id", flag = "misc_anim_id", default = "15609995579" })
	utilitySection:toggle({ name = "watermark", flag = "utility_watermark", default = true, callback = function(visible)
		if library.watermark_outline then
			library.watermark_outline.Visible = visible
		end
	end })
	utilitySection:button({ name = "rejoin", callback = function()
		notifications:create_notification({ name = "rejoining..." })
		Utility.rejoin()
	end })

	miscSection:button({ name = "test notification", callback = function()
		notifications:create_notification({ name = "vanta is running" })
	end })

	miscSection:button({ name = "unload", callback = unload })
end

buildMenu()

library:init_config(window)

Ragebot.start()
environment.Vanta = { unload = unload, library = library, target = Target, resolver = Resolver, body = Body, voidspam = VoidSpam, autofire = AutoFire, follow = Follow, aim = Aim, visuals = Visuals, autostomp = AutoStomp, shop = Shop, bounty = Bounty, esp = Esp, feedback = Feedback, world = World, crosshair = Crosshair, localchar = LocalChar, aimassist = AimAssist, legit = Legit, silent = SilentAim, trigger = Triggerbot, movement = Movement, skins = Skins, inventory = Inventory, status = Status, misc = Misc, utility = Utility, quickdraw = QuickDraw, adstrafe = AdStrafe, fullauto = FullAuto, antistomp = AntiStomp }

notifications:create_notification({ name = "loaded vanta" })
