local capabilities = require "st.capabilities"
local contactSensor = require "st.zwave.defaults.contactSensor"
local cc = require "st.zwave.CommandClass"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version=8 })
local log = require "log"
local utils = require("st.utils")
local json = require "st.json"

local constants = require "st.zwave.constants"

local ZWAVE_RING_RETROFITALARMKIT_FINGERPRINTS = {
  {mfr = 0x0346, prod = 0x0B01, model = 0x0101},
}

local function can_handle(opts, driver, device, ...)
  log.trace("can_handle device: " .. utils.stringify_table(device));
  for _, fingerprint in ipairs(ZWAVE_RING_RETROFITALARMKIT_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      log.trace("... Yes!!!")
      return true
    end
  end
  log.trace("... No!!!")
  return false
end

local function notification_report_handler(self, device, cmd)
  log.trace("NotificationReportHandler")
  local args = cmd.args
  local notification_type = args.notification_type
  if notification_type == Notification.notification_type.POWER_MANAGEMENT then
    local event = args.event
    -- if event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
    --   device:emit_event(capabilities.powerSource.powerSource.dc())
    -- elseif event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
    --   device:emit_event(capabilities.powerSource.powerSource.battery())
    -- end
  else
    -- use the default handler for motion sensor
    motionSensor.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
  end
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

  send_config(device, 4, oldPrefs.heartbeats, newPrefs.heartbeats, 1)
  
  -- send_config(device, 4, oldPrefs.announcementVolume, newPrefs.announcementVolume, 1)
  -- only in z-wave documentation
  -- send_config(device, 20, oldPrefs.securityBlinkDuration, newPrefs.securityBlinkDuration, 1)
  -- in official documentation it's 21, which is incorrect, in z-wave doc it's 22
  -- send_config(device, 22, oldPrefs.securityModeDisplay, newPrefs.securityModeDisplay, 2)
end

local function device_info_changed(self, device, event, args)
  if not device:is_cc_supported(cc.WAKE_UP) then
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
  -- increase the default size of key cache to easier support longer PIN (default: 8)
  --device:send(EntryControl:ConfigurationSet({key_cache_size=10, key_cache_timeout=5}))

  -- for componentName, _ in pairs(componentToAlarmData) do
  --   device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.off())
  -- end

end

local function device_init(self, device)
  log.debug("device_init: " .. utils.stringify_table(device))
  device:set_update_preferences_fn(update_preferences)  
end

-- local all_alarm_components = {}
-- for component_name in pairs(componentToAlarmData) do
--   table.insert(all_alarm_components, component_name)
-- end

local function zwave_configuration_report(self, device, cmd)
  log.debug("zwave_configuration_report")
  log.debug("  cmd:    " .. utils.stringify_table(cmd, "", true))
  local parameter_number = cmd.args.parameter_number
end

local ring_retrofit = {
  NAME = "Ring Retrofit Alarm Kit",
  zwave_handlers = {
    -- [cc.ENTRY_CONTROL] = {
    --   [EntryControl.NOTIFICATION] = entry_control_notification_handler
    -- },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = zwave_configuration_report
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
