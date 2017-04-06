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

local room_list = {}

local CMD = {}

--[[ enter room 
	param tbl need  
		room_id
		playerinfo
			- player_id
			- player_ws
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
	room_list[room.id] = room 

	skynet.send(tuibing, "lua", "gameStart")
	return 1
end

function CMD.test( ... )
	print("RoomManager test")
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