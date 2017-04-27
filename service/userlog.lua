--[[
	logger
		save server runtime logs, save infomation into log file every 5 minutes
		log from skynet.error

		logs retained for 30 days 
]]
local skynet = require "skynet"
require "skynet.manager"

local logtxt = ""
local tmptxt = ""
local lastlogday = 0

function delete_file(day)
	local c = os.execute( "rm -rf logs/"..day.."*" )
	if c == nil or c == false then
		skynet.error( string.format("[LOGINFO] delete day[%s] logs error", day) )
		return 1
	end
	return 0
end

function write_file()
	tmptxt = logtxt
	logtxt = ""

	if tmptxt == "" then
		return
	end
	local cur_time = os.time()
	local tmp = os.date( "%d", cur_time )
	if lastlogday == 0 then
		lastlogday = tmp
	end

	local name = os.date("%Y%m%d%H%M%S", cur_time)
	local file = io.open( "logs/"..name..".log", "a+" )
	file:write( tmptxt )
	file:close()
	tmptxt = ""

	if lastlogday ~= tmp then
		local t = cur_time - 30*24*60*60
		local del_day = os.date("%Y%m%d", t)
		delete_file(del_day)
		lastlogday = tmp
	end
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

function CMD.show()
	return logtxt
end

skynet.start(function()
	skynet.register ".logger"

	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		local r = f(...)
		if r then
			skynet.ret(skynet.pack(r))
		end
	end)

	skynet.fork( function( ... )
		while true do
			skynet.sleep( 100 * 300 )
			write_file()
		end
	end )
end)