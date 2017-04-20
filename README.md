# lyugame

clone skynet and build
https://github.com/cloudwu/skynet/

clone lyugame and put it in skynet root directory

move lyugame/3rdlib/protobuf.so to skynet/luaclib
move lyugame/3rdlib/protobuf.lua to skynet/lualib
make dir logs at skynet/

modify skynet source
	1 find skynet.lua
	2 find function skynet.timeout
	3 add "return session" at the function last line

	function skynet.timeout(ti, func)
		local session = c.intcommand("TIMEOUT",ti)
		assert(session)
		local co = co_create(func)
		assert(session_id_coroutine[session] == nil)
		session_id_coroutine[session] = co
		return session
	end

	4 add a function
	
	function skynet.stoptimer( session )
		session_id_coroutine[session] = "BREAK"
	end

	ps:this function is used for stop timeout coroutine
	
cd skynet

run ./skynet ./lyugame/config.lyugame

have fun