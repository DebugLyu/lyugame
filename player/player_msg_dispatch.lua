local pb = require "protobuf"
local skynet = require "skynet"
require "skynet.manager"

local md5 = require "md5"
require "gameconfig"

local httpc = require "http.httpc"
local dns = require "dns"

local MSG = {}
local config = require "config"

local phone_register = {
	phone = 0,
	check = 0,
}
function login( pack )
	-- print("pack", type(pack), pack)
	local account = pack.account or ""
	local password = pack.password or ""
	password = md5.sumhexa( password )

	if account == "" then
		return
	end
	player:login( account, password )
end

function registerToDb( account, password )
	password = md5.sumhexa( password )
	local ret = skynet.call( ".DBService", "lua", "UserRegister", account, password )
	if ret.result ~= 0 then
		local tbl = {}
		tbl.result = ret.result
		player:sendPacket( "ResRegister", tbl )
		config.Lprint(1, string.format("[INFO] register failed, account[%s], result[%d]", account, tbl.result))
	else
		player:loginSuccess( ret.roleinfo )
	end
end

function register( pack )
	local account = pack.account
	local password = pack.password
	registerToDb( account, password )
end

function registerphone( pack )
	local phonenum = pack.phonenum
	local password = pack.password
	local checknum = pack.checknum
	for i, v in pairs(phone_register)do
		print(i,v)
	end
	if phone_register.phone ~= phonenum or phone_register.check ~= checknum then
		local tbl = {}
		tbl.result = ErrorCode.PHONE_CHECK_ERROR
		config.Lprint(1, string.format("[INFO] register failed, account[%s], result[%d]", phonenum, tbl.result))
		player:sendPacket( "ResRegister", tbl )
		return 
	end

	registerToDb( phonenum, password )
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

function sendwin( pack )
	local pos = pack.pos
	local win = pack.win
	player:controlTuibing( pos, win )
end

function sendcheck( pack )
	local phonenum = pack.phonenum

	httpc.dns()	-- set dns server
	httpc.timeout = 300	-- set timeout 1 second

	local respheader = {}
	local checknum = math.random( 100000, 999999 )
	local checkstr = "/sms/send?mobile=".. phonenum .."&tpl_id=33286&tpl_value=%2523code%2523%253d".. checknum .."&dtype=&key=b498928e0a34704362c9010ec2ad3360"
	print( checkstr )
	-- local status, body = httpc.get("v.juhe.cn/sms", checkstr, respheader)
	local status, body = httpc.get("v.juhe.cn", checkstr, respheader)
	print("[header] =====>")
	for k,v in pairs(respheader) do
		print(k,v)
	end
	print("[body] =====>", status)
	print(body)
	
	
	phone_register.phone = phonenum
	phone_register.check = tostring(checknum)
end

MSG = {
	["Reqlogin"] = login,
	["ReqRegister"] = register,
	["ReqEnterRoom"] = enterroom,
	["ReqLeaveRoom"] = leaveroom,
	["ReqCheckName"] = getplayername,
	["ReqSendCheck"] = sendcheck,
	["ReqRegisterPhone"] = registerphone,
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
	["ReqSendWin"] = sendwin,
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