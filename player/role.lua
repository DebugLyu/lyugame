-- player.lua
require( "functions" )

local role = class( "role" )

function role:ctor( ... )
	self.id_ = 0
	self.name_ = ""
	self.state_ = 0
	self.room_ = 0
end

function role:__init__()
	self.id_ = 0
	self.name_ = ""
	self.state_ = 0
	self.room_ = 0
end

function role:setInfo(info)
	self.id_ = info.id or 0
	self.name_ = info.name or ""
	self.state_ = info.state or 0
	self.room_ = info.room or 0
end

return role