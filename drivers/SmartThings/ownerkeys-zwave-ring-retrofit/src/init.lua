local capabilities = require "st.capabilities"
local defaults = require "st.zwave.defaults"
local ZwaveDriver = require "st.zwave.driver"

local zwave_sensor_template = {
  supported_capabilities = {
    capabilities.refresh,
    capabilities.battery,
    capabilities.contactSensor
  },
  sub_drivers = {
    require("ring-retrofit")
  },
}

--Register the default z-wave command class handlers.
--These aer the z-wave side of things, not the SmartThings capabilities side of things.
--... lua_libs-api_v3/st/zwave/defaults is the source for the CC events/handlers
defaults.register_for_default_handlers(zwave_sensor_template, zwave_sensor_template.supported_capabilities)

local zwave_sensor = ZwaveDriver("zwave_retrofit", zwave_sensor_template)

zwave_sensor:run()
