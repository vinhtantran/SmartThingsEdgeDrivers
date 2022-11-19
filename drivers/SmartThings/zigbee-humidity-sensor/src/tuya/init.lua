local log = require "log"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = zcl_clusters.PowerConfiguration
local RelativeHumidity = zcl_clusters.RelativeHumidity
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local capabilities = require "st.capabilities"


local is_tuya_temperature_sensor = function(opts, driver, device)
  return device:get_manufacturer():find("_TZ2000") == 1 and device:get_model() == "TS0201"
end

local battery_percentage_remaining_handler = function(driver, device, value, zb_rx)
  log.debug("Handling Tuya battery percentage: " .. tostring(value.value))
  -- Tuya usualy reports 100% even if the battery is low, so skipping
end

function humidity_handler(driver, device, value, zb_rx)
  -- increase the precision (the default handler rounds the value)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.relativeHumidityMeasurement.humidity(value.value / 100.0))
end


local tuya_temperature_humdity_sensor = {
  NAME = "Tuya Temperature/Humidity Sensor",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0)
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percentage_remaining_handler,
        [PowerConfiguration.attributes.BatteryVoltage.ID] =  battery_defaults.battery_volt_attr_handler
      },
      [RelativeHumidity.ID] = {
        [RelativeHumidity.attributes.MeasuredValue.ID] = humidity_handler
      }
    }
  },
  can_handle = is_tuya_temperature_sensor
}

return tuya_temperature_humdity_sensor
