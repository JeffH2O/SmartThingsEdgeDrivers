local capabilities = require "st.capabilities"
local contactSensor = require "st.zwave.defaults.contactSensor"
local cc = require "st.zwave.CommandClass"
local Association = (require "st.zwave.CommandClass.Association")({ version = 2 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local MultiChannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({version=3})
local Notification = (require "st.zwave.CommandClass.Notification")({ version=8 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })
local log = require "log"
local utils = require("st.utils")
local json = require "st.json"

local constants = require "st.zwave.constants"

local ZWAVE_RING_RETROFITALARMKIT_FINGERPRINTS = {
  {mfr = 0x0346, prod = 0x0B01, model = 0x0101},
}

local function can_handle(opts, driver, device, ...)
  log.debug("can_handle opts:" .. utils.stringify_table(opts))
  for _, fingerprint in ipairs(ZWAVE_RING_RETROFITALARMKIT_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function notification_report_handler(self, device, cmd)
  log.trace("NotificationReportHandler:  cmd.args=" .. utils.stringify_table(cmd.args))
  local args = cmd.args
  local notification_type = args.notification_type
  local event = args.event

  if notification_type == Notification.notification_type.HOME_SECURITY then
    if event == Notification.event.home_security.STATE_IDLE then
      device:emit_component_event(device.profile.components["zone1"], capabilities.contactSensor.contact.closed())
    else 
      if event == Notification.event.home_security.INTRUSION then
        device:emit_component_event(device.profile.components["zone1"], capabilities.contactSensor.contact.open())
      end
    end
  end

  -- if notification_type == Notification.notification_type.POWER_MANAGEMENT then
  --   local event = args.event
  --   -- if event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
    --   device:emit_event(capabilities.powerSource.powerSource.dc())
    -- elseif event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
    --   device:emit_event(capabilities.powerSource.powerSource.battery())
    -- end
  -- else
    -- use the default handler for motion sensor
    -- motionSensor.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
  -- end

  -- cmd.args                        opened      closed
  --   event function:               0x1fd7da8   0x2078270
  --   notification_status function: 0x20884b0   0x20844b8
  --   notification type             0x2080b78   0x2090d80
  --   z_wave_alarm_event            0x20fac58   0x2081a60
  --   z_wave_alarm_status           0x20607a0   0x209a7a8
  --   z_wave_alarm_type             0x205c350   0x20867a8
  --   event                         2           0
  --   event_parameter               ""          "\x02"
  --   z_wave_alarm_event            2           0


  -- {args={event="STATE_IDLE", event_parameter="\x02", z_wave_alarm_event=0,           payload="\x00\x00\x00\xFF\x07\x00\x01\x02",
  -- {args={event="INTRUSION",  event_parameter="",     z_wave_alarm_event="INTRUSION", payload="\x00\x00\x00\xFF\x07\x02\x00",   

end


local function device_do_configure(self, device)
  log.trace("device_do_configure")
  device:refresh()

  device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = 60}))

  -- device:send(MultiChannelAssociation:Remove({grouping_identifier = 1, node_ids = {}}))
  -- device:send(Configuration:Set({ configuration_value = 1, parameter_number = 250, size = 1 }))
  device:send(Association:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}}))
  -- device:send(Association:Set({grouping_identifier = 3, node_ids = {self.environment_info.hub_zwave_id}}))
  -- device:send(Association:Set({grouping_identifier = 4, node_ids = {self.environment_info.hub_zwave_id}}))
  -- device:send(Association:Set({grouping_identifier = 5, node_ids = {self.environment_info.hub_zwave_id}}))
  -- device:send(Association:Set({grouping_identifier = 6, node_ids = {self.environment_info.hub_zwave_id}}))
  -- device:send(Association:Set({grouping_identifier = 7, node_ids = {self.environment_info.hub_zwave_id}}))
  -- device:send(Association:Set({grouping_identifier = 8, node_ids = {self.environment_info.hub_zwave_id}}))
  -- device:send(Association:Set({grouping_identifier = 9, node_ids = {self.environment_info.hub_zwave_id}}))

end

local function send_config(device, parameter_number, old_configuration_value, configuration_value, size)
  log.trace("send_config")
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
  log.trace("update_preferences")
  local oldPrefs = args.old_st_store.preferences
  local newPrefs = device.preferences

  print_preferences(self, oldPrefs, newPrefs)

  send_config(device, 4, oldPrefs.heartbeats, newPrefs.heartbeats, 2)

  -- send_config(device, 4, oldPrefs.announcementVolume, newPrefs.announcementVolume, 1)
  -- only in z-wave documentation
  -- send_config(device, 20, oldPrefs.securityBlinkDuration, newPrefs.securityBlinkDuration, 1)
  -- in official documentation it's 21, which is incorrect, in z-wave doc it's 22
  -- send_config(device, 22, oldPrefs.securityModeDisplay, newPrefs.securityModeDisplay, 2)
end

local function device_info_changed(self, device, event, args)
  log.trace("device_info_changed")

  if device:is_cc_supported(cc.WAKE_UP) then
    log.trace("... update_preferences not called")
  else
    log.trace("... not device:is_cc_supported(cc.WAKE_UP)")
    update_preferences(self, device, args)
  end
end


-- local componentToAlarmData = {
--   main = AlarmData(Indicator.indicator_id.ALARMING, false, false),
--   burglarAlarm = AlarmData(Indicator.indicator_id.ALARMING_BURGLAR, false, false),
--   fireAlarm = AlarmData(Indicator.indicator_id.ALARMING_SMOKE_FIRE, false, false),
--   carbonMonoxideAlarm = AlarmData(Indicator.indicator_id.ALARMING_CARBON_MONOXIDE, false, false),
--   medicalAlarm = AlarmData(0x13, false, true),
--   freezeAlarm = AlarmData(0x14, true, true),
--   waterLeakAlarm = AlarmData(0x15, true, true),
--   freezeAndWaterAlarm = AlarmData(0x81, true, true),
-- }

local function device_added(self, device)
  log.debug("device_added: " .. utils.stringify_table(device))

  -- register each zone?  or is it just "assocation group 2"?
  device:send(Association:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}}))

  -- increase the default size of key cache to easier support longer PIN (default: 8)
  --device:send(EntryControl:ConfigurationSet({key_cache_size=10, key_cache_timeout=5}))

  -- for componentName, _ in pairs(componentToAlarmData) do
  --   device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.off())
  -- end

end

local function device_init(self, device)
  log.debug(utils.stringify_table(device, "device_init: ", true))
  device:set_update_preferences_fn(update_preferences)
  
  device:emit_component_event(device.profile.components["zone1"], capabilities.contactSensor.contact.closed())
  device:emit_component_event(device.profile.components["zone2"], capabilities.contactSensor.contact.closed())
  device:emit_component_event(device.profile.components["zone3"], capabilities.contactSensor.contact.closed())
  device:emit_component_event(device.profile.components["zone4"], capabilities.contactSensor.contact.closed())
  device:emit_component_event(device.profile.components["zone5"], capabilities.contactSensor.contact.closed())
  device:emit_component_event(device.profile.components["zone6"], capabilities.contactSensor.contact.closed())
  device:emit_component_event(device.profile.components["zone7"], capabilities.contactSensor.contact.closed())
  device:emit_component_event(device.profile.components["zone8"], capabilities.contactSensor.contact.closed())

end

-- local all_alarm_components = {}
-- for component_name in pairs(componentToAlarmData) do
--   table.insert(all_alarm_components, component_name)
-- end

local function zwave_basic_report(self, device, cmd)
  log.trace("zwave_basic_report.  cmd=" .. utils.stringify_table(cmd))
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  device:emit_event(value == Basic.value.OFF_DISABLE and capabilities.switch.switch.off() or capabilities.switch.switch.on())

  if value >= 0 then
    device:emit_event(capabilities.switchLevel.level(value >= 99 and 100 or value))
  end
end

local function zwave_basic_set(self, device, cmd)
  log.trace("zwave_basic_report.  cmd=" .. utils.stringify_table(cmd))
end


local function zwave_configuration_report(self, device, cmd)
  log.debug("zwave_configuration_report")
  log.debug("  cmd:    " .. utils.stringify_table(cmd, "", true))
  --local parameter_number = cmd.args.parameter_number
end


local function wakeup_notification(self, device, cmd)
  log.debug("wakeup_notification")
  log.debug("  cmd:    " .. utils.stringify_table(cmd, "", true))
  --local parameter_number = cmd.args.parameter_number
  --TODO??? set device options/preferences/configs if we missed them while it was asleep?
end

local ring_retrofit = {
  NAME = "Ring Retrofit Alarm Kit",
  zwave_handlers = {
    -- [cc.ENTRY_CONTROL] = {
    --   [EntryControl.NOTIFICATION] = entry_control_notification_handler
    -- },
    [cc.BASIC] = {
      [Basic.REPORT] = zwave_basic_report,
      [Basic.SET] = zwave_basic_set
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = zwave_configuration_report
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    },
  },
  capability_handlers = {
    -- [capabilities.tone.ID] = {
    --   [capabilities.tone.commands.beep.NAME] = tone_handler,
    -- },
    -- [capabilities.chime.ID] = {
    --   [capabilities.chime.commands.chime.NAME] = chime_on,
    --   [capabilities.chime.commands.off.NAME] = chime_off,
    -- },
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = device_do_configure,
    infoChanged = device_info_changed,
  },
  can_handle = can_handle,
}

return ring_retrofit
