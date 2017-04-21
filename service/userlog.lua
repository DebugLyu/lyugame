--[[
	logger
		save server runtime logs, save infomation into log file every 5 minutes
		log from skynet.error
]]
local skynet = require "skynet"
require "skynet.manager"

local logtxt = ""
local tmptxt = ""

function write_file()
	tmptxt = logtxt
	logtxt = ""

	if tmptxt == "" then
		return
	end

	local name = os.date("%Y%m%d%H%M%S", os.time())
	local file = io.open( "logs/"..name..".log", "a+" )
	file:write( tmptxt )
	file:close()
	tmptxt = ""
end

skynet.register_protocol {
	name = "text",
	id = skynet.PTYPE_TEXT,
	unpack = skynet.tostring,
	dispatch = function(_, address, msg)
		local str = string.format( "[%s(%08x)]: %s", os.date("%Y-%m-%d %H:%M:%S", os.time()), address, msg);
		print( str )
		logtxt = logtxt .. str .. "\n"
	end
}

skynet.register_protocol {
	name = "SYSTEM",
	id = skynet.PTYPE_SYSTEM,
	unpack = function(...) return ... end,
	dispatch = function()
		-- reopen signal
		print("SIGHUP")
	end
}

local CMD = {}

function CMD.flush( ... )
	write_file()
end

skynet.start(function()
	skynet.register ".logger"

	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)

	skynet.fork( function( ... )
		while true do
			skynet.sleep( 100 * 300 )
			write_file()
		end
	end )
end)