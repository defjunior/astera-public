local RemotePacketCodec = {}

local TAG_NIL = 0
local TAG_NUMBER = 1
local TAG_BOOLEAN = 2
local TAG_STRING = 3
local TAG_VECTOR3 = 4
local TAG_COLOR3 = 5
local TAG_CFRAME = 6
local TAG_INSTANCE = 7
local TAG_ENUM = 8
local TAG_TABLE = 9

local function isArray(tbl)
	local count = 0
	for key, _ in pairs(tbl) do
		if key == "n" then
			continue
		end
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count += 1
	end
	for index = 1, count do
		if tbl[index] == nil then
			return false
		end
	end
	return true
end

local function measureValue(value)
	local valueType = typeof(value)
	if value == nil then
		return 1
	elseif valueType == "number" then
		return 9
	elseif valueType == "boolean" then
		return 2
	elseif valueType == "string" then
		return 3 + #value
	elseif valueType == "Vector3" then
		return 13
	elseif valueType == "Color3" then
		return 4
	elseif valueType == "CFrame" then
		return 49
	elseif valueType == "Instance" then
		return 3
	elseif valueType == "EnumItem" then
		local enumTypeName = value.EnumType and value.EnumType.Name or ""
		return 1 + (2 + #enumTypeName) + (2 + #value.Name)
	elseif valueType == "table" then
		local size = 4
		if isArray(value) then
			local length = tonumber(value.n) or #value
			for index = 1, length do
				size += measureValue(value[index])
			end
		else
			for key, entry in pairs(value) do
				size += measureValue(key)
				size += measureValue(entry)
			end
		end
		return size
	end

	error(("[RemotePacketCodec] unsupported value type: %s"):format(valueType))
end

local function writeString(buff, offset, value)
	local len = #value
	buffer.writeu16(buff, offset, len)
	buffer.writestring(buff, offset + 2, value, len)
	return 2 + len
end

local function encodeValue(buff, offset, value, instances)
	local valueType = typeof(value)
	if value == nil then
		buffer.writeu8(buff, offset, TAG_NIL)
		return 1
	elseif valueType == "number" then
		buffer.writeu8(buff, offset, TAG_NUMBER)
		buffer.writef64(buff, offset + 1, value)
		return 9
	elseif valueType == "boolean" then
		buffer.writeu8(buff, offset, TAG_BOOLEAN)
		buffer.writeu8(buff, offset + 1, value and 1 or 0)
		return 2
	elseif valueType == "string" then
		buffer.writeu8(buff, offset, TAG_STRING)
		return 1 + writeString(buff, offset + 1, value)
	elseif valueType == "Vector3" then
		buffer.writeu8(buff, offset, TAG_VECTOR3)
		buffer.writef32(buff, offset + 1, value.X)
		buffer.writef32(buff, offset + 5, value.Y)
		buffer.writef32(buff, offset + 9, value.Z)
		return 13
	elseif valueType == "Color3" then
		buffer.writeu8(buff, offset, TAG_COLOR3)
		buffer.writeu8(buff, offset + 1, math.clamp(math.floor(value.R * 255 + 0.5), 0, 255))
		buffer.writeu8(buff, offset + 2, math.clamp(math.floor(value.G * 255 + 0.5), 0, 255))
		buffer.writeu8(buff, offset + 3, math.clamp(math.floor(value.B * 255 + 0.5), 0, 255))
		return 4
	elseif valueType == "CFrame" then
		buffer.writeu8(buff, offset, TAG_CFRAME)
		local components = { value:GetComponents() }
		local ptr = offset + 1
		for index = 1, 12 do
			buffer.writef32(buff, ptr, components[index] or 0)
			ptr += 4
		end
		return 49
	elseif valueType == "Instance" then
		buffer.writeu8(buff, offset, TAG_INSTANCE)
		instances[#instances + 1] = value
		buffer.writeu16(buff, offset + 1, #instances)
		return 3
	elseif valueType == "EnumItem" then
		buffer.writeu8(buff, offset, TAG_ENUM)
		local enumTypeName = value.EnumType and value.EnumType.Name or ""
		local ptr = offset + 1
		ptr += writeString(buff, ptr, enumTypeName)
		ptr += writeString(buff, ptr, value.Name)
		return ptr - offset
	elseif valueType == "table" then
		buffer.writeu8(buff, offset, TAG_TABLE)
		local arrayLike = isArray(value)
		buffer.writeu8(buff, offset + 1, arrayLike and 1 or 2)
		local ptr = offset + 2
		if arrayLike then
			local length = tonumber(value.n) or #value
			buffer.writeu16(buff, ptr, length)
			ptr += 2
			for index = 1, length do
				ptr += encodeValue(buff, ptr, value[index], instances)
			end
		else
			local keys = {}
			for key, _ in pairs(value) do
				keys[#keys + 1] = key
			end
			buffer.writeu16(buff, ptr, #keys)
			ptr += 2
			for _, key in ipairs(keys) do
				ptr += encodeValue(buff, ptr, key, instances)
				ptr += encodeValue(buff, ptr, value[key], instances)
			end
		end
		return ptr - offset
	end

	error(("[RemotePacketCodec] unsupported payload type: %s"):format(valueType))
end

local function decodeString(buff, offset)
	local len = buffer.readu16(buff, offset)
	return buffer.readstring(buff, offset + 2, len), 2 + len
end

local function decodeValue(buff, offset, instances)
	local tag = buffer.readu8(buff, offset)
	local ptr = offset + 1
	if tag == TAG_NIL then
		return nil, 1
	elseif tag == TAG_NUMBER then
		return buffer.readf64(buff, ptr), 9
	elseif tag == TAG_BOOLEAN then
		return buffer.readu8(buff, ptr) == 1, 2
	elseif tag == TAG_STRING then
		local value, bytes = decodeString(buff, ptr)
		return value, 1 + bytes
	elseif tag == TAG_VECTOR3 then
		return Vector3.new(
			buffer.readf32(buff, ptr),
			buffer.readf32(buff, ptr + 4),
			buffer.readf32(buff, ptr + 8)
		), 13
	elseif tag == TAG_COLOR3 then
		return Color3.fromRGB(
			buffer.readu8(buff, ptr),
			buffer.readu8(buff, ptr + 1),
			buffer.readu8(buff, ptr + 2)
		), 4
	elseif tag == TAG_CFRAME then
		local components = table.create(12)
		for index = 1, 12 do
			components[index] = buffer.readf32(buff, ptr + ((index - 1) * 4))
		end
		return CFrame.new(table.unpack(components, 1, 12)), 49
	elseif tag == TAG_INSTANCE then
		local idx = buffer.readu16(buff, ptr)
		return instances[idx], 3
	elseif tag == TAG_ENUM then
		local enumTypeName, bytesA = decodeString(buff, ptr)
		local itemName, bytesB = decodeString(buff, ptr + bytesA)
		local enumType = Enum[enumTypeName]
		return enumType and enumType[itemName] or nil, 1 + bytesA + bytesB
	elseif tag == TAG_TABLE then
		local kind = buffer.readu8(buff, ptr)
		ptr += 1
		local length = buffer.readu16(buff, ptr)
		ptr += 2
		local output = {}
		local totalBytes = 4
		if kind == 1 then
			output.n = length
			for index = 1, length do
				local value, bytes = decodeValue(buff, ptr, instances)
				ptr += bytes
				output[index] = value
				totalBytes += bytes
			end
		else
			output.n = length
			for _ = 1, length do
				local key, keyBytes = decodeValue(buff, ptr, instances)
				ptr += keyBytes
				local value, valueBytes = decodeValue(buff, ptr, instances)
				ptr += valueBytes
				output[key] = value
				totalBytes += keyBytes + valueBytes
			end
		end
		return output, totalBytes
	end

	error(("[RemotePacketCodec] unsupported payload tag: %s"):format(tostring(tag)))
end

function RemotePacketCodec.EncodeTable(value)
	local payload = value
	local instances = {}
	local size = measureValue(payload)
	local packed = buffer.create(size)
	encodeValue(packed, 0, payload, instances)
	return packed, instances
end

function RemotePacketCodec.DecodeTable(packed, instances)
	if typeof(packed) ~= "buffer" then
		if type(packed) == "table" then
			return packed
		end
		return {}
	end
	local decoded = decodeValue(packed, 0, instances or {})
	return decoded
end

function RemotePacketCodec.EncodeCall(name, args)
	local payload = type(args) == "table" and args or {}
	local instances = {}
	local size = 4 + #name
	local count = tonumber(payload.n) or #payload
	for index = 1, count do
		size += measureValue(payload[index])
	end

	local packed = buffer.create(size)
	buffer.writeu16(packed, 0, #name)
	buffer.writestring(packed, 2, name, #name)
	local ptr = 2 + #name
	buffer.writeu16(packed, ptr, count)
	ptr += 2
	for index = 1, count do
		ptr += encodeValue(packed, ptr, payload[index], instances)
	end

	return packed, instances
end

function RemotePacketCodec.DecodeCall(expectedName, packed, instances)
	if typeof(packed) ~= "buffer" then
		return type(packed) == "table" and packed or {}
	end
	local size = buffer.len(packed)
	if size < 4 then
		error("[RemotePacketCodec] payload too small")
	end
	local nameLength = buffer.readu16(packed, 0)
	local encodedName = buffer.readstring(packed, 2, nameLength)
	if expectedName ~= nil and encodedName ~= expectedName then
		warn(("[RemotePacketCodec] call name mismatch: expected %s, got %s"):format(tostring(expectedName), tostring(encodedName)))
	end
	local ptr = 2 + nameLength
	local count = buffer.readu16(packed, ptr)
	ptr += 2
	local out = table.create(count)
	out.n = count
	for index = 1, count do
		local value, bytes = decodeValue(packed, ptr, instances or {})
		ptr += bytes
		out[index] = value
	end
	return out
end

function RemotePacketCodec.EncodeValue(value)
	local packed, instances = RemotePacketCodec.EncodeTable(value)
	return packed, instances
end

function RemotePacketCodec.DecodeValue(packed, instances)
	return RemotePacketCodec.DecodeTable(packed, instances)
end

return RemotePacketCodec
