-- ***************************************************************************************************************************************************
-- * Utility.lua                                                                                                                                     *
-- ***************************************************************************************************************************************************
-- * 0.5.0 / 2013.09.29 / Baanano: Moved most stuff to blUtil                                                                                        *
-- * 0.4.1 / 2012.07.10 / Baanano: Removed functionality not related to the LibPGC library                                                           *
-- * 0.4.0 / 2012.05.30 / Baanano: First version, splitted out of the old Init.lua                                                                   *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier
local Internal, Public = addonData.Internal, addonData.Public

function Internal.Utility.Converter(definitions)
	local lastOffset, fieldOffsets = 1, {}
	
	for i = 1, #definitions do
		local definition = definitions[i]
		
		fieldOffsets[definition.field] =
		{
			from = lastOffset,
			length = definition.length,
			to = lastOffset + definition.length - 1,
		}
		
		lastOffset = lastOffset + definition.length
	end

	return
		function(value)
			value = value or ("\000"):rep(lastOffset - 1)
		
			return setmetatable({},
			{
				__index =
					function(_, field)
						local fieldOffset = fieldOffsets[field]
						if not fieldOffset then return nil end
						
						local result = 0
						value:sub(fieldOffset.from, fieldOffset.to):gsub("(.)", function(c) result = result * 256 + c:byte() end)
						return result
					end,
				
				__newindex =
					function(_, field, val)
						local fieldOffset = fieldOffsets[field]
						if not fieldOffset then return nil end
						
						local result = {}
						for index = fieldOffset.length, 1, -1 do
							result[index] = string.char(val % 256)
							val = math.floor(val / 256)
						end
						
						value = value:sub(1, fieldOffset.from - 1) .. table.concat(result) .. value:sub(fieldOffset.to + 1)
					end,
				
				__tostring = function() return value end,
			})
		end
end