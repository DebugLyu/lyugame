-- player.lua

local skynet = require( "skynet" )
local pb = require "protobuf"
local parser = require "parser"
local config = require "config"
local queue = require "skynet.queue"
local cs = queue()

require "errorcode"
require "gameconfig"

player = {}
local CMD = {}
local MSG = require( "player_msg_dispatch" )

function player.__init__()
	-- 玩家基础信息
	player.account = ""
	player.id = 0
	player.name = ""
	player.room_info = {room_id = 0, room_sn = 0}
	player.gold = 0
	player.state = 0
	player.gmlevel = 0
	-- 网络信息
	player.ws_id = 0
	player.ws_service = 0
	player.ws_ip = ""
end

function player:sendPacket( head, tbl )
	local code = MSG.Package( head, tbl )
	if code then

		local lh = string.len( head )
		local lc = string.len( code )
		local send = string.pack( ">Hc"..lh.."c"..lc, lh, head, code )	
		skynet.send( player.ws_service, "lua", "send", player.ws_id, send )
	end
end

function player:loginSuccess( roleinfo, regtype )
	config.Ldump( roleinfo, "player.loginSuccess.roleinfo" )
	-- check seal acctount
	if roleinfo.state == PlayerState.Seal then
		if tonumber(roleinfo.statedate) > os.time() then
			-- seal time
			local toclient = {}
			toclient.result = ErrorCode.ACCOUNT_SEAL
			toclient.id = roleinfo.statedate
			toclient.name = 0
			toclient.gold = 0
			toclient.gmlevel = 0
			self:sendPacket( "Reslogin", toclient )
			return
		else
			local todb = {}
			todb.player_id = roleinfo.id
			todb.state = PlayerState.Normal
			todb.statedate = 0
			skynet.send( ".DBService", "lua", "statePlayer", todb )
		end
	end

	self.id = roleinfo.id
	self.account = roleinfo.account
	self.password = roleinfo.password
	self.name = roleinfo.name
	self.gold = roleinfo.gold
	self.gmlevel = roleinfo.gmlevel

	local toplayermanager = {
		player_id = self.id,
		player_name = self.name,
		player_account = self.account,
		room_info = self.room_info,
		player_sn = skynet.self()
	};
	skynet.send( ".PlayerManager", "lua", "addPlayer", toplayermanager )
	
	local toclient = {}
	toclient.result = 0
	toclient.id = self.id
	toclient.name = self.name
	toclient.gold = self.gold
	toclient.gmlevel = self.gmlevel
	self:sendPacket( "Reslogin", toclient )

	config.Lprint(1, string.format("[PLAYERINFO] player[%d] from ip[%s] loginSuccess", self.id, self.ws_ip))

	if regtype == 2 then
		local infoself = {}
		infoself.player_id = self.id
		infoself.gold = PHONE_REGISTER_GOLD
		infoself.logtype = GoldLog.PHONE_REGISTER
		self:addGold( infoself )
	end
end

function player:login( account, password )
	local tbl = {
		result = 0,
		id = 0,
		name = 0,
		gold = 0,
	}

	local ret = skynet.call( ".DBService", "lua", "UserLogin", account )
	local toclient = {}
	toclient.result = 0
	toclient.id = 0
	toclient.name = 0
	toclient.gold = 0
	toclient.gmlevel = 0
	if ret.result == 0 then
		if ret.roleinfo.password == password then			
			-- 判断是否在线
			local sn = skynet.call( ".PlayerManager", "lua", "getPlayerSN", ret.roleinfo.id )
			if sn == 0 then
				-- 登陆成功
				self:loginSuccess(ret.roleinfo)
			else
				local toother = {}
				toother.ip = self.ws_ip
				skynet.send( sn, "lua", "otherLogin", toother )
				toclient.result = ErrorCode.HAS_ONLINE
			end
		else
			toclient.result = ErrorCode.PASSWORD_ERROR
		end
	else
		-- 登陆失败
		toclient.result = ret.result
	end
	if toclient.result ~= 0 then
		self:sendPacket( "Reslogin", toclient )
	end
end

function player:trade( id, gold )

	local toclient = {}
	toclient.result = 0
	if self.gold < gold then
		toclient.result =  ErrorCode.GOLD_NOT_ENOUGH
		self:sendPacket( "ResTradeGold", toclient )
		return
	end

	local infoself = {}
	infoself.player_id = self.id
	infoself.gold = -gold
	infoself.logtype = GoldLog.USER_TRADE
	infoself.param1 = id

	local retself = self:addGold( infoself )

	if retself == 0 then
		local traget_gold = math.ceil( gold * TRADE_PERCENTAGE )
		local system_gold = gold - traget_gold

		local goldinfo = {}
		goldinfo.player_id = 0
		goldinfo.gold = gold
		goldinfo.logtype = GoldLog.TUIBING_SYSTEM_TRADE_PRE
		goldinfo.param1 = self.id
		goldinfo.param3 = id
		skynet.send( ".DBService", "lua", "PlayerAddGoldLog", goldinfo )

		local info = {}
		info.player_id = id
		info.gold = traget_gold
		info.logtype = GoldLog.USER_TRADE
		info.param1 = self.id
		local ret = skynet.call(".PlayerManager", "lua", "changeGold", info)
		if ret.result == 0 then
			config.Lprint( 1, string.format("[PLAYERINFO] player[%d] transfer gold[%d] to player[%d] got[%d], system got gold[%d]",
				self.id, gold, id, traget_gold, system_gold) )

			if ret.flag == 1 then
				local sn = skynet.call(".PlayerManager", "lua", "getPlayerSN", id)
				if sn > 0 then
					local tootherclient = {}
					tootherclient.player_id = self.id
					tootherclient.gold = gold
					skynet.send( sn, "lua", "gotTrade", tootherclient )
				end
			end
		else
			if ret.result ~= -1 then
				toclient.result = ret.result
			end
			local infoback = {}
			infoback.player_id = self.id
			infoback.gold = gold
			infoback.logtype = GoldLog.USER_TRADE_BACK
			infoback.param1 = id
			self:addGold( infoback )
		end
	else
		toclient.result = retself
	end
	self:sendPacket( "ResTradeGold", toclient )
end
--[[
	info
		player_id
		gold
]]
function player:gotTrade(info)
	local name = skynet.call(".PlayerManager", "lua", "getPlayerNameById", info.player_id)
	if name == 0 then
		config.Lprint(2, string.format("[ERROR] player[%d] gotTrade Check target[%d] Name error!",
			self.id, info.player_id))
		name = ""
	end

	local toclient = {}
	toclient.fromid = info.player_id
	toclient.fromname = name
	toclient.gold = info.gold
	self:sendPacket( "ToTreadeGold", toclient )
end

function player:enterRoom( room_id )
	local toroommanager = {
		room_id = room_id,
		playerinfo = { 
			player_id = self.id, 
			player_sn = skynet.self(),
			player_name = self.name,
		},
	}
	local ret = skynet.call(".RoomManager", "lua", "PlayerEnterRoom", toroommanager)
	
	if ret.result == 0 then
		self.room_info.room_id = ret.room_id
		self.room_info.room_sn = ret.room_sn
	end

	local toclient = {
		result = ret.result,
		roomid = ret.room_id,
	}
	self:sendPacket( "ResEnterRoom", toclient )
	config.Lprint(1, string.format("[PLAYERINFO] player[%d] enter room[%d], result[%d]", 
		self.id, room_id, ret.result ))
end

function player:leaveRoom()
	if self.room_info.room_id == 0 then
		return 
	end
	local toroommanager = {
		room_id = self.room_info.room_id,
		player_id = self.id
	}
	skynet.call( ".RoomManager", "lua", "PlayerLevelRoom", toroommanager)

	config.Lprint(1, string.format("[PLAYERINFO] player[%d] leave room[%d]", 
		self.id, self.room_info.room_id ))

	self.room_info.room_id = 0
	self.room_info.room_sn = 0
end

function player:getGold()
	return self.gold
end

function player:GMAddGold( id, gold, log )
	local toclient = {}
	toclient.result = 0
	if self.gmlevel < GM_ADD_GOLD_LEVEL then
		toclient.result = ErrorCode.PERMISSION_DENIED 
	else
		local gmlog = GMGoldTypeToLog[ log ]
		if gmlog == nil or gmlog == 0 then
			toclient.result = ErrorCode.LOGTYPE_ERROR 
		else
			local info = {}
			info.player_id = id
			info.gold = gold
			info.logtype = gmlog
			info.param1 = self.id
			config.Ldump( info, "player.GMAddGold.info" )

			local sn = skynet.call( ".PlayerManager", "lua", "getPlayerSN", id )
			if sn == 0 then
				-- 不在线直接写数据库
				skynet.call( ".DBService", "lua", "PlayerAddGold", info )
			else
				-- 在线直接添加
				skynet.call( sn, "lua", "addGold", info )
			end
		end
	end
	-- send to player
	self:sendPacket( "ResAddGold", toclient )

	config.Lprint(1, string.format("[GMINFO] GM[%d] add gold[%d] to player[%d], logtype[%d]", 
		self.id, gold, id, log ))
end

--[[
	info: 
		player_id : 0
		gold : -n ~ n
		logtype : gold source 
		param1 : 0
		param2 : ""
		param3 : 0
]]
function player:addGold( info )
	local gold = info.gold 
	if gold < 0 and self.gold < math.abs( gold ) then
		return ErrorCode.GOLD_NOT_ENOUGH
	end
	config.Ldump( info, "player.addGold.info" )

	if self.gold + gold > GLOBAL_MAX_GOLD then
		config.Lprint( 1, string.format("[PLAYERINFO] player[%d] gold more than MaxGold[%d]", self.id, GLOBAL_MAX_GOLD ))
		gold = GLOBAL_MAX_GOLD - self.gold
	end
	local before_gold = self.gold 
	self.gold = self.gold + gold

	local toclient = {}
	toclient.gold = self.gold
	self:sendPacket("ToGoldChange", toclient)

	-- 记录日志
	info.player_id = info.player_id or self.id
	skynet.call( ".DBService", "lua", "PlayerAddGoldLog", info )
	config.Lprint(1, string.format("[PLAYERINFO] player[%d] add gold[%d], add type[%d] before[%d], now[%d]", 
		self.id, gold, info.logtype, before_gold, self.gold ))
	return 0
end

function player:checkGold( gold )
	if self.gold >= gold then
		return 0
	end
	return ErrorCode.GOLD_NOT_ENOUGH
end

function player:reqTuibingInfo()
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end

	local ret = skynet.call( room_sn, "lua", "playerGetInfo", self.id)
end

function player:beBanker( t, gold )
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end

	local ret = 0
	local need = gold 
	if t == 2 then
		need = gold + TuiBingConfig.FAST_BANKER_NEED
	end

	if need > self.gold then
		ret = ErrorCode.GOLD_NOT_ENOUGH
	else
		local toroom = {
			player_id = self.id,
			player_sn = skynet.self(),
			player_name = self.name,
			gold = gold
		}
		ret = skynet.call( room_sn, "lua", "playerBeBanker", t, toroom )
	end
	if ret ~= 0 then
		local toclient = {}
		toclient.result = ret
		self:sendPacket( "ResBeBanker", toclient )
	end
	config.Lprint(1, string.format("[PLAYERINFO] player[%d] use gold[%d] beBanker, result[%d]", 
		self.id, gold, ret))
end

function player:unBanker()
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end

	local ret = skynet.call( room_sn, "lua", "playerUnBanker", self.id )
	config.Lprint(1, string.format("[PLAYERINFO] player[%d] ask for unBanker, result[%d]", self.id, ret))

	local toclient = {}
	toclient.result = ret
	self:sendPacket( "ResTuiBingUnbanker", toclient )
end

function player:leaveBankerQueue( ... )
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end

	local ret = skynet.call( room_sn, "lua", "playerLeaveQueue", self.id )
	if ret ~= 0 then
		local toclient = {}
		toclient.result = ret
		self:sendPacket( "ResTuibingLeaveQueue", toclient )
	end
	config.Lprint( 1, string.format("[PLAYERINFO] player[%d] leaveBankerQueue, result[%d]", 
		self.id, ret))
end
--[[keepBanker 继续坐庄
	iskeep : 0 keep 1 unkeep
]]
function player:keepBanker( iskeep, gold )
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end
	local toroom = {
		iskeep = iskeep,
		player_id = self.id,
		gold = gold,
	}

	if iskeep == 0 then
		if self.gold < gold then
			-- sub money move into game 
			local toclient = {}
			toclient.result = ErrorCode.GOLD_NOT_ENOUGH
			self:sendPacket( "ResKeepBanker", toclient )

			toroom.iskeep = 1
		end
	end

	local ret = skynet.call( room_sn, "lua", "plyaerKeepBanker", toroom )
	config.Lprint( 1, string.format("[PLAYERINFO] player[%d] keepBanker iskeep[%d], result[%d]", 
		self.id, toroom.iskeep, ret))
end

--[[beginTuibing 庄家开始游戏
]]
function player:beginTuibing()
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end
	local ret = skynet.call( room_sn, "lua", "bankerBeginGame" )
end

--[[下注
]]
function player:betTuibing(pos, gold)
	if self.gold < gold then
		return
	end
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end

	local toroom = {}
	toroom.player_id = self.id
	toroom.pos = pos
	toroom.gold = gold
	local ret = skynet.call( room_sn, "lua", "playerBet", toroom )
	config.Lprint( 1, string.format("[PLAYERINFO] player[%d] bet, result[%d]",self.id, ret))
end

function player:getTuibingAllPlayer()
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end
	skynet.call( room_sn, "lua", "playerAllPlayer", self.id )
end

function player:controlTuibing( pos, win )
	if self.gmlevel < GM_ADD_GOLD_LEVEL then
		return -- ErrorCode.PERMISSION_DENIED 
	end
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end
	local toroom = {}
	toroom.player_id = self.id
	toroom.pos = pos
	toroom.win = win
	skynet.send( room_sn, "lua", "gmControlWin", toroom )
end

--[[ 麻将相关

]]
function player:sendMahJong( pai )
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end

	local toroom = {}
	toroom.player_id = self.id
	toroom.mj = pai
	local ret = skynet.call( room_sn, "lua", "", toroom )
	if ret ~= 0 then
		local toplayer = {}
		toplayer.result = ret
		self:sendPacket( "ResMjSendMj", toplayer )
	end
end

--[[
/////////////////////功能相关//////////////////////////

]]

function player:save()
	if self.id == 0 then
		return
	end
	local toDB = {}
	toDB.player_id = self.id
	toDB.player_gold = self.gold
	skynet.send( ".DBService", "lua", "savePlayer", toDB )
end

--[[ 他人登陆，本号被顶掉 
	info
		ip
]]
function player:otherLogin( info )
	config.Lprint( 1, string.format("[PLAYERINFO] player[%d] from[%s] otherLogin!", self.id, info.ip ) )
	local tootherclient = {}
	tootherclient.type = 1
	self:sendPacket( "ToCloseClient", tootherclient )
	CMD.close()
end

--[[ 断开连接 ]]
function player:beforeDisconnect()
	config.Lprint( 1, string.format("[PLAYERINFO] player[%d] Disconnect!", self.id))
	local tootherclient = {}
	tootherclient.type = 2
	self:sendPacket( "ToCloseClient", tootherclient )
	CMD.close()
end

function CMD.init( conf )
	player.__init__()
	player.ws_id = conf.ws_id
	player.ws_service = conf.ws_service
	player.ws_ip = conf.ws_ip
end

function CMD.close()
	skynet.send( ".PlayerManager", "lua", "delPlayer", player.id )

	if player.room_info.room_id ~= 0 then
		player:leaveRoom()
	end

	player:save()
	skynet.timeout(5*100, function( ... )
		skynet.exit()	
	end)
	config.Lprint( 1, string.format("[PLAYERINFO] player[%d] close!", player.id))
end

skynet.start(function()
	-- 注册 protobuf message 
    local t = parser.register("gamebox.proto","lyugame/protocal/")
    skynet.dispatch( "lua", function(_,_, command, ...)
    	-- 注意命令方法 不要跟消息方法 重名，否则将会出错
		local f = CMD[command]
		if f then
			local r = cs( f, ... )
			skynet.ret(skynet.pack(r))
		end
		local cmsg = MSG[ command ]
		if cmsg then
			MSG.MessageDispatch( command, ... )
			-- cs(MSG.MessageDispatch, command, ...)
		end
		local p = player[ command ]
		if p then
			local r = cs( p, player, ... )
			skynet.ret(skynet.pack(r))
		end
	end)
	
	skynet.fork( function( ... )
		while true do
			skynet.sleep( 100 * 600 )
			player:save()
		end
	end )
end)