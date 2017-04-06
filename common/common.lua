function require_ex(modname)
    if package.loaded[modname] then
        package.loaded[modname] = nil
        print(string.format("require_ex %s", modname))
    end
    local ret, errstr = xpcall(function() require(modname) end, debug.traceback  )
    assert(ret, errstr)
    return ret
end

function module( name )
    local M = _G[name] or {}  
    _G[name]=M  
    package.loaded[name]=M  
    return M
end