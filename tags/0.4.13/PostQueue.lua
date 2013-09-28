-- ***************************************************************************************************************************************************
-- * Services/PostQueue.lua                                                                                                                          *
-- ***************************************************************************************************************************************************
-- * Posts auctions, splitting stacks if needed                                                                                                      *
-- ***************************************************************************************************************************************************
-- * 0.4.12/ 2013.09.17 / Baanano: Updated events to the new model                                                                                   *
-- * 0.4.4 / 2012.11.01 / Baanano: Added auto unjam (best effort)                                                                                    *
-- * 0.4.1 / 2012.07.14 / Baanano: Updated for LibPGC                                                                                                *
-- * 0.4.0 / 2012.06.17 / Baanano: Rewritten AHPostingService.lua                                                                                    *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

_G[addonID] = _G[addonID] or {}
local PublicInterface = _G[addonID]

local AUTO_UNJAM_FRAMES = 60

local CCreate = coroutine.create
local CResume = coroutine.resume
local CYield = coroutine.yield
local CAPost = Command.Auction.Post
local CEAttach = Command.Event.Attach
local CIMove = Command.Item.Move
local CISplit = Command.Item.Split
local IInteraction = Inspect.Interaction
local ICDetail = Inspect.Currency.Detail
local IIDetail = Inspect.Item.Detail
local IIList = Inspect.Item.List
local IQStatus = Inspect.Queue.Status
local MFloor = math.floor
local MMax = math.max
local MMin = math.min
local TInsert = table.insert
local TRemove = table.remove
local UACost = Utility.Auction.Cost
local UECreate = Utility.Event.Create
local UISInventory = Utility.Item.Slot.Inventory

local GetAuctionPostCallback = PublicInterface.GetAuctionPostCallback
local CopyTableRecursive = InternalInterface.Utility.CopyTableRecursive

local postingQueue = {}
local paused = false
local waitingUpdate = false
local waitingPost = false
local waitFrames = 5
local postingCoroutine = nil
local QueueChangedEvent = UECreate(addonID, "PostingQueueChanged")
local QueueStatusChangedEvent = UECreate(addonID, "PostingQueueStatusChanged")

local function PostingQueueCoroutine()
	repeat
		repeat
			if paused or waitingUpdate or waitingPost or #postingQueue <= 0 or not IInteraction("auction") or not IQStatus("global") then break end

			local postTable = postingQueue[1]
			local itemType = postTable.itemType

			if postTable.amount <= 0 then -- This post is finished
				TRemove(postingQueue, 1)
				QueueChangedEvent()
				QueueStatusChangedEvent()
				break
			end

			local searchStackSize = MMin(postTable.stackSize, postTable.amount)
			
			local lowerItems = {}
			local exactItems = {}
			local higherItems = {}

			local slot = UISInventory()
			local items = IIList(slot)
			local freeSlots = false
			for slotID, itemID in pairs(items) do repeat
				if type(itemID) == "boolean" then
					freeSlots = true
					break
				end
				local itemDetail = IIDetail(itemID)
				if itemDetail.bound == true or itemDetail.type ~= itemType then break end
				
				local itemStack = itemDetail.stack or 1
				local itemInfo = { itemID = itemID, slotID = slotID }
				
				if itemStack < searchStackSize then
					TInsert(lowerItems, itemInfo)
				elseif itemStack == searchStackSize then
					TInsert(exactItems, itemInfo)
				else
					TInsert(higherItems, itemInfo)
				end
			until true end
			
			if #exactItems > 0 then -- Found an exact match!
				local item = exactItems[1].itemID
				local tim = postTable.duration
				local bid = postTable.unitBidPrice * searchStackSize
				local buyout = nil
				if postTable.unitBuyoutPrice then 
					buyout = postTable.unitBuyoutPrice * searchStackSize 
				end

				local cost = UACost(item, tim, bid, buyout)
				local coinDetail = ICDetail("coin")
				local money = coinDetail and coinDetail.stack or 0
				if money < cost then -- Not enough money to post, abort
					TRemove(postingQueue, 1)
					QueueChangedEvent()
					QueueStatusChangedEvent()
					break
				end
				
				waitingUpdate = true
				waitingPost = true
				local postCallback = GetAuctionPostCallback(itemType, tim, bid, buyout)
				CAPost(item, tim, bid, buyout, function(...) postCallback(...); waitingPost = false; QueueStatusChangedEvent(); end)
				postingQueue[1].amount = postingQueue[1].amount - searchStackSize
				QueueChangedEvent()
				QueueStatusChangedEvent()
				break
			end

			if #lowerItems > 1 then -- Need to join two items
				local firstItemSlot = lowerItems[1].slotID
				local secondItemSlot = lowerItems[2].slotID
				CIMove(firstItemSlot, secondItemSlot)
				waitingUpdate = true
				QueueStatusChangedEvent()
				break
			end

			if #higherItems > 0 then -- Need to split an item
				if freeSlots then -- There are free slots, split
					local item = higherItems[1].itemID
					CISplit(item, searchStackSize)
					waitingUpdate = true
					QueueStatusChangedEvent()
					break
				else -- No free slots, move the item to the end of the queue
					TInsert(postingQueue, postTable)
					TRemove(postingQueue, 1)
					waitFrames = AUTO_UNJAM_FRAMES
					QueueChangedEvent()
					QueueStatusChangedEvent()
					break	
				end
			end

			-- If execution reach this point, there aren't enough stacks of the item to post, abort
			TRemove(postingQueue, 1)
			QueueChangedEvent()
			QueueStatusChangedEvent()
		until true
		CYield()
	until false
end

local function OnSystemUpdate()
	if not postingCoroutine then
		postingCoroutine = CCreate(PostingQueueCoroutine)
	end
	if waitFrames > 0 then
		waitFrames = waitFrames - 1
	else
		CResume(postingCoroutine)
	end
end
CEAttach(Event.System.Update.Begin, OnSystemUpdate, addonID .. ".PostQueue.OnSystemUpdate")

local function OnWaitingUnlock()
	if waitingUpdate then
		waitingUpdate = false
		QueueStatusChangedEvent()
	end
end
CEAttach(Event.Item.Slot, OnWaitingUnlock, addonID .. ".PostQueue.OnWaitingUnlockSlot")
CEAttach(Event.Item.Update, OnWaitingUnlock, addonID .. ".PostQueue.OnWaitingUnlockUpdate")

local function OnInteractionChanged(h, interaction, state)
	if interaction == "auction" then
		QueueStatusChangedEvent()
	end
end
CEAttach(Event.Interaction, OnInteractionChanged, addonID .. ".PostQueue.OnInteractionChanged")

local function OnGlobalQueueChanged(h, queue)
	if queue == "global" then
		QueueStatusChangedEvent()
	end
end
CEAttach(Event.Queue.Status, OnGlobalQueueChanged, addonID .. ".PostQueue.OnGlobalQueueChanged")

function PublicInterface.PostItem(item, stackSize, amount, unitBidPrice, unitBuyoutPrice, duration)
	if not item or not amount or not stackSize or not unitBidPrice or not duration then return false end
	
	amount, stackSize, unitBidPrice, duration = MFloor(amount), MFloor(stackSize), MFloor(unitBidPrice), MFloor(duration)
	if unitBuyoutPrice then unitBuyoutPrice = MMax(MFloor(unitBuyoutPrice), unitBidPrice) end
	if amount <= 0 or stackSize <= 0 or unitBidPrice <= 0 or (duration ~= 12 and duration ~= 24 and duration ~= 48) then return false end

	local itemType = nil
	if item:sub(1, 1) == "I" then
		itemType = item
	else
		local ok, itemDetail = pcall(IIDetail, item)
		itemType = ok and itemDetail and itemDetail.type or nil
	end
	if not itemType then return false end
	
	local postTable = 
	{ 
		itemType = itemType, 
		stackSize = stackSize, 
		amount = amount, 
		unitBidPrice = unitBidPrice, 
		unitBuyoutPrice = unitBuyoutPrice, 
		duration = duration,
	}
	TInsert(postingQueue, postTable)
	
	QueueChangedEvent()
	QueueStatusChangedEvent()
	return true
end

function PublicInterface.CancelPostingByIndex(index)
	if index < 0 or index > #postingQueue then return end
	TRemove(postingQueue, index)
	QueueChangedEvent()
	QueueStatusChangedEvent()
end

function PublicInterface.CancelAll()
	postingQueue = {}
	QueueChangedEvent()
	QueueStatusChangedEvent()
end

function PublicInterface.GetPostingQueue()
	return CopyTableRecursive(postingQueue)
end

function PublicInterface.GetPostingQueueStatus()
	local status = 0 -- Busy
	if paused then status = 1 -- Paused
	elseif #postingQueue <= 0 then status = 2 -- Empty
	elseif not IInteraction("auction") then status = 3 -- Not at the AH
	elseif waitingUpdate or waitingPost or not IQStatus("global") then status = 4 -- Waiting
	elseif waitFrames > 0 then status = 5 -- Jammed
	end
	
	return status, #postingQueue
end

function PublicInterface.GetPostingQueuePaused()
	return paused
end

function PublicInterface.SetPostingQueuePaused(pause)
	if pause == paused then return end
	paused = pause
	QueueStatusChangedEvent()
end
