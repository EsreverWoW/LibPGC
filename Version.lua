-- ***************************************************************************************************************************************************
-- * Version.lua                                                                                                                                     *
-- ***************************************************************************************************************************************************
-- * 0.5.0 / 2013.09.29 / Baanano: Refactored                                                                                                        *
-- * 0.4.4 / 2012.12.19 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier
local Internal, Public = addonData.Internal, addonData.Public

local CURRENT_VERSION = Internal.Constants.DATAMODEL_VERSION
local dataModels = {}
local migrationProcedures = {}

function Internal.Version.GetCurrentVersion()
	return CURRENT_VERSION
end

function Internal.Version.RegisterDataModel(version, model)
	if type(version) ~= "number" or type(model) ~= "function" then return end
	dataModels[version] = model
end

function Internal.Version.GetDataModelBuilder(version)
	return version and dataModels[version]
end

function Internal.Version.RegisterMigrationProcedure(version, procedure)
	if type(version) ~= "number" or type(procedure) ~= "function" then return end
	migrationProcedures[version] = procedure
end

function Internal.Version.LoadDataModel(data)
	local dataModel = nil
	local dataModelVersion = nil
	
	-- First check if any data model is capable of loading the raw data, in descending order
	for version = CURRENT_VERSION, 1, -1 do
		if dataModels[version] then
			local ok, modelLoaded = pcall(dataModels[version], data)
			if ok and modelLoaded then
				dataModel = modelLoaded
				dataModelVersion = version
				break
			end
		end
	end
	
	-- Try to migrate the data model to the current version
	repeat
		if not dataModel then break end -- If no data model was capable of loading the raw data, exit
	
		if dataModelVersion == CURRENT_VERSION then break end -- If the data model is already of the current version, exit
		
		local migrationProcedure = migrationProcedures[dataModelVersion]
		
		if not migrationProcedure then -- If no migration procedure is available, warn the user and exit
			print("Couldn't find a migration procedure for v" .. dataModelVersion .. ". Your data is unusable and will be wiped the next time you log out. If you want to backup it, save your " .. addonID .. ".lua SavedVariables file immediately!")
			dataModel = nil
			break
		end
		
		local success		
		success, dataModel, dataModelVersion = pcall(migrationProcedure, dataModel)
		if not success then -- If the migration procedure failed, warn the user and exit
			print("Migration procedure failed. Your data is unusable and will be wiped the next time you log out. If you want to backup it, save your " .. addonID .. ".lua SavedVariables file immediately!")
			dataModel = nil
			break
		end
	until false

	-- If no data model was capable of loading the raw data, or it couldn't be migrated to the current version, create a new empty data model of the current version
	if not dataModel then
		dataModel = dataModels[CURRENT_VERSION](nil)
		dataModelVersion = CURRENT_VERSION
	end
	
	-- Unload models and migration procedures, as they aren't needed anymore
	dataModels = nil
	migrationProcedures = nil

	-- Return the data model
	return dataModel	
end
