-- Lcall

local skynet = require "skynet"
require "skynet.manager"

local OutTime = 3 * 100

skynet.start(function(  )
	skynet.dispatch( "lua", function(_,_, session, func, ...  )
        local callback = false
        local timer = skynet.timeout( OutTime, function()
            if not callback then
                callback = true
                skynet.ret(skynet.pack( -1 ))
            end
        end)
        local ret = skynet.call( session, "lua", func, ... )
        if not callback then
            callback = true
            skynet.stoptimer(timer)
            skynet.ret(skynet.pack(ret))
        end
	end)

    skynet.register(".Lcall")
end)