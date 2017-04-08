-- tuibing.lua
local skynet = require "skynet"
local config = require "config"

require "functions"
require "gameconfig"
require "errorcode"

local talbe_insert = table.insert
local table_remove = table.remove

-- player : player_id player_ws player_sn player_gold
local player_list = {}
local game_state_timer = 0
local majiang = {0,1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8,9}

local TuiBingState = {
	Stop = 0, -- 未初始化
	Begin = 1, -- 新游戏开始
	Begin_Check_Begin = 2, -- 询问是否开始游戏
	Begin_Check_Keep = 3, -- 询问是否续庄

	-- Ready = 4, -- 准备好可以押注
	WaitOpen = 5, -- 等待开牌
	Openning = 6, -- 开牌阶段
	Reward= 7, -- 发放奖励
}

local PlayerState = {
	Natural = 0, -- 正常
	NotInRoom = 1, -- 不在房间
	OffLine = 2, -- 离线
	UnBanker = 3, -- 下庄
}

local TuiBing = {
	banker_list = {}, 		-- 上庄队列
	fast_banker_list = {},	-- 优先上庄队列
	state = TuiBingState.Unknow,
	banker = {
		player_id = 0, 
		player_ws = 0,
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
		player_ws = 0,
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
	while true do
		local p = self:findBanker()
		if p then
			local toplayer = {}
			toplayer.num = -TuiBingConfig.BANKER_GOLD
			toplayer.log = GoldLog.BANKER_NEED
			local ret = skynet.call( p.player_sn, "lua", "addGold", toplayer )
			if ret == 0 then
				self:BeBanker( p )
				return
			end
		else
			break
		end
	end
	self:initBanker()
end

local function toAddGold(id, gold, log)
	local toplayer = {}
	toplayer.num = gold
	toplayer.log = log
	-- 先查询房间数据
	local player_info = player_list[id]
	if player_info then
		skynet.call( player_info.player_sn, "lua", "addGold", toplayer )
		return
	end
	-- 询问 PlayerManager
	local sn = skynet.call( ".PlayerManager", "lua", "getPlayerSN", id )
	if sn ~= 0 then
		skynet.call( sn, "lua", "addGold", toplayer )
		return
	end
	-- 直接赋值数据库
	skynet.call( ".DBService", "lua", "PlayerAddGold", id, gold )
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
		toAddGold( self.banker.player_id, self.banker.banker_gold, GoldLog.BANKER_BACK )
		self:changeBanker()
		self:GameBegin()
	end
end

function TuiBing:GameBegin()
	-- self.running_time_ = 0
	config.Lprint(1, "state Begin", self.banker.player_id)
	self.state = TuiBingState.Begin
	skynet.stoptimer( game_state_timer )

	if self.banker.player_id == 0 then
		self:changeBanker()
	end

	if self.banker.player_id == 0 then
		self.state = TuiBingState.Stop
		self:sendGameState()
		return
	end

	self:initGame()

	-- 判断 坐庄次数
	if self.banker.banker_times < TuiBingConfig.BANKER_LIMIT_TIMES then
		self.banker.banker_times = self.banker.banker_times + 1
		-- 判断 庄家状态
		if self.banker.banker_state == PlayerState.Natural then
			self:sendBankerInfo()
			-- 判断 庄家剩余金币
			if self.banker.banker_gold < 1000 then
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

	game_state_timer = skynet.timeout( TuiBingConfig.WAIT_BEGIN*100, function()
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
	config.Lprint(1, "state Ready")
	
	self.state = TuiBingState.WaitOpen
	skynet.stoptimer(game_state_timer)
	self:sendGameState()
	game_state_timer = skynet.timeout( TuiBingConfig.WAIT_BET*100, function( ... )
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

	self.result = getMajiang()
	config.Ldump( self.result, "self.result" )

	local toclient = {}
	toclient.majiangs = {}
	for i, v in ipairs( self.result )do
		local m = {}
		m.majiang1 = v[1]
		m.majiang2 = v[2]
		talbe_insert( toclient.majiangs, m )
	end
	self:broatcast( "ToDealMajiang", toclient )

	game_state_timer = skynet.timeout( TuiBingConfig.WAIT_OPEN*100, function( ... )
		self:GameReward()
	end)
end

function TuiBing:GameReward()
	config.Lprint(1, "state Reward")
	self.state = TuiBingState.Reward
	skynet.stoptimer(game_state_timer)
	self:sendGameState()

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
			-- toAddGold( self.banker.player_id, gold_count, GoldLog.TUIBING_BANKER_WIN )
			self.banker.banker_gold = self.banker.banker_gold + gold_count
		end
	end
	local function pos_win( pos ) -- pos 1 南 2 天 3 北
		local infotbl = self.bet_info[ pos ]
		local gold_count = 0
		if infotbl then
			for player_id,gold in pairs(infotbl) do
				toAddGold( player_id, gold * 2, GoldLog.TUIBING_PLAYER_WIN )
				gold_count = gold_count + gold
			end
		end
		if gold_count > 0 then
			self.banker.banker_gold = self.banker.banker_gold - gold_count
		end 
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
			if num_b > num_o then
				-- 庄家赢
				banker_win( pos )
			else
				-- 玩家赢
				pos_win( pos )
			end
		elseif (is_double_b) and (not is_double_o) then
			-- 庄家 对儿
			-- 庄家赢
			banker_win( pos )
		elseif (not is_double_b) and (is_double_o) then
			-- 非庄家 对儿
			-- 玩家赢
			pos_win( pos )
		elseif ( is_double_b ) and ( is_double_o ) then
			-- 都是对儿
			if num_b >= num_o then
				-- 庄家赢
				banker_win( pos )
			else
				-- 玩家赢
				pos_win( pos )
			end
		end
	end
	compare( 1 )
	compare( 2 )
	compare( 3 )

	self:sendBankerInfo()

	game_state_timer = skynet.timeout(TuiBingConfig.WAIT_REWARD*100, function ( ... )
		-- 重新开始一局
		self:GameBegin()
	end)
end

--[[be banker
	param info 
		player_id
		player_ws
		player_sn
		player_name
]]
function TuiBing:BeBanker( info )
	if info == nil then return end
	self.banker = { -- 庄家
		player_id = info.player_id, 
		player_ws = info.player_ws,
		player_sn = info.player_sn, 
		player_name = info.player_name, 
		banker_times = 0,
		banker_gold = TuiBingConfig.BANKER_GOLD,
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
info	: 	player_id, player_ws, player_sn, player_name ]]
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
		if checkGold( info.player_sn, TuiBingConfig.BANKER_GOLD ) == 0 then
			talbe_insert( self.banker_list, info )
		else
			ret = ErrorCode.GOLD_NOT_ENOUGH
		end
	elseif t == 2 then
		if checkGold( info.player_sn, TuiBingConfig.BANKER_GOLD + TuiBingConfig.FAST_BANKER_NEED ) == 0 then
			local toplayer = {}
			toplayer.num = -TuiBingConfig.FAST_BANKER_NEED
			toplayer.log = GoldLog.ADD_FAST_QUEUE
			local ret = skynet.call( info.player_sn, "lua", "addGold", toplayer )
			if ret == 0 then 
				talbe_insert( self.fast_banker_list, info )
			end
		else
			ret = ErrorCode.GOLD_NOT_ENOUGH
		end
	end
	if ret == 0 then
		self:sendBankerQueueInfo()
		if self.state == TuiBingState.Stop then
			self:GameBegin()
		end
	end
	return ret
end

function TuiBing:playerUnBanker( player_id )
	if self.banker.player_id ~= player_id then
		return ErrorCode.NOT_BANKER
	end
	self.banker.banker_state = PlayerState.UnBanker
	return 0
end

function TuiBing:playerLeaveQueue( player_id )
	local changed = false
	local function checklist( list, player_id )
		for i,pinfo in ipairs(list) do
			if pinfo.player_id == player_id then
				table_remove( list, i )
				changed = true
				break
			end
		end
	end
	checklist( self.fast_banker_list, player_id )
	if not changed then checklist( self.banker_list, player_id ) end

	if changed then
		self:sendBankerQueueInfo()
		return 0
	else
		return ErrorCode.NOT_IN_QUEUE
	end
end

--[[addPlayer param roleinfo
	player_id
	player_ws
	player_sn
]]
function TuiBing:addPlayer( roleinfo )
	if self.banker.player_id == roleinfo.player_id then
		self.banker.banker_state = PlayerState.Natural
		self.banker.player_id = roleinfo.player_id
		self.banker.player_sn = roleinfo.player_sn
		self.banker.player_ws = roleinfo.player_ws
	end
	local info = roleinfo
	info.state = PlayerState.Natural
	player_list[ roleinfo.player_id ] = roleinfo

	skynet.timeout( 10, function( ... )
		self:sendGameState( roleinfo.player_sn )
		self:sendBankerInfo( roleinfo.player_sn )
		self:sendBankerQueueInfo( roleinfo.player_sn )
		self:sendPosGold( roleinfo.player_sn )
	end )
	return 0
end 

function TuiBing:delPlayer( player_id )
	if self.banker.player_id == player_id then
		self.banker.banker_state = PlayerState.NotInRoom
	end

	self:playerLeaveQueue( player_id )
	player_list[ player_id ] = nil
	return 0
end

--[[KeepTuiBingBanker
	info
		iskeep
		player_id
		gold
]]
function TuiBing:KeepTuiBingBanker( info )
	if info.iskeep == 0 then
		if self.banker.player_id == info.player_id then
			self.banker.banker_gold = self.banker.banker_gold + info.gold
			if self.banker.banker_gold > 1000 then
				skynet.stoptimer(game_state_timer)
				toAskBankerBegin( self.banker.player_sn )
				self.state = TuiBingState.Begin_Check_Begin
				game_state_timer = skynet.timeout( TuiBingConfig.WAIT_BEGIN*100, function()
					self:GameReady()
				end )
			else
				self:unBebanker()
			end
		else
			self:unBebanker()
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

function TuiBing:getBetTotalGold()
	local gold = 0
	for pos,pos_info in pairs(self.bet_info) do
		for id, g in pairs(pos_info) do
			gold = gold + g
		end
	end
	return gold
end

function TuiBing:sendPosGold( sn )
	local toclient = {}
	toclient.gold = self:getBetTotalGold()
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

	if self.state ~= TuiBingState.WaitOpen then
		return
	end

	if not (info.pos == TuiBingConfig.POS_SOUTH or info.pos == TuiBingConfig.POS_SKY or
		info.pos == TuiBingConfig.POS_NORTH) then
		skynet.error("[TuiBing] Player bet, error pos["..info.pos.."]")
		return
	end

	if self:getBetTotalGold() + info.gold > self.banker.banker_gold then
		return 
	end

	local player = player_list[ info.player_id ]
	if player == nil then
		skynet.error(string.format("[TuiBing] Player bet, error player[%s] no in the game room",info.player_id))
		return
	end

	local infotbl = self.bet_info[ info.pos ]
	if infotbl[ info.player_id ] == nil then
		infotbl[ info.player_id ] = 0
	end
	infotbl[ info.player_id ] = infotbl[ info.player_id ]  + info.gold

	local toclient = {}
	toclient.result = 0
	toclient.id = player.player_id
	toclient.pos = info.pos
	toclient.gold = info.gold
	self:broatcast( "ResTuiBingBet", toclient )
	self:sendPosGold()
	return 0
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

skynet.start(function(  )
	skynet.dispatch( "lua", function(_,_, command, ...)
		local f = TuiBing[command]
		local r = f(TuiBing,...)
		if r then
			skynet.ret(skynet.pack(r))
		end
	end)
end)