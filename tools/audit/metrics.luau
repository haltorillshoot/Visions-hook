local fs = require("@lune/fs")
local luau = require("@lune/luau")
local base = ""
for _, name in ipairs({ "Visions-hook.lua", "Des-Hood/Des-Hood.lua", "Vanta/Vanta.lua", "Visions-hook-menu.lua", "Raknet/DesyncResearch.lua", "Raknet/RaknetResearch.lua" }) do
	local source = fs.readFile(base .. name)
	local best, bytecode = math.huge, nil
	for _ = 1, 3 do
		local start = os.clock()
		bytecode = luau.compile(source)
		best = math.min(best, os.clock() - start)
	end
	local ok, err = pcall(luau.load, source)
	print(string.format("%-28s src=%8.1f KB  bytecode=%8.1f KB  compile=%6.0f ms  loads=%s%s", name, #source / 1024, #bytecode / 1024, best * 1000, tostring(ok), ok and "" or (" " .. tostring(err):sub(1, 80))))
end
