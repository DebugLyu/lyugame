-- room.lua
local skynet = require("skynet")
local seat = {
	id = 0,
	playerid = 0,
	islocked = false,
	isready = false,	
},



local room = {
	seedid = 0,
	player_list = {},

	seat_list = {},
}
room.name, room.type = ...

local CMD = {}

function CMD.start( seedid )
	room.seedid = seedid

	for i=1,8 do
		local seat_ = {}
		setmetatable(seat_, { __index = seat })
		seat_.id = i
		room.seat_list[i] = seat_
	end
end

function getFreeSeat()
	for i=1,8 do
		local seat_ = room.seat_list[i]
		if seat_.islocked == false and seat_.playerid == 0 then
			return i
		end
	end
	return 0
end

function CMD.addPlayer( pid )
	local seat_id = getFreeSeat()
	if seat_id == 0 then
		return 1
	end
	room.player_list[ pid ] = { seat_id, pid }
end

skynet.start( function( ... )
	skynet.dispatch( function( _,_,commond, ... )
		local f = CMD[ common ]
		if f then
			local r = f(...)
			if r  then
				skynet.ret( skynet.pack( r ) )
			end
		end
	end )
end )