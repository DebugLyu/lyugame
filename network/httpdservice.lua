local skynet = require "skynet"
local socket = require "socket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local config = require "config"
local table = table
local string = string
local md5 = require "md5"

require "gameconfig"
require "errorcode"

local keycode = "xhqipai"
local mode = ...

if mode == "agent" then

local function response(id, ...)
	local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
	if not ok then
		-- if err == sockethelper.socket_error , that means socket closed.
		config.Lprint(1, string.format("[HTTP] id[%d] response error[%s]", id, err))
	end
end

local function checkSign( req )
	local str = ""
	local act = tonumber( req.action )
	local gm = req.gm
	local time = req.time

	local player_id = tonumber( req.uid ) or 0
	if act == HttpAction.PAYMENT then
		local gold = tonumber(req.gold) or 0		
		str = gm .. gold .. player_id .. time .. keycode
	elseif act == HttpAction.KICK then
		str = gm .. player_id .. time .. keycode
	elseif act == HttpAction.SEAL then
		local timestamp = tonumber( req.timestamp ) or 0 
		str = gm .. player_id .. timestamp .. time .. keycode
	else

	end
	return md5.sumhexa( str )
end

local function playerPayment( gm_account, host, player_id, gold )
	if player_id == 0 then
		return ErrorCode.PARAM_ERROR
	end
	if gold == 0 then
		return ErrorCode.PARAM_ERROR
	end

	config.Lprint( 1, string.format( "[HTTP] gm[%s][%s] add gold[%d] for player[%d]", gm_account, host, gold, player_id ))
	local toplayermanager = {}
	toplayermanager.player_id = player_id
	toplayermanager.gold = gold
	toplayermanager.logtype = GoldLog.GM_ADD_HOUTAI
	toplayermanager.param2 = gm_account .. "|" .. host
	local ret = skynet.call( ".PlayerManager", "lua", "changeGold", toplayermanager )
	if ret.result == 0 then
		todb = {}
		todb.player_id = player_id
		todb.gm = gm_account
		todb.host = host
		todb.action = HttpAction.PAYMENT
		todb.param1 = gold
		skynet.send( ".DBService", "lua", "HttpLog", todb )
	end
	return ret.result
end

local function playerKicked( gm_account, host, player_id )
	if player_id == 0 then
		return ErrorCode.PARAM_ERROR
	end
	config.Lprint( 1, string.format( "[HTTP] gm[%s][%s] Kick player[%d]", gm_account, host, player_id ))
	local toplayermanager = {}
	toplayermanager.player_id = player_id
	local ret = skynet.call( ".PlayerManager", "lua", "kickPlayer", toplayermanager )
	if ret == 0 then
		todb = {}
		todb.player_id = player_id
		todb.gm = gm_account
		todb.host = host
		todb.action = HttpAction.KICK
		skynet.send( ".DBService", "lua", "HttpLog", todb )
	end
	return ret
end

local function playerSeal( gm_account, host, player_id, timestamp )
	if player_id == 0 then
		return ErrorCode.PARAM_ERROR
	end
	if timestamp == 0 then
		return ErrorCode.PARAM_ERROR
	end
	config.Lprint( 1, string.format( "[HTTP] gm[%s][%s] seal up player[%d] to time[%s]",
				 gm_account, host, player_id, os.date("%Y-%m-%d %H:%M:%S", timestamp)) )

	local toplayermanager = {}
	toplayermanager.player_id = player_id
	local ret = skynet.call( ".PlayerManager", "lua", "kickPlayer", toplayermanager )

	local todb = {}
	todb.player_id = player_id
	todb.state = PlayerState.Seal
	todb.statedate = timestamp
	local ret = skynet.call( ".DBService", "lua", "statePlayer", todb )
	if ret == 0 then
		todb = {}
		todb.player_id = player_id
		todb.gm = gm_account
		todb.host = host
		todb.action = HttpAction.SEAL
		todb.param1 = timestamp
		skynet.send( ".DBService", "lua", "HttpLog", todb )
	end
	return ret
end

skynet.start(function()
	skynet.dispatch("lua", function (_,_,id,addr)
		socket.start(id)

		-- limit request body size to 8192 (you can pass nil to unlimit)
		local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8192)
		if code then
			if code ~= 200 then
				response(id, code)
			else
				local tmp = {}
				if header.host then
					-- table.insert(tmp, string.format("host: %s", header.host))
				end
				local path, query = urllib.parse(url)
				-- table.insert(tmp, string.format("path: %s", path))
				local req = {}
				if query then
					local q = urllib.parse_query(query)
					for k, v in pairs(q) do
						-- table.insert(tmp, string.format("query: %s= %s", k,v))
						req[ k ] = v
					end
				end
				local act = tonumber( req.action )
				if act == nil then
					return 0
				end

				local sign_server = checkSign(req)
				local sign_php = req.sign 

				local result = 0
				if sign_php == sign_server then
					if act == HttpAction.PAYMENT then
						local gm = req.gm
						local gold = tonumber(req.gold) or 0
						local player_id = tonumber( req.uid ) or 0
						result = playerPayment( gm, addr, player_id, gold )
					elseif act == HttpAction.KICK then
						local gm = req.gm
						local player_id = tonumber( req.uid ) or 0
						result = playerKicked( gm, addr, player_id )
					elseif act == HttpAction.SEAL then
						local gm = req.gm
						local player_id = tonumber( req.uid ) or 0
						local timestamp = tonumber( req.timestamp ) or 0 
						
						result = playerSeal( gm, addr, player_id, timestamp )
					else
						-- config.Lprint( 1, string.format( "[ERROR] host[%s] request action[%s] error.", header.host, tostring(act) ) )
						
						result = ErrorCode.PARAM_ERROR
					end
				else
					result = ErrorCode.SIGN_ERROR
				end
				response(id, code, result.."")
			end
		else
			if url == sockethelper.socket_error then
				skynet.error("socket closed")
				config.Lprint(1, string.format("[HTTP] id[%d] socket closed", id))
			else
				skynet.error(url)
			end
		end
		socket.close(id)
	end)
end)

else

skynet.start(function()
	local agent = {}
	for i= 1, 2 do
		agent[i] = skynet.newservice(SERVICE_NAME, "agent")
	end
	local balance = 1
	local id = socket.listen("0.0.0.0", 8002)
	skynet.error("Listen web port 8001")
	socket.start(id , function(id, addr)
		config.Lprint(1, string.format("[HTTP] id[%d][%s] connected, pass it to agent", id, addr, agent[balance]))
		skynet.send(agent[balance], "lua", id, addr)
		balance = balance + 1
		if balance > #agent then
			balance = 1
		end
	end)
end)

end