-- mahjong.lua
--[[

]]

local skynet = require "skynet"
local config = require "config"

local Timer = require "LTimer"
require "functions"
require "gameconfig"
require "errorcode"

local table_insert = table.insert
local table_remove = table.remove

local mahjongs = {
	 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9, -- 条
	11,12,13,14,15,16,17,18,19,11,12,13,14,15,16,17,18,19,11,12,13,14,15,16,17,18,19,11,12,13,14,15,16,17,18,19, -- 万
	21,22,23,24,25,26,27,28,29,21,22,23,24,25,26,27,28,29,21,22,23,24,25,26,27,28,29,21,22,23,24,25,26,27,28,29, -- 饼
	31,32,33,34, -- 东
	41,42,43,44, -- 南
	51,52,53,54, -- 西
	61,62,63,64, -- 北
	71,72,73,74, -- 中
	81,82,83,84, -- 发
	91,92,93,94, -- 白
}

local MahJongDirection = {
	East = 1,
	South = 2,
	West = 3,
	North = 4,
}

local MahjongType = {
	Tiao = 0,
	Bing = 1,
	Wan = 2,
	Dong = 3,
	Nan = 4,
	Xi = 5,
	Bei = 6,
	Zhong = 7,
	Fa = 8,
	Bai = 9,
}

local PlayerState = {
	Normal = 0,
	NotReady = 1,
	Ready = 2,
	Leave = 3,
}

local MahjongLogic = {
	Nothing = 0,
	Peng = 2,
	Gang = 3,
	AnGang = 4,
	NormalHu = 5,
	DoubleHu = 6,
}

local Mahjong = {
	--[[ 1东 2南 3西 4北 
		{player_id,player_sn,player_name,player_state,{mj},{outmj},{peng},{gang}}
		player_state : PlayerState ]]
	player_list = {}, 
	cur_pos = 0, -- 当前出牌人
	begin_pos = 0, -- 起始出牌位置
	cur_pai = 0, -- 当前出牌人出的牌
	remainder_mahjong = {}, -- 剩余麻将
	need_restart = true,
}

local player_select_timer = 0
local player_send_timer = 0

local function getMahjongType( p )
	return math.floor( mj / 10 )
end

local function getOneMahjong( tbl )
	local i = math.random(1, #tbl)
	local n = tbl[ i ]
	tableremove( tbl, i )
	return n
end

local function get13Mahjong( tbl )
	local tmp = {}
	for i=1,13 do
		table.insert( tmp, getOneMahjong( tbl ) )
	end
	return tmp
end

function Mahjong:broadcastReady()
	if #self.player_list >= 4 then
		self:broadcast("ToMjReady",{}) 
	end
end

function Mahjong:checkReady()
	if times = 0
	for pos, player_info in pairs(self.player_list) do
		if player_info.player_state == PlayerState.Ready then
			times = times + 1
		end
	end
	if times >= 4 then
		self:start()
	end
end

function Mahjong:start()
	self.cur_pos = 0
	self.remainder_mahjong = clone( mahjongs )	

	self.player_list[1].mj = get13Mahjong(self.remainder_mahjong)
	self.player_list[2].mj = get13Mahjong(self.remainder_mahjong)
	self.player_list[3].mj = get13Mahjong(self.remainder_mahjong)
	self.player_list[4].mj = get13Mahjong(self.remainder_mahjong)

	self:playerStep()
end

-- 必须为数组结构
local function table_connect(tbl1, tbl2)
	local t = tbl1
	for k,v in ipairs(tbl2) do
		t[#t+1] = v
	end
	return t
end

-- 检查胡牌
local function checkHupai( mj, pai )
	local total = mj
	if pai then
		total = table_connect(mj,{pai})
	end
	local trymj = {}
	local function restart()
		trymj = clone( total )
	end
	-- 先判断对对胡
	restart()
	local function matchDouble( tbl )
		if #tbl == 0 then
			return true
		end
		local pai = tbl[1]
		table_remove( tbl, 1 )
		for i,p in ipairs(tbl) do
			if pai == p then
				table_remove( tbl, i )
				if matchDouble( tbl ) then
					return true
				end
			end
		end
		return false
	end
	local ok = matchDouble( trymj )
	if ok then
		return MahjongLogic.DoubleHu
	end
	-- 判断普通胡牌规则
	local function matchSingle( tbl )
		if #tbl == 0 then
			return true
		end
		local tmp = {}
		-- 四种匹配规则  (A A A)  (A A+ A++) (A- A A+) (A-- A- A)
		local function reMatchStart()
			tmp = clone( tbl )
		end
		
		local function findMatch( tbl, pai )
			local ok = false
			for i,p in ipairs(tbl) do
				if pai == p then
					table_remove( tbl, i )
					ok = true
					break
				end
			end
			return ok
		end
		local ok = false
		-- 1 A A A
		for i,p in ipairs(tbl) do
			reMatchStart()
			table_remove( tmp, i )
			local tmp1 = clone( tmp )
			ok = findMatch( tmp, p )
			if ok then
				ok = findMatch( tmp, p )
				if ok then
					return matchSingle( tmp )
				end
			end
		end
		-- 2 A A+ A++
		for i,p in ipairs(tbl) do
			reMatchStart()
			table_remove( tmp, i )
			local tmp1 = clone( tmp )
			if p % 10 <= 7 then --最大为 7 8 9
				ok = findMatch( tmp, p+1 )
				if ok then
					ok = findMatch( tmp, p + 2 )
					if ok then
						return matchSingle( tmp )
					end
				end
			end
		end
		-- 3 A- A A+
		for i,p in ipairs(tbl) do
			reMatchStart()
			table_remove( tmp, i )
			if p % 10 > 1 and p % 10 < 9 then -- 2~8
				ok = findMatch( tmp, p-1 )
				if ok then
					ok = findMatch( tmp, p+1 )
					if ok then
						matchSingle( tmp )
					end
				end
			end
		end
		-- 4 A-- A- A
		for i,p in ipairs(tbl) do
			reMatchStart()
			table_remove( tmp, i )
			if p % 10 >= 3 then
				ok = findMatch( tmp, p - 2 )
				if ok then
					ok = findMatch( tmp, p - 1 )
					if ok then
						return matchSingle( tmp )
					end
				end
			end
		end

		return false
	end
	local function checkSingle(pai, tbl)
		-- 优先找到 将牌
		local ok = false
		for i,p in ipairs( tbl ) do
			if pai == p then
				ok = true
				table_remove( tbl, i )
				break
			end
		end
		-- 该牌无法匹配到将牌
		if not ok then
			return false
		end
		return matchSingle( tbl )
	end
	for i, pai in ipairs(mj) do
		restart()
		table_remove(trymj, i) 
		if checkSingle( pai, trymj ) then
			return MahjongLogic.NormalHu
		end
	end
	return MahjongLogic.Nothing
end

local function checkPengPai( mj, pai )
	local times = 0
	for k,p in pairs( mj ) do
		if p == pai then
			times = times + 1
		end
	end

	if times >= 2 then
		return true
	end
	return false
end

local function checkGangPai( mj, pai )
	local times = 0
	for k,p in pairs( mj ) do
		if p == pai then
			times = times + 1
		end
	end

	if times >= 3 then
		return true
	end
	return false
end

local function checkGang_Peng( pengs, pai )
	for k, info in pairs( pengs ) do
		if info.pai = pai then
			return true, info.target, k
		end
	end
	return false, 0
end

local function checkAnGang( mjs, pai )
	local times = 0 
	for k,p in pairs(mjs) do
		if p == pai then
			times = times + 1
		end
	end
	if times == 3 then
		return true
	end
	return false
end

local function checkAllAnGang( mjs )
	local mjs_clone = {}
	local function restart()
		mjs_clone = clone( mjs )
	end
	local ret = {}

	for i = #mjs, 1, -1 do
		local p = mjs_clone[i]
		table_remove( mjs_clone, i )
		if checkGangPai( mjs_clone, p ) then
			table_insert(ret, p)
		end
	end
	return ret
end

function Mahjong:playerStep( pos )
	if pos == nil then
		if self.cur_pos == 0 then
			self.begin_pos = math.random(2,12)
			self.cur_pos = self.begin_pos % 4
		else
			self.cur_pos = self.cur_pos + 1	
		end
	else
		self.cur_pos = pos
	end

	-- 抽一张牌
	local one = getOneMahjong(self.remainder_mahjong)
	local player_info = self.player_list[cur_pos]
	local majiangs = player_info.mj
	local player_id = player_info.player_id
	local sn = player_info.player_sn
	-- 推给玩家 起牌
	local toplayer = {}
	toplayer.pai = one
	sendToPlayer( sn, "ToMjGetMj", toplayer )

	toplayer = {}	
	toplayer.states = {}
	-- 检查所有暗杠牌
	local ret = checkAllAnGang( majiangs )
	if #ret > 0 then
		for i, p in ipairs(ret) do
			table_insert( toplayer.states, {state = MahjongLogic.AnGang, pai = p, pos = cur_pos} )
		end
	end
	-- 检查碰牌 是否有杠
	local result, target = checkGang_Peng( player_info.peng, one ) 
	if result then
		table_insert( toplayer.states, {state = MahjongLogic.Gang, pai = one, pos = target} )
	end
	-- 检查是否有暗杠
	if checkAnGang( majiangs, one ) then
		table_insert( toplayer.states, {state = MahjongLogic.AnGang, pai = one, pos = cur_pos} )
	end
	-- 检查是否胡牌
	local logic = checkHupai( majiangs, one )
	if logic > MahjongLogic.Nothing then
		table_insert( toplayer.states, {state = logic, pai = one, pos = cur_pos} )
	end
	-- 插入 麻将堆
	table_insert( self.player_list[cur_pos].mj, one )
	-- 如果有选择逻辑 推给玩家
	if #toplayer.states > 0 then
		sendToPlayer( sn, "ToMjSelected", toplayer )
	end

	if player_info.player_state == PlayerState.Leave then
		self:playerSendMj( { player_id = player_id, mj = one } )
	else
		player_send_timer = Timer.registerTimer( MahJongConfig.WAIT_SEND_MJ * 100, function( ... )
			self:playerSendMj( { player_id = player_id, mj = one } )
		end )
	end
end

function Mahjong:sendToPlayer( sn, head, body )
	skynet.call( sn, "lua", "sendPacket", head, body )
end

function Mahjong:getPlayerPos( player_id )
	local pos = 0
	for p, info in pairs( self.player_list ) do
		if info.player_id == player_id then
			pos = p
		end
	end
	return pos
end
--[[playerSendMj
	info
		player_id
		mj	
]]
function Mahjong:playerSendMj( info )
	local player_pos = self:getPlayerPos( info.player_id )
	if player_pos == 0 then
		return ErrorCode.MAHJONG_PLAYER_NOT_FOUND
	end
	local find = false
	local list = self.player_list[ player_pos ].mj
	for k, pai in pairs( list ) do
		if pai == info.mj then
			find = true
			table_remove( self.player_list[ player_pos ].mj, k )
			break
		end
	end
	if not find then
		return ErrorCode.MAHJONG_MJ_NOT_FOUND
	end
	-- 取消定时器
	if player_send_timer > 0 then
		Timer.unregisterTimer(player_send_timer) 
		player_send_timer = 0
	end
	-- 记录出牌
	table_insert( self.player_list[ player_pos ].outmj, info.mj )
	self.cur_pai = info.mj
	find = false
	for pos, player_info in pairs(self.player_list) do
		if player_info.player_id ~= info.player_id then
			local mjs = player_info.mj
			local ret = checkPengPai( mjs, info.mj )
			local toplayer = {}
			toplayer.states = {}
			if #ret > 0 then	
				for _, s in pairs( ret ) do
					table_insert( toplayer.states, {state = s} )
				end
			end
			ret = checkHupai( mjs, info.mj )
			if ret ~= MahjongLogic.Nothing then
				table_insert( toplayer.states, {state = ret} )
			end
			if #toplayer.states > 0 then
				find = true
				sendToPlayer( player_info.player_sn, "ToMjSelected", toplayer )
			end
		end
	end
	if find then
		-- 有人要牌
		self:broadcast( "ToMjSmOneUse", {} )
		player_select_timer = Timer.registerTimer( MahJongConfig.WAIT_SELECT, function( ... )
			self:playerStep()
		end )
	else
		-- 没人要
		self:playerStep()
	end
end

--[[playerPeng
	info
		player_id
		selected
]]
function Mahjong:playerPeng( info )
	local player_pos = self:getPlayerPos( info.player_id )
	if player_pos == 0 then
		return ErrorCode.MAHJONG_PLAYER_NOT_FOUND
	end
	-- 取消选择定时器
	if player_select_timer > 0 then
		Timer.unregisterTimer( player_select_timer ) 
		player_select_timer = 0
	end
	local pai = self.cur_pai
	local mj = self.player_list[ player_pos ].mj
	
	if checkPengPai( mj, pai ) == false then
		return ErrorCode.MAHJONG_ERROR_COMMAND
	end

	local times = 0
	for i = #mj, 1, -1 do
		if pai == mj[ i ] then
			times = times + 1
			table_remove(self.player_list[ player_pos ].mj, i)
			if times >= 2 then
				break
			end
		end
	end
	local note = {pai = pai, target = self.cur_pos }
	table_insert( self.player_list[ player_pos ].peng, note )
	self.cur_pos = player_pos

	if selected == 0 then

	end 
	player_send_timer = Timer.registerTimer( MahJongConfig.WAIT_SEND_MJ * 100, function( ... )
		self:playerSendMj( { player_id = info.player_id, mj = info.selected } )
	end )
end
--[[playerGang
	info
		player_id
		pai
]]
function Mahjong:playerGang( info )
	local player_pos = self:getPlayerPos( info.player_id )
	if player_pos == 0 then
		return ErrorCode.MAHJONG_PLAYER_NOT_FOUND
	end
	-- 取消选择定时器
	if player_select_timer > 0 then
		Timer.unregisterTimer( player_select_timer ) 
		player_select_timer = 0
	end
	local mj = self.player_list[ player_pos ].mj
	local tpos = self.cur_pos

	local function subMj( mj, pai, spos, tpos )
		local times = 0
		for i = #mj, 1, -1 do
			if pai == mj[ i ] then
				times = times + 1
				table_remove( self.player_list[ spos ].mj, i )
				if times >= 3 then
					break
				end
			end
		end
		local note = {pai = pai, target = tpos }
		table_insert( self.player_list[ spos ].gang, note )
		self:playerStep( spos )
	end

	if self.cur_pos == player_pos then
		-- 自己的杠牌 暗杠
		local ret = checkAllAnGang( mj )
		if #ret > 0 then
			for k,p in pairs(ret) do
				if p == info.pai then
					subMj( mj, info.pai, player_pos, player_pos )
					break
				end
			end
		end
	else
		-- 杠别人
		local pai = self.cur_pai
		local pengs = self.player_list[ player_pos ].peng

		if checkGangPai( mj, pai ) then
			-- local times = 0
			-- for i = #mj, 1, -1 do
			-- 	if pai == mj[ i ] then
			-- 		times = times + 1
			-- 		table_remove(self.player_list[ player_pos ].mj, i)
			-- 		if times >= 3 then
			-- 			break
			-- 		end
			-- 	end
			-- end
			-- local info = {pai = pai, target = self.cur_pos }
			-- table_insert( self.player_list[ player_pos ].gang, info )
			-- self:playerStep( player_pos )
			subMj( mj, pai, player_pos, self.cur_pos )
		else
			local result, target, k = checkGang_Peng( pengs, pai )
			if result then
				table_remove( self.player_list[ player_pos ].peng, k )
				local info = {pai = pai, target = target}
				table_insert( self.player_list[ player_pos ].gang, info )
				self:playerStep( player_pos )
			else
				return ErrorCode.MAHJONG_ERROR_COMMAND
			end
		end
	end
	
	
	return 0
end

--[[ playerHu
	info 
	player_id
]]
function Mahjong:playerHu()
	local player_pos = self:getPlayerPos( info.player_id )
	if player_pos == 0 then
		return ErrorCode.MAHJONG_PLAYER_NOT_FOUND
	end
	-- 取消选择定时器
	if player_select_timer > 0 then
		Timer.unregisterTimer( player_select_timer ) 
		player_select_timer = 0
	end

	local mj = self.player_list[ player_pos ].mj
	if player_pos == self.cur_pos then
		-- 自摸
		if checkHupai( mj, nil ) then
			-- 发送奖励
			
			-- 重新开始一局
			self:broadcastReady()
			return 0
		end
	else
		-- 点炮
		local pai = self.cur_pai
		if checkHupai( mj, pai ) then
			-- 发送奖励
			
			-- 重新开始一局
			self:broadcastReady()
			return 0
		end
	end
	return ErrorCode.MAHJONG_ERROR_COMMAND
end
--[[initPlayer
	init player info
]]
function Mahjong:initPlayer( player )
	player.player_state = PlayerState.Normal
	player.gang = {}
	player.peng = {}
	player.mj = {}
	player.outmj = {}
end

--[[ addPlayer info
	player_id
	player_sn
	player_name
]]
function Mahjong:addPlayer(info)
	if #self.player_list >= 4 then
		return ErrorCode.MAHJONG_ROOM_FULL
	end
	self:initPlayer( info )
	table_insert( self.player_list, info )
end

function Mahjong:delPlayer( player_id )
	for pos, player_info in pairs(self.player_list) do
		if player_info.player_id == player_id then
			table_remove( self.player_list, pos )
		end
	end
end

function Mahjong:playerLeave( player_id )
	for pos, player_info in pairs( self.player_list ) do
		if player_info.player_id == player_id then
			player_info.player_state = PlayerState.Leave
		end		
	end
end

function Mahjong:playerReady( player_id )
	local ischange = false
	for pos, player_info in pairs( self.player_list ) do
		if player_info.player_id == player_id then
			player_info.player_state = PlayerState.Ready
			ischange = true
			self:checkReady()
			break
		end
	end
	if ischange then
		local toplayer = {}
		toplayer.ids = {}
		for pos,info in pairs(self.player_list) do
			if info.player_state == PlayerState.Ready then
				table_insert( toplayer.ids, pos )
			end
		end
		self:broadcast( "ResMJReady", toplayer )
		self:checkReady()
	end
end

function Mahjong:broadcast( head, body ) -- pkg:{head = "head", body = "body"}
	for id, p in pairs( player_list ) do
		skynet.call( p.player_sn, "lua", "sendPacket", head, body )
	end
end

skynet.start(function( ... )
	skynet.dispatch( "lua", function(_,_, command, ...)
		local f = Mahjong[command]
		local r = f(Mahjong,...)
		if r then
			skynet.ret(skynet.pack(r))
		end
	end)
end)