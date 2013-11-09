-- ***************************************************************************************************************************************************
-- * NativeIndexer.lua                                                                                                                               *
-- ***************************************************************************************************************************************************
-- * 0.5.0 / 2013.09.29 / Baanano: Adapted to blTasks                                                                                                *
-- * 0.4.4 / 2012.08.12 / Baanano: Fixed minor category bugs                                                                                         *
-- * 0.4.1 / 2012.07.10 / Baanano: Moved to LibPGC                                                                                                   *
-- * 0.4.0 / 2012.05.31 / Baanano: Rewritten AuctionTree.lua                                                                                         *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier
local Internal, Public = addonData.Internal, addonData.Public

function Internal.Indexer.Native()
	local nativeIndexer = {}
	
	local auctionIDs = {}
	local searchTree = {}
	
	function nativeIndexer.AddAuction(itemType, auctionID, callings, rarity, level, category, name, price)
		name = name:upper()
		
		for calling, flag in pairs(callings) do
			if flag then
				searchTree[calling] = searchTree[calling] or {}
				searchTree[calling][rarity] = searchTree[calling][rarity] or {}
				searchTree[calling][rarity][level] = searchTree[calling][rarity][level] or {}
				searchTree[calling][rarity][level][category] = searchTree[calling][rarity][level][category] or {}
				searchTree[calling][rarity][level][category][name] = searchTree[calling][rarity][level][category][name] or {}
				searchTree[calling][rarity][level][category][name][price] = searchTree[calling][rarity][level][category][name][price] or {}
				searchTree[calling][rarity][level][category][name][price][auctionID] = itemType
			end
		end
		
		auctionIDs[auctionID] = itemType
	end
	
	function nativeIndexer.RemoveAuction(auctionID, callings, rarity, level, category, name, price)
		if not auctionIDs[auctionID] then return end
		
		name = name:upper()
		
		for calling, flag in pairs(callings) do
			if flag then
				searchTree[calling][rarity][level][category][name][price][auctionID] = nil
			end
		end
		
		auctionIDs[auctionID] = nil
	end
	
	function nativeIndexer.Search(calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
		local contextHandle = blTasks.Task.Current()
		
		local results = {}
		
		name = name and name:upper() or nil
		
		for callingName, callingSubtree in pairs(searchTree) do
			if not calling or calling == callingName then
				for rarityName, raritySubtree in pairs(callingSubtree) do
					if not rarity or rarity <= rarityName then
						for level, levelSubtree in pairs(raritySubtree) do
							if (not levelMin or level >= levelMin) and (not levelMax or level <= levelMax) then
								for categoryName, categorySubtree in pairs(levelSubtree) do
									if not category or categoryName:sub(1, category:len()) == category then
										for itemName, nameSubtree in pairs(categorySubtree) do
											if not name or itemName:find(name, 1, true) then
												for price, priceSubtree in pairs(nameSubtree) do
													if (not priceMin or price >= priceMin) and (not priceMax or price <= priceMax) then
														for auctionID, itemType in pairs(priceSubtree) do
															results[auctionID] = itemType
														end
													end
													contextHandle:BreathShort()
												end
											end
											contextHandle:BreathShort()
										end
									end
									contextHandle:BreathShort()
								end
							end
							contextHandle:BreathShort()
						end
					end
					contextHandle:BreathShort()
				end
			end
			contextHandle:BreathShort()
		end
		
		return results
	end
	
	return nativeIndexer
end
