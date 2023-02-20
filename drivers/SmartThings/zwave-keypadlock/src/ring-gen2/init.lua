local capabilities = require "st.capabilities"
local motionSensor = require "st.zwave.defaults.motionSensor"
local cc = require "st.zwave.CommandClass"
local EntryControl = (require "st.zwave.CommandClass.EntryControl")({ version=1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version=8 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local Indicator = (require "st.zwave.CommandClass.Indicator")({ version=3 })
local log = require "log"
local utils = require("st.utils")
local json = require "st.json"

local constants = require "st.zwave.constants"
local LockCodesDefaults = require "st.zwave.defaults.lockCodes"

local fieldNames  = {
  lockCodes = "lockCodes",
}

local function getLockCodes(device)
  local lockCodes = device:get_field(fieldNames.lockCodes)
  if (lockCodes == nil) then return {} end
  return utils.deep_copy(lockCodes)
end


local ZWAVE_RING_GEN2_FINGERPRINTS = {
  {mfr = 0x0346, prod = 0x0101, model = 0x0301},
  {mfr = 0x0346, prod = 0x0101, model = 0x0401},
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_RING_GEN2_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function notification_report_handler(self, device, cmd)
  log.trace("NotificationReportHandler")
  local args = cmd.args
  local notification_type = args.notification_type
  if notification_type == Notification.notification_type.POWER_MANAGEMENT then
    local event = args.event
    if event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      device:emit_event(capabilities.powerSource.powerSource.dc())
    elseif event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      device:emit_event(capabilities.powerSource.powerSource.battery())
    end
  else
    -- use the default handler for motion sensor
    motionSensor.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
  end
end

local function incorrect_pin(device)
  log.trace("incorrect_pin")
  device:send(Indicator:Set({
    indicator_objects = {
      { indicator_id = Indicator.indicator_id.NOT_OK, property_id = Indicator.property_id.MULTILEVEL, value = 100 },
    }
  }))
end

local eventTypeToComponentName = {
  [EntryControl.event_type.DISARM_ALL] = "disarmAllButton",
  --[EntryControl.event_type.ARM_HOME] = "armHomeButton",
  [EntryControl.event_type.ARM_AWAY] = "armAwayButton",
  --[EntryControl.event_type.POLICE] = "policeButton",
  --[EntryControl.event_type.FIRE] = "fireButton",
  --[EntryControl.event_type.ALERT_MEDICAL] = "alertMedicalButton",
  --[EntryControl.event_type.ALERT_PANIC] = "panicCombination",
}

local function entry_control_notification_handler(self, device, cmd)
  log.trace("Entry Control Notification handler")
  local args = cmd.args
  local event_type = args.event_type
  local event_data = args.event_data
  log.trace("  Entry Control eventType = " .. event_type .. ", event data = " .. event_data)
  local componentName = eventTypeToComponentName[event_type]
  if componentName == nil then
    log.debug("Unhandled entry control event type: " .. event_type)
    return
  end

  local validCodeEntry = nil
  local enteredPIN = event_data
  local lockCodes = getLockCodes(device)
  for _, lockCode in pairs(lockCodes) do
    if lockCode.codePIN == enteredPIN then
      validCodeEntry = lockCode
      break
    end
  end

  if validCodeEntry == nil then
    incorrect_pin(device)
    return
  end

  log.trace("  Valid code entered: " .. utils.stringify_table(validCodeEntry))
  local component = device.profile.components.main
  if event_type == EntryControl.event_type.DISARM_ALL then
    device:emit_component_event(component, capabilities.lock.lock.unlocked())
  elseif event_type == EntryControl.event_type.ARM_AWAY then
    device:emit_component_event(component, capabilities.lock.lock.locked())
  end
  
  -- log.debug("entry_control, after lock stuff")
  --trying something here:
  --says "disarm", but i would like a positive ding and to enable the light for 10 seconds.
  -- device:send(Indicator:Set({
  --   indicator_objects = {
  --     {
  --       indicator_id = Indicator.indicator_id.OK,
  --       property_id = Indicator.property_id.MULTILEVEL,
  --       value = 100  -- turn off the light
  --     },
  --   }
  -- }))

end

local function device_do_configure(self, device)
  device:refresh()
end

local function send_config(device, parameter_number, old_configuration_value, configuration_value, size)
  if old_configuration_value ~= configuration_value then
    log.debug("send_config for " .. tostring(parameter_number) .. " " .. tostring(old_configuration_value) .. " --> " .. tostring(configuration_value) )
    device:send(Configuration:Set({
        parameter_number = parameter_number,
        configuration_value = configuration_value,
        size = size
    }))
  end
end

local function print_preferences(self, oldPrefs, newPrefs)
  for id, value in pairs(newPrefs) do
    if oldPrefs[id] ~= newPrefs[id] then
      print("prefChanged", id .. string.rep(' ', 25 - #id),  oldPrefs[id], " -->",  newPrefs[id])
    else
      print("pref       ", id .. string.rep(' ', 25 - #id),  newPrefs[id])
    end
  end
end

local function bool_to_number(value)
  return value and 1 or 0
end

local function update_preferences(self, device, args)
  local oldPrefs = args.old_st_store.preferences
  local newPrefs = device.preferences

  print_preferences(self, oldPrefs, newPrefs)

  send_config(device, 4, oldPrefs.announcementVolume, newPrefs.announcementVolume, 1)
  send_config(device, 5, oldPrefs.keyVolume, newPrefs.keyVolume, 1)
  send_config(device, 6, oldPrefs.sirenVolume, newPrefs.sirenVolume, 1)
  send_config(device, 7, oldPrefs.emergencyDuration, newPrefs.emergencyDuration, 1)
  send_config(device, 8, oldPrefs.longPressNumberDuration, newPrefs.longPressNumberDuration, 1)
  send_config(device, 9, oldPrefs.proximityDisplayTimeout, newPrefs.proximityDisplayTimeout, 1)
  send_config(device, 10, oldPrefs.btnPressDisplayTimeout, newPrefs.btnPressDisplayTimeout, 1)
  send_config(device, 11, oldPrefs.statusChgDisplayTimeout, newPrefs.statusChgDisplayTimeout, 1)
  send_config(device, 12, oldPrefs.securityModeBrightness, newPrefs.securityModeBrightness, 1)
  send_config(device, 13, oldPrefs.keyBacklightBrightness, newPrefs.keyBacklightBrightness, 1)
  send_config(device, 14, oldPrefs.ambientSensorLevel, newPrefs.ambientSensorLevel, 1)
  send_config(device, 15, bool_to_number(oldPrefs.proximityOnOff), bool_to_number(newPrefs.proximityOnOff), 1)
  send_config(device, 16, oldPrefs.rampTime, newPrefs.rampTime, 1)
  send_config(device, 17, oldPrefs.lowBatteryTrshld, newPrefs.lowBatteryTrshld, 1)
  send_config(device, 18, oldPrefs.language, newPrefs.language, 1)
  send_config(device, 19, oldPrefs.warnBatteryTrshld, newPrefs.warnBatteryTrshld, 1)
  -- only in z-wave documentation
  send_config(device, 20, oldPrefs.securityBlinkDuration, newPrefs.securityBlinkDuration, 1)
  -- in official documentation it's 21, which is incorrect, in z-wave doc it's 22
  send_config(device, 22, oldPrefs.securityModeDisplay, newPrefs.securityModeDisplay, 2)
end

local function device_info_changed(self, device, event, args)
  if not device:is_cc_supported(cc.WAKE_UP) then
    update_preferences(self, device, args)
  end
end

local buttonComponents = {
  "disarmAllButton",
  "armHomeButton",
  "armAwayButton",
  -- "policeButton",
  -- "fireButton",
  -- "alertMedicalButton",
  -- "panicCombination",
}


local function AlarmData(indicator_id, keypad_blinking, voice)
  return {
    indicator_id = indicator_id,
    keypad_blinking = keypad_blinking,
    voice = voice,
  }
end

local componentToAlarmData = {
  main = AlarmData(Indicator.indicator_id.ALARMING, false, false),
  burglarAlarm = AlarmData(Indicator.indicator_id.ALARMING_BURGLAR, false, false),
  fireAlarm = AlarmData(Indicator.indicator_id.ALARMING_SMOKE_FIRE, false, false),
  carbonMonoxideAlarm = AlarmData(Indicator.indicator_id.ALARMING_CARBON_MONOXIDE, false, false),
  medicalAlarm = AlarmData(0x13, false, true),
  freezeAlarm = AlarmData(0x14, true, true),
  waterLeakAlarm = AlarmData(0x15, true, true),
  freezeAndWaterAlarm = AlarmData(0x81, true, true),
}

local function device_added(self, device)
  log.debug("device_added")
  -- increase the default size of key cache to easier support longer PIN (default: 8)
  device:send(EntryControl:ConfigurationSet({key_cache_size=10, key_cache_timeout=5}))
  local buttonValuesEvent = capabilities.button.supportedButtonValues({"pushed"})
  local buttonsNumberEvent = capabilities.button.numberOfButtons({value = 1})
  for _, componentName in pairs(buttonComponents) do
    local component = device.profile.components[componentName]
    device:emit_component_event(component, buttonValuesEvent)
    device:emit_component_event(component, buttonsNumberEvent)
  end

  device:emit_event(capabilities.powerSource.powerSource.unknown())
  device:emit_event(capabilities.securitySystem.securitySystemStatus.disarmed())
  for componentName, _ in pairs(componentToAlarmData) do
    device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.off())
  end
  device:emit_component_event(device.profile.components.doorBell, capabilities.chime.chime.off())
  device:emit_event(capabilities.motionSensor.motion.inactive())

  -- discover power source
  device:send(Notification:Get({
    notification_type = Notification.notification_type.POWER_MANAGEMENT,
    event = Notification.event.power_management.AC_MAINS_RE_CONNECTED
  }))
  device:send(Notification:Get({
    notification_type = Notification.notification_type.POWER_MANAGEMENT,
    event = Notification.event.power_management.AC_MAINS_DISCONNECTED
  }))

  -- set silently the initial security system state to disarmed
  device:send(Indicator:Set({
    indicator_objects = {
      {
        indicator_id = Indicator.indicator_id.NOT_ARMED,
        property_id = Indicator.property_id.MULTILEVEL,
        value = 0  -- turn off the light
      },
      {
        indicator_id = Indicator.indicator_id.NOT_ARMED,
        property_id = Indicator.property_id.SPECIFIC_VOLUME,
        value = 0  -- turn off the sound
      },
    }
  }))
end

local function device_init(self, device)
  log.debug("device_init")
  device:set_update_preferences_fn(update_preferences)

  -- log.debug(" lockCodesCapability: " .. utils.stringify_table(capabilities.lockCodes, "", true ))
  -- capabilities.lockCodes.maxCodes(20)
  -- log.debug(" lockCodesCapability: " .. utils.stringify_table(capabilities.lockCodes, "", true ))
  
end

local component_to_sound = {
  bypassRequired = 16,
  entryDelay = 17,
  exitDelay = 18,
  notifyingContacts = 131,
  alertAcknowledged = 132,
  monitoringActivated = 133,
}

local function tone_handler(self, device, cmd)
  local componentName = cmd.component
  local soundId = component_to_sound[componentName]
  if soundId ~= nil then
    local preferences = device.preferences
    if componentName == "entryDelay" or componentName == "exitDelay" then
      local delayTime = componentName == "entryDelay" and preferences.entryDelayTime or preferences.exitDelayTime
      device:send(Indicator:Set({
        indicator_objects = {
          {
            indicator_id = soundId,
            property_id = Indicator.property_id.TIMEOUT_MINUTES,
            value = delayTime // 60
          },
          {
            indicator_id = soundId,
            property_id = Indicator.property_id.TIMEOUT_SECONDS,
            value = delayTime % 60
          },
        }
      }))
    else
      device:send(Indicator:Set({
        indicator_objects = {{
          indicator_id = soundId,
          property_id = Indicator.property_id.SPECIFIC_VOLUME,
          value = preferences.announcementVolume * 10
      }}}))
    end
  end
end

local function chime_on(self, device, cmd)
  local soundId = device.preferences.doorBellSound
  device:send(Indicator:Set({
    indicator_objects = {{
      indicator_id = soundId,
      property_id = Indicator.property_id.SPECIFIC_VOLUME,
      value = device.preferences.doorbellVolume * 10
  }}}))
  device:emit_component_event(device.profile.components.doorBell, capabilities.chime.chime.off())
end

local function chime_off(self, device, cmd)
  device:emit_component_event(device.profile.components.doorBell, capabilities.chime.chime.off())
end

local securitySystemStatusToIndicator = {
  disarmed = Indicator.indicator_id.NOT_ARMED,
  armedStay = Indicator.indicator_id.ARMED_STAY,
  armedAway = Indicator.indicator_id.ARMED_AWAY,
  ready = Indicator.indicator_id.READY,
}

local all_alarm_components = {}
for component_name in pairs(componentToAlarmData) do
  table.insert(all_alarm_components, component_name)
end

local keypad_blinking_components = {}
local alert_components = {}
for component_name, alarm_data in pairs(componentToAlarmData) do
  if alarm_data.keypad_blinking then
    table.insert(keypad_blinking_components, component_name)
  else
    table.insert(alert_components, component_name)
  end
end

-- local function alarm_off(self, device, cmd)
--   log.debug("ALARM_OFF")
--   local componentName = cmd.component
--   local alarm_data = componentToAlarmData[componentName]
--   if alarm_data == nil then
--     return
--   end
--   local indicator_id = alarm_data.indicator_id

--   if alarm_data.keypad_blinking then
--     for _, kp_component_name in pairs(keypad_blinking_components) do
--       device:emit_component_event(device.profile.components[kp_component_name], capabilities.alarm.alarm.off())
--     end
--   else
--     -- HACK: to disable the alarm we use the security mode without sound and LED. Is there a better solution?
--     local securitySystemStatus = device:get_latest_state("main", capabilities.securitySystem.ID, "securitySystemStatus")
--     indicator_id = securitySystemStatusToIndicator[securitySystemStatus]
--     -- the hack above turns off all alarms
--     for _, alarm_component_name in pairs(all_alarm_components) do
--       device:emit_component_event(device.profile.components[alarm_component_name], capabilities.alarm.alarm.off())
--     end
--   end
--   device:send(Indicator:Set({
--     indicator_objects = {
--       {
--         indicator_id = indicator_id,
--         property_id = Indicator.property_id.MULTILEVEL,
--         value = 0  -- turn off the light
--       },
--       {
--         indicator_id = indicator_id,
--         property_id = Indicator.property_id.SPECIFIC_VOLUME,
--         value = 0  -- turn off the sound
--       },
--     }
--   }))
-- end

-- local function turn_off_other_alarms(device, alarm_data, component_name)
--   if alarm_data.keypad_blinking then
--     for _, kp_component_name in pairs(keypad_blinking_components) do
--       if kp_component_name ~= component_name then
--         device:emit_component_event(device.profile.components[kp_component_name], capabilities.alarm.alarm.off())
--       end
--     end
--   else
--     for _, alert_component_name in pairs(alert_components) do
--       if alert_component_name ~= component_name then
--         device:emit_component_event(device.profile.components[alert_component_name], capabilities.alarm.alarm.off())
--       end
--     end
--   end
-- end

-- local function alarm_both(self, device, cmd)
--   log.debug("ALARM_BOTH")
--   local componentName = cmd.component
--   local alarm_data = componentToAlarmData[componentName]
--   if alarm_data == nil then
--     return
--   end
--   local preferences = device.preferences
--   local indicator_id = alarm_data.indicator_id
--   local volume = 10 * (alarm_data.voice and preferences.announcementVolume or preferences.sirenVolume)

--   device:send(Indicator:Set({
--     indicator_objects = {
--       {
--         indicator_id = indicator_id,
--         property_id = Indicator.property_id.SPECIFIC_VOLUME,
--         value = volume,
--       }
--     }
--   }))

--   turn_off_other_alarms(device, alarm_data, componentName)
--   device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.both())
-- end

-- local function alarm_siren(self, device, cmd)
--   log.debug("ALARM_SIREN")
--   local componentName = cmd.component
--   local alarm_data = componentToAlarmData[componentName]
--   if alarm_data == nil then
--     return
--   end
--   if not alarm_data.keypad_blinking then
--     -- fallback for alarms that does not support turning off the light
--     alarm_both(self, device, cmd)
--     return
--   end
--   local indicator_id = alarm_data.indicator_id
--   device:send(Indicator:Set({
--     indicator_objects = {
--       {
--         indicator_id = indicator_id,
--         property_id = Indicator.property_id.MULTILEVEL,
--         value = 0
--       },
--     }
--   }))

--   turn_off_other_alarms(device, alarm_data, componentName)
--   device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.siren())
-- end

-- local function alarm_strobe(self, device, cmd)
--   log.debug("ALARM_STROBE")
--   local componentName = cmd.component
--   local alarm_data = componentToAlarmData[componentName]
--   if alarm_data == nil then
--     return
--   end
--   local indicator_id = alarm_data.indicator_id

--   device:send(Indicator:Set({
--         indicator_objects = {
--           {
--             indicator_id = indicator_id,
--             property_id = Indicator.property_id.SPECIFIC_VOLUME,
--             value = 0
--           }
--   }}))

--   turn_off_other_alarms(device, alarm_data, componentName)
--   device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.strobe())
-- end



local function emitLockCodes(device)
  local lockCodes = getLockCodes(device)
  --should we NOT publish the PINs?  For now I am so that other apps CAN see the PINs
  --If this deems to not be compatible with SLGA or something else, or is a security vulnerabiliyt, may need to re-think this.
  device:emit_event(capabilities.lockCodes.lockCodes(json.encode(lockCodes), {visibility = {displayed = false }}))
end

local function debugPrintLockCodes(device)
  local lockCodes = getLockCodes(device)
  log.debug(utils.stringify_table(lockCodes, "current lockCodes:", true))
end

local function getChangeType(device, codeSlot)
  local lockCodes = getLockCodes(device)
  if (lockCodes[codeSlot] == nil) then
    return LockCodesDefaults.CHANGE_TYPE.SET
  else
    return LockCodesDefaults.CHANGE_TYPE.CHANGED
  end
end


local function lockCodes_deleteCode(self, device, cmd)
  --cmd.args = {codeSlot = 3}
  local codeSlot = cmd.args.codeSlot
  log.debug("lockCodes_deleteCode")
  log.debug("  codeSlot: " .. tostring(codeSlot))

  local lockCodes = getLockCodes(device)
  lockCodes[tostring(codeSlot)] = nil
  device:set_field(fieldNames.lockCodes, lockCodes, {persist = true})
  emitLockCodes(device)

  local code_changed_event = capabilities.lockCodes.codeChanged("", { state_change = true })
  code_changed_event.value = tostring(cmd.args.codeSlot) .. LockCodesDefaults.CHANGE_TYPE.DELETED
  device:emit_event(code_changed_event)

end

local function lockCodes_nameSlot(self, device, cmd)
  log.debug("lockCodes_nameSlot")
  local codeSlot = cmd.args.codeSlot
  local newCodeName = cmd.args.codeName

  local lockCodes = getLockCodes(device)
  if ( (lockCodes == nil) or (lockCodes[tostring(codeSlot)] == nil)) then
    log.error("Cannot change the name for a codeSlot that doesn't exist.  codeSlot=" .. tostring(codeSlot))
    return
  end

  lockCodes[tostring(cmd.args.codeSlot)].codeName = newCodeName
  device:set_field(fieldNames.lockCodes, lockCodes, {persist = true})
  emitLockCodes(device)
  local code_changed_event = capabilities.lockCodes.codeChanged("", { state_change = true })
  code_changed_event.value = tostring(cmd.args.codeSlot) .. LockCodesDefaults.CHANGE_TYPE.RENAMED
  --code_changed_event["data"] = { codeName = cmd.args.codeName}
  device:emit_event(code_changed_event)

end

local function lockCodes_reloadAllCodes(driver, device, cmd)
  log.debug("lockCodes_reloadAllCodes - top")
  debugPrintLockCodes(device)
  emitLockCodes(device)

  -- local component = "main"
  -- if cmd ~= nil then component = device:endpoint_to_component(cmd.src_channel) end
  -- local max_codes = device:get_latest_state(component,
  --   capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
  -- log.debug("lockCodes_reloadAllCodes - max_codes " .. (max_codes or "nil"))
  -- if (max_codes == nil) then
  --  -- device:send(UserCode:UsersNumberGet({}))
  --  device:emit_event(capabilities.lockCodes.maxCodes(tostring(40), { visibility = { displayed = false } }))
  -- end
  -- local checking_code = device:get_field(constants.CHECKING_CODE)
  -- log.debug("lockCodes_reloadAllCodes - checking_code " .. (checking_code or "nil"))
  -- local scanning = false
  -- -- either we haven't started checking
  -- if (checking_code == nil) then
  --   checking_code = 1
  --   device:set_field(constants.CHECKING_CODE, checking_code)
  --   device:emit_event(capabilities.lockCodes.scanCodes("Scanning", { visibility = { displayed = false } }))
  --   log.debug("lockCodes_reloadAllCodes -  after emit_event 'scanning' ")
  --   -- use a flag here because sometimes state doesn't propagate immediately
  --   scanning = true
  -- end
  -- or scanning got stuck
  -- if (scanning or device:get_latest_state(component, capabilities.lockCodes.ID, capabilities.lockCodes.scanCodes.NAME) == "Scanning") then
  --     -- device:send(UserCode:Get({user_identifier = checking_code}))
  --     --> sends command to zwave device, then device gets the user code report handler, which sets the code via code_set_event
  --     --> mock one out here.
  --     LockCodesDefaults.code_set_event(device, 1, "aaaa")
  --     LockCodesDefaults.clear_code_state(device, 1)
  --     --local codeName = LockCodesDefaults.get_code_name(device, 1)
  --     local changeType = LockCodesDefaults.get_change_type(device, 1)
  --     local code_changed_event = capabilities.lockCodes.codeChanged("", { state_change = true })
  --     code_changed_event.value = "1" .. changeType
  --     code_changed_event["data"] = { codeName = "aaaa"}
  --     device:emit_event(code_changed_event)
  --     --LockCodesDefaults.verify_set_code_completion(device, cmd, 1)

  --     --LockCodesDefaults.code_set_event(device, 2, "bbbb")
      
  -- end
  
  -- log.debug("cmd.args.supported_users: " .. (cmd.args.supported_users or "nil"))
  -- device:emit_event(capabilities.lockCodes.maxCodes(cmd.args.supported_users, { visibility = { displayed = false } }))

end

local function lockCodes_requestCode(self, device, cmd)
  log.debug("lockCodes_requestCode")
  log.debug("  cmd:    " .. utils.stringify_table(cmd, "", true))
end


local function lockCodes_setCode(self, device, cmd)
  -- cmd.args example:  {codeName = "Joe Smith", codePIN = "1234", codeSlot = 5}
  -- cmd.args example for rename: {codeName = "Joe Smith", codePIN = "", codeSlot = 5}

  log.debug("lockCodes_setCode - top")
  --TODO: move "max number of codes" defaults to init/added?
  -- local component = "main"
  -- if cmd ~= nil then component = device:endpoint_to_component(cmd.src_channel) end
  -- local max_codes = device:get_latest_state(component, capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
  -- log.debug("lockCodes_setCode - max_codes " .. (max_codes or "nil"))
  -- if (max_codes == nil) then
  --  -- device:send(UserCode:UsersNumberGet({}))
  --  device:emit_event(capabilities.lockCodes.maxCodes(tostring(40), { visibility = { displayed = false } }))
  -- end

  --If they are renaming a slot, then redirect to that path.
  if (cmd.args.codePIN == "") then
    self:inject_capability_command(device, {
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.nameSlot.NAME,
      args = {cmd.args.codeSlot, cmd.args.codeName},
    })
    return
  end

  local lockCodes = getLockCodes(device)
  lockCodes[tostring(cmd.args.codeSlot)] = {codeSlot = cmd.args.codeSlot, codePIN = cmd.args.codePIN, codeName = cmd.args.codeName}
  device:set_field(fieldNames.lockCodes, lockCodes, {persist = true})
  emitLockCodes(device)

  local changeType = getChangeType(device, cmd.args.codeSlot)
  local code_changed_event = capabilities.lockCodes.codeChanged("", { state_change = true })
  code_changed_event.value = tostring(cmd.args.codeSlot) .. changeType
  code_changed_event["data"] = { codeName = cmd.args.codeName}
  device:emit_event(code_changed_event)
end

local function lockCodes_setCodeLength(self, device, cmd)
  log.debug("lockCodes_setCodeLength")
  log.debug("  cmd:    " .. utils.stringify_table(cmd, "", true))
end

local function lockCodes_unlockWithTimeout(self, device, cmd)
  log.debug("lockCodes_unlockWithTimeout")
end

local function lockCodes_updateCodes(self, device, cmd)
  log.debug("lockCodes_updateCodes")
end

local function generic_lock(self, device, cmd)
  log.debug("generic_lock (lock_lock or lockCodes_lock)")
  device:emit_event(capabilities.lock.lock.locked())
  device:emit_event(capabilities.lockCodes.lock.locked())
end

local function generic_unlock(self, device, cmd)
  log.debug("generic_unlock (lock_unlock or lockCodes_unlock)")
  device:emit_event(capabilities.lock.lock.unlocked())
  device:emit_event(capabilities.lockCodes.lock.unlocked())
end


local function zwave_configuration_report(self, device, cmd)
  log.debug("zwave_configuration_report")
  log.debug("  cmd:    " .. utils.stringify_table(cmd, "", true))
  local parameter_number = cmd.args.parameter_number
end

local ring_gen2 = {
  NAME = "Ring Keypad 2nd Gen",
  zwave_handlers = {
    [cc.ENTRY_CONTROL] = {
      [EntryControl.NOTIFICATION] = entry_control_notification_handler
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = zwave_configuration_report
    },
  },
  capability_handlers = {
    -- [capabilities.securitySystem.ID] = {
    --   [capabilities.securitySystem.commands.armAway.NAME] = opebnDoor_command,
    --   [capabilities.securitySystem.commands.armStay.NAME] = closeDoorAndCheckout_command,
    --   [capabilities.securitySystem.commands.disarm.NAME] = closeDoor_command,
    -- },
    [capabilities.tone.ID] = {
      [capabilities.tone.commands.beep.NAME] = tone_handler,
    },
    [capabilities.chime.ID] = {
      [capabilities.chime.commands.chime.NAME] = chime_on,
      [capabilities.chime.commands.off.NAME] = chime_off,
    },
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.deleteCode.NAME] = lockCodes_deleteCode,
      [capabilities.lockCodes.commands.lock.NAME] = generic_lock,
      [capabilities.lockCodes.commands.nameSlot.NAME] = lockCodes_nameSlot,
      [capabilities.lockCodes.commands.reloadAllCodes.NAME] = lockCodes_reloadAllCodes,
      [capabilities.lockCodes.commands.requestCode.NAME] = lockCodes_requestCode,
      [capabilities.lockCodes.commands.setCode.NAME] = lockCodes_setCode,
      [capabilities.lockCodes.commands.setCodeLength.NAME] = lockCodes_setCodeLength,
      [capabilities.lockCodes.commands.unlock.NAME] = generic_unlock,
      [capabilities.lockCodes.commands.unlockWithTimeout.NAME] = lockCodes_unlockWithTimeout,
      [capabilities.lockCodes.commands.updateCodes.NAME] = lockCodes_updateCodes,
    },
    -- [capabilities.alarm.ID] = {
    --   [capabilities.alarm.commands.off.NAME] = alarm_off,
    --   [capabilities.alarm.commands.both.NAME] = alarm_both,
    --   [capabilities.alarm.commands.siren.NAME] = alarm_siren,
    --   [capabilities.alarm.commands.strobe.NAME] = alarm_strobe,
    -- },
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = generic_lock,
      [capabilities.lock.commands.unlock.NAME] = generic_unlock,
    },
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = device_do_configure,
    infoChanged = device_info_changed,
  },
  can_handle = can_handle,
}

return ring_gen2
