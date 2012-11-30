-- ***************************************************************************************************************************************************
-- * Scanner.lua                                                                                                                                     *
-- ***************************************************************************************************************************************************
-- * Processes auction scans and stores them in the auction DB                                                                                       *
-- ***************************************************************************************************************************************************
-- * 0.4.4 / 2012.08.12 / Baanano: Fixed minor bug in Event.LibPGC.AuctionData                                                                       *
-- * 0.4.1 / 2012.07.10 / Baanano: Updated for LibPGC                                                                                                *
-- * 0.4.0 / 2012.05.31 / Baanano: Rewritten AHMonitoringService.lua                                                                                 *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

_G[addonID] = _G[addonID] or {}
local PublicInterface = _G[addonID]

local MAX_DATA_AGE = 30 * 24 * 60 * 60
local PAGESIZE = 1000

local CreateTask = LibScheduler.CreateTask
local GetPlayerName = InternalInterface.Utility.GetPlayerName
local IInteraction = Inspect.Interaction
local IADetail = Inspect.Auction.Detail
local IIDetail = Inspect.Item.Detail
local MFloor = math.floor
local MMax = math.max
local MMin = math.min
local Release = LibScheduler.Release
local Time = Inspect.Time.Server
local TInsert = table.insert
local TRemove = table.remove
local TSort = table.sort
local ipairs = ipairs
local pairs = pairs

local auctionTable = {}
local auctionTableLoaded = false

local cachedAuctions = {}
local cachedItemTypes = {}

local alreadyMatched = {}
local pendingPosts = {}

local nativeIndexer = InternalInterface.Indexers.BuildNativeIndexer()
local ownIndex = {}

local lastTask = nil

local AuctionDataEvent = Utility.Event.Create(addonID, "AuctionData")

InternalInterface.Scanner = InternalInterface.Scanner or {}

local function TryMatchAuction(auctionID)
	if alreadyMatched[auctionID] then return end
	
	local itemType = cachedAuctions[auctionID]
	local pending = itemType and pendingPosts[itemType] or nil
	local itemInfo = auctionTable[itemType]
	local auctionInfo = itemInfo and itemInfo.activeAuctions[auctionID] or nil
	
	if not pending or not auctionInfo then return end
	
	for index, pendingData in ipairs(pending) do
		if not pendingData.matched and pendingData.bid == auctionInfo.bid and pendingData.buy == auctionInfo.buy then
			auctionTable[itemType].activeAuctions[auctionID].minExpire = pendingData.timestamp + pendingData.tim * 3600 
			auctionTable[itemType].activeAuctions[auctionID].maxExpire = auctionInfo.firstSeen + pendingData.tim * 3600 
			pendingPosts[itemType][index].matched = true
			alreadyMatched[auctionID] = true
			return
		end
	end
	auctionTable[itemType].activeAuctions[auctionID].postPending = true
end

local function TryMatchPost(itemType, tim, timestamp, bid, buyout)
	local itemInfo = auctionTable[itemType]
	local auctions = itemInfo and itemInfo.activeAuctions or {}
	for auctionID, auctionInfo in pairs(auctions) do
		if auctionInfo.postPending and bid == auctionInfo.bid and buyout == auctionInfo.buy then
			auctionTable[itemType].activeAuctions[auctionID].minExpire = timestamp + tim * 3600 
			auctionTable[itemType].activeAuctions[auctionID].maxExpire = auctionInfo.firstSeen + tim * 3600 
			auctionTable[itemType].activeAuctions[auctionID].postPending = nil
			alreadyMatched[auctionID] = true
			return
		end
	end
	pendingPosts[itemType] = pendingPosts[itemType] or {}
	TInsert(pendingPosts[itemType], { tim = tim, timestamp = timestamp, bid = bid, buy = buyout or 0 })
end

local function OnAuctionData(criteria, auctions)
	local auctionScanTime = Time()
	local expireTimes = 
	{ 
		short =		{ auctionScanTime, 			auctionScanTime + 7200 }, 
		medium =	{ auctionScanTime + 7200, 	auctionScanTime + 43200 }, 
		long =		{ auctionScanTime + 43200, 	auctionScanTime + 172800 },
	}

	local totalAuctions, newAuctions, updatedAuctions, removedAuctions, beforeExpireAuctions = {}, {}, {}, {}, {}
	local totalItemTypes, newItemTypes, updatedItemTypes, removedItemTypes, modifiedItemTypes = {}, {}, {}, {}, {}
	
	local playerName = GetPlayerName()
	
	local function ProcessItemType(itemType)
		if cachedItemTypes[itemType] then return end
		
		local itemDetail = IIDetail(itemType)

		local name, icon, rarity, level = itemDetail.name, itemDetail.icon, itemDetail.rarity or "", itemDetail.requiredLevel or 1
		local category, callings = itemDetail.category or "", itemDetail.requiredCalling
		callings =
		{
			warrior = (not callings or callings:find("warrior")) and true or nil,
			cleric = (not callings or callings:find("cleric")) and true or nil,
			rogue = (not callings or callings:find("rogue")) and true or nil,
			mage = (not callings or callings:find("mage")) and true or nil,
		}
		
		if not auctionTable[itemType] then
			auctionTable[itemType] =
			{
				name = name,
				icon = icon,
				rarity = rarity,
				level = level,
				category = category,
				callings = callings,
				activeAuctions = {},
				expiredAuctions = {},
			}
		else
			local oldData = auctionTable[itemType]
			
			local oldName = oldData.name
			local oldIcon = oldData.icon
			local oldRarity = oldData.rarity
			local oldLevel = oldData.level
			local oldCategory = oldData.category
			local oldCallings = oldData.callings
			
			if name ~= oldName or icon ~= oldIcon or rarity ~= oldRarity  or level ~= oldLevel or category ~= oldCategory or callings.warrior ~= oldCallings.warrior or callings.cleric ~= oldCallings.cleric or callings.rogue ~= oldCallings.rogue or callings.mage ~= oldCallings.mage then
				auctionTable[itemType].name = name
				auctionTable[itemType].icon = icon
				auctionTable[itemType].rarity = rarity
				auctionTable[itemType].level = level
				auctionTable[itemType].category = category
				auctionTable[itemType].callings = callings

				for auctionID, auctionData in pairs(oldData.activeAuctions) do
					nativeIndexer:RemoveAuction(auctionID, oldCallings, oldRarity, oldLevel, oldCategory, oldName, auctionData.buy)
					nativeIndexer:AddAuction(itemType, auctionID, callings, rarity, level, category, name, auctionData.buy)
				end
				
				modifiedItemTypes[itemType] = true
			end
		end		
		
		cachedItemTypes[itemType] = true
	end
	
	local function ProcessAuction(auctionID, auctionDetail)
		local itemType = auctionDetail.itemType
		
		ProcessItemType(itemType)
		auctionTable[itemType].lastSeen = auctionScanTime
		cachedAuctions[auctionID] = itemType
		
		TInsert(totalAuctions, auctionID)
		totalItemTypes[itemType] = true
		
		local auctionData = auctionTable[itemType].activeAuctions[auctionID]
		if not auctionData then
			local itemTypeData = auctionTable[itemType]
			itemTypeData.activeAuctions[auctionID] = 
			{
				stack = auctionDetail.itemStack or 1,
				bid = auctionDetail.bid,
				buy = auctionDetail.buyout or 0,
				seller = auctionDetail.seller,
				firstSeen = auctionScanTime,
				lastSeen = auctionScanTime,
				minExpire = expireTimes[auctionDetail.time][1],
				maxExpire = expireTimes[auctionDetail.time][2],
				own = auctionDetail.seller == playerName and true or nil,
				bidded = auctionDetail.bidder and auctionDetail.bidder ~= "0" and true or nil,
				ownBidded = auctionDetail.bidder and auctionDetail.bidder == playerName and auctionDetail.bid or 0,
			}
			auctionData = itemTypeData.activeAuctions[auctionID]
			
			TInsert(newAuctions, auctionID)
			newItemTypes[itemType] = true
			
			nativeIndexer:AddAuction(itemType, auctionID, itemTypeData.callings, itemTypeData.rarity, itemTypeData.level, itemTypeData.category, itemTypeData.name, auctionDetail.buyout or 0)
			
			if auctionDetail.seller == playerName then
				TryMatchAuction(auctionID)
			end
		else
			auctionData.lastSeen = auctionScanTime
			auctionData.minExpire = MMax(auctionData.minExpire, expireTimes[auctionDetail.time][1])
			auctionData.maxExpire = MMin(auctionData.maxExpire, expireTimes[auctionDetail.time][2])
			auctionData.own = auctionData.own or auctionDetail.seller == playerName or nil
			auctionData.bidded = auctionData.bidded or (auctionDetail.bidder and auctionDetail.bidder ~= "0") or nil
			
			if auctionDetail.bidder and auctionDetail.bidder == playerName then auctionData.ownBidded = auctionDetail.bid end
			
			if auctionDetail.bid > auctionData.bid then
				auctionData.bid = auctionDetail.bid
				auctionData.bidded = true
				TInsert(updatedAuctions, auctionID)
				updatedItemTypes[itemType] = true
			end			
		end
		
		if auctionData.own then ownIndex[auctionID] = itemType end
	end
	
	local function ProcessAuctions()
		local preprocessingSuccessful = true
		
		for auctionID in pairs(auctions) do
			local ok, auctionDetail = pcall(IADetail, auctionID)
			if not ok or not auctionDetail then
				preprocessingSuccessful = false 
				break 
			end
			ProcessAuction(auctionID, auctionDetail)
			Release()
		end

		if criteria.type == "search" then
			local auctionCount = 0
			if not preprocessingSuccessful then
				for auctionID in pairs(auctions) do auctionCount = auctionCount + 1  end
			else
				auctionCount = #totalAuctions
			end
			if not criteria.index or (criteria.index == 0 and auctionCount < 50) then
				local matchingAuctions = nativeIndexer:Search(criteria.role, criteria.rarity, criteria.levelMin, criteria.levelMax, criteria.category, criteria.priceMin, criteria.priceMax, criteria.text)
				for auctionID, itemType in pairs(matchingAuctions) do
					if not auctions[auctionID] then
						local itemData = auctionTable[itemType]
						local auctionData = itemData.activeAuctions[auctionID]

						TInsert(removedAuctions, auctionID)
						removedItemTypes[itemType] = true
						if auctionScanTime < auctionData.minExpire then
							auctionData.beforeExpiration = true
							TInsert(beforeExpireAuctions, auctionID)
						end
						
						nativeIndexer:RemoveAuction(auctionID, itemData.callings, itemData.rarity, itemData.level, itemData.category, itemData.name, auctionData.buy)
						ownIndex[auctionID] = nil
						
						itemData.expiredAuctions[auctionID] = auctionData
						itemData.activeAuctions[auctionID] = nil
					end
					Release()
				end
			end
		elseif criteria.type == "mine" then
			for auctionID, itemType in pairs(ownIndex) do
				local itemData = auctionTable[itemType]
				local auctionData = itemData.activeAuctions[auctionID]
				if not auctions[auctionID] and auctionData.seller == playerName then
					TInsert(removedAuctions, auctionID)
					removedItemTypes[itemType] = true
					if auctionScanTime < auctionData.minExpire then
						auctionData.beforeExpiration = true
						TInsert(beforeExpireAuctions, auctionID)
					end
					
					nativeIndexer:RemoveAuction(auctionID, itemData.callings, itemData.rarity, itemData.level, itemData.category, itemData.name, auctionData.buy)
					ownIndex[auctionID] = nil
					
					itemData.expiredAuctions[auctionID] = auctionData
					itemData.activeAuctions[auctionID] = nil
				end
				Release()
			end
		end

		if criteria.sort and criteria.sort == "time" and criteria.sortOrder then
			local knownAuctions = {}
			if preprocessingSuccessful then
				knownAuctions = totalAuctions
			else
				for auctionID in pairs(auctions) do
					if cachedAuctions[auctionID] then
						TInsert(knownAuctions, auctionID)
						Release()
					end
				end
			end
			
			local sortFunction = nil
			if criteria.sortOrder == "descending" then
				sortFunction = function(a, b) return auctions[a] < auctions[b] end
			else
				sortFunction = function(a, b) return auctions[b] < auctions[a] end
			end
			
			local knownAuctionsPages = {}
			for index, auctionID in ipairs(knownAuctions) do
				local page = MFloor(index / PAGESIZE) + 1
				knownAuctionsPages[page] = knownAuctionsPages[page] or {}
				TInsert(knownAuctionsPages[page], auctionID)
				Release()
			end
			
			for _, page in pairs(knownAuctionsPages) do
				TSort(page, sortFunction)
				Release()
			end
			
			knownAuctions = {}
			repeat
				local minPageIndex = nil
				
				for pageIndex, page in pairs(knownAuctionsPages) do
					if #page > 0 then
						if not minPageIndex or sortFunction(page[1], knownAuctionsPages[minPageIndex][1]) then
							minPageIndex = pageIndex
						end
					end
				end
				
				if minPageIndex then
					TInsert(knownAuctions, knownAuctionsPages[minPageIndex][1])
					TRemove(knownAuctionsPages[minPageIndex], 1)
				end
				
				Release()
			until not minPageIndex
			
			for index = 2, #knownAuctions, 1 do
				local auctionID = knownAuctions[index]
				local prevAuctionID = knownAuctions[index - 1]
				
				local auctionMET = auctionTable[cachedAuctions[auctionID]].activeAuctions[auctionID].minExpire
				local prevAuctionMET = auctionTable[cachedAuctions[prevAuctionID]].activeAuctions[prevAuctionID].minExpire
				
				if auctionMET < prevAuctionMET then
					auctionTable[cachedAuctions[auctionID]].activeAuctions[auctionID].minExpire = prevAuctionMET
				end
				Release()
			end
			for index = #knownAuctions - 1, 1, -1 do
				local auctionID = knownAuctions[index]
				local nextAuctionID = knownAuctions[index + 1]
				
				local auctionXET = auctionTable[cachedAuctions[auctionID]].activeAuctions[auctionID].maxExpire
				local nextAuctionXET = auctionTable[cachedAuctions[nextAuctionID]].activeAuctions[nextAuctionID].maxExpire
				
				if auctionXET > nextAuctionXET then
					auctionTable[cachedAuctions[auctionID]].activeAuctions[auctionID].maxExpire = nextAuctionXET
				end
				Release()
			end
		end		
	end
	
	local function ProcessCompleted()
		AuctionDataEvent(criteria.type, totalAuctions, newAuctions, updatedAuctions, removedAuctions, beforeExpireAuctions, totalItemTypes, newItemTypes, updatedItemTypes, removedItemTypes, modifiedItemTypes)
	end
	
	lastTask = CreateTask(ProcessAuctions, ProcessCompleted, nil, lastTask) or lastTask
end
TInsert(Event.Auction.Scan, { OnAuctionData, addonID, addonID .. ".Scanner.OnAuctionData" })

local function LoadAuctionTable(addonId)
	if addonId == addonID then
		LibPGCDump = {}
		LibPGCDump[1] = LibPGCDump
		
		if type(_G[addonID .. "AuctionTable"]) == "table" then
			auctionTable = _G[addonID .. "AuctionTable"]
		else
			auctionTable = {}
		end

		for itemType, itemData in pairs(auctionTable) do
			if itemData.activeAuctions then
				for auctionID, auctionData in pairs(itemData.activeAuctions) do
					nativeIndexer:AddAuction(itemType, auctionID, itemData.callings, itemData.rarity, itemData.level, itemData.category, itemData.name, auctionData.buy)
					if auctionData.own then ownIndex[auctionID] = itemType end
				end
			else
				auctionTable = {}
				break
			end
		end

		auctionTableLoaded = true
	end
end
TInsert(Event.Addon.SavedVariables.Load.End, {LoadAuctionTable, addonID, addonID .. ".Scanner.LoadAuctionData"})

local function SaveAuctionTable(addonId)
	if addonId == addonID and auctionTableLoaded then
		local purgeTime = Time() - MAX_DATA_AGE
		
		for itemType, itemData in pairs(auctionTable) do
			local hasAuctions = false
			for auctionID, auctionData in pairs(itemData.activeAuctions) do
				auctionData.postPending = nil
				hasAuctions = true
				break
			end
			for auctionID, auctionData in pairs(itemData.expiredAuctions) do
				if auctionData.lastSeen < purgeTime then
					auctionTable[itemType].expiredAuctions[auctionID] = nil
				else
					hasAuctions = true
				end
			end
			if not hasAuctions then
				auctionTable[itemType] = nil
			end
		end
		
		_G[addonID .. "AuctionTable"] = auctionTable
	end
end
TInsert(Event.Addon.SavedVariables.Save.Begin, {SaveAuctionTable, addonID, addonID .. ".Scanner.SaveAuctionData"})

local function ProcessAuctionBuy(auctionID)
	local itemType = cachedAuctions[auctionID]
	local itemInfo = itemType and auctionTable[itemType] or nil
	local auctionInfo = itemInfo and itemInfo.activeAuctions[auctionID] or nil
	
	if auctionInfo then
		nativeIndexer:RemoveAuction(auctionID, itemInfo.callings, itemInfo.rarity, itemInfo.level, itemInfo.category, itemInfo.name, auctionInfo.buy)
		ownIndex[auctionID] = nil
		
		auctionInfo.ownBought = true
		auctionInfo.beforeExpiration = true
		
		itemInfo.expiredAuctions[auctionID] = auctionInfo
		itemInfo.activeAuctions[auctionID] = nil
		
		AuctionDataEvent("playerbuy", {auctionID}, {}, {}, {auctionID}, {auctionID}, {[itemType] = true}, {}, {}, {[itemType] = true}, {})
	end
end

local function ProcessAuctionBid(auctionID, amount)
	local itemType = cachedAuctions[auctionID]
	local itemInfo = itemType and auctionTable[itemType] or nil
	local auctionInfo = itemInfo and itemInfo.activeAuctions[auctionID] or nil
	
	if auctionInfo then
		if auctionInfo.buy and auctionInfo.buy > 0 and amount >= auctionInfo.buy then
			ProcessAuctionBuy(auctionID)
		else
			auctionInfo.bidded = true
			auctionInfo.bid = amount
			auctionInfo.ownBidded = amount
			AuctionDataEvent("playerbid", {auctionID}, {}, {auctionID}, {}, {}, {[itemType] = true}, {}, {[itemType] = true}, {}, {})
		end
	end
end

local function ProcessAuctionCancel(auctionID)
	local itemType = cachedAuctions[auctionID]
	local itemInfo = itemType and auctionTable[itemType] or nil
	local auctionInfo = itemInfo and itemInfo.activeAuctions[auctionID] or nil

	if auctionInfo then
		nativeIndexer:RemoveAuction(auctionID, itemInfo.callings, itemInfo.rarity, itemInfo.level, itemInfo.category, itemInfo.name, auctionInfo.buy)
		ownIndex[auctionID] = nil
		
		auctionInfo.cancelled = true
		auctionInfo.beforeExpiration = true
		
		itemInfo.expiredAuctions[auctionID] = auctionInfo
		itemInfo.activeAuctions[auctionID] = nil
		
		AuctionDataEvent("playercancel", {auctionID}, {}, {}, {auctionID}, {auctionID}, {[itemType] = true}, {}, {}, {[itemType] = true}, {})
	end
end

local function GetAuctionData(itemType, auctionID)
	itemType = itemType or (auctionID and cachedAuctions[auctionID])
	if not itemType or not auctionTable[itemType] then return nil end
	
	local auctionData = auctionTable[itemType].activeAuctions[auctionID] or auctionTable[itemType].expiredAuctions[auctionID]
	if not auctionData then return nil end
	
	return
	{
		active = auctionTable[itemType].activeAuctions[auctionID] and true or false,
		itemType = itemType,
		itemName = auctionTable[itemType].name,
		itemIcon = auctionTable[itemType].icon,
		itemRarity = auctionTable[itemType].rarity,
		stack = auctionData.stack,
		bidPrice = auctionData.bid,
		buyoutPrice = auctionData.buy ~= 0 and auctionData.buy or nil,
		bidUnitPrice = auctionData.bid / auctionData.stack,
		buyoutUnitPrice = auctionData.buy ~= 0 and (auctionData.buy / auctionData.stack) or nil,
		sellerName = auctionData.seller,
		firstSeenTime = auctionData.firstSeen,
		lastSeenTime = auctionData.lastSeen,
		minExpireTime = auctionData.minExpire,
		maxExpireTime = auctionData.maxExpire,
		own = auctionData.own or false,
		bidded = auctionData.bidded or false,
		removedBeforeExpiration = auctionData.beforeExpiration or false,
		ownBidded = auctionData.ownBidded,
		ownBought = auctionData.ownBought or false,
		cancelled = auctionData.cancelled or false,
	}
end

local function SearchAuctionsAsync(calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
	local auctions = nativeIndexer:Search(calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
	for auctionID, itemType in pairs(auctions) do
		auctions[auctionID] = GetAuctionData(itemType, auctionID)
		Release()
	end
	return auctions
end

local function GetAuctionDataAsync(item, startTime, endTime, excludeExpired)
	local auctions = {}
	
	startTime = startTime or 0
	endTime = endTime or Time()
	
	if not item then
		for itemType, itemInfo in pairs(auctionTable) do
			for auctionID in pairs(itemInfo.activeAuctions) do
				local auctionData = GetAuctionData(itemType, auctionID)
				if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
					auctions[auctionID] = auctionData
				end
				Release()
			end
			
			if not excludeExpired then
				for auctionID in pairs(itemInfo.expiredAuctions) do
					local auctionData = GetAuctionData(itemType, auctionID)
					if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
						auctions[auctionID] = auctionData
					end
					Release()
				end
			end
		end
	else
		local itemType = nil
		if item:sub(1, 1) == "I" then
			itemType = item
		else
			local ok, itemDetail = pcall(IIDetail, item)
			itemType = ok and itemDetail and itemDetail.type or nil
		end
		
		local itemInfo = itemType and auctionTable[itemType] or nil
		if not itemInfo then return {} end
		
		for auctionID in pairs(itemInfo.activeAuctions) do
			local auctionData = GetAuctionData(itemType, auctionID)
			if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
				auctions[auctionID] = auctionData
			end
			Release()
		end
		
		if not excludeExpired then
			for auctionID in pairs(itemInfo.expiredAuctions) do
				local auctionData = GetAuctionData(itemType, auctionID)
				if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
					auctions[auctionID] = auctionData
				end
				Release()
			end
		end
	end
	
	return auctions
end

local function GetOwnAuctionDataAsync()
	local auctions = {}
	for auctionID, itemType in pairs(ownIndex) do
		auctions[auctionID] = GetAuctionData(itemType, auctionID)
		Release()
	end
	return auctions
end



function PublicInterface.GetAuctionBuyCallback(auctionID)
	return function(failed)
		if failed then return end
		lastTask = CreateTask(function() ProcessAuctionBuy(auctionID) end, nil, nil, lastTask) or lastTask
	end
end

function PublicInterface.GetAuctionBidCallback(auctionID, amount)
	return function(failed)
		if failed then return end
		lastTask = CreateTask(function() ProcessAuctionBid(auctionID, amount) end, nil, nil, lastTask) or lastTask
	end
end

function PublicInterface.GetAuctionPostCallback(itemType, duration, bid, buyout)
	local timestamp = Time()
	return function(failed)
		if not failed then
			lastTask = CreateTask(function() TryMatchPost(itemType, duration, timestamp, bid, buyout or 0) end, nil, nil, lastTask) or lastTask
		end
	end
end

function PublicInterface.GetAuctionCancelCallback(auctionID)
	return function(failed)
		if failed then return end
		lastTask = CreateTask(function() ProcessAuctionCancel(auctionID) end, nil, nil, lastTask) or lastTask
	end
end

PublicInterface.GetAuctionData = GetAuctionData

function PublicInterface.SearchAuctions(callback, calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(function() return SearchAuctionsAsync(calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name) end, callback, nil, lastTask) or lastTask
end

function PublicInterface.GetAllAuctionData(callback, item, startTime, endTime)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(function() return GetAuctionDataAsync(item, startTime, endTime, false) end, callback, nil, lastTask) or lastTask
end

function PublicInterface.GetActiveAuctionData(callback, item)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(function() return GetAuctionDataAsync(item, nil, nil, true) end, callback, nil, lastTask) or lastTask
end

function PublicInterface.GetOwnAuctionData(callback)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(GetOwnAuctionDataAsync, callback, nil, lastTask) or lastTask
end	

function PublicInterface.GetAuctionCached(auctionID)
	return cachedAuctions[auctionID] and true or false
end

function PublicInterface.GetLastTimeSeen(item)
	if not item then return nil end

	local itemType = nil
	if item:sub(1, 1) == "I" then
		itemType = item
	else
		local ok, itemDetail = pcall(IIDetail, item)
		itemType = ok and itemDetail and itemDetail.type or nil
	end
	
	return itemType and auctionTable[itemType] and auctionTable[itemType].lastSeen or nil 
end	

function PublicInterface.GetLastTask()
	return lastTask
end
