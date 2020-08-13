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

---@class Conflict
Conflict = CpObject()

-- a collision trigger must be present for at least so many milliseconds before it is considered for a conflict
Conflict.detectionThresholdMilliSec = 1000
-- a collision trigger must be cleared for at least so many milliseconds before it is removed from a conflict
Conflict.clearThresholdMilliSec = 1000

function Conflict:init(vehicle1, vehicle2, triggerId, d, eta, otherD, otherEta, yRotDiff)
	self.vehicle1 = vehicle1
	self.vehicle2 = vehicle2
    self.triggers = {}
	-- need to count them ourselves as it triggers is a hash, not an array
	self.nTriggers = 0
	self:onDetected(triggerId, vehicle1, vehicle2, d, eta, otherD, otherEta, yRotDiff)
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
	return self.nTriggers < 1
end

function Conflict:onDetected(triggerId, detectedBy, otherVehicle, d, eta, otherD, otherEta, yRotDiff)
	self.triggers[triggerId] = {detectedBy = detectedBy, otherVehicle = otherVehicle,
								d = d, eta = eta, otherD = otherD, otherEta = otherEta,
								yRotDiff = yRotDiff, detectedAt = g_time}
	self:update()
end

function Conflict:onCleared(triggerId)
	self.triggers[triggerId].timeCleared = g_time
	self:update()
end

function Conflict:update()
	local minEta = math.huge
	self.nTriggers = 0
	local triggersToRemove = {}
	for _, trigger in pairs(self.triggers) do
		if not trigger.timeCleared and trigger.eta < minEta and g_time - trigger.detectedAt > Conflict.detectionThresholdMilliSec then
			self.closestTrigger = trigger
			minEta = self.closestTrigger.eta
		end
		self.nTriggers = self.nTriggers + 1
		if trigger.timeCleared and g_time - trigger.timeCleared > Conflict.clearThresholdMilliSec then
			-- been cleared long ago, mark for removal
			table.insert(triggersToRemove, trigger)
			self.nTriggers = self.nTriggers - 1
		end
	end
	-- remove cleared triggers
	for _, trigger in pairs(triggersToRemove) do
		self.triggers[trigger] = nil
	end
end

function Conflict:resolve()
	if self.closestTrigger then
		-- if we are already holding someone, keep doing so until the conflict is resolved, otherwise:
		if not self.vehicleToHold then
			if math.abs(self.closestTrigger.yRotDiff) < math.rad(45) then
				-- one vehicle is behind the other
				if self.closestTrigger.d < self.closestTrigger.otherD then
					-- detecting vehicle is closer to the conflict, so the other is behind it
					self.vehicleToHold = self.closestTrigger.otherVehicle
					self.vehicleWithRightOfWay = self.closestTrigger.detectedBy
				else
					self.vehicleToHold = self.closestTrigger.detectedBy
					self.vehicleWithRightOfWay = self.closestTrigger.otherVehicle
				end
			else
				-- vehicles crossing paths, decide on priority
				if self.closestTrigger.detectedBy.cp.driver:is_a(CombineUnloadAIDriver) and
						self.closestTrigger.otherVehicle.cp.driver:is_a(CombineAIDriver) then
					self.vehicleToHold = self.closestTrigger.detectedBy
					self.vehicleWithRightOfWay = self.closestTrigger.otherVehicle
				elseif self.closestTrigger.otherVehicle.cp.driver:is_a(CombineUnloadAIDriver) and
						self.closestTrigger.detectedBy.cp.driver:is_a(CombineAIDriver) then
					self.vehicleToHold = self.closestTrigger.otherVehicle
					self.vehicleWithRightOfWay = self.closestTrigger.detectedBy
				else
					self.vehicleToHold = self.closestTrigger.otherVehicle
					self.vehicleWithRightOfWay = self.closestTrigger.detectedBy
				end
			end
		end
		if self.vehicleToHold.cp.driver then
			self.vehicleToHold.cp.driver:onConflict(self.vehicleWithRightOfWay,
					self.closestTrigger.d, self.closestTrigger.eta, self.closestTrigger.yRotDiff, true)
		end
	else
		return nil
	end
end

function Conflict:getClosest()
	if self.closestTrigger then
		return self.detectedBy, self.conflictingVehicle, self.closestTrigger.d, self.closestTrigger.eta,
			self.closestTrigger.otherD, self.closestTrigger.otherEta, self.closestTrigger.yRotDiff
	else
		return nil
	end
end

function Conflict:__tostring()
	local result = string.format('Traffic conflict: %s <-> %s %d triggers', self.vehicle1:getName(), self.vehicle2:getName(), self.nTriggers)
	if self.closestTrigger then
		result = string.format('%s, closest %.1f m %d sec %.1f°', result, self.closestTrigger.d or -1, self.closestTrigger.eta or -1,
				self.closestTrigger.yRotDiff and math.deg(self.closestTrigger.yRotDiff) or 0)
	end
	return result
end

--- TrafficController provides a cooperative collision avoidance facility for all Courseplay driven vehicles.
--

TrafficController = CpObject()
TrafficController.debugChannel = 4

function TrafficController:init()
	---@type Conflict[]
	self.conflicts = {}
	self:debug('Traffic controller initialized')
end

-- This should be called once in an update cycle (globally, not vehicle specific)
function TrafficController:update()
	-- iterate backwards as we'll remove table elements
	for i = #self.conflicts, 1, -1 do
		---@type Conflict
		local conflict = self.conflicts[i]
		conflict:update()
		conflict:resolve()
		if conflict:isCleared() then
			table.remove(self.conflicts, i)
		end
	end
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

function TrafficController:onConflictDetected(vehicle, otherVehicle, triggerId, d, eta, otherD, otherEta, yRotDiff)
	for _, conflict in ipairs(self.conflicts) do
		if conflict:isBetween(vehicle, otherVehicle) then
			conflict:onDetected(triggerId, vehicle, otherVehicle, d, eta, otherD, otherEta, yRotDiff)
			return
		end
	end
	-- first conflict for this vehicle pair
	table.insert(self.conflicts, Conflict(vehicle, otherVehicle, triggerId, d, eta, otherD, otherEta, yRotDiff))
end

function TrafficController:onConflictCleared(vehicle, otherVehicle, triggerId)
	for i, conflict in ipairs(self.conflicts) do
		if conflict:isBetween(vehicle, otherVehicle) then
			conflict:onCleared(triggerId)
			return
		end
	end
end

g_trafficController = TrafficController()

