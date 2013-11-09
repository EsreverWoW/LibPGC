-- ***************************************************************************************************************************************************
-- * Prolog.lua                                                                                                                                      *
-- ***************************************************************************************************************************************************
-- * 0.5.0 / 2013.09.29 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier

-- Initialize Internal table
addonData.Internal = addonData.Internal or {}
local Internal = addonData.Internal

-- Initialize Internal hierarchy
Internal.Constants = {}
Internal.Indexer = {}
Internal.Utility = {}
Internal.Version = {}

-- Initialize Public table
_G[addonID] = _G[addonID] or {}
addonData.Public = _G[addonID]
local Public = addonData.Public

-- Initialize Public hierarchy
Public.Callback = {}
Public.Search = {}
Public.Item = {}
Public.Auction = {}
Public.Queue = {}
