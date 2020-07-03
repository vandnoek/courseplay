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
Reservation = CpObject()

function Reservation:init(vehicleId, timeStamp)
	self.vehicleId = vehicleId
	self.timeStamp = timeStamp
end

OwnReservation = CpObject()

function OwnReservation:init(vehicleId, timeStamp)
	self.vehicleId = vehicleId
	self.timeStamp = timeStamp
	self.ownPosition = true
end
--- TrafficController provides a cooperative collision avoidance facility for all Courseplay driven vehicles.
--
-- The TrafficController is a singleton object and should be initialized once after CP is loaded and
-- then call update() to update its clock (the clock is needed to remove stale reservations)
--
-- Vehicles should call reserve() when they reach a waypoint to reserve the next section of their path and to make sure
-- their path is not in conflict with another vehicle's future path.
--
-- Reservations are per tile in a grid representing the map. When a vehicle asks for a reservation, TrafficController
-- reserves the tiles under the future path of the vehicle (based on the course it is driving).
--
-- TrafficController looks into the future for lookaheadTimeSeconds (30 by default) only. So when a vehicle calls
-- reserve() with a waypoint index, only the part of the course lying within lookaheadTimeSeconds from that waypoint
-- is actually reserved.
--
-- The calculation is based on the speed stored in the course, or if that does not exist, the speed passed in to
-- reserve() or if none, it defaults to 10 km/h.
--
-- When reserve() is called, TrafficController also frees all tiles reserved for the waypoints behind the passed
-- in waypoint index.
--
-- When the course of the vehicle is updated or multiple waypoints are skipped, the vehicle should call cancel()
-- to cancel all existing reservations and then reserve() again from the current waypoint index.
--
-- TrafficController also periodically cleans up all stale reservations based on the timestamp recorded at
-- the time of the reservation and on the internal clock value. This is to make sure that forgotten reservations
-- don't block other vehicles forever.
--
-- Usage:
---------
-- After init() is called once to initialize the TrafficController singleton, call update()
-- periodically to update the internal clock and trigger the cleanup when necessary.
--
-- Vehicles should be calling reserve() once start moving with the current waypoint index and
-- check the return value.
-- If reserve returns false it means it could not reserve all the tiles for the next lookaheadTimeSeconds
-- and the vehicle should stop as its path is conflicting with another vehicles's path. The stopped
-- vehicle keeps calling reserve() until it returns true, at that point the path should be clear.
--

TrafficController = CpObject()
TrafficController.debugChannel = 4

function TrafficController:init()
	self.dateFormatString = '%H%M%S'
	self.prevTimeString = getDate(self.dateFormatString)
	self.clock = 0
	-- this is our window of traffic awareness, we only plan for the next 30 seconds
	self.lookaheadTimeSeconds = 15
	-- the reservation table grid size in meters. This should be less than the maximum waypoint distance
	self.gridSpacing = 1
	-- every so often we clean up stale reservations
	self.cleanUpIntervalSeconds = 20
	self.staleReservationTimeoutSeconds = 3 * self.lookaheadTimeSeconds
	-- this holds all the reservations
	self.reservations = {}
	-- this contains the vehicleId of the blocking vehicle
	self.blockingVehicleId = {}
	self.solvers = {}
	self:debug('Traffic controller initialized')
end

--- Update our clock and take care of stale entries
-- This should be called once in an update cycle (globally, not vehicle specific)
function TrafficController:update(dt)
	-- TODO: use
	-- The Giants engine does not seem to provide a clock, so implement our own.
	local currentTimeString = getDate(self.dateFormatString)
	if self.prevTimeString ~= currentTimeString then
		self.prevTimeString = currentTimeString
		self.clock = self.clock + 1
	end
	if self.clock % self.cleanUpIntervalSeconds == 0 then
		self:cleanUp()
	end

	self:drawDebugInfo()
end

--- Make a reservation for the next lookaheadTimeSeconds interval
-- @param vehicleId unique ID of the reserving vehicle
---@param course Course vehicle course
-- @param fromIx index of the course waypoint where we start the reservation
---@param width number vehicle width
-- @param speed expected speed of the vehicle in km/h. If not given will use the speed in the course.
-- @return true if successfully reserved _all_ tiles. When returning false it may
-- reserve some of the tiles though.
function TrafficController:reserve(vehicleId, course, fromIx, width, speed)
	self:freePreviousTiles(vehicleId, course, fromIx, width, speed)
	local ok = self:reserveNextTiles(vehicleId, course, fromIx, width, speed)
	if ok then
		self.blockingVehicleId[vehicleId] = nil
	end
	return ok
end

function TrafficController:reserveOwnPosition(vehicle)
	self:cancelOwnPosition(vehicle.rootNode)
	local length = vehicle.cp.totalLength or 5
	for i=0,-length,-self.gridSpacing do
		local x,y,z = localToWorld(vehicle.rootNode,0,0,i)
		local currentPoint = Point(x, z)
		local gx,gz = self:getGridCoordinates(currentPoint)
		local gridPoint = Point(gx,gz)
		self:reserveGridPoint(gridPoint, OwnReservation(vehicle.rootNode, self.clock))
	end
end

function TrafficController:cancelOwnPosition(vehicleId)
	for row in pairs(self.reservations) do
		for col in pairs(self.reservations[row]) do
			local reservation = self.reservations[row][col]
			if reservation and reservation.vehicleId == vehicleId and reservation.ownPosition then
				self.reservations[row][col] = nil
			end
		end
	end
end

function TrafficController:solve(vehicleId)
	if not self.solvers[vehicleId] then
		self.solvers[vehicleId] = TrafficControllerSolver(vehicleId)
	end
	self.solvers[vehicleId]:solveCollision()
end


function TrafficController:resetSolver(vehicleId)
	if self.solvers[vehicleId] then
		self.solvers[vehicleId]= nil
	end
end

function TrafficController:getHasSolver(vehicleId)
	return g_trafficController.solvers[vehicleId] ~= nil
end


function TrafficController:getBlockingVehicleId(vehicleId)
	return self.blockingVehicleId[vehicleId]
end

--- Free waypoints already passed
-- use the link to the previous tile to walk back until the oldest one is reached.
function TrafficController:freePreviousTiles(vehicleId, course, fromIx, width, speed)
	local tiles = self:getGridPointsUnderCourse(course, fromIx - 2, width, speed, true)
	for i = 1, #tiles do
		self:freeTile(tiles[i], vehicleId)
	end
end

function TrafficController:reserveNextTiles(vehicleId, course, fromIx, width, speed)
	local ok = true
	local gridPoints = self:getGridPointsUnderCourse(course, fromIx, width, speed, false)
	for i = 1, #gridPoints do
		if not self:reserveTile(gridPoints[i], Reservation(vehicleId, self.clock)) then
			return false
		end
	end
	return ok
end



local function plotLine(pixels, x0, y0, x1, y1)
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	local dx, sx = math.abs(x1 - x0), x0 < x1 and 1 or -1
	local dy, sy = -math.abs(y1 - y0), y0 < y1 and 1 or -1
	local err, e2 = dx + dy

	while true do
		table.insert(pixels, Point(x0, -y0))
		e2 = 2 * err
		if e2 >= dy then
			if x0 == x1 then break end
			err = err + dy
			x0 = x0 + sx
		end
		if e2 <= dx then
			if y0 == y1 then break end
			err = err + dx
			y0 = y0 + sy
		end
	end
end

---@return table
local function plotThickLine(pixels, x0, y0, x1, y1, w)
	w = math.max(2, math.floor(w + 0.5))
	local halfWidth = math.floor(w / 2 + 0.5)
	local dx, dy = x1 - x0, y1 - y0
	local s = Vector(x0, y0)
	---@type Vector
	local v = Vector(dx, dy):rotate(math.rad(-90))
	plotLine(pixels, x0, y0, x1, y1)
	for w1 = 1, halfWidth do
		v:setLength(w1)
		local s1 = s + v
		plotLine(pixels, s1.x, s1.y, s1.x + dx, s1.y + dy)
	end
	v = Vector(dx, dy):rotate(math.rad(90))
	for w1 = 1, halfWidth do
		v:setLength(w1)
		local s1 = s + v
		plotLine(pixels, s1.x, s1.y, s1.x + dx, s1.y + dy)
	end
	return pixels
end


--- Get the list of tiles the segment of the course defined by the iterator is passing through, using the
-- speed in the course or the one supplied here. Will find the tiles reached in lookaheadTimeSeconds only
-- (based on the speed and the waypoint distance)
---@param course Course
function TrafficController:getGridPointsUnderCourse(course, fromIx, width, speed, backwards)
	local tiles = {}
	local vMetersPerSecond = (speed or course:getAverageSpeed(fromIx, 3) or 10) / 3.6
	local toIx = course:getNextWaypointIxWithinDistance(fromIx, vMetersPerSecond * self.lookaheadTimeSeconds, backwards)
	if not toIx then return tiles end
	for i = fromIx, toIx - 1, backwards and -1 or 1 do
		local x0, _, z0 = course:getWaypointPosition(i)
		local x1, _, z1 = course:getWaypointPosition(i + 1)
		tiles = plotThickLine(tiles, x0, -z0, x1, -z1, width)
	end
	return tiles
end

--- If waypoint a and b a farther apart than the grid spacing then we need to
-- add points in between so wo don't miss a tile
function TrafficController:getIntermediatePoints(course, ixA, ixB)
	local ax,_,az = course:getWaypointPosition(ixA)
	local bx,_,bz = course:getWaypointPosition(ixB)
	local dx, dz = bx - ax, bz - az
	local d = math.sqrt(dx * dx + dz * dz)
	local nx, nz = dx / d, dz / d
	local nPoints = math.floor((d - 0.001) / self.gridSpacing) -- 0.001 makes sure we have only one wp even if a and b are exactly on the grid
	local x, z = ax, az
	local intermediatePoints = {}
	for i = 1, nPoints do
		x, z = x + self.gridSpacing * nx, z + self.gridSpacing * nz
		table.insert(intermediatePoints, {x = x, z = z})
	end
	return intermediatePoints
end

--- Add tiles around x, z to the list of tiles.
function TrafficController:getTilesAroundPoint(point)
	return {
		point,
		Point(point.x - 1, point.z),
		Point(point.x + 1, point.z),
		Point(point.x, point.z - 1),
		Point(point.x, point.z + 1)
	}
end

--- Reserve a grid point. This will reserve the tile the point is on and the adjacent tiles (above, below, left and right,
-- but not diagonally) as well to make sure the vehicle has enough clearance from all sides.
function TrafficController:reserveGridPoint(point, reservation)
	local ok = true
	-- reserve tiles around point
	for _, tile in ipairs(self:getTilesAroundPoint(point)) do
		ok = ok and  self:reserveTile(tile, reservation)
	end
	return ok
end

function TrafficController:freeGridPoint(point, vehicleId)
	-- free tiles around point
	for _, tile in ipairs(self:getTilesAroundPoint(point)) do
		self:freeTile(tile, vehicleId)
	end
end

function TrafficController:freeTile(point, vehicleId)
	if not self.reservations[point.x] then
		return
	end
	if not self.reservations[point.x][point.z] then
		return
	end
	if self.reservations[point.x][point.z].vehicleId == vehicleId then
		-- no more reservations left, remove entry
		self.reservations[point.x][point.z] = nil
	end
end

function TrafficController:reserveTile(point, reservation)
	if not self.reservations[point.x] then
		--print("make a new X:"..tostring(point.x))
		self.reservations[point.x] = {}
	end
	if self.reservations[point.x][point.z] then
		--print(string.format("check reservations[%d][%d]:",point.x,point.z))
		if self.reservations[point.x][point.z].vehicleId == reservation.vehicleId then
			-- already reserved for this vehicle
			return true
		elseif reservation.ownPosition then
			-- reserved for another vehicle but we overwrite it because this is a vehicles position and no one other should be here
		else
			-- reserved for another vehicle
			self.blockingVehicleId[reservation.vehicleId] = self.reservations[point.x][point.z].vehicleId
			return false
		end
	end
	--print(string.format("self.reservations[%s][%s] = reservation",tostring(point.x),tostring(point.z)))
	self.reservations[point.x][point.z] = reservation
	return true
end

function TrafficController:getGridCoordinates(wp)
	local gridX = math.floor(wp.x / self.gridSpacing)
	local gridZ = math.floor(wp.z / self.gridSpacing)
	return gridX, gridZ
end

function TrafficController:getGridCoordinatesFromCourse(course,ix)
	local x,_,z = course:getWaypointPosition(ix)
	local gridX = math.floor(x / self.gridSpacing)
	local gridZ = math.floor(z / self.gridSpacing)
	return gridX, gridZ
end


--- Cancel all reservations for a vehicle
function TrafficController:cancel(vehicleId)
	for row in pairs(self.reservations) do
		for col in pairs(self.reservations[row]) do
			local reservation = self.reservations[row][col]
			if reservation and reservation.vehicleId == vehicleId then
				self.reservations[row][col] = nil
			end
		end
	end
end

--- Clean up all stale reservations
function TrafficController:cleanUp(vehicleId)
	local nTotalReservedTiles = 0
	local nFreedTiles = 0
	for row in pairs(self.reservations) do
		for col in pairs(self.reservations[row]) do
			local reservation = self.reservations[row][col]
			if reservation and not reservation.ownPosition then
				nTotalReservedTiles = nTotalReservedTiles + 1
				if reservation.timeStamp <= (self.clock - self.staleReservationTimeoutSeconds) then
					self.reservations[row][col] = nil
					nFreedTiles = nFreedTiles + 1
					nTotalReservedTiles = nTotalReservedTiles - 1
				end
			end
		end
	end
	if nFreedTiles > 0 then
		self:debug('Clean up: freed %d tiles, total %d reserved tiles remaining.', nFreedTiles, nTotalReservedTiles)
	end
end

function TrafficController:forwardIterator(from, to)
	return  function()
		local i, n = from - 1, to
		return function()
			i = i + 1
			if i <= n then return i end
		end
	end
end

function TrafficController:backwardIterator(from)
	return  function()
		local i = from
		return function()
			i = i - 1
			if i >= 1 then return i end
		end
	end
end

function TrafficController:__tostring()
	local result = ''
	for row = 0, 9 do
		for col = 0, 9 do
			local reservation = self.reservations[row] and self.reservations[row][col]
			if reservation then
				result = result .. reservation.vehicleId
			else
				result = result .. '.'
			end
		end
		result = result .. '\n'
	end
	return result
end

function TrafficController:debug(...)
	courseplay:debug(string.format(...), self.debugChannel)
end

function TrafficController:drawDebugInfo()
	if not courseplay.debugChannels[self.debugChannel] then return end
		--self.reservations[point.x][point.z].vehicleId
	for pointX, list in pairs (self.reservations) do
		for pointZ, _ in pairs(list) do
			local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,pointX*self.gridSpacing,1,pointZ*self.gridSpacing)
			--cpDebug:drawPoint(pointX*self.gridSpacing+1.5, y+0.2, pointZ*self.gridSpacing+1.5, 0, 0, 100)
			--cpDebug:drawPoint(pointX*self.gridSpacing+-1.5, y+0.2, pointZ*self.gridSpacing-1.5, 100, 0, 0)
			cpDebug:drawPoint(pointX*self.gridSpacing, y+0.2, pointZ*self.gridSpacing, 1, 1, 1)
			--Utils.renderTextAtWorldPosition(pointX*self.gridSpacing,y+0.2,pointZ*self.gridSpacing, tostring(data.vehicleId), getCorrectTextSize(0.012), 0)
		end
	end
end

g_trafficController = TrafficController()

