CourseEvent = {};
local CourseEvent_mt = Class(CourseEvent, Event);

InitEventClass(CourseEvent, "CourseEvent");

function CourseEvent:emptyNew()
	local self = Event:new(CourseEvent_mt);
	self.className = "CourseEvent";
	return self;
end

function CourseEvent:new(vehicle,course)
	self.vehicle = vehicle;
	self.course = course
	return self;
end

function CourseEvent:readStream(streamId, connection) -- wird aufgerufen wenn mich ein Event erreicht
	courseplay.debugVehicle(5,self.vehicle,"readStream course event")
	if streamReadBool(streamId) then
		self.vehicle = NetworkUtil.getObject(streamReadInt32(streamId))
	else
		self.vehicle = nil
	end
	local wp_count = streamReadInt32(streamId)
	self.course = {}
	for w = 1, wp_count do
		table.insert(self.course, CourseEvent:readWaypoint(streamId))
	end
	self:run(connection);
end

function CourseEvent:writeStream(streamId, connection)  -- Wird aufgrufen wenn ich ein event verschicke (merke: reihenfolge der Daten muss mit der bei readStream uebereinstimmen 
	courseplay.debugVehicle(5,self.vehicle,"writeStream course event")
	if self.vehicle ~= nil then
		streamWriteBool(streamId, true)
		streamWriteInt32(streamId, NetworkUtil.getObjectId(self.vehicle))
	else
		streamWriteBool(streamId, false)
	end
	streamWriteInt32(streamId, #(self.course))
	for w = 1, #(self.course) do
		CourseEvent:writeWaypoint(streamId, self.course[w],w)
	end
end

function CourseEvent:run(connection) -- wir fuehren das empfangene event aus
	courseplay.debugVehicle(5,self.vehicle,"run course event")
	if self.vehicle then 
		courseplay:setVehicleWaypoints(self.vehicle, self.course)
	end
	if not connection:getIsServer() then
		courseplay.debugVehicle(5,self.vehicle,"broadcast course event feedback")
		g_server:broadcastEvent(CourseEvent:new(self.vehicle,self.course), nil, connection, self.vehicle);
	end;
end

function CourseEvent.sendEvent(vehicle,course)
	if course and #course > 0 then
		if g_server ~= nil then
			courseplay.debugVehicle(5,vehicle,"broadcast course event")
			g_server:broadcastEvent(CourseEvent:new(vehicle,course), nil, nil, vehicle);
		else
			courseplay.debugVehicle(5,vehicle,"send course event")
			g_client:getServerConnection():sendEvent(CourseEvent:new(vehicle,course));
		end;
	else 
		courseplay.infoVehicle(vehicle, 'CourseEvent Error: course = nil or #course<1!!!')
	end
end


function CourseEvent:writeWaypoint(streamId, waypoint,index)
	courseplay.debugVehicle(5,self.vehicle,"waypoint: %s",tostring(index))
	if courseplay.debugChannels[5] then
		DebugUtil.printTableRecursively(waypoint, '  ', 1, 1)
	end
	streamWriteFloat32(streamId, waypoint.cx or 0)
	streamWriteFloat32(streamId, waypoint.cz or 0)
	streamWriteFloat32(streamId, waypoint.angle or 0)
	streamWriteBool(streamId, waypoint.wait or false)
	streamWriteBool(streamId, waypoint.rev or false)
	streamWriteBool(streamId, waypoint.crossing or false)
	streamWriteInt32(streamId, waypoint.speed or 0)

	streamWriteBool(streamId, waypoint.generated or false)
	
	streamWriteBool(streamId, waypoint.turnStart or false)
	streamWriteBool(streamId, waypoint.turnEnd or false)
	streamWriteInt32(streamId, waypoint.ridgeMarker or 0)
	streamWriteInt32(streamId, waypoint.headlandHeightForTurn or 0)
	
	streamWriteBool(streamId, waypoint.isConnectingTrack or false)
	streamWriteBool(streamId, waypoint.mustReach or false)
	streamWriteBool(streamId, waypoint.align or false)
	streamWriteInt32(streamId, waypoint.lane or 0)
	streamWriteInt32(streamId, waypoint.radius or 0)
	--[[
	
		wp.generated = true
		wp.ridgeMarker = point.ridgeMarker
		wp.angle = courseGenerator.toCpAngleDeg( point.nextEdge.angle )
		wp.cx = point.x
		wp.cz = -point.y
		wp.wait = nil
		if point.rev then
			wp.rev = point.rev
		else
			wp.rev = false
		end
		wp.crossing = nil
		wp.speed = 0

		if point.passNumber then
			wp.lane = -point.passNumber
		end
		if point.turnStart then
			wp.turnStart = true
		end
		if point.turnEnd then
			wp.turnEnd = true
		end
		if point.isConnectingTrack then
			wp.isConnectingTrack = true
		end
		if point.mustReach then
			wp.mustReach = true
		end
		if point.align then
			wp.align = true
		end
		wp.headlandHeightForTurn = point.headlandHeightForTurn
		if point.islandBypass then
			-- save radius only for island bypass sections for now.
			wp.radius = point.radius
		end
	
	]]--
end;

function CourseEvent:readWaypoint(streamId)
	local cx = streamReadFloat32(streamId)
	local cz = streamReadFloat32(streamId)
	local angle = streamReadFloat32(streamId)
	local wait = streamReadBool(streamId)
	local rev = streamReadBool(streamId)
	local crossing = streamReadBool(streamId)
	local speed = streamReadInt32(streamId)

	local generated = streamReadBool(streamId)
	--local dir = streamDebugReadString(streamId)
	local turnStart = streamReadBool(streamId)
	local turnEnd = streamReadBool(streamId)
	local ridgeMarker = streamReadInt32(streamId)
	local headlandHeightForTurn = streamReadInt32(streamId)

	local isConnectingTrack = streamReadBool(streamId)
	local mustReach = streamReadBool(streamId)
	local align = streamReadBool(streamId)
	local lane = streamReadInt32(streamId)
	local radius = streamReadInt32(streamId)

	local wp = {
		cx = cx, 
		cz = cz, 
		angle = angle, 
		wait = wait, 
		rev = rev, 
		crossing = crossing, 
		speed = speed,
		generated = generated,
		turnStart = turnStart,
		turnEnd = turnEnd,
		ridgeMarker = ridgeMarker,
		headlandHeightForTurn = headlandHeightForTurn,
		
		isConnectingTrack = isConnectingTrack,
		mustReach = mustReach,
		align = align,
		lane = lane,
		radius = radius
	};
	return wp;
end;