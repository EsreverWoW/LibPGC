-- ***************************************************************************************************************************************************
-- * v3-to-v4.lua                                                                                                                                    *
-- ***************************************************************************************************************************************************
-- * 0.5.0 / 2013.09.29 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier
local Internal, Public = addonData.Internal, addonData.Public

local ORIGINAL_VERSION = 3
local TARGET_VERSION = 4
local FAKE_ITEM = "i0000000000000000"

local function Migration(oldModel)
	print("Migrating " .. addonID .. " saved data from v" .. ORIGINAL_VERSION .. " to v" .. TARGET_VERSION .. "...")
	
	local contextHandle = blTasks.Task.Current()
	
	local itemCount = 0
	local auctionCount = 0
	
	local newModel = Internal.Version.GetDataModelBuilder(TARGET_VERSION)
	if not newModel then
		error("Couldn't find a target data model builder")
	end
	newModel = newModel()

	for itemType in pairs(oldModel:RetrieveAllItems()) do
		local name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen = oldModel:RetrieveItemData(itemType)
		if not newModel:StoreItem(itemType, name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen) then
			error("Couldn't migrate item")
		end
		
		for auctionID in pairs(oldModel:RetrieveAllAuctions(itemType)) do
			contextHandle:BreathShort()
			
			local seller, bid, buy, ownBid, firstSeen, lastSeen, minExpire, maxExpire, stack, flags, active = oldModel:RetrieveAuctionData(itemType, auctionID)
			
			local firstUnseen = 0
			if not active then
				if flags.beforeExpiration then
					firstUnseen = minExpire
				else
					firstUnseen = maxExpire
				end
			end

			if not newModel:StoreAuction(itemType, auctionID, active, seller, FAKE_ITEM, bid, buy, ownBid, firstSeen, firstUnseen, minExpire, maxExpire, stack, flags) then
				error("Couldn't migrate auction")
			end
			auctionCount = auctionCount + 1
			
			contextHandle:BreathShort()
		end
		
		itemCount = itemCount + 1
	end

	print(addonID .. " saved data has been successfully migrated to v" .. TARGET_VERSION .. ": " .. itemCount .. " item(s), " .. auctionCount .. " auction(s).")
	
	return newModel, TARGET_VERSION
end

Internal.Version.RegisterMigrationProcedure(ORIGINAL_VERSION, Migration)
