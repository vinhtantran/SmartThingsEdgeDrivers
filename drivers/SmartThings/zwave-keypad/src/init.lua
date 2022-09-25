local capabilities = require "st.capabilities"
local defaults = require "st.zwave.defaults"
local ZwaveDriver = require "st.zwave.driver"

local zwave_keypad_template = {
  supported_capabilities = {
    capabilities.refresh,
    capabilities.motionSensor,
    capabilities.powerSource,
    capabilities.battery,
  },
  sub_drivers = {
--    require("ring-gen2")
  },
}

defaults.register_for_default_handlers(zwave_keypad_template, zwave_keypad_template.supported_capabilities)

local zwave_keypad = ZwaveDriver("zwave_keypad", zwave_keypad_template)

zwave_keypad:run()
