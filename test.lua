-- test.lua
local skynet = require "skynet"
local timer = require( "LTimer" )

skynet.start(function( ... )
	-- local t = 1
	local t = skynet.timeout( 3, function( ... )
		print("aaaaaaaaaaa",...)
	end )
	skynet.stoptimer(t)
	local t = skynet.timeout( 3, function( ... )
		print("bbbbbbbbbbb")
	end )
	skynet.stoptimer(t)
	local t = skynet.timeout( 3, function( ... )
		print("vvvvvvvvvvvv")
	end )
	skynet.stoptimer(t)
	local t = skynet.timeout( 5*100, function( ... )
		print("ccccccccccccc")
	end )
end) 