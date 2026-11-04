---Lead model: every place that leads a target by its velocity goes through here, so the units, caps and trust rules live in one file.
---Pure functions only (no game state), so they can be tested outside Roblox. The shipped script gets this file injected by tools/build/bundle.py.
local Lead = {}

local vector3New = Vector3.new
local vector3Zero = Vector3.zero

-- Constants.
Lead.PREDICTION_AUTO = 2 -- the prediction slider's top (value / 1000): automatic, worked out from the ping
Lead.TRUST_MIN_SPEED = 30 -- studs/s, a replicated velocity below this is not a fast movement
Lead.TRUST_MAX_SPEED = 600
Lead.TRUST_MIN_TOLERANCE = 15 -- studs/s the replicated and the measured velocity may differ by, at least
Lead.TRUST_TOLERANCE_SHARE = 0.35 -- ... or this share of the replicated speed
Lead.DESYNC_SPEED = 80 -- studs/s, a faster "velocity" that is not trusted is a desync jumping about
Lead.LEAD_FAST_SPEED = 60 -- studs/s, Lead Fast Targets leads a steady flight faster than this
Lead.DISPLAY_DELAY = 0.16 -- seconds, what this client shows of another player is about ping + this old (measured: 220 to 250 ms at a 54 ms ping)
Lead.DISPLAY_LEAD_MIN = 0.12 -- seconds
Lead.DISPLAY_LEAD_MAX = 0.45 -- seconds
Lead.CAP = 60 -- studs, longest lead from an untrusted velocity
Lead.CAP_TRUSTED = 150 -- studs, longest lead from a velocity both readings agree on
Lead.GRAVITY_MIN_VERTICAL_SPEED = 1.5 -- studs/s, below this the lead has no gravity term
Lead.FLOOR_TRIGGER = -2 -- studs, a lead going further down than this is checked against the floor
Lead.FLOOR_PROBE_EXTRA = 6 -- studs, how far past the lead the floor is looked for
Lead.FLOOR_CLEARANCE = 3.5 -- studs, the lead stops this far over the floor
Lead.FOLLOW_RAMP_START = 30 -- studs/s, the follow lead starts here and is whole from FOLLOW_MIN_SPEED
Lead.FOLLOW_MIN_SPEED = 40 -- studs/s
Lead.FOLLOW_CAP = 60 -- studs
Lead.FOLLOW_DEFAULT_MS = 80
Lead.PRE_FIRE_CAP = 40 -- studs
Lead.PRE_FIRE_DEFAULT_MS = 60

---Whether the replicated velocity agrees with how the position really changed, which makes a fast movement real.
---A desync or a faked velocity does not agree: one of the two jumps about without the other.
---It is checked against the measured position change, not the Velocity Source's reading: the estimator called real falls of 90 to 150
---studs/s stationary or inconsistent, so they were never trusted and the resolver then took their lead away.
---@param replicated Vector3? the body's AssemblyLinearVelocity
---@param measured Vector3 the velocity measured from the position change
---@return boolean
function Lead.isTrusted(replicated, measured)
	if not replicated then
		return false
	end

	local speed = replicated.Magnitude

	return speed == speed
		and speed > Lead.TRUST_MIN_SPEED
		and speed < Lead.TRUST_MAX_SPEED
		and (replicated - measured).Magnitude <= math.max(Lead.TRUST_MIN_TOLERANCE, speed * Lead.TRUST_TOLERANCE_SHARE)
end

---The lead time before Prediction Strength: 0 is off, the slider's top is automatic from the ping, anything between is fixed.
---Lead Fast Targets turns an off prediction into the automatic one for a fast, steady flight (watched: an opponent's fly-bys at 150 to 300
---studs/s took the character from full to dead in 0.8 s while every shot back would have landed behind it).
---@param prediction number slider value / 1000
---@param ping number milliseconds
---@param leadFast boolean? false turns Lead Fast Targets off
---@param speed number studs/s of the velocity that is being led
---@param steady boolean? whether the last two readings went the same way at about the same speed
---@return number seconds
function Lead.factor(prediction, ping, leadFast, speed, steady)
	local factor = prediction == 0 and 0 or prediction == Lead.PREDICTION_AUTO and ping / 500 or prediction

	if factor == 0 and leadFast ~= false and speed > Lead.LEAD_FAST_SPEED and steady then
		factor = ping / 500
	end

	return factor
end

---The lead time in seconds. A trusted fast movement is never led for less than the delay the client shows it with.
---The server checks a claim against where it has the head, and a fast target was claimed that far behind (36 studs at 150 studs/s, past the
---25 the server takes), up and down as much as sideways. Prediction Strength scales the prediction only; the display delay is the delay
---itself, not a setting (at 50% a 230 studs/s fall was led 20 studs instead of 45).
---@param factor number seconds
---@param strength number percent
---@param trusted boolean
---@param ping number milliseconds
---@return number seconds
function Lead.leadTime(factor, strength, trusted, ping)
	local leadTime = factor * (strength / 100)

	if trusted then
		leadTime = math.max(leadTime, math.clamp(ping / 1000 + Lead.DISPLAY_DELAY, Lead.DISPLAY_LEAD_MIN, Lead.DISPLAY_LEAD_MAX))
	end

	return leadTime
end

---The capped lead vector. A target in the air falls back while the shot is on its way, so the vertical lead bends with gravity instead of
---going on in a straight line (5.6 studs too high after a quarter of a second). A velocity that is not a number gives no lead.
---The cap keeps a bad velocity sample from throwing the aim far away from the target; a movement both readings agree on gets more (a
---300 studs/s flier needs about 90 studs).
---@param velocity Vector3
---@param leadTime number seconds
---@param trusted boolean
---@param gravity number workspace.Gravity
---@return Vector3
function Lead.vector(velocity, leadTime, trusted, gravity)
	local raw = velocity * leadTime

	if math.abs(velocity.Y) > Lead.GRAVITY_MIN_VERTICAL_SPEED and leadTime > 0 then
		raw = raw - vector3New(0, 0.5 * gravity * leadTime * leadTime, 0)
	end

	local length = raw.Magnitude

	if length ~= length then
		return vector3Zero
	end

	local cap = trusted and Lead.CAP_TRUSTED or Lead.CAP

	return length > cap and raw.Unit * cap or raw
end

---Never below the floor under the target: a faller's lead stops where it lands.
---@param lead Vector3
---@param hitboxPosition Vector3
---@param probe function (origin, direction, context) -> the height of the floor below, or nil
---@param context any handed to the probe
---@return Vector3
function Lead.clampToFloor(lead, hitboxPosition, probe, context)
	if not (lead.Y < Lead.FLOOR_TRIGGER) then
		return lead
	end

	local floorHeight = probe(hitboxPosition, vector3New(0, lead.Y - Lead.FLOOR_PROBE_EXTRA, 0), context)

	if floorHeight then
		local lowest = floorHeight + Lead.FLOOR_CLEARANCE

		if hitboxPosition.Y + lead.Y < lowest then
			return vector3New(lead.X, math.min(0, lowest - hitboxPosition.Y), lead.Z)
		end
	end

	return lead
end

---The prediction's lead for one step.
---@param velocity Vector3 the velocity to lead (after a Velocity Source)
---@param measured Vector3 the velocity measured from the position change
---@param replicated Vector3? the body's AssemblyLinearVelocity
---@param resolver boolean? whether the resolver is on
---@param prediction number slider value / 1000
---@param ping number milliseconds
---@param leadFast boolean?
---@param steady boolean? from Lead.isSteady
---@param strength number percent
---@param gravity number
---@param hitboxPosition Vector3
---@param probe function floor probe, see Lead.clampToFloor
---@param context any handed to the probe
---@return Vector3 lead
---@return boolean trusted
function Lead.compute(velocity, measured, replicated, resolver, prediction, ping, leadFast, steady, strength, gravity, hitboxPosition, probe, context)
	local trusted = Lead.isTrusted(replicated, measured)

	if trusted then
		velocity = replicated
	end

	-- With the resolver on, a "velocity" faster than anyone runs that does not agree with the movement is a desync: no lead from it.
	if resolver and velocity.Magnitude > Lead.DESYNC_SPEED and not trusted then
		velocity = vector3Zero
	end

	local factor = Lead.factor(prediction, ping, leadFast, velocity.Magnitude, steady)
	local lead = Lead.vector(velocity, Lead.leadTime(factor, strength, trusted, ping), trusted, gravity)

	return Lead.clampToFloor(lead, hitboxPosition, probe, context), trusted
end

---Whether the velocity went the same way at about the same speed as the reading before (a flight, not a desync hopping about).
---@param previous Vector3?
---@param velocity Vector3
---@return boolean
function Lead.isSteady(previous, velocity)
	return previous ~= nil
		and previous.Magnitude > 1
		and velocity.Magnitude > 1
		and previous.Unit:Dot(velocity.Unit) > 0.8
		and math.abs(velocity.Magnitude - previous.Magnitude) < previous.Magnitude * 0.6
end

---Where along the target's way the body goes, beyond the aim: what the client sees late plus the trip of the body to the server.
---Whole from FOLLOW_MIN_SPEED, as it always was; it now fades in from FOLLOW_RAMP_START instead of switching on at once.
---The body offset is held to the trusted cap together with the prediction's own lead, which used to be a second, independent cap.
---@param velocity Vector3 the measured velocity of the target
---@param leadMs number Lead Time setting, milliseconds
---@param trusted boolean whether the prediction trusted this fast movement
---@param aimLead Vector3 the lead the aim already carries
---@return Vector3
function Lead.followAhead(velocity, leadMs, trusted, aimLead)
	if not trusted then
		return vector3Zero
	end

	local speed = velocity.Magnitude

	if not (speed > Lead.FOLLOW_RAMP_START) then
		return vector3Zero
	end

	local ahead = velocity * (leadMs / 1000)

	if ahead.Magnitude > Lead.FOLLOW_CAP then
		ahead = ahead.Unit * Lead.FOLLOW_CAP
	end

	if speed < Lead.FOLLOW_MIN_SPEED then
		ahead = ahead * ((speed - Lead.FOLLOW_RAMP_START) / (Lead.FOLLOW_MIN_SPEED - Lead.FOLLOW_RAMP_START))
	end

	-- Largest share of `ahead` that keeps the aim lead and the body offset inside one trusted cap (the positive root of |a + s*b| = cap).
	local reach = Lead.CAP_TRUSTED
	local aheadSquared = ahead:Dot(ahead)

	if aheadSquared > 0 and (aimLead + ahead).Magnitude > reach then
		local along = aimLead:Dot(ahead)
		local room = along * along - aheadSquared * (aimLead:Dot(aimLead) - reach * reach)

		ahead = ahead * (room > 0 and math.max(0, (-along + math.sqrt(room)) / aheadSquared) or 0)
	end

	return ahead
end

---How fast the target and this client close in on each other, along the line between them. 0 when they are not closing.
---@param way Vector3 unit vector from the origin to the target
---@param theirs Vector3 target velocity
---@param mine Vector3 own velocity
---@return number studs/s
function Lead.closingSpeed(way, theirs, mine)
	local relative = theirs - mine
	local closing = -(relative.X * way.X + relative.Y * way.Y + relative.Z * way.Z)

	if closing ~= closing or closing <= 0 then
		return 0
	end

	return closing
end

---How far ahead of the target Auto Fire's Pre Fire puts the shot.
---@param closing number studs/s from Lead.closingSpeed
---@param preFireMs number Pre Fire Time setting, milliseconds
---@return number studs
function Lead.preFire(closing, preFireMs)
	if closing ~= closing or closing <= 0 then
		return 0
	end

	return math.min(closing * (preFireMs / 1000), Lead.PRE_FIRE_CAP)
end

return Lead
