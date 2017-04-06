-- test.lua
local skynet = require "skynet"

function a()
	while true do
		skynet.sleep(100)
		skynet.error("ccccccc")
	end
end

skynet.start(function( ... )
	local t = 1
	skynet.fork(function( ... )
		while true do
		skynet.error("t = " .. t)
		skynet.sleep(100)
		end
	end)
	a()
end) 