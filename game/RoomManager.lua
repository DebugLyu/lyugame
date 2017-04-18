-- RoomManager.lua
-- room: 
--		id = game seed id -- tuibing has const id
--		ws = skynet.id
--		type = game type

local skynet = require("skynet")
local config = require( "config" )
require "skynet.manager"
require "gameconfig"
require "errorcode"

local seedid = config.ROOM_SEED_BEGIN

local RoomState = {
	Close = 0,
	Openning = 1,
	Running = 2,
	Closing = 3,
}
-- local room = {}
-- room.id
-- room.sn
-- room.type
-- room.state
local room_list = {}

local CMD = {}

--[[ enter room 
	param tbl need  
		room_id
		playerinfo
			- player_id
			- player_name
			- player_sn
 	return tbl need
		result  - 0 success 
		room_id 
		room_sn
--]]
function CMD.PlayerEnterRoom( tbl ) -- tbl room_id
	local room = room_list[tbl.room_id]
	local tosource = {}
	tosource.result = 0
	tosource.room_id = tbl.room_id
	tosource.room_sn = 0
	if room then
		local ret = skynet.call(room.sn, "lua", "addPlayer", tbl.playerinfo )
		tosource.result = ret
		tosource.room_sn = room.sn
	else
		tosource.result = ErrorCode.ROOM_NOT_FOUND
	end
	
	return tosource
end

--[[Leave room 
	param tbl
		room_id
		player_id
	return 
		result
]]
function CMD.PlayerLevelRoom( tbl )
	local room = room_list[tbl.room_id]
	local tosource = {}
	if room then
		skynet.send( room.sn, "lua", "delPlayer", tbl.player_id )
		tosource.result = 0
	else
		tosource.result = ErrorCode.ROOM_NOT_FOUND
	end
	return tosource
end

function CMD.CreateTuiBing()
	local tuibing = skynet.newservice("tuibing")
	
	local room = {}
	room.id = TuiBingConfig.ROOM_ID
	room.sn = tuibing
	room.type = GameType.TUIBING
	room.state = RoomState.Openning
	room_list[room.id] = room 

	local res = skynet.call(tuibing, "lua", "gameStart")
	if res == 0 then
		room_list[room.id].state = RoomState.Running
	end
	return 1
end

function CMD.test( ... )
	print("RoomManager test")
end


function exit(  )
	local topmgr = {}
	topmgr.from = 1
	skynet.call( ".PlayerManager", "lua", "ServerCloseBack", topmgr )
	skynet.timeout(5*100, function( ... )
		skynet.exit()	
	end)
end

function checkCloseRoom()
	local noerror = true
	for room_id, room_info in pairs(room_list) do
		if room_info.state ~= RoomState.Close then
			noerror = false
		end
	end
	if noerror then
		exit()
	end
end
--[[
	info 
		room_id
]]
function CMD.RoomCloseBack( info )
	local room_info = room_list[ info.room_id ]
	if room_info then
		room_info.state = RoomState.Close
	end
	checkCloseRoom()
end

function CMD.close()
	for room_id, room_info in pairs(room_list) do
		local ok = skynet.call( room_info.sn, "lua", "close" )
		if ok == true then
			skynet.kill( room_info.sn )
			room_info.state = RoomState.Close
		else
			room_info.state = RoomState.Closing
		end
	end
	checkCloseRoom()
end

skynet.start(function(  )
	skynet.dispatch( "lua", function(_,_, command, ...)
		local f = CMD[command]
		local r = f(...)
		if r then
			skynet.ret(skynet.pack(r))
		end
	end)
	skynet.register(".RoomManager")
end)