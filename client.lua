-- client.lua
package.cpath = "luaclib/?.so"
package.path = "lualib/?.lua;examples/?.lua;lyugame/?.lua;lyugame/protocal/?.lua"

if _VERSION ~= "Lua 5.3" then
	error "Use lua 5.3"
end

local socket = require "clientsocket"
local fd = assert(socket.connect("127.0.0.1", 8001))

local pb = require "protobuf"
local parser = require "parser"

parser.register("gamebox.proto","lyugame/protocal/")

local function printf( ... )
	print( string.format( ... ) )
end

local function send_package(fd, pack)
	-- local package = string.pack(">s2", string.pack("i4i4i4i4i4i4i4i4i4i4i4",pack,pack*2,pack*3,pack*4,pack*5,pack*6,pack*7,pack,pack,pack,pack))
	-- print("send",package, string.len(package))
	-- socket.send(fd, package)
	stringbuffer = pb.encode("tutorial.Reqlogin", {
		name = "liyan",
	})
	socket.send(fd, stringbuffer)
end

-- send_package( fd, 200 )

local function dispatch_package()
	while true do
		local r = socket.recv(fd)		
		if not r then
			break
		end
		print("r = ", r)
		local a = string.unpack( ">i4",r )
		print("a = ", a)
	end
end
local i = 0
while true do
	dispatch_package()
	local cmd = socket.readstdin()
	if cmd then
		send_package( fd, tonumber(cmd) )
		i = i + 1
	end
		socket.usleep(1000)
		
		
end