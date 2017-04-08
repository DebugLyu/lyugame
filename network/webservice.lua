--[[
    websocket:
        protocal   head||body 
--]]
local skynet = require "skynet"
local socket = require "socket"
local string = require "string"
local websocket = require "websocket"
local httpd = require "http.httpd"
local urllib = require "http.url"
local sockethelper = require "http.sockethelper"
local pb = require "protobuf"
local parser = require "parser"
local config = require "config"

local handler = {}
-- socket list
local ws_list = {}
local player_list = {}

function handler.on_open(ws)
    config.Lprint(1, string.format("%d::open", ws.id))
    local player = skynet.newservice("player")
    skynet.call(player, "lua", "init", { ws_id = ws.id, ws_service = skynet.self() })
    player_list[ ws.id ] = player
    ws_list[ws.id] = ws
    -- local agent = skynet.newservice("agent")
    -- agent_list[ws.id] = agent
end

function handler.on_message(ws, message)
    config.Lprint(1, string.format("%d receive:%s", ws.id, message))
    local msglen = string.len( message )
    local headlen, n = string.unpack(">H", message)
    if msglen < n + headlen - 1 then
        return
    end
    local head = string.sub( message, n, headlen + n - 1)
    -- local head = string.match( message, "(.*)||" )
    -- local body = string.match( message, "||(.*)" )
    if string.len(head) > 0 then
        local proto_head = "tutorial." .. head
        local c = pb.check( proto_head )
        if c then
            local body = string.sub( message, n+headlen, string.len(message) )
            local p = player_list[ ws.id ]
            if p then
                skynet.send( p, "lua", head, body )
            else
            
            end
        else
            skynet.error( "[ERROR] check pb head faild, head["..head.."]")
        end
    else
        skynet.error( "[ERROR] check pb head faild, head len < 0")
    end
    
end

function handler.on_close(ws, code, reason)
    config.Lprint(1, string.format("%d close:%s  %s", ws.id, code, reason))
    skynet.call( player_list[ws.id], "lua", "close" )
    ws_list[ws.id] = nil
end

local function handle_socket(id)
    -- limit request body size to 8192 (you can pass nil to unlimit)
    local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), nil)
    if code then
        if url == "/ws" then
            local ws = websocket.new(id, header, handler)
            ws:start()
        end
    end
end
---------------------------------------------
-- service Commond 
-- function 
--      send  ws send msg to client
---------------------------------------------
local CMD = {} 
function CMD.send( id, code )
    -- config.Lprint(1, "sendto", id, code)
    local ws = ws_list[id]
    if ws then
        ws:send_binary(code)
    end
end

skynet.start(function()
    -- 注册 protobuf message
    parser.register("gamebox.proto","lyugame/protocal/")
    -- 监听本地端口
    local address = "0.0.0.0:8001"
    skynet.error("Listening "..address)
    local id = assert(socket.listen(address))

    socket.start(id , function(id, addr)
       socket.start(id)
       pcall(handle_socket, id)
    end)

    skynet.dispatch( "lua", function( _,_, common, ... )
        local f = CMD[ common ] 
        if f then
            f( ... )
        end 
    end)
end)
