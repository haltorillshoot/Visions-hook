-- Every shipped script has to compile. Under lune this is the only check that runs on the whole file.
--   lune run tests/compile.spec
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failed = 0

for _, name in ipairs({ "Visions-hook.lua", "Des-Hood/Des-Hood.lua", "Vanta/Vanta.lua", "Raknet/DesyncResearch.lua", "Raknet/RaknetResearch.lua" }) do
	local ok, err = pcall(luau.load, fs.readFile(name))

	if not ok then
		failed += 1
	end

	print(string.format("%-30s %s", name, ok and "compiles" or ("FAILS: " .. tostring(err):sub(1, 160))))
end

if failed > 0 then
	process.exit(1)
end
