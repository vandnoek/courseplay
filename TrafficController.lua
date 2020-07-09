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

function Conflict:init(vehicle1, vehicle2, triggerId, d, eta)
	self.vehicle1 = vehicle1
	self.vehicle2 = vehicle2
	self:update(triggerId, d, eta)
end

function Conflict:isBetween(vehicle1, vehicle2)
	if vehicle1 == self.vehicle1 and vehicle2 == self.vehicle2 then
		return true
	elseif vehicle1 == self.vehicle2 and vehicle2 == self.vehicle1 then
		return true
	else
		return false
	end
end

function Conflict:isCleared()
	return #self.triggers < 1
end

function Conflict:update(triggerId, d, eta)
	self.triggers[triggerId] = {d = d, eta = eta}
	self.closestTrigger = self.triggers[triggerId]
	local minD = math.huge
	for _, trigger in ipairs(self.triggers) do
		if trigger.d < minD then
			self.closestTrigger = trigger
			minD = d
		end
	end
end

function Conflict:__tostring()
	local result = string.format('%s <-> %s %d triggers', self.vehicle1:getName(), self.vehicle2:getName(), #self.triggers)
	if self.closestTrigger then
		result = string.format('%s, closest %.1f m %d sec', result, self.closestTrigger.d, self.closestTrigger.eta)
	end
	return result
end

--- TrafficController provides a cooperative collision avoidance facility for all Courseplay driven vehicles.
--

TrafficController = CpObject()
TrafficController.debugChannel = 4

function TrafficController:init()
	self.conflicts = {}
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
	local x, y, size = 0.1, 0.8, 0.012
	for i, conflict in ipairs(self.conflicts) do
		renderText(x, y, size, string.format('%d %s', i, conflict))
		y = y - size * 1.1
	end
end

function TrafficController:onConflictDetected(vehicle, otherVehicle, triggerId, d, eta)
	for conflict in ipairs(self.conflicts) do
		if conflict:isBetween(vehicle, otherVehicle) then
			conflict:update(triggerId, d, eta)
			return
		end
	end
	-- no conflict yet for this vehicle pair
	table.insert(self.conflicts, Conflict(vehicle, otherVehicle, triggerId, d, eta))
end

function TrafficController:onConflictCleared(vehicle, otherVehicle, triggerId, d, eta)
	for i, conflict in ipairs(self.conflicts) do
		if conflict:isBetween(vehicle, otherVehicle) then
			conflict:update(triggerId, d, eta)
			if conflict:isCleared() then
				table.remove(self.conflicts, i)
			end
			return
		end
	end
end

g_trafficController = TrafficController()

