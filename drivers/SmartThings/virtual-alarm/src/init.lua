local Driver = require "st.driver"
local log = require "log"
local capabilities = require "st.capabilities"

local IS_INITIALIZED = "is_initialized"

local function discovery_handler(self, opts)
  log.debug("HANDLE_DISCOVERY")
  if not self.datastore[IS_INITIALIZED] then
    local device_data = {
      type = "LAN",
      device_network_id = "virtual-alarm-creator",
      label = "Virtual Alarm Creator",
      profile = "device-creator",
      manufacturer = "Virtual Manufacturer",
      model = "Virtual Model",
      vendor_provided_label = "Virtual Alarm Creator"
    }

    self:try_create_device(device_data)
  end
end

local function device_added(self, device)
  log.debug("DEVICE_ADDED")
  device:online()
  self.datastore[IS_INITIALIZED] = true
end

local function device_init(self, device)
  log.debug("DEVICE_INIT")
  if device:supports_capability(capabilities.alarm) then
    log.debug("Initializing child")
    device:emit_event(capabilities.alarm.alarm.off())
  end
end

local function device_removed(self, device)
  log.debug("DEVICE_REMOVED")
  if device:supports_capability(capabilities.momentary) then
    log.debug("Parent device removed")
    self.datastore[IS_INITIALIZED] = false
  end
end

local function create_child(self, device, cmd)
  log.debug('CREATE_CHILD')
  local device_data = {
      type = "LAN",
      device_network_id = 'virtual-alarm-' .. math.random(1, 4294967295),
      label = "Virtual Alarm",
      profile = 'virtual-alarm',
      manufacturer = 'Virtual Manufacturer',
      model = 'Virtual Model',
      vendor_provided_label = "Virtual Alarm"
  }

  self:try_create_device(device_data)
end

local function alarm_off(self, device, cmd)
  log.debug("ALARM_OFF")
  device:emit_component_event(device.profile.components.main, capabilities.alarm.alarm.off())
end

local function alarm_siren(self, device, cmd)
  log.debug("ALARM_SIREN")
  device:emit_component_event(device.profile.components.main, capabilities.alarm.alarm.siren())
end

local function alarm_strobe(self, device, cmd)
  log.debug("ALARM_STROBE")
  device:emit_component_event(device.profile.components.main, capabilities.alarm.alarm.strobe())
end

local function alarm_both(self, device, cmd)
  log.debug("ALARM_BOTH")
  device:emit_component_event(device.profile.components.main, capabilities.alarm.alarm.both())
end

local driver = Driver("Virtual Alarm", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    removed = device_removed,
  },
  capability_handlers = {
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.off.NAME] = alarm_off,
      [capabilities.alarm.commands.siren.NAME] = alarm_siren,
      [capabilities.alarm.commands.strobe.NAME] = alarm_strobe,
      [capabilities.alarm.commands.both.NAME] = alarm_both,
    },
    [capabilities.momentary.ID] = {
      [capabilities.momentary.commands.push.NAME] = create_child,
    }
  }
})

driver:run()
