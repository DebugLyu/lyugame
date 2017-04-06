local skynet = require( "skynet" )

local Timer = {}
local timer_seed = 100
local timer_func = {}

function Timer:registerTimer( time, func )
	timer_seed = timer_seed + 1
	skynet.timeout( time * 100, function( ... )
		if timer_func[ timer_seed ] then
			func()
		end
	end )
	timer_func[ timer_seed ] = true
	return timer_seed
end

function Timer:unregisterTimer( key )
	timer_func[key] = false
end

return Timer