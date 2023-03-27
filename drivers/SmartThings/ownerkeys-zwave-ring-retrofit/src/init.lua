local capabilities = require "st.capabilities"
local defaults = require "st.zwave.defaults"
local ZwaveDriver = require "st.zwave.driver"
local log = require "log"


--- Map component to end_points(channels)
---
--- @param device st.zwave.Device
--- @param component_id string ID
--- @return table dst_channels destination channels e.g. {2} for Z-Wave channel 2 or {} for unencapsulated
local function component_to_endpoint(device, component_id)
  log.trace("parent.component_to_endpoint")
  local ep_num = component_id:match("switch(%d)")
  return { ep_num and tonumber(ep_num) }
end

--- Map end_point(channel) to Z-Wave endpoint 9 channel)
---
--- @param device st.zwave.Device
--- @param ep number the endpoint(Z-Wave channel) ID to find the component for
--- @return string the component ID the endpoint matches to
local function endpoint_to_component(device, ep)
  log.trace("parent.endpoint_to_component")
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

--- Initialize device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local device_init = function(self, device)
  log.trace("parent.device_init")
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
  end
end


local zwave_sensor_template = {
  supported_capabilities = {
    capabilities.refresh,
    capabilities.battery,
    capabilities.contactSensor,
    capabilities.zwMultichannel
  },
  sub_drivers = {
    require("ring-retrofit"),
  },
  lifecycle_handlers = {
    init = device_init,
  }
}

--Register the default z-wave command class handlers.
--These aer the z-wave side of things, not the SmartThings capabilities side of things.
--... lua_libs-api_v3/st/zwave/defaults is the source for the CC events/handlers
defaults.register_for_default_handlers(zwave_sensor_template, zwave_sensor_template.supported_capabilities)

local zwave_sensor = ZwaveDriver("zwave_retrofit", zwave_sensor_template)

zwave_sensor:run()
