--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vajko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--- A reservation we put in the reservation table.
Conflict = CpObject()

function Conflict:init(vehicleId, timeStamp)
	self.vehicleId = vehicleId
	self.timeStamp = timeStamp
end

--- TrafficController provides a cooperative collision avoidance facility for all Courseplay driven vehicles.
--

TrafficController = CpObject()
TrafficController.debugChannel = 4

function TrafficController:init()
	self:debug('Traffic controller initialized')
end

-- This should be called once in an update cycle (globally, not vehicle specific)
function TrafficController:update(dt)
	self:drawDebugInfo()
end

function TrafficController:debug(...)
	courseplay:debug(string.format(...), self.debugChannel)
end

function TrafficController:drawDebugInfo()
	if not courseplay.debugChannels[self.debugChannel] then return end
end

g_trafficController = TrafficController()

