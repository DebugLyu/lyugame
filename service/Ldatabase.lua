-- Ldatabase.lua
local skynet = require "skynet"
require "skynet.manager"

local mysql = require "mysql"
local config = require "config"
require "errorcode"

local db = nil

local sqls = {
	["login"] = "SELECT * FROM user WHERE account='%s';",
	["register"] = "INSERT INTO user (account, name, password, gold, state, statedate, adddate) VALUES ('%s', '%s', '%s', 0, 0, 0, now());\
					SELECT * FROM user WHERE account='%s';",
	["save"] = "UPDATE user SET gold = %d WHERE id = %d",
	["addgold"] = "UPDATE user SET gold = gold + %d WHERE id = %d",
	["addgoldlog"] = "INSERT INTO logs ( `playerid`, `num`, `type`, `param1`, `param2`, `param3`, `date`) VALUES \
					( '%d', '%d', '%d', '%d', '%s', '%d', now())",
	["userinfo"] = "SELECT * FROM user WHERE id='%d'",
	["seal"] = "UPDATE user SET state = '%d', statedate = '%d' WHERE id = '%d'",
	["httplog"] = "INSERT INTO httplogs (`gm`, `action`, `playerid`, `param1`, `param2`, `host`, `date` ) VALUES \
					( '%s', '%d', '%d', '%d', '%d', '%s', now() )"
}

local CMD = {}

function CMD.run( sql )
	local res =  db:query( sql )
	return res
end

function CMD.UserLogin( account, password )
	local sql = string.format( sqls[ "login" ], account ) 
	local res = CMD.run( sql )

	local ret = {}
	ret.result = 0
	if type( res ) == "table" then
		if #res == 0 then
			ret.result = ErrorCode.NO_ACCOUNT
		else
			ret.roleinfo = res[1]
		end
	else
		ret.result = ErrorCode.DBSERVICE_ERROR
		config.Lprint(2, string.format("[ERROR] DB Error, UserLogin failed, account =", account))
	end
	return ret
end

function CMD.UserRegister( account, password )
	local sql = string.format( sqls[ "login" ], account ) 
	local res = CMD.run( sql )

	local ret = {}
	ret.result = 0

	-- config.Ldump( res , "UserRegister" )

	if type( res ) == "table" then
		if #res == 0 then
			sql = string.format( sqls[ "register" ], account, account, password, account )
			res = CMD.run( sql )
			if res.mulitresultset == true then
				ret.roleinfo = res[2][1]
				return ret
			end
		else
			ret.result = ErrorCode.ACCOUNT_REPEAT
		end
	else
		ret.result = ErrorCode.DBSERVICE_ERROR
		config.Lprint(2, string.format("[ERROR] DB Error, UserRegister failed, account =", account))
	end
	
	return ret
end

--[[
	info
		player_id
		gold
		logtype
		param1  int
		param2  string
		param3  int
]]
function CMD.PlayerAddGold( info )
	if info.gold == 0 then
		return ErrorCode.PARAM_ERROR
	end

	local sql = string.format( sqls["addgold"], info.gold, info.player_id )

	local res = CMD.run( sql )
	if type( res ) == "table" then
		if res.affected_rows >= 1 then
			CMD.PlayerAddGoldLog( info )
			return 0
		end
	end
	-- skynet.error( string.format("[ERROR] player[%d] add gold error "))
	config.Lprint( 2, string.format( "[ERROR] DB Error, player[%d] add gold[%d] error", info.player_id, info.gold ) )
	config.Ldump( res, "DB.PlayerAddGold.res" )
	return ErrorCode.DB_PLAYER_NOT_FOUND
end
--[[
	info
		player_id : id can use 0, 0 is system
		gold
		logtype
		param1  int
		param2  string
		param3  int
]]
function CMD.PlayerAddGoldLog( info )
	if info.gold == 0 then
		return ErrorCode.PARAM_ERROR
	end
	info.logtype = info.logtype or 0
	info.param1 = info.param1 or 0
	info.param2 = info.param2 or ""
	info.param3 = info.param3 or 0

	local sql = string.format( sqls["addgoldlog"], info.player_id, info.gold, info.logtype, info.param1, info.param2, info.param3 )
	local res = CMD.run( sql )

	return 0
end

--[[
	info
		player_id : id must > 0

	return
		number is error code
		tbl is success role info tbl
]]
function CMD.getPlayerInfo( info )
	if info.player_id == nil or info.player_id == 0 then
		return ErrorCode.PARAM_ERROR
	end

	local sql = string.format( sqls[ "userinfo" ], info.player_id )
	local res = CMD.run( sql )
	local ret = 0
	if type( res ) == "table" then
		if #res == 0 then
			ret = ErrorCode.NO_USER_ID
		else
			ret = res[1]
		end
	else
		ret = ErrorCode.DBSERVICE_ERROR
		config.Lprint(2, string.format( "[ERROR] DB Error, DBService UserLogin failed, account[%s]", account))
	end
	return ret
end

--[[
	info
		player_id
		state
		statedate
]]
function CMD.statePlayer( info )
	if info.player_id == nil or info.player_id == 0 then
		return ErrorCode.PARAM_ERROR 
	end
	local sql = string.format( sqls[ "seal" ], info.state, info.statedate, info.player_id )
	local res = CMD.run( sql )

	if type( res ) == "table" then
		if res.affected_rows >= 1 then
			return 0
		end
	end
	return ErrorCode.DBSERVICE_ERROR
end

--[[
	info
		gm : string gm string
		action : 	int  1 payment 2 kick player 3 seal up player
		player_id : int  1 payment to player id 2 kick player id 3 seal up player id
		host : string gm host
		param1 : 	int  1 payment gold 2 null 3 seal up to time
		param2 : 	int  1 null 2 null 3 null
]]
function CMD.HttpLog(info)
	if info.player_id == nil or info.player_id == 0 then
		return ErrorCode.PARAM_ERROR 
	end
	if info.gm == nil or info.gm == "" then
		return ErrorCode.PARAM_ERROR 
	end
	info.param1 = info.param1 or 0
	info.param2 = info.param2 or 0
	
	local sql = string.format( sqls[ "httplog" ], info.gm, info.action, info.player_id, info.param1, info.param2, info.host )
	local res = CMD.run( sql )
	return 0
end

--[[save player info
	param info need
		player_id
		player_gold
]]
function CMD.savePlayer( info )
	local sql = string.format( sqls[ "save" ], info.player_gold, info.player_id ) 
	local res = CMD.run( sql )
end

function CMD.close()
	
end

skynet.start(function()
	local function on_connect(db)
		db:query("set charset utf8");
	end
	
	db = mysql.connect({
		host 		= 	config.database_config.ip,		 
		port 		= 	config.database_config.port,
		database 	= 	config.database_config.database,
		user 		= 	config.database_config.user,
		password	= 	config.database_config.password,
		max_packet_size = 1024 * 1024,
		on_connect = on_connect
	})
	if not db then
		config.Lprint(1,"[INFO] DB failed to connect")
	end
	config.Lprint(1,"[INFO] DB success to connect to mysql server")

	skynet.dispatch( "lua", function(_,_, command, ...)
    	-- 注意命令方法 不要跟消息方法 重名，否则将会出错
		local f = CMD[command]
		if f then
			skynet.ret(skynet.pack(f(...)))
		end
	end)
	-- skynet.name(".DBService", skynet.self())
	skynet.register(".DBService")
end)


