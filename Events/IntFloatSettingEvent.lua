IntFloatSettingEvent = {};
IntFloatSettingEvent.TYPE_SETTING = 0
IntFloatSettingEvent.TYPE_GLOBAL = 1
IntFloatSettingEvent.TYPE_COURSEGENERATOR = 2
local IntFloatSettingEvent_mt = Class(IntFloatSettingEvent, Event);

InitEventClass(IntFloatSettingEvent, "IntFloatSettingEvent");

function IntFloatSettingEvent:emptyNew()
	local self = Event:new(IntFloatSettingEvent_mt);
	self.className = "IntFloatSettingEvent";
	return self;
end

function IntFloatSettingEvent:new(vehicle,parentName, name, value,isInt)
	courseplay:debug(string.format("courseplay:IntFloatSettingEvent:new(%s, %s, %s)", tostring(name),tostring(parentName), tostring(value)), 5)
	self.vehicle = vehicle;
	self.parentName = parentName
	self.messageNumber = Utils.getNoNil(self.messageNumber, 0) + 1
	self.name = name
	self.value = value;
	self.isInt = isInt
	return self;
end

function IntFloatSettingEvent:readStream(streamId, connection) -- wird aufgerufen wenn mich ein Event erreicht
	if streamReadBool(streamId) then
		self.vehicle = NetworkUtil.getObject(streamReadInt32(streamId))
	else
		self.vehicle = nil
	end
	self.parentName = streamReadString(streamId)
	local messageNumber = streamReadFloat32(streamId)
	self.name = streamReadString(streamId)
	if streamReadBool(streamId) then
		self.value = streamReadInt32(streamId)
	else 
		self.value = streamReadFloat32(streamId)
	end
	courseplay:debug("	readStream",5)
	courseplay:debug("		id: "..tostring(self.vehicle).."/"..tostring(messageNumber).."  self.parentName: "..tostring(self.parentName).."  self.name: "..tostring(self.name).."  self.value: "..tostring(self.value),5)

	self:run(connection);
end

function IntFloatSettingEvent:writeStream(streamId, connection)  -- Wird aufgrufen wenn ich ein event verschicke (merke: reihenfolge der Daten muss mit der bei readStream uebereinstimmen 
	courseplay:debug("		writeStream",5)
	courseplay:debug("			id: "..tostring(self.vehicle).."/"..tostring(self.messageNumber).."  self.parentName: "..tostring(self.parentName).."  self.name: "..tostring(self.name).."  value: "..tostring(self.value),5)

	if self.vehicle ~= nil then
		streamWriteBool(streamId, true)
		streamWriteInt32(streamId, NetworkUtil.getObjectId(self.vehicle))
	else
		streamWriteBool(streamId, false)
	end
	streamWriteString(streamId, self.parentName)
	streamWriteFloat32(streamId, self.messageNumber)
	streamWriteString(streamId, self.name)
	if self.isInt then 
		streamWriteBool(streamId, true)
		streamWriteInt32(streamId, self.value)
	else 
		streamWriteBool(streamId, false)
		streamWriteFloat32(streamId, self.value)
	end
end

function IntFloatSettingEvent:run(connection) -- wir fuehren das empfangene event aus
	courseplay:debug("\t\t\trun",5)
	courseplay:debug(('\t\t\t\tid=%s, name=%s, value=%s'):format(tostring(self.vehicle),tostring(self.parentName), tostring(self.name), tostring(self.value)), 5);

	if self.vehicle then 
		self.vehicle.cp[self.parentName][self.name]:setFromNetwork(self.value)
	else
		courseplay[self.parentName][self.name]:setFromNetwork(self.value)
	end
	if not connection:getIsServer() then
		courseplay:debug("broadcast settings event feedback",5)
		g_server:broadcastEvent(IntFloatSettingEvent:new(self.vehicle,self.parentName, self.name, self.value), nil, connection, self.vehicle);
	end;
end

function IntFloatSettingEvent.sendEvent(vehicle,parentName, name, value,isInt)
	if g_server ~= nil then
		courseplay:debug("broadcast settings event", 5)
		courseplay:debug(('\tid=%s, name=%s, value=%s'):format(tostring(vehicle), tostring(name), tostring(value)), 5);
		g_server:broadcastEvent(IntFloatSettingEvent:new(vehicle,parentName, name, value,isInt), nil, nil, self);
	else
		courseplay:debug("send settings event", 5)
		courseplay:debug(('\tid=%s, name=%s, value=%s'):format(tostring(vehicle), tostring(name), tostring(value)), 5);
		g_client:getServerConnection():sendEvent(IntFloatSettingEvent:new(vehicle,parentName, name, value,isInt));
	end;
end

