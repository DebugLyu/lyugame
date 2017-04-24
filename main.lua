-- main.lua
local skynet = require("skynet")
local lpbc = require("protobuf")
local datacenter = require "datacenter"

skynet.start(function()
	skynet.error("Server start")
	-- start 启动控制台
	skynet.newservice("debug_console",8000)
	-- 启动websocket
	local web_service = skynet.newservice( "webservice" )
	-- 启动唯一服务 房间管理器
	skynet.uniqueservice "RoomManager"
	-- 启动唯一服务 玩家管理器
	skynet.uniqueservice("PlayerManager", web_service)

	-- 启动唯一服务 DB服务
	skynet.uniqueservice "Ldatabase"

	-- local watchdog = skynet.newservice("watchdog")
	-- skynet.call(watchdog, "lua", "start", {
	-- 	port = 8888,
	-- 	maxclient = 5,
	-- 	nodelay = true,
	-- })
	skynet.send(".RoomManager", "lua", "CreateTuiBing")

	skynet.newservice( "httpdservice" )

	datacenter.set("ServerState", 1)

	skynet.exit()
end)