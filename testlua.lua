-- testlua.lua
local t = {}
t[1] = {a = 1321}
t[2] = {a = 22222}

local c = t[1]
t[1] = nil
table.remove( t, 1 )
print(c.a)
print(t[1].a)