-- player.lua

local skynet = require( "skynet" )
local pb = require "protobuf"
local parser = require "parser"
local config = require "config"

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
	-- 网络信息
	player.ws_id = 0
	player.ws_service = 0
end

function player:sendPacket( head, tbl )
	config.Ldump( tbl, "Send packet ["..head.."]" )
	local code = MSG.Package( head, tbl )
	if code then
		local send = string.pack( ">H", string.len(head) ) .. head .. code	
		skynet.send( player.ws_service, "lua", "send", player.ws_id, send )
	end
end

function player:loginSuccess( roleinfo )
	config.Ldump( roleinfo, "roleinfo" )
	self.id = roleinfo.id
	self.name = roleinfo.name
	self.account = roleinfo.account
	self.id = roleinfo.id
	self.name = roleinfo.name
	self.gold = roleinfo.gold
	local toplayermanager = {
		player_id = self.id,
		player_name = self.name,
		room_info = self.room_info,
		player_ws = self.ws_id,
		player_sn = skynet.self()
	};
	skynet.send( ".PlayerManager", "lua", "addPlayer", toplayermanager )
	local toclient = {}
	toclient.result = 0
	toclient.id = self.id
	toclient.name = self.name
	toclient.gold = self.gold
	self:sendPacket( "Reslogin", toclient )
end

function player:login( account, password )
	local tbl = {
		result = 0,
		id = 0,
		name = 0,
		gold = 0,
	}
	local ret = skynet.call( ".DBService", "lua", "UserLogin", account )
	config.Ldump( ret, "roleinfo ret" )
	local toclient = {}
	toclient.result = 0
	toclient.id = 0
	toclient.name = 0
	toclient.gold = 0
	if ret.result == 0 then
		if ret.roleinfo.password == password then
			-- 判断是否在线
			local sn = skynet.call( ".PlayerManager", "lua", "getPlayerSN", ret.id )
			if sn == 0 then
				-- 登陆成功
				self:loginSuccess(ret.roleinfo)
			else
				skynet.send( sn, "lua", "otherLogin" )
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

function player:enterRoom( room_id )
	local toroommanager = {
		room_id = room_id,
		playerinfo = { 
			player_id = self.id, 
			player_ws = self.ws_id, 
			player_sn = skynet.self() 
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
end

function player:leaveRoom()
	local toroommanager = {
		room_id = self.room_info.room_id,
		player_id = self.id
	}
	skynet.call( ".RoomManager", "lua", "PlayerLevelRoom", toroommanager)
	self.room_info.room_id = 0
	self.room_info.room_sn = 0
end

function player:getGold()
	return self.gold
end
--[[
	addGold param info 
	num : -n ~ n
	log : gold source 
]]
function player:addGold( info )
	local num = info.num 
	if num < 0 and self.gold < num then
		return ErrorCode.GOLD_NOT_ENOUGH
	end

	self.gold = self.gold + info.num

	local toclient = {}
	toclient.gold = self.gold
	self:sendPacket("ToGoldChange", toclient)
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

function player:beBanker( t )
	local room_sn = self.room_info.room_sn
	
	if room_sn == 0 then
		return
	end
	local toroom = {
		player_id = self.id,
		player_ws = self.ws_id,
		player_sn = skynet.self(),
		player_name = self.name,
	}
	local ret = skynet.call( room_sn, "lua", "playerBeBanker", t, toroom )
	if ret ~= 0 then
		local toclient = {}
		toclient.result = ret
		self:sendPacket( "ResBeBanker", toclient )
	end
end

function player:unBanker()
	local room_sn = self.room_info.room_sn
	if room_sn == 0 then
		return
	end

	local ret = skynet.call( room_sn, "lua", "playerUnBanker", self.id )
	if ret ~= 0 then
		local toclient = {}
		toclient.result = ret
		self:sendPacket( "ResTuiBingUnbanker", toclient )
	end
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
end
--[[keepBanker 继续坐庄

]]
function player:keepBanker( iskeep, gold )
	local room_sn = self.room_info.room_sn

	local toroom = {
		iskeep = iskeep,
		player_id = self.id,
		gold = gold,
	}

	if iskeep == 0 then
		if self.gold >= gold then
			self.gold = self.gold - gold
		else
			local toclient = {}
			toclient.result = ErrorCode.GOLD_NOT_ENOUGH
			self:sendPacket( "ResKeepBanker", toclient )
			toroom.iskeep = 1
		end
	end
	local ret = skynet.call( room_sn, "lua", "KeepTuiBingBanker", toroom )
end

--[[beginTuibing 庄家开始游戏
]]
function player:beginTuibing()
	local room_sn = self.room_info.room_sn
	local ret = skynet.call( room_sn, "lua", "bankerBeginGame" )
end

--[[下注
]]
function player:betTuibing(pos, gold)
	if self.gold < gold then
		return
	end
	local room_sn = self.room_info.room_sn
	local toroom = {}
	toroom.player_id = self.id
	toroom.pos = pos
	toroom.gold = gold
	local ret = skynet.call( room_sn, "lua", "playerBet", toroom )
	if ret == 0 then
		local info = {}
		info.num = -gold
		info.log = GoldLog.TUIBONG_BET
		self:addGold( info )
	end
end
--[[ 麻将相关

]]
function player:sendMahJong( pai )
	local room_sn = self.room_info.room_sn
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

function player:save()
	local toDB = {}
	toDB.player_id = self.id
	toDB.player_gold = self.gold
	skynet.send( ".DBService", "lua", "savePlayer", toDB )
end

--[[ 他人登陆，本号被顶掉 ]]
function player:otherLogin()
	local tootherclient = {}
	tootherclient.type = 1
	self:sendPacket( "ToCloseClient", tootherclient )
	CMD.close()
end

function CMD.init( conf )
	player.__init__()
	player.ws_id = conf.ws_id
	player.ws_service = conf.ws_service
end

function CMD.close()
	skynet.error("Player end", player.id )
	skynet.send( ".PlayerManager", "lua", "delPlayer", player.id )

	if player.room_info.room_id ~= 0 then
		local toroommanager = {}
		toroommanager.player_id = player.id
		toroommanager.room_id = player.room_info.room_id
		skynet.call( ".RoomManager", "lua", "PlayerLevelRoom", toroommanager )
	end

	player:save()
	skynet.timeout(5*100, function( ... )
		skynet.exit()	
	end)
end

skynet.start(function()
	-- 注册 protobuf message 
    local t = parser.register("gamebox.proto","lyugame/protocal/")
    skynet.dispatch( "lua", function(_,_, command, ...)
    	-- 注意命令方法 不要跟消息方法 重名，否则将会出错
		local f = CMD[command]
		if f then
			skynet.ret(skynet.pack(f(...)))
		end
		local cmsg = MSG[ command ]
		if cmsg then
			MSG.MessageDispatch( command, ... )
		end
		local p = player[ command ]
		if p then
			skynet.ret(skynet.pack(p(player, ... )))
		end
	end)
	
	skynet.fork( function( ... )
		while true do
			skynet.sleep( 100 * 600 )
			player:save()
		end
	end )
end)