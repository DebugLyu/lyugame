-- agent.lua
--[[
	agent 用于管理 player实体 和 socket 消息分发等事务 相关事务
]]

local skynet = require( "skynet" )
local role = require( "role" )


--[[
	start:
		param1 : conf 
			client = socket fd, 
]]
local CMD = {}
local net = {}
net.ws_service = ... 
player = role.new()
local dispatch = require("msg_diapatch")

-- param wsid, 
function CMD.start( wsid )
	net.wsid = wsid
end
-- 参数 pinfo { id, name, state, room }
function CMD.playerInit( pinfo )
	player = role.new()
	player:setInfo( pinfo )
	skynet.call( ".PlayerManager", "lua", "delPlayer", player.id_ )
	return player
end

function CMD.close()
	skynet.call( ".PlayerManager", "lua", "delPlayer", player.id_ )
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		local f = CMD[command]
		if f  then 
			local r = f(...)
			if r then
				skynet.ret(skynet.pack(r))
			end
		end
	end)
end)