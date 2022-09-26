local capabilities = require "st.capabilities"
local motionSensor = require "st.zwave.defaults.motionSensor"
local cc = require "st.zwave.CommandClass"
local EntryControl = (require "st.zwave.CommandClass.EntryControl")({ version=1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version=8 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local Indicator = (require "st.zwave.CommandClass.Indicator")({ version=3 })
local log = require "log"


local ZWAVE_RING_GEN2_FINGERPRINTS = {
  {mfr = 0x0346, prod = 0x0101, model = 0x0401}
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
  log.debug("NotificationReportHandler")
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
  device:send(Indicator:Set({
    indicator_objects = {
      { indicator_id = Indicator.indicator_id.NOT_OK, property_id = Indicator.property_id.MULTILEVEL, value = 100 },
    }
  }))
end

local eventTypeToComponentName = {
  [EntryControl.event_type.DISARM_ALL] = "disarmAllButton",
  [EntryControl.event_type.ARM_HOME] = "armHomeButton",
  [EntryControl.event_type.ARM_AWAY] = "armAwayButton",
  [EntryControl.event_type.POLICE] = "policeButton",
  [EntryControl.event_type.FIRE] = "fireButton",
  [EntryControl.event_type.ALERT_MEDICAL] = "alertMedicalButton",
  [EntryControl.event_type.ALERT_PANIC] = "panicCombination",
}

local function entry_control_notification_handler(self, device, cmd)
  log.debug("Entry Control Notification handler")
  local args = cmd.args
  local event_type = args.event_type
  local event_data = args.event_data
  local componentName = eventTypeToComponentName[event_type]
  if componentName == nil then
    log.debug("Unhandled entry control event type: " .. event_type)
    return
  end
  local component = device.profile.components[componentName]
  if event_type == EntryControl.event_type.DISARM_ALL or event_type == EntryControl.event_type.ARM_HOME then
    local pin = device.preferences.pin
    if event_data ~= pin then
      incorrect_pin(device)
      return
    end
  end
  device:emit_component_event(component, capabilities.button.button.pushed({state_change = true}))
end

local function device_do_configure(self, device)
  device:refresh()
end

local function send_config(device, parameter_number, old_configuration_value, configuration_value, size)
  if old_configuration_value ~= configuration_value then
    device:send(Configuration:Set({
        parameter_number = parameter_number,
        configuration_value = configuration_value,
        size = size
    }))
  end
end

local function bool_to_number(value)
  return value and 1 or 0
end

local function update_preferences(self, device, args)
  local oldPrefs = args.old_st_store.preferences
  local newPrefs = device.preferences

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
  "policeButton",
  "fireButton",
  "alertMedicalButton",
  "panicCombination",
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
  device:set_update_preferences_fn(update_preferences)
end

local function arm_away_command(self, device)
  log.debug("ARM AWAY")
  device:emit_event(capabilities.securitySystem.securitySystemStatus.armedAway())
  device:send(Indicator:Set({
      indicator_objects = {
        {
          indicator_id = Indicator.indicator_id.ARMED_AWAY,
          property_id = Indicator.property_id.MULTILEVEL,
          value = 100
        },
      }
  }))
end

local function arm_stay_command(self, device)
  log.debug("ARM STAY")
  device:emit_event(capabilities.securitySystem.securitySystemStatus.armedStay())
  device:send(Indicator:Set({
      indicator_objects = {{
        indicator_id = Indicator.indicator_id.ARMED_STAY,
        property_id = Indicator.property_id.MULTILEVEL,
        value = 100
  }}}))
end

local function disarm_command(self, device)
  log.debug("DISARM")
  device:emit_event(capabilities.securitySystem.securitySystemStatus.disarmed())
  device:send(Indicator:Set({
      indicator_objects = {{
        indicator_id = Indicator.indicator_id.NOT_ARMED,
        property_id = Indicator.property_id.MULTILEVEL,
        value = 100
  }}}))
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

local function alarm_off(self, device, cmd)
  log.debug("ALARM_OFF")
  local componentName = cmd.component
  local alarm_data = componentToAlarmData[componentName]
  if alarm_data == nil then
    return
  end
  local indicator_id = alarm_data.indicator_id

  if alarm_data.keypad_blinking then
    for _, kp_component_name in pairs(keypad_blinking_components) do
      device:emit_component_event(device.profile.components[kp_component_name], capabilities.alarm.alarm.off())
    end
  else
    -- HACK: to disable the alarm we use the security mode without sound and LED. Is there a better solution?
    local securitySystemStatus = device:get_latest_state("main", capabilities.securitySystem.ID, "securitySystemStatus")
    indicator_id = securitySystemStatusToIndicator[securitySystemStatus]
    -- the hack above turns off all alarms
    for _, alarm_component_name in pairs(all_alarm_components) do
      device:emit_component_event(device.profile.components[alarm_component_name], capabilities.alarm.alarm.off())
    end
  end
  device:send(Indicator:Set({
    indicator_objects = {
      {
        indicator_id = indicator_id,
        property_id = Indicator.property_id.MULTILEVEL,
        value = 0  -- turn off the light
      },
      {
        indicator_id = indicator_id,
        property_id = Indicator.property_id.SPECIFIC_VOLUME,
        value = 0  -- turn off the sound
      },
    }
  }))
end

local function turn_off_other_alarms(device, alarm_data, component_name)
  if alarm_data.keypad_blinking then
    for _, kp_component_name in pairs(keypad_blinking_components) do
      if kp_component_name ~= component_name then
        device:emit_component_event(device.profile.components[kp_component_name], capabilities.alarm.alarm.off())
      end
    end
  else
    for _, alert_component_name in pairs(alert_components) do
      if alert_component_name ~= component_name then
        device:emit_component_event(device.profile.components[alert_component_name], capabilities.alarm.alarm.off())
      end
    end
  end
end

local function alarm_both(self, device, cmd)
  log.debug("ALARM_BOTH")
  local componentName = cmd.component
  local alarm_data = componentToAlarmData[componentName]
  if alarm_data == nil then
    return
  end
  local preferences = device.preferences
  local indicator_id = alarm_data.indicator_id
  local volume = 10 * (alarm_data.voice and preferences.announcementVolume or preferences.sirenVolume)

  device:send(Indicator:Set({
    indicator_objects = {
      {
        indicator_id = indicator_id,
        property_id = Indicator.property_id.SPECIFIC_VOLUME,
        value = volume,
      }
    }
  }))

  turn_off_other_alarms(device, alarm_data, componentName)
  device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.both())
end

local function alarm_siren(self, device, cmd)
  log.debug("ALARM_SIREN")
  local componentName = cmd.component
  local alarm_data = componentToAlarmData[componentName]
  if alarm_data == nil then
    return
  end
  if not alarm_data.keypad_blinking then
    -- fallback for alarms that does not support turning off the light
    alarm_both(self, device, cmd)
    return
  end
  local indicator_id = alarm_data.indicator_id
  device:send(Indicator:Set({
    indicator_objects = {
      {
        indicator_id = indicator_id,
        property_id = Indicator.property_id.MULTILEVEL,
        value = 0
      },
    }
  }))

  turn_off_other_alarms(device, alarm_data, componentName)
  device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.siren())
end

local function alarm_strobe(self, device, cmd)
  log.debug("ALARM_STROBE")
  local componentName = cmd.component
  local alarm_data = componentToAlarmData[componentName]
  if alarm_data == nil then
    return
  end
  local indicator_id = alarm_data.indicator_id

  device:send(Indicator:Set({
        indicator_objects = {
          {
            indicator_id = indicator_id,
            property_id = Indicator.property_id.SPECIFIC_VOLUME,
            value = 0
          }
  }}))

  turn_off_other_alarms(device, alarm_data, componentName)
  device:emit_component_event(device.profile.components[componentName], capabilities.alarm.alarm.strobe())
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
  },
  capability_handlers = {
    [capabilities.securitySystem.ID] = {
      [capabilities.securitySystem.commands.armAway.NAME] = arm_away_command,
      [capabilities.securitySystem.commands.armStay.NAME] = arm_stay_command,
      [capabilities.securitySystem.commands.disarm.NAME] = disarm_command,
    },
    [capabilities.tone.ID] = {
      [capabilities.tone.commands.beep.NAME] = tone_handler,
    },
    [capabilities.chime.ID] = {
      [capabilities.chime.commands.chime.NAME] = chime_on,
      [capabilities.chime.commands.off.NAME] = chime_off,
    },
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.off.NAME] = alarm_off,
      [capabilities.alarm.commands.both.NAME] = alarm_both,
      [capabilities.alarm.commands.siren.NAME] = alarm_siren,
      [capabilities.alarm.commands.strobe.NAME] = alarm_strobe,
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
