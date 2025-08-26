require("config/enum")
local uevrUtils = require("libs/uevr_utils")

local M = {}

local gripOn = false
local gripOnCount = 0
local RXState = 0
local deadZone = 26000
local spellDeadZone = 12000
local snapTurnDeadZone = 8000
local triggerValue = 100

function doLeftHandRemap(state)
	local ThumbLX = state.Gamepad.sThumbLX
	local ThumbLY = state.Gamepad.sThumbLY
	local LTrigger= state.Gamepad.bLeftTrigger

	--avoiding deadzone issues
	if LTrigger <= triggerValue then
		if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X) then
			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_X)
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_LEFT)
		end
		--revelio on A
		if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_A) then
			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_A)
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
		end

		-- up and down are jumping and rolling
		-- These need to be disabled when in a menu
		if ThumbLY >= deadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_DOWN)
		elseif ThumbLY <= -deadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_RIGHT)
		end
		state.Gamepad.bLeftTrigger = 0
	--actual pressing    
	elseif LTrigger > triggerValue then
		--the folloging 2 should be a condition applied to whereever turning is handled
		--state.Gamepad.sThumbLX=0
		--state.Gamepad.sThumbLY=0
		if ThumbLX >= spellDeadZone  then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_RIGHT)
		elseif ThumbLX <= -spellDeadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_LEFT)
		elseif ThumbLY >= spellDeadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_UP)
		elseif ThumbLY <= -spellDeadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_DOWN)
		end
	end
end

function doRightHandRemap(state)
    local ThumbRX = state.Gamepad.sThumbRX
    local ThumbRY = state.Gamepad.sThumbRY
    local RTrigger= state.Gamepad.bRightTrigger

	--avoiding deadzone issues
	if RTrigger <= triggerValue then
		--up and down are jumping and rolling
		--left shoulder shows tool wheel
		if not gripOn then
			if ThumbRY >= deadZone then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_A)
			elseif ThumbRY <= -deadZone then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_B)
			end
			state.Gamepad.bRightTrigger = 0
		end
	--actual pressing right trigger maps spells to right stick
	elseif RTrigger > triggerValue then
		--the folloging 2 should be a condition applied to whereever turning is handled
		--state.Gamepad.sThumbRX=0
		--state.Gamepad.sThumbRY=0
		if ThumbRX >= spellDeadZone  then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_B)
		elseif ThumbRX <= -spellDeadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
		elseif ThumbRY >= spellDeadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_Y)
		elseif ThumbRY <= -spellDeadZone then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_A)
		end
	end

end

function M.handleInput(state, decoupledYawCurrentRot, isDecoupledYawDisabled, locomotionMode,
	controlMode, inputIsLeftHanded, wandInLeftHand, snapAngle, smoothTurnSpeed, useSnapTurn, AlphaDiff, isInMenu)

	if not inputIsLeftHanded and wandInLeftHand then
		local tmp = state.Gamepad.bLeftTrigger
		state.Gamepad.bLeftTrigger = state.Gamepad.bRightTrigger
		state.Gamepad.bRightTrigger = tmp
	end

	if isInMenu then
		return decoupledYawCurrentRot
	end

	--disable decoupled yaw during grip press
	local gripButton = XINPUT_GAMEPAD_LEFT_SHOULDER
	if inputIsLeftHanded then
		gripButton = XINPUT_GAMEPAD_RIGHT_SHOULDER
	end
	if uevrUtils.isButtonPressed(state, gripButton) then
		--print("Left grip triggered\n")
		gripOn = true
		gripOnCount = 200
		disableDecoupledYaw(true)
	elseif uevrUtils.isButtonNotPressed(state, gripButton) and gripOn then
		--print("Left grip released\n")
		if gripOnCount == 0 then --give it a slight delay to kick out
			gripOn = false
			setLocomotionMode(locomotionMode)
		else
			gripOnCount = gripOnCount - 1
		end
	end

	--support for advanced input mode
	local overrideDecoupledYaw = false
	if controlMode == ControllerMode.Advanced then
		if inputIsLeftHanded then
			if state.Gamepad.bLeftTrigger > triggerValue then
				overrideDecoupledYaw = true
			end
			doLeftHandRemap(state)
		else
			if state.Gamepad.bRightTrigger > triggerValue then
				overrideDecoupledYaw = true
			end
			doRightHandRemap(state)
		end
	end

	--calculate decoupled Yaw
	if not isDecoupledYawDisabled and not overrideDecoupledYaw then
		--Read Gamepad stick input for rotation compensation
		local ThumbLX = state.Gamepad.sThumbLX
		local ThumbLY = state.Gamepad.sThumbLY
		local ThumbRX = state.Gamepad.sThumbRX
		local ThumbRY = state.Gamepad.sThumbRY

		if inputIsLeftHanded then
			ThumbLX = state.Gamepad.sThumbRX
			ThumbLY = state.Gamepad.sThumbRY
			ThumbRX = state.Gamepad.sThumbLX
			ThumbRY = state.Gamepad.sThumbLY
		end

		if locomotionMode == LocomotionMode.Head then
			if inputIsLeftHanded then
				state.Gamepad.sThumbRX= ThumbLX*math.cos(-AlphaDiff)- ThumbLY*math.sin(-AlphaDiff)
				state.Gamepad.sThumbRY= math.sin(-AlphaDiff)*ThumbLX + ThumbLY*math.cos(-AlphaDiff)
			else
				state.Gamepad.sThumbLX= ThumbLX*math.cos(-AlphaDiff)- ThumbLY*math.sin(-AlphaDiff)
				state.Gamepad.sThumbLY= math.sin(-AlphaDiff)*ThumbLX + ThumbLY*math.cos(-AlphaDiff)
			end
		end

		if useSnapTurn then
			if ThumbRX > snapTurnDeadZone and RXState == 0 then
				decoupledYawCurrentRot=decoupledYawCurrentRot + snapAngle
				RXState=1
			elseif ThumbRX < -snapTurnDeadZone and RXState == 0 then
				decoupledYawCurrentRot=decoupledYawCurrentRot - snapAngle
				RXState=1
			elseif ThumbRX <= snapTurnDeadZone and ThumbRX >=-snapTurnDeadZone then
				RXState=0
			end
		else
			local smoothTurnRate = smoothTurnSpeed / 12.5
			local rate = ThumbRX/32767
			rate =  rate*rate*rate*rate
			if ThumbRX > 2200 then
				decoupledYawCurrentRot = decoupledYawCurrentRot + (rate * smoothTurnRate)
			end
			if ThumbRX < -2200 then
				decoupledYawCurrentRot = decoupledYawCurrentRot - (rate * smoothTurnRate)
			end
		end

		--keep the decoupled yaw in the range of -180 to 180
		if decoupledYawCurrentRot > 180 then
			decoupledYawCurrentRot = -360 + decoupledYawCurrentRot
		end
		if decoupledYawCurrentRot < -180 then
			decoupledYawCurrentRot = 360 + decoupledYawCurrentRot
		end
	end
	return decoupledYawCurrentRot
end

return M