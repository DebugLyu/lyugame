-- tuibing.lua
local skynet = require "skynet"
local config = require "config"

require "functions"
require "gameconfig"
require "errorcode"

local talbe_insert = table.insert
local table_remove = table.remove

-- player : player_id player_sn player_gold
local player_list = {}
local game_state_timer = 0
local majiang = {0,1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8,9}

local TuiBingState = {
	Stop = 0, -- 未初始化
	Begin = 1, -- 新游戏开始
	Begin_Check_Begin = 2, -- 询问是否开始游戏
	Begin_Check_Keep = 3, -- 询问是否续庄

	Ready = 4, -- 准备好可以押注
	WaitOpen = 5, -- 等待开牌
	Openning = 6, -- 开牌阶段
	Reward= 7, -- 发放奖励

	Close = 8, -- 服务器关闭
}

local PlayerState = {
	Natural = 0, -- 正常
	NotInRoom = 1, -- 不在房间
	OffLine = 2, -- 离线
	UnBanker = 3, -- 下庄
}

local TuiBing = {
	room_id = TuiBingConfig.ROOM_ID,
	game_serial = 0,
	-- player_id, player_sn, player_name, gold 
	banker_list = {}, 		-- 上庄队列
	-- player_id, player_sn, player_name, gold 
	fast_banker_list = {},	-- 优先上庄队列
	state = TuiBingState.Unknow,
	banker = {
		player_id = 0, 
		player_sn = 0, 
		player_name = "", 
		banker_times = 0,
		banker_gold = 0,
		banker_state = PlayerState.Unknow,
	},

	bet_info = { -- 1 南 2 天 3 北
		[1] = {}, 	-- 内容 key = player_id, value = gold
		[2] = {},
		[3] = {},
	},

	result = {[1]={0,0},[2]={0,0},[3]={0,0},[4]={0,0}},
}

function TuiBing:initGame()
	self.result = {[1]={0,0},[2]={0,0},[3]={0,0},[4]={0,0}}
	self.bet_info = { [1] = {}, [2] = {}, [3] = {},}
end

function TuiBing:initBanker()
	self.banker = {
		player_id = 0, 
		player_sn = 0, 
		player_name = "", 
		banker_times = 0,
		banker_gold = 0,
		banker_state = PlayerState.Unknow,
	}
end

function TuiBing:gameStart()
	math.randomseed( os.time() )
	self.running_time_ = 1
	self.state = TuiBingState.Stop
	skynet.fork(function( ... )
		while true do
			skynet.sleep( 100 ) -- 100 1s
			self.running_time_ = self.running_time_ + 1
			-- self:update()
			-- config.Lprint( 1, "TuiBing GameState :", self.state )
		end
	end)
	return 0
	-- self.GameBegin()
end

-- 通知客户端游戏状态
function TuiBing:sendGameState( sn )
	local toclient = {}
	toclient.state = self.state
	if sn then
		self:sendToPlayer( sn, "ToTuiBingGameState", toclient )
	else
		self:broatcast("ToTuiBingGameState", toclient)
	end
end

-- 找到一个庄家
function TuiBing:findBanker()
	-- 优先上庄队列
	local p = self.fast_banker_list[1]
	if p then
		self.fast_banker_list[1] = nil
		table_remove( self.fast_banker_list, 1 )
		return p
	end
	-- 普通上庄队列
	p = self.banker_list[1]
	if p then
		self.banker_list[1] = nil
		table_remove( self.banker_list, 1 )
		return p
	end
	return nil
end

function TuiBing:changeBanker()
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d] changeBanker, old banker[%d]", 
		self.room_id, self.banker.player_id) )
	while true do
		local p = self:findBanker()
		if p then
			self:BeBanker( p )
			return
		else
			break
		end
	end
	self:initBanker()
end

--[[
	info
		player_id
		gold
		logtype
		param1
		param2
		param3
]]
local function toAddGold( info )
	local allinfo = {}
	allinfo.player_id = info.player_id
	allinfo.gold = info.gold
	allinfo.logtype = info.logtype
	allinfo.param1 = info.param1 or 0
	allinfo.param2 = info.param2 or ""
	allinfo.param3 = info.param3 or 0

	-- 先查询房间数据
	local player_info = player_list[allinfo.player_id]
	if player_info then
		config.Ldump( allinfo, "TuiBing.toAddGold.RoomPlayer")
		return skynet.call( player_info.player_sn, "lua", "addGold", allinfo )
	end
	-- 询问 PlayerManager
	local ret = skynet.call( ".PlayerManager", "lua", "changeGold", allinfo )
	return ret
end

local function toAskBankerBegin( sn )
	-- print(debug.traceback())
	local toclient = {}
	skynet.call( sn, "lua", "sendPacket", "ToBankerBegin", toclient)
end

function TuiBing:sendBankerInfo( sn )
	local toclient = {}
	toclient.name = self.banker.player_name
	toclient.gold = self.banker.banker_gold
	toclient.id = self.banker.player_id
	toclient.times = self.banker.banker_times
	if sn then
		self:sendToPlayer( sn, "ToTuibingBankerInfo",toclient )
	else
		self:broatcast("ToTuibingBankerInfo",toclient)
	end
end

function TuiBing:unBebanker()
	if self.banker.player_id ~= 0 then
		config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] player[%d] unBebanker, send back gold[%d]",
			self.room_id, self.game_serial, self.banker.player_id, self.banker.banker_gold) )

		local goldinfo = {}
		goldinfo.player_id = self.banker.player_id
		goldinfo.gold = self.banker.banker_gold
		goldinfo.logtype = GoldLog.BANKER_BACK
		goldinfo.param3 = self.game_serial

		toAddGold( goldinfo )

		self:changeBanker()
		self:GameBegin()
	end
end

function TuiBing:GameClose()
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d] state Close",self.room_id) )

	self:unBebanker()
	for id,info in pairs(player_list) do
		local toroommanager = {
			room_id = self.room_id,
			player_id = id
		}
		skynet.call( ".RoomManager", "lua", "PlayerLevelRoom", toroommanager)
	end

	local tormgr = {}
	tormgr.room_id = self.room_id
	skynet.call( ".RoomManager", "lua", "RoomCloseBack", tormgr)
end

function TuiBing:GameBegin()
	-- self.running_time_ = 0
	if self.state == TuiBingState.Close then
		self:GameClose()
	end

	self.state = TuiBingState.Begin
	skynet.stoptimer( game_state_timer )

	if self.banker.player_id == 0 then
		self:changeBanker()
	end

	if self.banker.player_id == 0 then
		self.state = TuiBingState.Stop
		self:sendGameState()
		config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d] No Banker, Game stop", 
			self.room_id) )
		return
	end
	
	self.game_serial = os.time()

	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] state Begin, Banker[%d], state[%d], Bank Times[%d]",
		self.room_id, self.game_serial, self.banker.player_id, self.banker.banker_state, self.banker.banker_times) )

	self:initGame()

	-- 判断 坐庄次数
	if self.banker.banker_times < TuiBingConfig.BANKER_LIMIT_TIMES then
		self.banker.banker_times = self.banker.banker_times + 1
		-- 判断 庄家状态
		if self.banker.banker_state == PlayerState.Natural then
			self:sendBankerInfo()
			-- 判断 庄家剩余金币
			if self.banker.banker_gold < TuiBingConfig.BANKER_LESS_GOLD then
				local tobanker = {}
				skynet.call( self.banker.player_sn, "lua", "sendPacket", "ToKeepBanker", tobanker )
				self.state = TuiBingState.Begin_Check_Keep
				self:sendGameState()
			else
				local toclient = {}
				toAskBankerBegin( self.banker.player_sn )
				self.state = TuiBingState.Begin_Check_Begin
				self:sendGameState()
			end
		else
			-- 下庄处理
			self:unBebanker()
			return
		end
	else
		-- 下庄处理
		self:unBebanker()
		return;
	end

	local wait_time = TuiBingConfig.WAIT_BEGIN
	if self.state == TuiBingState.Begin_Check_Keep then
		wait_time = TuiBingConfig.WAIT_KEEP
	end
	
	game_state_timer = skynet.timeout( wait_time*100, function()
		if self.state == TuiBingState.Begin_Check_Begin then
			self:GameReady()
		elseif self.state == TuiBingState.Begin_Check_Keep then
			self:unBebanker()
		else 
			self:initBanker()
			self:initGame()
			self.state = TuiBingState.Unknow
		end
	end )
end

function TuiBing:GameReady()
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] state Ready, Banker[%d], Gold[%d]", 
		self.room_id, self.game_serial, self.banker.player_id, self.banker.banker_gold) )
	
	self.state = TuiBingState.Ready
	skynet.stoptimer(game_state_timer)
	self:sendGameState()
	game_state_timer = skynet.timeout( TuiBingConfig.WAIT_BET*100, function( ... )
		self:GameWaitOpen()
	end )
end

function TuiBing:GameWaitOpen()
	self.state = TuiBingState.WaitOpen
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] state WaitOpen", self.room_id, self.game_serial) )
	skynet.stoptimer(game_state_timer)
	self:sendGameState()

	game_state_timer = skynet.timeout( TuiBingConfig.WAIT_OPEN*100, function( ... )
		self:GameDeal()
	end )
end

local function getMajiang()
	local mj = clone( majiang )
	
	local function randomTbl( tbl )
		local i = math.random(1, #tbl)
		local n = tbl[ i ]
		table_remove( tbl, i )
		return n
	end
	local banker = { randomTbl(mj), randomTbl(mj) }
	local sky = { randomTbl(mj), randomTbl(mj) }
	local south = { randomTbl(mj), randomTbl(mj) }
	local north = { randomTbl(mj), randomTbl(mj) }
	return {banker, south, sky, north}
end

function TuiBing:GameDeal()
	self.state = TuiBingState.Openning
	self:sendGameState()
	skynet.stoptimer(game_state_timer)
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] state Deal, south[%d] sky[%d] north[%d]", 
		self.room_id, self.game_serial, self:getBetTotalGold(1),self:getBetTotalGold(2),self:getBetTotalGold(3)) )

	self.result = getMajiang()
	config.Ldump( self.result, "TuiBing.GameDeal.result" )

	local toclient = {}
	toclient.majiangs = {}
	for i, v in ipairs( self.result )do
		local m = {}
		m.majiang1 = v[1]
		m.majiang2 = v[2]
		talbe_insert( toclient.majiangs, m )
	end
	toclient.dice1 = math.random( 1, 6 )
	toclient.dice2 = math.random( 1, 6 )
	self:broatcast( "ToDealMajiang", toclient )

	game_state_timer = skynet.timeout( TuiBingConfig.WAIT_OPENED*100, function( ... )
		self:GameReward()
	end)
end

local function systemPreLog( id, pos, gold )
	local goldinfo = {}
	goldinfo.player_id = 0
	goldinfo.gold = gold
	goldinfo.logtype = GoldLog.TUIBING_SYSTEM_PRE
	goldinfo.param1 = id
	goldinfo.param2 = tostring(pos)
	goldinfo.param3 = self.game_serial

	skynet.call( ".DBService", "lua", "PlayerAddGoldLog", info )
end

function TuiBing:GameReward()
	self.state = TuiBingState.Reward
	skynet.stoptimer(game_state_timer)
	self:sendGameState()
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] state Reward", 
		self.room_id, self.game_serial) )

	local function isdouble( tbl )
		local double = false
		if tbl[1] == tbl[2] then
			double = true
		end
		return double, tbl[1]
	end

	local function banker_win( pos )
		local infotbl = self.bet_info[ pos ]
		local gold_count = 0
		if infotbl then
			for player_id,gold in pairs(infotbl) do
				gold_count = gold_count + gold
			end
		end
		if gold_count > 0 then
			local banker_reward = math.ceil(gold_count * TuiBingConfig.PERCENTAGE)
			local system_reward = gold_count - banker_reward
			self.banker.banker_gold = self.banker.banker_gold + system_reward

			systemPreLog( self.banker.player_id, system_reward, 0 )
		end
		return 0
	end
	local function pos_win( pos ) -- pos 1 南 2 天 3 北
		local infotbl = self.bet_info[ pos ]
		local gold_count = 0
		if infotbl then
			for player_id,gold in pairs(infotbl) do
				gold_count = gold_count + gold
			end
		end
		if gold_count > 0 then
			self.banker.banker_gold = self.banker.banker_gold - gold_count
		end 
		return 1
	end

	local banker = self.result[1]
	local is_double_b, num_b = isdouble(banker)	

	local function compare( pos )	
		local other = self.result[ pos + 1 ]
		local is_double_o, num_o = isdouble(other)	
		if (not is_double_b) and (not is_double_o) then
			-- 双方都不是对儿
			num_b = ( banker[1] + banker[2] ) % 10
			num_o = ( other[1] + other[2] ) % 10
			if num_b >= num_o then
				-- 庄家赢
				return banker_win( pos )
			else
				-- 玩家赢
				return pos_win( pos )
			end
		elseif (is_double_b) and (not is_double_o) then
			-- 庄家 对儿
			-- 庄家赢
			return banker_win( pos )
		elseif (not is_double_b) and (is_double_o) then
			-- 非庄家 对儿
			-- 玩家赢
			return pos_win( pos )
		elseif ( is_double_b ) and ( is_double_o ) then
			-- 都是对儿
			if num_b == 0 then
				-- 庄家赢
				return banker_win( pos )
			elseif num_o == 0 then
				-- 玩家赢
				return pos_win( pos )
			else
				if num_b >= num_o then
					-- 庄家赢
					return banker_win( pos )
				else
					-- 玩家赢
					return pos_win( pos )
				end
			end
		end
	end
	-- 0 庄赢 1玩家赢
	local list = {compare( 1 ), compare( 2 ), compare( 3 )}
	local toclient = {}
	toclient.iswiner = list

	toclient.posgold = {0,0,0}
	for player_id, player_info in pairs( player_list ) do
		local gold_count = 0
		for pos=1, 3 do
			local infotbl = self.bet_info[ pos ]
			local iswin = list[ pos ]
			if iswin == 1 then
				local gold = infotbl[ player_id ]
				if gold then
					local win_gold = math.ceil(gold * 2 * TuiBingConfig.PERCENTAGE)
					local system_reward = gold*2 - win_gold
					toclient.posgold[ pos ] = win_gold
					local goldinfo = {}
					goldinfo.player_id = player_id
					goldinfo.gold = win_gold
					goldinfo.logtype = GoldLog.TUIBING_PLAYER_WIN
					goldinfo.param3 = self.game_serial
					toAddGold( goldinfo )

					systemPreLog( player_id, system_reward, pos )
				end
			end
		end
		self:sendToPlayer( player_info.player_sn, "ToTuiBingResult", toclient )
	end
	
	self:sendBankerInfo()

	game_state_timer = skynet.timeout(TuiBingConfig.WAIT_REWARD*100, function ( ... )
		-- 重新开始一局
		self:GameBegin()
	end)
end

--[[be banker
	param info 
		player_id
		player_sn
		player_name
		gold
]]
function TuiBing:BeBanker( info )
	if info == nil then return end

	self.banker = { -- 庄家
		player_id = info.player_id, 
		player_sn = info.player_sn, 
		player_name = info.player_name, 
		banker_times = 0,
		banker_gold = info.gold,
		banker_state = PlayerState.Natural,
	}

	self:sendBankerQueueInfo()
end

function TuiBing:sendBankerQueueInfo( sn )
	local toclient = {}

	toclient.bankerid = self.banker.player_id
	toclient.bankername = self.banker.player_name

	local tbl = {}
	for i,v in ipairs( self.fast_banker_list ) do
		local p = {}
		p.playerid = v.player_id
		p.playername = v.player_name
		p.type = 2
		talbe_insert( tbl, p )
	end

	for i,v in ipairs( self.banker_list ) do
		local p = {}
		p.playerid = v.player_id
		p.playername = v.player_name
		p.type = 1
		talbe_insert( tbl, p )
	end
	toclient.queue = tbl
	if sn then
		self:sendToPlayer( sn, "ResTuiBingQueueChange", toclient )
	else
		self:broatcast("ResTuiBingQueueChange", toclient)
	end
end

--[[
playerBeBanker param
t 		: 	1 normal queue 2 fast queue
info	: 	player_id, player_sn, player_name, gold ]]
function TuiBing:playerBeBanker( t, info )
	if self.banker.player_id == info.player_id then
		return ErrorCode.UR_BANKER
	end

	for i,v in ipairs(self.fast_banker_list) do
		if v.player_id == info.player_id then
			return ErrorCode.HAS_IN_QUEUE
		end
	end
	for i,v in ipairs(self.banker_list) do
		if v.player_id == info.player_id then
			return ErrorCode.HAS_IN_QUEUE
		end
	end

	local function checkGold( sn, gold )
		return skynet.call( sn, "lua", "checkGold", gold )
	end

	local ret = 0
	if t == 1 then
		if checkGold( info.player_sn, info.gold ) == 0 then
			talbe_insert( self.banker_list, info )
		else
			ret = ErrorCode.GOLD_NOT_ENOUGH
		end
	elseif t == 2 then
		if checkGold( info.player_sn, info.gold + TuiBingConfig.FAST_BANKER_NEED ) == 0 then
			local toplayer = {}
			toplayer.gold = -TuiBingConfig.FAST_BANKER_NEED
			toplayer.logtype = GoldLog.ADD_FAST_QUEUE
			toplayer.param1 = self.game_serial
			toplayer.param3 = #self.fast_banker_list
			local ret = skynet.call( info.player_sn, "lua", "addGold", toplayer )
			if ret == 0 then 
				talbe_insert( self.fast_banker_list, info )
			end
		else
			ret = ErrorCode.GOLD_NOT_ENOUGH
		end
	end
	if ret == 0 then
		local toplayer = {}
		toplayer.gold = -info.gold
		toplayer.logtype = GoldLog.BANKER_NEED

		local ret = skynet.call( info.player_sn, "lua", "addGold", toplayer )
		if ret == 0 then 
			self:sendBankerQueueInfo()
			if self.state == TuiBingState.Stop then
				self:GameBegin()
			end
		end
	end
	return ret
end

function TuiBing:playerGetInfo( player_id )
	local info = player_list[ player_id ]
	if info then
		self:sendGameState( info.player_sn )
		self:sendBankerInfo( info.player_sn )
		self:sendBankerQueueInfo( info.player_sn )
		self:sendPosGold( info.player_sn )
	end
end

function TuiBing:playerUnBanker( player_id )
	if self.banker.player_id ~= player_id then
		return ErrorCode.NOT_BANKER
	end
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] Player[%d] ask unBanker", 
	 						self.room_id, self.game_serial, player_id ) )

	self.banker.banker_state = PlayerState.UnBanker
	return 0
end

function TuiBing:playerLeaveQueue( player_id )
	local changed = false
	local function checklist( list, player_id )
		for i,pinfo in ipairs(list) do
			if pinfo.player_id == player_id then
				table_remove( list, i )
				local goldinfo = {}
				goldinfo.player_id = pinfo.player_id
				goldinfo.gold = pinfo.gold
				goldinfo.logtype = GoldLog.BANKER_BACK 
				goldinfo.param3 = self.game_serial
				toAddGold( goldinfo )
				changed = true
				break
			end
		end
	end
	checklist( self.fast_banker_list, player_id )
	if not changed then checklist( self.banker_list, player_id ) end

	if changed then
		self:sendBankerQueueInfo()
		config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] player[%d] LeaveQueue", 
			self.room_id, self.game_serial, player_id) )
		return 0
	else
		return ErrorCode.NOT_IN_QUEUE
	end
end

--[[addPlayer param roleinfo
	player_id
	player_sn
	player_name
]]
function TuiBing:addPlayer( roleinfo )
	if self.state == TuiBingState.Close then
		return ErrorCode.TUIBING_ROOMCLOSE
	end
	if self.banker.player_id == roleinfo.player_id then
		self.banker.banker_state = PlayerState.Natural
		self.banker.player_id = roleinfo.player_id
		self.banker.player_sn = roleinfo.player_sn
		self.banker.player_name = roleinfo.player_name
	end
	local info = roleinfo
	info.state = PlayerState.Natural
	player_list[ roleinfo.player_id ] = roleinfo
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d] add Player[%d]", self.room_id, roleinfo.player_id) )
	return 0
end 

function TuiBing:delPlayer( player_id )
	if self.banker.player_id == player_id then
		self.banker.banker_state = PlayerState.NotInRoom
	end

	self:playerLeaveQueue( player_id )
	player_list[ player_id ] = nil
	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d] del Player[%d]", self.room_id, player_id) )
	return 0
end

--[[plyaerKeepBanker
	info
		iskeep
		player_id
		gold
]]
function TuiBing:plyaerKeepBanker( info )
	if info.iskeep == 0 then
		-- is keep
		if self.banker.player_id == info.player_id then
			-- player is banker, add banker gold
			local goldinfo = {}
			goldinfo.player_id = info.player_id
			goldinfo.gold = -info.gold
			goldinfo.logtype = GoldLog.TUIBING_KEEP_BANKER
			goldinfo.param3 = self.game_serial
			local ret = toAddGold( goldinfo )
			if ret == 0 then
	 			self.banker.banker_gold = self.banker.banker_gold + info.gold
	 			self:sendBankerInfo()
	 			if self.state == TuiBingState.Begin_Check_Keep then
	 				-- is check keep state, need begin game
	 				if self.banker.banker_gold > TuiBingConfig.BANKER_LESS_GOLD then
	 					skynet.stoptimer(game_state_timer)
	 					
	 					toAskBankerBegin( self.banker.player_sn )
	 					self.state = TuiBingState.Begin_Check_Begin
	 					self:sendGameState()
	 					game_state_timer = skynet.timeout( TuiBingConfig.WAIT_BEGIN*100, function()
	 						self:GameReady()
	 					end )
	 					config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] Player[%d] use gold[%d] keep banker, total gold[%d]", 
	 						self.room_id, self.game_serial, info.player_id, info.gold, self.banker.banker_gold) )
	 				else
	 					-- be keep, but gold still less than begin game
	 					self:unBebanker()
	 				end
	 			else
	 				-- not check state jast add gold
	 			end
			end
		end
	elseif info.iskeep == 1 then
		if self.state == TuiBingState.Begin_Check_Keep or
			self.state == TuiBingState.Begin_Check_Begin then
			self:unBebanker()
		else
			self.banker.banker_state = PlayerState.UnBanker
		end
	end
end

function TuiBing:bankerBeginGame()
	if self.state == TuiBingState.Begin_Check_Begin then
		skynet.stoptimer(game_state_timer) 
		self.state = TuiBingState.Ready
		self:GameReady()
	end
end

function TuiBing:getBetTotalGold( pos )
	local gold = 0
	local count = (pos == nil or pos == 0)
	if count then
		for p,pos_info in pairs(self.bet_info) do
			for id, g in pairs(pos_info) do
				gold = gold + g
			end
		end
	else
		local list = self.bet_info[ pos ]
		for id, g in pairs(list) do
			gold = gold + g
		end
	end
	return gold
end

function TuiBing:sendPosGold( sn )
	local toclient = {}
	toclient.gold = {self:getBetTotalGold(1),self:getBetTotalGold(2),self:getBetTotalGold(3)}
	if sn then
		self:sendToPlayer( sn, "ToTuiBingBetGold", toclient )
	else
		self:broatcast( "ToTuiBingBetGold", toclient )
	end
end
--[[ info 
	player_id
	pos
	gold
]]
function TuiBing:playerBet( info )
	if info.player_id == self.banker.player_id then
		return ErrorCode.BANKER_NO_BET
	end

	if self.state ~= TuiBingState.Ready then
		return -1
	end

	if not (info.pos == TuiBingConfig.POS_SOUTH or info.pos == TuiBingConfig.POS_SKY or
		info.pos == TuiBingConfig.POS_NORTH) then
		config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] player[%d] bet, pos[%d] error", 
			self.room_id, self.game_serial, info.player_id, info.pos ) )
		return -2
	end

	if self:getBetTotalGold() + info.gold > self.banker.banker_gold then
		return -3
	end

	local player = player_list[ info.player_id ]
	if player == nil then
		config.Lprint( 1, string.format("[TUIBINGINFO] TuiBing[%d][%d] player[%d] bet, player no in the game room",
			self.room_id, self.game_serial, info.player_id ) )
		return -4
	end

	local infotbl = self.bet_info[ info.pos ]
	if infotbl[ info.player_id ] == nil then
		infotbl[ info.player_id ] = 0
	end

	local goldinfo = {}
	goldinfo.player_id = info.player_id
	goldinfo.gold = -info.gold
	goldinfo.logtype = GoldLog.TUIBONG_BET
	goldinfo.param3 = self.game_serial
	local ret = toAddGold( goldinfo )
	if ret ~= 0 then
		return ret
	end

	infotbl[ info.player_id ] = infotbl[ info.player_id ]  + info.gold

	config.Lprint( 1, string.format( "[TUIBINGINFO] TuiBing[%d][%d] player[%d] Bet gold[%d], count[%d]", 
		self.room_id, self.game_serial, info.player_id, info.gold, infotbl[ info.player_id ] ) )

	local toclient = {}
	toclient.result = 0
	toclient.id = player.player_id
	toclient.pos = info.pos
	toclient.gold = info.gold
	self:broatcast( "ResTuiBingBet", toclient )
	self:sendPosGold()
	return 0
end

function TuiBing:playerAllPlayer( pid )
	local toclient = {}
	local list = {}
	local sn = 0
	for player_id, player_info in pairs(player_list) do
		if pid == player_id then
			sn = player_info.player_sn
		else
			local p = {}
			p.id = player_info.player_id
			p.name = player_info.player_name
			talbe_insert( list, p )
		end
	end
	toclient.list = list
	if sn == 0 then
		return
	end
	self:sendToPlayer( sn, "ResTuiBingAllPlayer", toclient )
end

function TuiBing:sendToPlayer( sn, head, body )
	skynet.call( sn, "lua", "sendPacket", head, body )
end

function TuiBing:broatcast( head, body ) -- pkg:{head = "head", body = "body"}
	for id, p in pairs( player_list ) do
		skynet.call( p.player_sn, "lua", "sendPacket", head, body )
	end
end

--[[check param t
	1: game state
	2 : banker info
	2
]]
-- skynet.info_func(function( t )
-- 	print("t",type(t),tostring(t))
-- 	if t == nil then
-- 		return TuiBing.state
-- 	end
-- 	local cmd = tonumber(t) or 0
-- 	if cmd == 1 then
-- 		return TuiBing.state
-- 	elseif cmd == 2 then
-- 		return TuiBing.banker
-- 	else
-- 		return TuiBing.state
-- 	end
-- end)

function TuiBing:check( t, ... )
	if t == nil or t == 1 then
		return "TuiBing.state = " .. TuiBing.state
	elseif t == 2 then
		return TuiBing.banker
	elseif t == 3 then
		return player_list
	end
end

function TuiBing:ServiceClose()
	if self.state ~= TuiBingState.Stop then
		self.state = TuiBingState.Close
		return false
	end
	skynet.timeout(5*100, function( ... )
		skynet.exit()	
	end)
	return true
end

skynet.start(function(  )
	skynet.dispatch( "lua", function(_,_, command, ...)
		local f = TuiBing[command]
		local r = f(TuiBing,...)
		if r then
			skynet.ret(skynet.pack(r))
		end
	end)
end)