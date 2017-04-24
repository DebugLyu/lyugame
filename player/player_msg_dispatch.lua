local pb = require "protobuf"
local skynet = require "skynet"
require "skynet.manager"

require "gameconfig"

local MSG = {}
local config = require "config"
-- local pb = ...

function login( pack )
	-- print("pack", type(pack), pack)
	local account = pack.account or ""
	local password = pack.password or ""

	if account == "" then
		return
	end
	player:login( account, password )
end

function register( pack )
	local account = pack.account
	local password = pack.password

	local ret = skynet.call( ".DBService", "lua", "UserRegister", account, password )
	if ret.result ~= 0 then
		local tbl = {}
		tbl.result = ret.result
		player:sendPacket( "ResRegister", tbl )
		config.Lprint(1, string.format("[INFO] register failed, account[%s], result[%d]", account, ret.result))
	else
		player:loginSuccess( ret.roleinfo )
	end
end

function enterroom( pack )
	local roomid = pack.roomid
	player:enterRoom( roomid )
end

function leaveroom( pack )
	player:leaveRoom( roomid )
end

function bebanker( pack )
	local t = pack.type
	local gold = pack.gold
	player:beBanker(t, gold)
end

function unbanker( pack )
	player:unBanker()
end

function keepbanker( pack )
	local iskeep = pack.iskeep
	local gold = pack.gold
	player:keepBanker( iskeep, gold )
end

function bankerbegin( pack )
	player:beginTuibing()
end

function tuibingbet( pack )
	local pos = pack.pos
	local gold = pack.gold
	player:betTuibing(pos, gold)
end

function addgold( pack )
	local gold = pack.gold
	local id = pack.id
	local goldtype = pack.logtype	
	-- local info = {}
	-- info.id = id
	-- info.gold = gold
	-- info.log = GoldLog.GM_ADD
	-- info.param1 = 0
	-- info.param2 = ""
	-- player:addGold( info )
	player:GMAddGold( id, gold, goldtype )
end

function leavequeue()
	player:leaveBankerQueue()
end

function sendmahjong()
	local mj = pack.pai
	player:sendMahJong( mj )
end

function tuibinginfo(pack)
	player:reqTuibingInfo()
end

function tuibingallplayer( pack )
	player:getTuibingAllPlayer()
end

function getplayername( pack )
	local index = pack.index
	local id = pack.id

	local toplayer = {}
	toplayer.result = 0
	toplayer.id = id
	toplayer.index = index
	toplayer.name = ""
	local ret = skynet.call( ".PlayerManager", "lua", "getPlayerNameById", id )
	if type(ret) == "number" then
		toplayer.result = ret
	elseif type( ret ) == "string" then
		toplayer.name = ret
	else
		config.Lprint( 2, string.format("[ERROR] packet Error, getplayername check error userid[%d]", id ))
		return
	end
	player:sendPacket( "ResCheckName", toplayer );
end

function tradegold( pack )
	local target = pack.toid
	local gold = pack.gold

	player:trade( target, gold )
end

MSG = {
	["Reqlogin"] = login,
	["ReqRegister"] = register,
	["ReqEnterRoom"] = enterroom,
	["ReqLeaveRoom"] = leaveroom,
	["ReqCheckName"] = getplayername,
	-- 交互
	["ReqTradeGold"] = tradegold,
	-- 推饼相关
	["ReqBeBanker"] = bebanker,
	["ReqKeepBanker"] = keepbanker,
	["ReqTuiBingBet"] = tuibingbet,
	["ReqTuiBingBegin"] = bankerbegin,
	["ReqAddGold"] = addgold,
	["ReqTuiBingUnbanker"] = unbanker,
	["ReqTuibingLeaveQueue"] = leavequeue,
	["ReqTuiBingInfo"] = tuibinginfo,
	["ReqTuiBingAllPlayer"] = tuibingallplayer,
	-- 麻将相关
	["ReqMjSendMj"] = sendmahjong,
}

function MSG.MessageDispatch( head, msgbody )
	local func = MSG[head]
	if func then
		local a,b,c = pcall( pb.decode, head, msgbody )
		local code = pb.decode( "tutorial."..head, msgbody )
		if code then
			func( code )
		end
	else
		config.Lprint(2, string.format("[ERROR] MSG Not define. head[%s]", head))
	end
end

function MSG.Package( head, tbl )
	local code = pb.encode("tutorial." .. head, tbl)
	if code then
		return code
	end
	return nil
end

return MSG