-- PlayerManager.lua
local skynet = require "skynet" 
require "skynet.manager"

local tinsert = table.insert
local tremove = table.remove

local web_service = ...

local player_list = {}
local player_outline_pool = {}

local CMD = {}

local player_seed = 100000

function relogin( name, p )
	
end
--[[addPlayer
	pinfo
		- player_id, 
		- player_name 
		- room_info
			- room_id 
			- room_sn
		- player_ws
		- player_sn
]]
function CMD.addPlayer( pinfo )
	if player_list[ pinfo.player_id ] == nil then
		player_list[ pinfo.player_id ] = pinfo
	end
end

-- 检查用户名是否重复，如不重复返回 player seed id
function CMD.checkPlayerName( name )
	-- for k,p in pairs(player_outline_pool) do
	-- 	if p.player_name == name then
	-- 		relogin( name, p )
	-- 	end
	-- end
	for id,p in pairs(player_list) do
		if p.player_name == name then
			return 1
		end
	end
	player_seed = player_seed + 1
	return player_seed
end

function CMD.delPlayer( player_id )
	local pinfo = player_list[ player_id ]
	tinsert( player_outline_pool, pinfo )
	if #player_outline_pool > 50 then
		player_outline_pool[1] = nil
		tremove( player_outline_pool, 1 )
	end
	player_list[ player_id ] = nil
end

--[[getPlayerSN
	return 0 :offline >0:player_sn
]]
function CMD.getPlayerSN( player_id )
	local pinfo = player_list[ player_id ]
	local sn = 0
	if pinfo then
		sn = pinfo.player_sn
	end
	return sn
end

-- t type: default 0 全体 1 大厅 
function CMD.broadcast( t, pkg )
	for id,p in pairs( player_list ) do
		if t == 0 or ( t == 1 and p.roomid == 0 ) then
			skynet.call( web_service, "lua", "send", p.player_ws, pkg )
		end
	end
end

function CMD.test_1( ... )
	print("aaaaaaaaaa")
end

skynet.start(function(  )
	skynet.dispatch( "lua", function(_,_, command, ...)
		local f = CMD[command]
		local r = f(...)
		if r then
			skynet.ret(skynet.pack(r))
		end
	end)
	skynet.register(".PlayerManager")
end)