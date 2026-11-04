-- The original (pre-rewrite) Visions-hook.lua, read straight from the backup branch so tests compare against the real code and not a retyped copy.
local process = require("@lune/process")

local BACKUP_REF = "backup/pre-rewrite-2026-11-04"

local result = process.exec("git", { "show", BACKUP_REF .. ":Visions-hook.lua" })
assert(result.ok, "git show failed: " .. tostring(result.stderr))

local source = string.gsub(result.stdout, "\r\n", "\n")
local module = { source = source }

---The text from the first match of startMarker up to (not including) the first match of endMarker after it. Errors when an anchor is missing.
---@param startMarker string plain text
---@param endMarker string plain text
---@return string
function module.slice(startMarker, endMarker)
	local startAt = string.find(source, startMarker, 1, true)
	assert(startAt, "start anchor not found: " .. startMarker:sub(1, 60))

	local endAt = string.find(source, endMarker, startAt, true)
	assert(endAt, "end anchor not found: " .. endMarker:sub(1, 60))

	return string.sub(source, startAt, endAt - 1)
end

return module
