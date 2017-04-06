-- config.lua


local config = {
	DebugLevel = 1, -- 0 非debug 1 输出所有信息 2  3 仅输出重要信息
	PLAYER_ID_SEED_BEGIN = 10000,	
	ROOM_SEED_BEGIN = 100,

	database_config = {
		ip = "127.0.0.1",
		port = 3307,
		database = "qipai",
		user = "root",
		password = "123456",
	},
}

function config.Lprint( level, msg, ... )
	if config.DebugLevel == 0 then return end
	if level >= config.DebugLevel then 
		print( "["..os.date("%Y-%m-%d %H:%M:%S", os.time()).."]", msg, ... )
	end
end	


function config.Ldump( value, description )
	--默认打印层级3
	if type(nesting) ~= "number" then
	    nesting = 999
	end

	local lookupTable = {}
	local result =  {}

	local function _v(v)
	    if type(v) == "string" then
	        v = "\"" .. v .. "\""
	    end
	    return tostring(v)
	end

	local function _dump(value, description, indent, nest, keylen)
	    description = description or "<var>"
	    spc = ""
	    if type(keylen) == "number" then
	        spc = string.rep(" ",keylen - string.len(_v(description)))
	    end

	    if type(value) ~= "table" then
	        result[#result + 1] = string.format("%s%s%s = %s", indent, _v(description), spc, _v(value))
	    elseif lookupTable[value] then
	        result[#result + 1] = string.format("%s%s%s = *REF*", indent, description, spc)
	    else
	        lookupTable[value] = true
	        if nest > nesting then
	            result[#result + 1] = string.format("%s%s = *MAX NESTING*", indent, description)
	        else
	            result[#result + 1] = string.format("%s%s = {" , indent, _v(description))
	            local indent2 = indent .. "    "
	            local keys = {}
	            local keylen = 0
	            local values = {}
	            for k, v in pairs(value) do
	                keys[#keys + 1] = k
	                local vk = _v(k)
	                local vk1 = string.len(vk)
	                if vk1 > keylen then
	                    keylen = vk1
	                end
	                values[k] = v
	            end
	            table.sort(keys,function(a, b)
	                if type(a) == "number" and type(b) == "number" then
	                    return a < b
	                else
	                    return tostring(a) < tostring(b)
	                end
	            end)

	            for i, k in pairs(keys) do
	                _dump(values[k], k, indent2,nest + 1,keylen)
	            end
	            result[#result + 1] = string.format("%s}", indent)
	        end
	    end
	end
	_dump(value,description, "- ", 1)

	for i, line in pairs(result) do
	    config.Lprint(1,line)
	end
end
return config