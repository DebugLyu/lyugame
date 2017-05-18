local skynet = require "skynet"

function skynet.lcall(session, func, ...)
    return skynet.call( ".Lcall","lua", session, func, ... )
end

return skynet