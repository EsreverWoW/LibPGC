-- ***************************************************************************************************************************************************
-- * v2.lua                                                                                                                                          *
-- ***************************************************************************************************************************************************
-- * LibPGC DataModel v2                                                                                                                             *
-- ***************************************************************************************************************************************************
-- * 0.4.4 / 2013.01.02 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

local CheckFlag = function(value, flag) return bit.band(value, flag) == flag end
local Release = LibScheduler.Release
local TInsert = table.insert
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local type = type

local VERSION = 2
local ITEM, AUCTIONS = 1, 2
local MAX_DATA_AGE = 30 * 24 * 60 * 60

local function DataModelBuilder(rawData)
	local I_NAME, I_ICON, I_CATEGORY, I_LEVEL, I_CALLINGS, I_RARITY, I_LASTSEEN = 1, 2, 3, 4, 5, 6, 7
	local IC_WARRIOR, IC_CLERIC, IC_ROGUE, IC_MAGE, IC_PRIMALIST = 1, 2, 3, 4, 5
	local A_SELLER, A_BID, A_BUY, A_OWNBID, A_FIRSTSEEN, A_LASTSEEN, A_REMAINING, A_STACK, A_FLAGS = 1, 2, 3, 4, 5, 6, 7, 8, 9
	local AF_OWN, AF_BIDDED, AF_BEFOREEXPIRATION, AF_OWNBOUGHT, AF_CANCELLED = 1, 2, 3, 4, 5

	-- If rawData is empty, create an empty model
	if rawData == nil then
		rawData =
		{
			items = {},
			auctions = {},
			auctionSellers = {},
			itemNames = {},
			itemIcons = {},
			itemCategories = {},
			version = VERSION,
		}
	end
	
	-- Check if the raw data is in the proper format
	if type(rawData) ~= "table" or rawData.version ~= VERSION then
		error("Wrong data format")
	end
	
	-- Create the DataModel object
	local dataModel = {}
	
	-- Create the reverse lookups
	local reverseSellers = {}
	for index, seller in ipairs(rawData.auctionSellers) do
		reverseSellers[seller] = index
		Release()
	end
	
	local reverseNames = {}
	for index, name in ipairs(rawData.itemNames) do
		reverseNames[name] = index
		Release()
	end
	
	local reverseIcons = {}
	for index, icon in ipairs(rawData.itemIcons) do
		reverseIcons[icon] = index
		Release()
	end
	
	local reverseCategories = {}
	for index, category in ipairs(rawData.itemCategories) do
		reverseCategories[category] = index
		Release()
	end
	
	-- Perform maintenance
	local purgeTime = Inspect.Time.Server() - MAX_DATA_AGE
	
	for auctionID, auctionData in pairs(rawData.auctions) do
		if auctionData[A_LASTSEEN] < purgeTime then
			rawData.auctions[auctionID] = nil
		end
		Release()
	end
	
	for itemType, itemData in pairs(rawData.items) do
		for auctionID in pairs(itemData[AUCTIONS]) do
			if not rawData.auctions[auctionID] then
				itemData[AUCTIONS][auctionID] = nil
			end
		end
		if not next(itemData[AUCTIONS]) then
			rawData.items[itemType] = nil
		end
		Release()
	end
	
	-- Model	
	function dataModel:GetRawData()
		return rawData
	end
	
	function dataModel:GetVersion()
		return VERSION
	end
	
	-- Items
	function dataModel:CheckItemExists(itemType)
		return itemType and rawData.items[itemType] and true or false
	end
	
	function dataModel:RetrieveAllItems()
		local itemTypes = {}
		for itemType in pairs(rawData.items) do
			itemTypes[itemType] = true
		end
		return itemTypes
	end
	
	function dataModel:RetrieveItemData(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		
		return 	rawData.itemNames[itemData[I_NAME]],
				rawData.itemIcons[itemData[I_ICON]],
				rawData.itemCategories[itemData[I_CATEGORY]],
				itemData[I_LEVEL],
				{
					warrior = itemData[I_CALLINGS][IC_WARRIOR] and true or false,
					cleric = itemData[I_CALLINGS][IC_CLERIC] and true or false,
					rogue = itemData[I_CALLINGS][IC_ROGUE] and true or false,
					mage = itemData[I_CALLINGS][IC_MAGE] and true or false,
					primalist = itemData[I_CALLINGS][IC_PRIMALIST] and true or false,
				},
				itemData[I_RARITY],
				itemData[I_LASTSEEN]
	end

	function dataModel:RetrieveItemName(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return rawData.itemNames[itemData[I_NAME]]
	end
	
	function dataModel:RetrieveItemIcon(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return rawData.itemIcons[itemData[I_ICON]]
	end
	
	function dataModel:RetrieveItemCategory(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return rawData.itemCategories[itemData[I_CATEGORY]]
	end
	
	function dataModel:RetrieveItemRequiredLevel(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return itemData[I_LEVEL]
	end
	
	function dataModel:RetrieveItemRequiredCallings(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return
		{
			warrior = itemData[I_CALLINGS][IC_WARRIOR] and true or false,
			cleric = itemData[I_CALLINGS][IC_CLERIC] and true or false,
			rogue = itemData[I_CALLINGS][IC_ROGUE] and true or false,
			mage = itemData[I_CALLINGS][IC_MAGE] and true or false,
			primalist = itemData[I_CALLINGS][IC_PRIMALIST] and true or false,
		}
	end
	
	function dataModel:RetrieveItemRarity(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return itemData[I_RARITY]
	end
	
	function dataModel:RetrieveItemLastSeen(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return itemData[I_LASTSEEN]
	end
	
	function dataModel:StoreItem(itemType, name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen)
		if not itemType then return false end
		if not name or not icon or not category or not requiredLevel or type(requiredCallings) ~= "table" or not rarity or not lastSeen then return false end
		
		rawData.items[itemType] = rawData.items[itemType] or { {}, {}, }
		
		local nameID = reverseNames[name]
		if not nameID then
			TInsert(rawData.itemNames, name)
			nameID = #rawData.itemNames
			reverseNames[name] = nameID
		end
		
		local iconID = reverseIcons[icon]
		if not iconID then
			TInsert(rawData.itemIcons, icon)
			iconID = #rawData.itemIcons
			reverseIcons[icon] = iconID
		end
		
		local categoryID = reverseCategories[category]
		if not categoryID then
			TInsert(rawData.itemCategories, category)
			categoryID = #rawData.itemCategories
			reverseCategories[category] = categoryID
		end
		
		rawData.items[itemType][ITEM] =
		{
			[I_NAME] = nameID,
			[I_ICON] = iconID,
			[I_CATEGORY] = categoryID,
			[I_LEVEL] = requiredLevel,
			[I_CALLINGS] =
			{
				[IC_WARRIOR] = requiredCallings.warrior and 1 or nil,
				[IC_CLERIC] = requiredCallings.cleric and 1 or nil,
				[IC_ROGUE] = requiredCallings.rogue and 1 or nil,
				[IC_MAGE] = requiredCallings.mage and 1 or nil,
				[IC_PRIMALIST] = requiredCallings.primalist and 1 or nil,
			},
			[I_RARITY] = rarity,
			[I_LASTSEEN] = lastSeen,
		}
		
		return true
	end
	
	function dataModel:ModifyItemName(itemType, name)
		if not itemType or not rawData.items[itemType] then return false end
		if not name then return false end
		
		local nameID = reverseNames[name]
		if not nameID then
			TInsert(rawData.itemNames, name)
			nameID = #rawData.itemNames
			reverseNames[name] = nameID
		end
		
		rawData.items[itemType][ITEM][I_NAME] = nameID
		
		return true
	end
	
	function dataModel:ModifyItemIcon(itemType, icon)
		if not itemType or not rawData.items[itemType] then return false end
		if not icon then return false end
		
		local iconID = reverseIcons[icon]
		if not iconID then
			TInsert(rawData.itemIcons, icon)
			iconID = #rawData.itemIcons
			reverseIcons[icon] = iconID
		end
		
		rawData.items[itemType][ITEM][I_ICON] = iconID

		return true
	end
	
	function dataModel:ModifyItemCategory(itemType, category)
		if not itemType or not rawData.items[itemType] then return false end
		if not category then return false end
		
		local categoryID = reverseCategories[category]
		if not categoryID then
			TInsert(rawData.itemCategories, category)
			categoryID = #rawData.itemCategories
			reverseCategories[category] = categoryID
		end
		
		rawData.items[itemType][ITEM][I_CATEGORY] = categoryID

		return true
	end
	
	function dataModel:ModifyItemRequiredLevel(itemType, requiredLevel)
		if not itemType or not rawData.items[itemType] then return false end
		if not requiredLevel then return false end
		
		rawData.items[itemType][ITEM][I_LEVEL] = requiredLevel

		return true
	end
	
	function dataModel:ModifyItemRequiredCallings(itemType, requiredCallings)
		if not itemType or not rawData.items[itemType] then return false end
		if type(requiredCallings) ~= "table" then return false end

		rawData.items[itemType][ITEM][I_CALLINGS] =
		{
			[IC_WARRIOR] = requiredCallings.warrior and 1 or nil,
			[IC_CLERIC] = requiredCallings.cleric and 1 or nil,
			[IC_ROGUE] = requiredCallings.rogue and 1 or nil,
			[IC_MAGE] = requiredCallings.mage and 1 or nil,
			[IC_PRIMALIST] = requiredCallings.primalist and 1 or nil,
		}

		return true
	end
	
	function dataModel:ModifyItemRarity(itemType, rarity)
		if not itemType or not rawData.items[itemType] then return false end
		if not rarity then return false end
		
		rawData.items[itemType][ITEM][I_RARITY] = rarity

		return true
	end
	
	function dataModel:ModifyItemLastSeen(itemType, lastSeen)
		if not itemType or not rawData.items[itemType] then return false end
		if not lastSeen then return false end
		
		rawData.items[itemType][ITEM][I_LASTSEEN] = lastSeen

		return true
	end
	
	-- Auctions
	function dataModel:CheckAuctionExists(itemType, auctionID)
		return rawData.auctions[auctionID] ~= nil
	end
	
	function dataModel:CheckAuctionActive(itemType, auctionID)
		return itemType and rawData.items[itemType] and rawData.items[itemType][AUCTIONS][auctionID] == true
	end
	
	function dataModel:CheckAuctionExpired(itemType, auctionID)
		return itemType and rawData.items[itemType] and rawData.items[itemType][AUCTIONS][auctionID] == false
	end
	
	function dataModel:RetrieveAllAuctions(itemType)
		if not itemType or not rawData.items[itemType] then return nil end
		
		local auctions = {}
		for auctionID in pairs(rawData.items[itemType][AUCTIONS]) do
			auctions[auctionID] = true
		end
		
		return auctions
	end
	
	function dataModel:RetrieveActiveAuctions(itemType)
		if not itemType or not rawData.items[itemType] then return nil end
		
		local auctions = {}
		for auctionID, active in pairs(rawData.items[itemType][AUCTIONS]) do
			if active then
				auctions[auctionID] = true
			end
		end
		
		return auctions
	end
	
	function dataModel:RetrieveExpiredAuctions(itemType)
		if not itemType or not rawData.items[itemType] then return nil end
		
		local auctions = {}
		for auctionID, active in pairs(rawData.items[itemType][AUCTIONS]) do
			if not active then
				auctions[auctionID] = true
			end
		end
		
		return auctions
	end
	
	function dataModel:RetrieveAuctionData(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return nil end
		
		local active = rawData.items[itemType][AUCTIONS][auctionID]
		local auctionData = rawData.auctions[auctionID]

		return rawData.auctionSellers[auctionData[A_SELLER]],
				auctionData[A_BID], auctionData[A_BUY], auctionData[A_OWNBID],
				auctionData[A_FIRSTSEEN], auctionData[A_LASTSEEN], auctionData[A_REMAINING],
				auctionData[A_STACK],
				{
					own = auctionData[A_FLAGS][AF_OWN] and true or false,
					bidded = auctionData[A_FLAGS][AF_BIDDED] and true or false,
					beforeExpiration = auctionData[A_FLAGS][AF_BEFOREEXPIRATION] and true or false,
					ownBought = auctionData[A_FLAGS][AF_OWNBOUGHT] and true or false,
					cancelled = auctionData[A_FLAGS][AF_CANCELLED] and true or false,
				},
			   active
	end
	
	function dataModel:RetrieveAuctionSeller(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return rawData.auctionSellers[auctionData[A_SELLER]]
	end
	
	function dataModel:RetrieveAuctionBid(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return auctionData[A_BID]
	end
	
	function dataModel:RetrieveAuctionBuy(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return auctionData[A_BUY]
	end
	
	function dataModel:RetrieveAuctionOwnBid(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return auctionData[A_OWNBID]
	end
	
	function dataModel:RetrieveAuctionFirstSeen(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return auctionData[A_FIRSTSEEN]
	end
	
	function dataModel:RetrieveAuctionLastSeen(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return auctionData[A_LASTSEEN]
	end

	function dataModel:RetrieveAuctionRemaining(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return auctionData[A_REMAINING]
	end
	
	function dataModel:RetrieveAuctionStack(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return auctionData[A_STACK]
	end
	
	function dataModel:RetrieveAuctionFlags(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = rawData.auctions[auctionID]
		return
		{
			own = auctionData[A_FLAGS][AF_OWN] and true or false,
			bidded = auctionData[A_FLAGS][AF_BIDDED] and true or false,
			beforeExpiration = auctionData[A_FLAGS][AF_BEFOREEXPIRATION] and true or false,
			ownBought = auctionData[A_FLAGS][AF_OWNBOUGHT] and true or false,
			cancelled = auctionData[A_FLAGS][AF_CANCELLED] and true or false,
		}
	end

	function dataModel:StoreAuction(itemType, auctionID, active, seller, bid, buy, ownBid, firstSeen, lastSeen, remaining, stack, flags)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not seller or not bid or not buy or not ownBid or not firstSeen or not lastSeen or not remaining or not stack or type(flags) ~= "table" then return false end
		
		local sellerID = reverseSellers[seller]
		if not sellerID then
			TInsert(rawData.auctionSellers, seller)
			sellerID = #rawData.auctionSellers
			reverseSellers[seller] = sellerID
		end
		
		rawData.auctions[auctionID] =
		{
			[A_SELLER] = sellerID,
			[A_BID] = bid,
			[A_BUY] = buy,
			[A_OWNBID] = ownBid,
			[A_FIRSTSEEN] = firstSeen,
			[A_LASTSEEN] = lastSeen,
			[A_REMAINING] = remaining,
			[A_STACK] = stack,
			[A_FLAGS] =
			{
				[AF_OWN] = flags.own and 1 or nil,
				[AF_BIDDED] = flags.bidded and 1 or nil,
				[AF_BEFOREEXPIRATION] = flags.beforeExpiration and 1 or nil,
				[AF_OWNBOUGHT] = flags.ownBought and 1 or nil,
				[AF_CANCELLED] = flags.cancelled and 1 or nil,
			},
		}
		
		rawData.items[itemType][AUCTIONS][auctionID] = active and true or false

		return true		
	end
	
	function dataModel:ModifyAuctionSeller(itemType, auctionID, seller)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not seller then return false end

		local sellerID = reverseSellers[seller]
		if not sellerID then
			TInsert(rawData.auctionSellers, seller)
			sellerID = #rawData.auctionSellers
			reverseSellers[seller] = sellerID
		end
		
		rawData.auctions[auctionID][A_SELLER] = sellerID

		return true
	end
	
	function dataModel:ModifyAuctionBid(itemType, auctionID, bid)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not bid then return false end

		rawData.auctions[auctionID][A_BID] = bid

		return true
	end
	
	function dataModel:ModifyAuctionBuy(itemType, auctionID, buy)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not buy then return false end

		rawData.auctions[auctionID][A_BUY] = buy

		return true
	end
	
	function dataModel:ModifyAuctionOwnBid(itemType, auctionID, ownBid)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not ownBid then return false end

		rawData.auctions[auctionID][A_OWNBID] = ownBid

		return true
	end
	
	function dataModel:ModifyAuctionFirstSeen(itemType, auctionID, firstSeen)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not firstSeen then return false end

		rawData.auctions[auctionID][A_FIRSTSEEN] = firstSeen

		return true
	end
	
	function dataModel:ModifyAuctionLastSeen(itemType, auctionID, lastSeen)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not lastSeen then return false end

		rawData.auctions[auctionID][A_LASTSEEN] = lastSeen

		return true
	end

	function dataModel:ModifyAuctionRemaining(itemType, auctionID, remaining)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not remaining then return false end

		rawData.auctions[auctionID][A_REMAINING] = remaining

		return true
	end
	
	function dataModel:ModifyAuctionStack(itemType, auctionID, stack)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not stack then return false end

		rawData.auctions[auctionID][A_STACK] = stack

		return true
	end
	
	function dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if type(flags) ~= "table" then return false end

		rawData.auctions[auctionID][A_FLAGS] =
		{
			[AF_OWN] = flags.own and 1 or nil,
			[AF_BIDDED] = flags.bidded and 1 or nil,
			[AF_BEFOREEXPIRATION] = flags.beforeExpiration and 1 or nil,
			[AF_OWNBOUGHT] = flags.ownBought and 1 or nil,
			[AF_CANCELLED] = flags.cancelled and 1 or nil,
		}

		return true
	end
	
	function dataModel:ExpireAuction(itemType, auctionID)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		
		rawData.items[itemType][AUCTIONS][auctionID] = false
		
		return true
	end
	
	return dataModel
end

InternalInterface.Version.RegisterDataModel(VERSION, DataModelBuilder)
