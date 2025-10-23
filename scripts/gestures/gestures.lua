require("gestures/gesture_map")
require("config/enum")
local flickDetection = require("gestures/gestures_flick") 
local vectorDetection = require("gestures/gestures_vector") 
local gesturesUIModule = require("gestures/gestures_ui") 
local uevrUtils = require("libs/uevr_utils")

local M = {}

local flickThreshold = 65  	-- Adjust based on sensitivity (higher number harder to fire, lower number easier to fire)
local castTimeout = 0.1		--the amount of time in seconds between when the flick is detected and when the spell is actually cast

local castTimer = nil
local spellManager = nil
local triggerPressLocked = false
local isTriggerPressed = false

local currentFlickSpell = nil

local scheduledSpell = nil

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[gestures] " .. text, logLevel)
	end
end

local function isSpellAvailable(spellRecord)
	if spellRecord ~= nil then
		if spellManager == nil then
			spellManager = uevr.api:find_uobject("SpellManagerBPInterface /Script/Phoenix.Default__SpellManagerBPInterface")
		end
		if spellManager ~= nil then
			return spellManager:IsUnlocked(spellRecord.LookupName)
		end
	end
	return false
end


local function getPawnWand(pawn)
	if pawn ~= nil and UEVR_UObjectHook.exists(pawn) then
		local success, wand = pcall(function()
			return pawn:GetWand()
		end)	
		if success then return wand else return nil end
	end
	return nil
end

local function castPewPew(pawn)
	local wand = getPawnWand(pawn)
	if wand ~= nil then
		wand:CastPewPewSpell()
	end
end

local function castCurrentFlickSpell(pawn)
	local wand = getPawnWand(pawn)
	if wand ~= nil then
		if currentFlickSpell == nil then
			--print("Casting active spell\n")
			currentFlickSpell =  wand:GetActiveSpellTool()
		else
			--print("Casting flick spell\n")
			if currentFlickSpell ~= nil and UEVR_UObjectHook.exists(currentFlickSpell) then
				pcall(function() --GetSpellToolRecord can be nil even if the test for currentFlickSpell succeeds
					local spellToolRecord = currentFlickSpell:GetSpellToolRecord()
					if spellToolRecord ~= nil and isSpellAvailable(spellToolRecord) then 
						--wand:CancelCurrentSpell()
						wand:ActivateSpellTool(spellToolRecord, true)
						wand:CastSpell(currentFlickSpell, true)
					end
				end)	
			else
				currentFlickSpell = nil
			end
		end
	end
end

--Search Toolset.ToolRecord in UEVR or Phoenix.InventoryItemToolRecord
--ITEM_CaptureDevice
--ITEM_CreatureFeed
--Item_CreaturePettingBrush
local currentTool = nil
--spellName is spell lookup name like "Spell_Flipendo"
local function castSpellByName(pawn, spellName)
	local wand = getPawnWand(pawn)
	if spellName ~= nil and spellName ~= "" and wand ~= nil then
		M.print("Casting spell by name " .. spellName)
		if string.sub(spellName, 1, 6) == "Spell_" then -- this is a spell call
			if spellName == "Spell_PewPew" then
				castPewPew(pawn)
				local currentActiveSpell = wand:GetActiveSpellTool()
				currentFlickSpell = currentActiveSpell
			else
				local toolsetComponent = wand.ToolSetComponent
				if toolsetComponent ~= nil then
					local toolRecords = toolsetComponent:GetToolRecords()
					for index, spellToolRecord in pairs(toolRecords) do
						local lookupName = spellToolRecord.LookupName:to_string()
						if lookupName == spellName then
							M.print("Found spell tool record for " .. lookupName .. " ")
							local isUnlocked = isSpellAvailable(spellToolRecord) --spellManager:IsUnlocked(spellToolRecord.LookupName)
							M.print(lookupName .. " is unlocked: " .. (isUnlocked and "true" or "false"))
							if isUnlocked then
								wand:CancelCurrentSpell()
								local spellTool = wand:ActivateSpellTool(spellToolRecord, false)
								if spellTool ~= nil then
									wand:CastActiveSpell()
									--print("Casting spell complete","\n")
									currentFlickSpell = spellTool
								end
								break
							end
						end
					end
				else
					M.print("Spell Toolset component not available")
				end
			end
		else -- this is a use item call
			local inventoryToolSet = pawn.InventoryToolSetComponent
			if inventoryToolSet ~= nil then
				inventoryToolSet:ClearActiveTool()
				local toolRecords = inventoryToolSet:GetToolRecords()
				if toolRecords ~= nil then
					local found = false
					local toolName = spellName
					for index, toolRecord in pairs(toolRecords) do
						local lookupName = toolRecord.LookupName:to_string()
						if lookupName == toolName then
							M.print("Found tool lookup name for " .. toolRecord:get_full_name() .. "\tisLoaded: " .. (toolRecord:IsLoaded() and "true" or "false"))
							--toolRecord:IsLoaded() is false when tool wont activate. How to load tool record? AsyncLoadToolByName doesnt seem to work
							if toolRecord:IsLoaded() == false then 
								local name = ""
								if string.find(toolRecord:get_full_name(), "CreatureFeedToolRecord") then
									name = "BlueprintGeneratedClass /Game/Gameplay/ToolSet/Items/InventoryItems/CreatureFeed/BP_FeedTool_CreatureFeed.BP_FeedTool_CreatureFeed_C"
								elseif string.find(toolRecord:get_full_name(), "CreaturePettingBrushToolRecord") then
									name = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/Petting/BP_CreaturePettingTool.BP_CreaturePettingTool_C"
								elseif string.find(toolRecord:get_full_name(), "CaptureDeviceToolRecord") then
									name = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/CreatureCapture/CaptureDevice/BP_Capture_Device_New.BP_Capture_Device_New_C"
								elseif string.find(toolRecord:get_full_name(), "HippogriffMountToolRecord") then
									--This code works but lib:CanUseHippogriff() returns true even when youre too low a level so for now going
									--to stick with if default way to summon is used one then can use gestures after
									-- local lib = uevrUtils.find_first_instance("Class /Script/Phoenix.UIBlueprintFunctionLibrary", true)
									-- if lib ~= nil and lib:CanUseHippogriff() then
										-- name = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/Mounts/BP_HippogriffMountTool.BP_HippogriffMountTool_C"
									-- else
										-- uevrUtils.print("Can't use Hippogriff yet")
									-- end
									
									--this will also mount the hippo without needing the code above but also doesnt check for too low level
									--local tool = uevrUtils.getLoadedAsset("BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/Mounts/BP_HippogriffMountTool.BP_HippogriffMountTool_C")
									--tool:SpawnAndMountCreature(true, false)
								end
								
								if name ~= "" then
									local tool = uevrUtils.getLoadedAsset(name)
								end
							end
							found = true
							local isUnlocked = inventoryToolSet:IsToolUsageAllowed(toolRecord) 
							if isUnlocked then
								-- local currentTool = inventoryToolSet:ClearActiveTool() -- inventoryToolSet:GetActiveTool()
								-- if currentTool ~= nil then
									-- print("Current active tool is",currentTool:get_full_name(),"\n")
									-- currentTool:EndItemUsage()
									-- currentTool:UnequipTool()									
								-- end
								inventoryToolSet:AsyncLoadToolByName(toolRecord.LookupName)
								local tool =  inventoryToolSet:ActivateTool(toolRecord)
								if tool ~= nil then
									tool:BeginItemUsage()
									currentTool = tool
									M.print("Tool activated: " .. tool:get_full_name())
									delay(3000, function()
										currentTool:EndItemUsage()
										--pawn:RevertSpeedMode()
										--pawn:SetSpeedMode()
										M.print("Tool usage ended: " .. currentTool:get_full_name())
									end)
								else
									--inventoryToolSet:AsyncLoadToolByName(toolRecord.LookupName)
									--toolRecord:LoadComplete(toolRecord)
									--toolRecord:LoadComplete()
									M.print("Could not activate tool")
								end
							else
								M.print("Tool not unlocked")
							end
							break
						end
					end
					if not found then 
						M.print("Tool not found")
					end
				else
					M.print("Inventory Toolset toolrecords not available")
				end
			else
				M.print("Inventory Toolset component not available")
			end
		end
	end
end

function M.castSpellByName(pawn, spellName)
	castSpellByName(pawn, spellName)
end

-- slotID 3 up
-- slotID 4 right
-- slotID 5 down
-- slotID 6 left
local function castSlotSpell(pawn, slotID)
	local wand = getPawnWand(pawn)
	if wand ~= nil then
		local spellRecord = wand:GetSpellRecordFromSlot(slotID)
		--print("Spell type",spellRecord.AudioSwitchName:to_string(),"\n")
		if isSpellAvailable(spellRecord) then
			local spellTool = wand:ActivateSpellTool(spellRecord, true)
			if spellTool ~= nil then
				wand:CastSpell(spellTool, true)
			end
		end
	end
end

--spells like accio will remain active unless cancelled
local function cancelContinuousActiveSpells(pawn)
	local wand = getPawnWand(pawn)
	if wand ~= nil then		
		local currentActiveSpell = wand:GetActiveSpellTool()
		local spellName = currentActiveSpell:GetSpellToolRecord().LookupName:to_string()
		if spellName == "Spell_Lumos" or spellName == "Spell_Accio" or spellName == "Spell_Wingardium" then
			wand:CancelCurrentSpell()
		end
	end
end

local function updateCastTimer(pawn, delta)
	if castTimer ~= nil then
		if castTimer > 0 then 
			castTimer = castTimer - delta
		else
			castCurrentFlickSpell(pawn)
			castTimer = nil
		end
	end
	if scheduledSpell ~= nil then
		if scheduledSpell["timeout"] > 0 then
			scheduledSpell["timeout"] = scheduledSpell["timeout"] - delta
		else
			castSpellByName(pawn, scheduledSpell["name"])
			scheduledSpell = nil
		end
	end
end

local wasTriggerPressed = false
local endWandPosition = nil
local gestureStartDelay = nil

local glyphToSpellNameMap = nil
local function initGestures()
	if glyphToSpellNameMap == nil then
		glyphToSpellNameMap = {}
		for key, value in pairs(spellNameToGlyphMap) do
			glyphToSpellNameMap[value] = key
		end
	end
end

function M.reset()
	flickDetection.reset()
	vectorDetection.reset()
end

local function endBulletTime(pawn)
	pawn:EndBulletTime(1.0)
	pawn.CharacterMovement:SetActive(true, false)
	pawn.CharacterMovement:SetComponentTickEnabled(true)
	flickDetection.reset()
	vectorDetection.reset()
	gesturesUIModule.clearBeams()
	gestureStartDelay = nil
end

function M.handleGestures(pawn, gestureMode, wandTargetDirection, wandPosition, delta)
	--print("handleGestures called",wandTargetDirection, delta, gestureMode,"\n")
	if gestureMode ~= GestureMode.Spells or wandTargetDirection == nil then return end

	initGestures()
	updateCastTimer(pawn, delta)

	local flickDetected, isUpDirection = flickDetection.updateGestureDetection(delta, wandTargetDirection, flickThreshold)
	if flickDetected then
		--M.print("flick detected")
		--if you yank your hand back, cancel spells like accio. If you flick forward then cast an active spell
		if isUpDirection then
			cancelContinuousActiveSpells(pawn)
		else
			castTimer = castTimeout
		end
	end

	if gestureStartDelay ~= nil then
		gestureStartDelay["timeout"] = gestureStartDelay["timeout"] - delta
		if gestureStartDelay["timeout"] < 0 then
			-- StartBulletTime(float Dilation, float Duration, bool DoFixedCam, float PlayerDilation, float EaseInDuration, float EaseOutDuration)
			pawn:StartBulletTime(0.15, 5.0, false, 1.0, 0.4, 2.0)
			--After casting a spell the pawn animation can make the character move forward
			--which interferes with casting a new spell
			--setting this false disables character movement while casting
			gesturesUIModule.spawnBeamAtWandPosition(gestureStartDelay["startPosition"])
			gestureStartDelay = nil
		end
	end

	local gestureID, angleChangeDetected, detectionFailed = vectorDetection.updateGestureDetection(delta, wandPosition, wandTargetDirection, isTriggerPressed)
	--print("Detection failed", detectionFailed,"\n")
	if detectionFailed then
		detectionLock = true
		endBulletTime(pawn)
		uevr.params.vr.trigger_haptic_vibration(0, 0.1, 200, 1.0, uevr.params.vr.get_right_joystick_source())
		delay(200, function()
			uevr.params.vr.trigger_haptic_vibration(0.0, 0.1, 200, 1.0, uevr.params.vr.get_right_joystick_source())
		end)
	elseif not detectionLock then
		if isTriggerPressed then
			if not wasTriggerPressed then
				cancelContinuousActiveSpells(pawn)
				pawn.CharacterMovement:SetActive(false, false) 
				pawn.CharacterMovement:SetComponentTickEnabled(false)
				gestureStartDelay = {timeout = 0.3, startPosition = wandPosition}
			end
			if gestureStartDelay == nil then
				gesturesUIModule.updateBeam(endWandPosition)
				if angleChangeDetected then
					gesturesUIModule.spawnBeamAtWandPosition(wandPosition)
				end
			end
		elseif wasTriggerPressed then
			endBulletTime(pawn)
		end
		endWandPosition = wandPosition

		if gestureID ~= "" then
			local spellName = glyphToSpellNameMap[gestureID]
			if spellName == "Spell_Transformation" then spellName = "Spell_TransformationOverland" end
			scheduledSpell = {name = spellName, keepActive = true, timeout = 0.2}
		end
	end

	--if detection fail lock is on and trigger was released then reset the lock
	if wasTriggerPressed and not isTriggerPressed then
		detectionLock = false
	end
	wasTriggerPressed = isTriggerPressed
end

function M.cancelCurrentSpell(pawn)
	local wand = getPawnWand(pawn)
	if wand ~= nil then
		wand:CancelCurrentSpell()
	end
end

function M.isCastingSpell(pawn, spellName)
	local wand = getPawnWand(pawn)
	if wand ~= nil then		
		local currentActiveSpell = wand:GetActiveSpellTool()
		if currentActiveSpell ~= nil then
			local activeSpellName = currentActiveSpell:GetSpellToolRecord().LookupName:to_string()
			if spellName == activeSpellName then
				return true
			end
		end
	end
	return false
end

function M.handleInput(state, isLeftHanded)
	local triggerValue = state.Gamepad.bRightTrigger
	if isLeftHanded then triggerValue = state.Gamepad.bLeftTrigger end

	local triggerPressed = false
	if triggerValue > 100 then
		if not triggerPressLocked then
			triggerPressed = true
			--if a spell is cast via buttons (or joystick) while the trigger is in the pressed state then disable isTriggerPressed until after the next release
			if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_B)
				or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X)
				or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_Y)
				or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_A) then
					--print("Spell button press detected\n")
					triggerPressed = false
					triggerPressLocked = true
			end
		end
	else
		triggerPressLocked = false
	end
	isTriggerPressed = triggerPressed
end

function M.printSpellInfo(pawn)
	local spellManager = uevr.api:find_uobject("SpellManagerBPInterface /Script/Phoenix.Default__SpellManagerBPInterface")
	M.print("Spell Manager: " .. spellManager:get_full_name().. ", Loadouts: " .. spellManager.NumLoadouts .. ", Spells Per Loadout: " .. spellManager.SpellsPerLoadout, LogLevel.Critical)
	M.print(" Total available spells: " .. spellManager:GetAvailableSpellCount(true) .. " Unlocked Spells: " .. spellManager:GetAvailableSpellCount(false), LogLevel.Critical)
	
	local wand = getPawnWand(pawn)
	if wand ~= nil then
		local spellTool =  wand:GetActiveSpellTool()
		if spellTool ~= nil and UEVR_UObjectHook.exists(spellTool) then
			M.print(" Active spell: " .. spellTool:GetSpellType():to_string() .. "   Category: " .. spellTool:GetSpellCategory() .. "   Name: " .. spellTool:GetSourceActor():get_full_name(), LogLevel.Critical)
			--local available = wand:IsSpellToolAvailable(spellTool:GetSpellToolRecord(), true)
		else
			M.print(" No active spell tool", LogLevel.Critical)
		end
		
		local toolsetComponent = wand.ToolSetComponent
		if toolsetComponent ~= nil then
			local spellsStr = ""
			local toolRecords = toolsetComponent:GetToolRecords()
			if toolRecords ~= nil then
				spellsStr = spellsStr .. "Index\tName\t\tLookup Name\tLock Name\tUnlocked\n"
				for index, spellToolRecord in pairs(toolRecords) do
					local lookupName = spellToolRecord.LookupName:to_string()
					local toolRecordName = spellToolRecord.AudioSwitchName:to_string()
					local lockName = spellToolRecord.LockName:to_string()
					local isUnlocked = spellManager:IsUnlocked(spellToolRecord.LookupName)
					spellsStr = spellsStr .. toolsetComponent:GetToolRecordIndex(spellToolRecord) .. "\t" .. toolRecordName .. "\t" .. lookupName .. "\t" .. lockName .. "\t" .. (isUnlocked and "true" or "false") .. "\n"
				end
			end
			M.print("\n" .. spellsStr, LogLevel.Critical)
		else
			M.print("Spell list not available", LogLevel.Critical)
		end
	end
	
	local inventoryToolSet = pawn.InventoryToolSetComponent
	local toolRecords = inventoryToolSet:GetToolRecords()
	local toolsStr = ""
	if toolRecords ~= nil then
		toolsStr = toolsStr .. "Inventory Tools\n"
		toolsStr = toolsStr .. "Index\tLookup Name\tLock Name\tUnlocked\n"
		for index, toolRecord in pairs(toolRecords) do
			local lookupName = toolRecord.LookupName:to_string()
			local lockName = toolRecord.LockName:to_string()
			local isUnlocked = inventoryToolSet:IsToolUsageAllowed(toolRecord)
			toolsStr = toolsStr .. inventoryToolSet:GetToolRecordIndex(toolRecord) .. "\t" .. lookupName .. "\t" .. lockName .. "\t" .. (isUnlocked and "true" or "false") .. "\n"
		end
	end
	M.print("\n" .. toolsStr, LogLevel.Critical)
end

local spellNameRemap = {}
spellNameRemap["WingardiumLeviosa"] = "Spell_Wingardium"
spellNameRemap["Imperio"] = "Spell_Imperius"
spellNameRemap["AvadaKedavra"] = "Spell_Avadakedavra"
spellNameRemap["Alteration"] = "Spell_Transformation"
spellNameRemap["BasicShot"] = "Spell_PewPew"
spellNameRemap["Evanesco"] = "Spell_Vanishment"
spellNameRemap["Bombarda"] = "Spell_Expulso"
spellNameRemap["BeastTool_Food"] = "ITEM_CreatureFeed"
spellNameRemap["BeastTool_Brush"] = "Item_CreaturePettingBrush"
spellNameRemap["BeastTool_Bag"] = "ITEM_CaptureDevice"

function M.showGlyphForSpell(spellName, forwardVector, position)
	local selectedSpellName = spellNameRemap[spellName]
	if selectedSpellName == nil then selectedSpellName = "Spell_" .. spellName end

	M.print("Showing glyph for spell: " .. selectedSpellName)
	gesturesUIModule.clearGlyphs()
	local gestureName = spellNameToGlyphMap[selectedSpellName]
	for i = 1, #glyphGestures do
		local gesture = glyphGestures[i]
		if gesture["id"] == gestureName then
			gesturesUIModule.drawGlyph(gesture["angles"], gesture["lengths"], forwardVector, position)
			break
		end
	end
end

function M.hideGlyphs()
	gesturesUIModule.clearGlyphs()
end

return M
