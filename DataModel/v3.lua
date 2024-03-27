-- ***************************************************************************************************************************************************
-- * v3.lua                                                                                                                                          *
-- ***************************************************************************************************************************************************
-- * LibPGC DataModel v3                                                                                                                             *
-- ***************************************************************************************************************************************************
-- * 0.4.4 / 2013.02.04 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

local CheckFlag = function(value, flag) return bit.band(value, flag) == flag end
local Converter = InternalInterface.Utility.Converter
local Release = LibScheduler.Release
local TInsert = table.insert
local ipairs = ipairs
local next = next
local pairs = pairs
local type = type

local VERSION = 3
local ITEM, AUCTIONS = 1, 2
local MAX_DATA_AGE = 30 * 24 * 60 * 60

local ItemConverter = Converter({
	{ field = "name",     length = 4, },
	{ field = "icon",     length = 4, },
	{ field = "category", length = 2, },
	{ field = "level",    length = 1, },
	{ field = "callings", length = 1, },
	{ field = "rarity",   length = 1, },
	{ field = "lastSeen", length = 4, },
})

local AuctionConverter = Converter({
	{ field = "seller",    length = 3, },
	{ field = "bid",       length = 5, },
	{ field = "buy",       length = 5, },
	{ field = "ownbid",    length = 5, },
	{ field = "firstSeen", length = 4, },
	{ field = "lastSeen",  length = 4, },
	{ field = "minExpire", length = 4, },
	{ field = "maxExpire", length = 4, },
	{ field = "stacks",    length = 2, },
	{ field = "flags",     length = 1, },
})

local function DataModelBuilder(rawData)
	local IC_WARRIOR, IC_CLERIC, IC_ROGUE, IC_MAGE, IC_PRIMALIST = 16, 8, 4, 2, 1
	local AF_OWN, AF_BIDDED, AF_BEFOREEXPIRATION, AF_OWNBOUGHT, AF_CANCELLED = 128, 64, 32, 16, 8

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
		if AuctionConverter(auctionData).lastSeen < purgeTime then
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
		
		itemData = ItemConverter(itemData)
		local callings = itemData.callings
		
		return 	rawData.itemNames[itemData.name],
				rawData.itemIcons[itemData.icon],
				rawData.itemCategories[itemData.category],
				itemData.level,
				{
					warrior = CheckFlag(callings, IC_WARRIOR),
					cleric = CheckFlag(callings, IC_CLERIC),
					rogue = CheckFlag(callings, IC_ROGUE),
					mage = CheckFlag(callings, IC_MAGE),
					primalist = CheckFlag(callings, IC_PRIMALIST),
				},
				itemData.rarity,
				itemData.lastSeen
	end

	function dataModel:RetrieveItemName(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return rawData.itemNames[ItemConverter(itemData).name]
	end
	
	function dataModel:RetrieveItemIcon(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return rawData.itemIcons[ItemConverter(itemData).icon]
	end
	
	function dataModel:RetrieveItemCategory(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return rawData.itemCategories[ItemConverter(itemData).category]
	end
	
	function dataModel:RetrieveItemRequiredLevel(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return ItemConverter(itemData).level
	end
	
	function dataModel:RetrieveItemRequiredCallings(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		local callings = ItemConverter(itemData).callings
		return
		{
			warrior = CheckFlag(callings, IC_WARRIOR),
			cleric = CheckFlag(callings, IC_CLERIC),
			rogue = CheckFlag(callings, IC_ROGUE),
			mage = CheckFlag(callings, IC_MAGE),
			primalist = CheckFlag(callings, IC_PRIMALIST),
		}
	end
	
	function dataModel:RetrieveItemRarity(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return ItemConverter(itemData).rarity
	end
	
	function dataModel:RetrieveItemLastSeen(itemType)
		local itemData = itemType and rawData.items[itemType] and rawData.items[itemType][ITEM] or nil
		if not itemData then return end
		return ItemConverter(itemData).lastSeen
	end
	
	function dataModel:StoreItem(itemType, name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen)
		if not itemType then return false end
		if not name or not icon or not category or not requiredLevel or type(requiredCallings) ~= "table" or not rarity or not lastSeen then return false end
		
		rawData.items[itemType] = rawData.items[itemType] or { "", {}, }
		
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
		
		local itemData = ItemConverter()
		itemData.name = nameID
		itemData.icon = iconID
		itemData.category = categoryID
		itemData.level = requiredLevel
		itemData.callings = (requiredCallings.warrior and IC_WARRIOR or 0) +
		                    (requiredCallings.cleric and IC_CLERIC or 0) +
		                    (requiredCallings.rogue and IC_ROGUE or 0) +
		                    (requiredCallings.mage and IC_MAGE or 0) +
							(requiredCallings.primalist and IC_PRIMALIST or 0)
		itemData.rarity = rarity
		itemData.lastSeen = lastSeen
		
		rawData.items[itemType][ITEM] = tostring(itemData)
		
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
		
		local itemData = ItemConverter(rawData.items[itemType][ITEM])
		itemData.name = nameID
		rawData.items[itemType][ITEM] = tostring(itemData)
		
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
		
		local itemData = ItemConverter(rawData.items[itemType][ITEM])
		itemData.icon = iconID
		rawData.items[itemType][ITEM] = tostring(itemData)

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
		
		local itemData = ItemConverter(rawData.items[itemType][ITEM])
		itemData.category = categoryID
		rawData.items[itemType][ITEM] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemRequiredLevel(itemType, requiredLevel)
		if not itemType or not rawData.items[itemType] then return false end
		if not requiredLevel then return false end
		
		local itemData = ItemConverter(rawData.items[itemType][ITEM])
		itemData.level = requiredLevel
		rawData.items[itemType][ITEM] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemRequiredCallings(itemType, requiredCallings)
		if not itemType or not rawData.items[itemType] then return false end
		if type(requiredCallings) ~= "table" then return false end

		local itemData = ItemConverter(rawData.items[itemType][ITEM])
		itemData.callings = (requiredCallings.warrior and IC_WARRIOR or 0) +
		                    (requiredCallings.cleric and IC_CLERIC or 0) +
		                    (requiredCallings.rogue and IC_ROGUE or 0) +
		                    (requiredCallings.mage and IC_MAGE or 0) +
							(requiredCallings.primalist and IC_PRIMALIST or 0)
		rawData.items[itemType][ITEM] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemRarity(itemType, rarity)
		if not itemType or not rawData.items[itemType] then return false end
		if not rarity then return false end
		
		local itemData = ItemConverter(rawData.items[itemType][ITEM])
		itemData.rarity = rarity
		rawData.items[itemType][ITEM] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemLastSeen(itemType, lastSeen)
		if not itemType or not rawData.items[itemType] then return false end
		if not lastSeen then return false end
		
		local itemData = ItemConverter(rawData.items[itemType][ITEM])
		itemData.lastSeen = lastSeen
		rawData.items[itemType][ITEM] = tostring(itemData)

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
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		local flags = auctionData.flags
		
		return rawData.auctionSellers[auctionData.seller],
				auctionData.bid, auctionData.buy, auctionData.ownbid,
				auctionData.firstSeen, auctionData.lastSeen, auctionData.minExpire, auctionData.maxExpire,
				auctionData.stacks,
				{
					own = CheckFlag(flags, AF_OWN),
					bidded = CheckFlag(flags, AF_BIDDED),
					beforeExpiration = CheckFlag(flags, AF_BEFOREEXPIRATION),
					ownBought = CheckFlag(flags, AF_OWNBOUGHT),
					cancelled = CheckFlag(flags, AF_CANCELLED),
				},
			   active
	end
	
	function dataModel:RetrieveAuctionSeller(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return rawData.auctionSellers[auctionData.seller]
	end
	
	function dataModel:RetrieveAuctionBid(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.bid
	end
	
	function dataModel:RetrieveAuctionBuy(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.buy
	end
	
	function dataModel:RetrieveAuctionOwnBid(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.ownbid
	end
	
	function dataModel:RetrieveAuctionFirstSeen(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.firstSeen
	end
	
	function dataModel:RetrieveAuctionLastSeen(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.lastSeen
	end
	
	function dataModel:RetrieveAuctionMinExpire(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.minExpire
	end
	
	function dataModel:RetrieveAuctionMaxExpire(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.maxExpire
	end
	
	function dataModel:RetrieveAuctionStack(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.stacks
	end
	
	function dataModel:RetrieveAuctionFlags(itemType, auctionID)
		if not itemType or not rawData.items[itemType] then return end
		local flags = AuctionConverter(rawData.auctions[auctionID]).flags
		return
		{
			own = CheckFlag(flags, AF_OWN),
			bidded = CheckFlag(flags, AF_BIDDED),
			beforeExpiration = CheckFlag(flags, AF_BEFOREEXPIRATION),
			ownBought = CheckFlag(flags, AF_OWNBOUGHT),
			cancelled = CheckFlag(flags, AF_CANCELLED),
		}
	end

	function dataModel:StoreAuction(itemType, auctionID, active, seller, bid, buy, ownBid, firstSeen, lastSeen, minExpire, maxExpire, stack, flags)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not seller or not bid or not buy or not ownBid or not firstSeen or not lastSeen or not minExpire or not maxExpire or not stack or type(flags) ~= "table" then return false end
		
		local sellerID = reverseSellers[seller]
		if not sellerID then
			TInsert(rawData.auctionSellers, seller)
			sellerID = #rawData.auctionSellers
			reverseSellers[seller] = sellerID
		end
		
		local auctionData = AuctionConverter()
		
		auctionData.seller = sellerID
		auctionData.bid = bid
		auctionData.buy = buy
		auctionData.ownbid = ownBid
		auctionData.firstSeen = firstSeen
		auctionData.lastSeen = lastSeen
		auctionData.minExpire = minExpire
		auctionData.maxExpire = maxExpire
		auctionData.stacks = stack
		auctionData.flags = (flags.own and AF_OWN or 0) +
		                    (flags.bidded and AF_BIDDED or 0) +
		                    (flags.beforeExpiration and AF_BEFOREEXPIRATION or 0) +
		                    (flags.ownBought and AF_OWNBOUGHT or 0) +
		                    (flags.cancelled and AF_CANCELLED or 0)
		
		rawData.auctions[auctionID] = tostring(auctionData)
		
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
		
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.seller = sellerID
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionBid(itemType, auctionID, bid)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not bid then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.bid = bid
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionBuy(itemType, auctionID, buy)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not buy then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.buy = buy
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionOwnBid(itemType, auctionID, ownBid)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not ownBid then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.ownbid = ownBid
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionFirstSeen(itemType, auctionID, firstSeen)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not firstSeen then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.firstSeen = firstSeen
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionLastSeen(itemType, auctionID, lastSeen)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not lastSeen then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.lastSeen = lastSeen
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionMinExpire(itemType, auctionID, minExpire)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not minExpire then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.minExpire = minExpire
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionMaxExpire(itemType, auctionID, maxExpire)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not maxExpire then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.maxExpire = maxExpire
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionStack(itemType, auctionID, stack)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if not stack then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.stacks = stack
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
		if not itemType or not rawData.items[itemType] or not auctionID then return false end
		if type(flags) ~= "table" then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.flags = (flags.own and AF_OWN or 0) +
		                    (flags.bidded and AF_BIDDED or 0) +
		                    (flags.beforeExpiration and AF_BEFOREEXPIRATION or 0) +
		                    (flags.ownBought and AF_OWNBOUGHT or 0) +
		                    (flags.cancelled and AF_CANCELLED or 0)
		rawData.auctions[auctionID] = tostring(auctionData)		

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
