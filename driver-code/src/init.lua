-- LEVITON VRCS2-MRZ EDGE DRIVER FOR SMARTTHINGS
-- 
-- Copyright 2025, Shane de Silva
-- Acknowledgements:
--  Based on Driver made by Henry Robinson and contributions by Brian Dahlem's Groovy Driver, Copyright 2014
--  Jeff Brown (j9brown) for decoding Leviton LED commands
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Implementation notes:
--   This driver turns the VRCS2 Controller into 2 switches ... note that state is SOLELY maintained in the SmartThings driver (switch state is not queried)
--   While the original Leviton design allows the user to select from 2 scenes, this driver handles each button independently
--   Functions used:
--       a) Scene Activation signals that a button has been pressed
--       b) Manufacturer-specific commands control the LED settings (turns scenes on/off)
--
-- Device settings tracked:
--   lastScene:           button # for last scene that was activated, used to handle debounce logic
--   lastTime:            OS time when the last button was pressed.  Prevents any action within 2 seconds of button activation
--   switchConfigured:    flag to avoid continuous configuration of associations (if true, then device was configured)

local capabilities = require "st.capabilities"
local ZwaveDriver = require "st.zwave.driver"
local utils = require "st.utils"
local defaults = require "st.zwave.defaults"
local log = require "log"
local throttle_send = require "throttle_send"

--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2})
local Association = (require "st.zwave.CommandClass.Association") ({version = 2})
local SceneControllerConf= (require "st.zwave.CommandClass.SceneControllerConf")({ version = 1})
local SceneActuatorConf= (require "st.zwave.CommandClass.SceneActuatorConf")({ version = 1})
local SceneActivation= (require "st.zwave.CommandClass.SceneActivation")({ version = 1})
local Configuration = (require "st.zwave.CommandClass.Configuration") ({version = 1})
local ManufacturerProprietary = (require "st.zwave.CommandClass.ManufacturerProprietary")({ version = 1})
local ManufacturerSpecific = (require "st.zwave.CommandClass.ManufacturerSpecific")({ version = 1})
local Version = (require "st.zwave.CommandClass.Version")({ version = 2})
local zw = require "st.zwave"

local switchNames = {"main", "switch2"}

local ZWAVE_LEVITON_VRCS2_FINGERPRINTS = {
  {mfr = 0x001D, prod = 0x1102, model = 0x0243} -- Leviton VRCS2-MRZ
}

local function can_handle_LEVITON_VRCS2_MRZ(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_LEVITON_VRCS2_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

-- helper functions 

-- pace the commands to the device
local function queue_command (device, cmd)
  local cmds = {}
  table.insert (cmds, { msg = cmd })
  throttle_send (device, cmds)
end

-- determine which devices should receive commands based in Sync Option
local function build_device_list (driver, device, includeDevice)
  local deviceList = {}
  if (includeDevice) then deviceList = {device} end
  if (not device.preferences.sync) then
    return deviceList 
  end
  local devices = driver:get_devices()
  for index = 1,#devices do
    if (devices[index].preferences.sync) and (devices[index] ~= device) then
      table.insert (deviceList, devices[index])
    end
  end
  return deviceList
end

-- update the LED bit
-- 1) Retrieve the latest state for each switch and build the bitmap
-- 2) The bitmap is the last byte of the command (green is the last 4 bits)
-- 3) If we have sync enabled and multiple devices, update the LEDs for each device
-- 4) Setting the LED will enable/disable scene for each switch (controlled by lit LED)
-- Indicator Lights -->
-- Use these messages to override the indicator lights.
--   91 00 1D 0D 01 00 00 : Reset LEDs to locally controlled operation (default behavior).
--   91 00 1D 0D 01 FF xx : Set LEDs by OR-ing together the following bit patterns.
--       00000000: button 1 off
--       00000001: button 1 green
--       00000000: button 2 off
--       00000010: button 2 green

local function update_LEDs (driver, device) 
  local bitmap = 0
  for i = 2,1,-1 do
    bitmap = bitmap << 1
    local state = device:get_latest_state (switchNames[i], "switch", "switch")
    bitmap = (state == "off") and bitmap or (bitmap | 1)
  end
-- LEDs get set, but get an unsupported command response from device
  local cmdString = string.format("\x1D\x0D\x01\xFF%c", bitmap)
  local devices = build_device_list (driver, device, true)
  for index = 1,#devices do
    devices[index]:send(zw.Command(0x91, 0x00, cmdString))
  end
end

-- Event handlers -- many are not received but kept here just in case we see them

local function basic_set_handler(self, device, cmd)
  log.debug("------ Unexpected Received basic set handler")
end


local function basic_report_handler(self, device, cmd)
  log.debug("------ Unexpected Received basic report handler")
end

local function switch_binary_report_handler(self, device, cmd)
  local switchState = cmd.args.value == SwitchBinary.value.ON_ENABLE and "on" or "off"
  device:emit_component_event(device.profile.components[switchNames[cmd.src_channel + 1]], capabilities.switch.switch[switchState]())
end

local function association_report_handler(self, device, cmd)
  log.debug("------ Unexpected received association report")
end

local function association_groupings_report_handler(self, device, cmd)
  log.debug("------Unexpected received association groupings report")
end

local function scene_actuator_conf_get_handler(self, device, cmd)
  log.debug("------ Unexpected received Scene_Actuator_Conf_Get")
end

local function scene_actuator_conf_report_handler(self, device, cmd)
  log.debug("------ Unexpected received Scene_Actuator_Conf_Report")
end

local function configuration_report_handler(self, device, cmd)
  log.debug("------ Unexpected received Configuration_Report")
end

local function proprietary_handler(self, device, cmd)
  log.debug("------ Received mfg proprietary")
end

local function confReport_handler(self, device, cmd)
  log.debug("------ Unexpected Received conf report")
end

local function scene_controller_handler(self, device, cmd)
  log.debug("------ Unexpected Controller Configuration Report")
end

-- Z-WAVE Commands handled
-- 1) Scene Activation: Button was pressed to turn on/off

local function scene_activation_handler(self, device, cmd)
  log.trace("------ Received Scene_Activation")
  local devices = build_device_list (self, device, true)
  local button = cmd.args.scene_id
  button = (button > 2) and (button - 2) or button
  -- Allow for debounce, may get multiple messages for same press
  -- Ignore if same scene within 2 seconds
  if ((button == device:get_field("lastScene")) and (os.difftime(os.time(), device:get_field("lastTime"))<2)) then
    log.trace("Repeated press, no action taken")
  else
    -- Update history to new setting
    device:set_field("lastScene", button)
    device:set_field("lastTime", os.time())
    local switchState = device:get_latest_state (switchNames[button], "main", "switch2")
    -- toggle the switch
    local action = ((switchState == "on") and capabilities.switch.switch.off) or capabilities.switch.switch.on
    -- apply the new state to all devices
    for index = 1,#devices do
      devices[index]:emit_component_event(device.profile.components[switchNames[button]], action())
    end
    update_LEDs (self, device)
  end
end

-- UI or APP Commands
-- ON: Set switch state to ON
-- OFF: Set switch state to OFF
--
-- For each command, determine which switches should get updated
-- Updates are to the SmartThings state only
--

local function capability_handle_on(driver, device, command)
  log.trace ("UI/APP sent an on command for switch ", device.label, command.component)
  local oldState = device:get_latest_state (command.component, "switch", "switch")
  -- ignore if state is already on
  if (oldState ~= "on") then
    log.trace ("Turning switch on")
    local devices = build_device_list (driver, device, true)
    for index = 1,#devices do
      devices[index]:emit_component_event(device.profile.components[command.component], capabilities.switch.switch.on())
      devices[index]:send(SwitchBinary:Set({
        target_value = SwitchBinary.value.ON_ENABLE,
        duration = 0
      }))
    end
    update_LEDs (driver, device)
  else
    log.trace ("Switch was already on.  Command skipped.")
  end
end

local function capability_handle_off(driver, device, command)
  log.debug ("UI/APP sent an off command for switch ", device.label, command.component)
  local oldState = device:get_latest_state (command.component, "switch", "switch")
  -- ignore if state is already off
  if (oldState ~= "off") then
    log.debug ("Turning switch off")
    local devices = build_device_list (driver, device, true)
    for index = 1,#devices do
      devices[index]:emit_component_event(device.profile.components[command.component], capabilities.switch.switch.off())
      devices[index]:send(SwitchBinary:Set({
        target_value = SwitchBinary.value.OFF_DISABLE,
        duration = 0
      }))
    end
    update_LEDs (driver, device)
  else
    log.trace ("Switch was already off.  Command skipped.")
  end
end

local function version_handler (driver, device, cmd)
  log.debug("Received version report")
end
-- Associate the hub so that messages can be collected

local function set_associations (self, device)
  if (device:get_field("switchConfigured") == nil) then
    log.trace ("Updating associations for switch.")
    local hub = device.driver.environment_info.hub_zwave_id or 1
    for button = 1,2 do
      queue_command (device, Association:Remove({grouping_identifier = button, node_ids = {}}))
      queue_command (device, Association:Remove({grouping_identifier = button+2, node_ids = {}}))
      queue_command (device, Association:Set({grouping_identifier = button, node_ids = {hub}}))
      queue_command (device, Association:Set({grouping_identifier = button+2, node_ids = {hub}})) 
      queue_command (device, SceneControllerConf:Set({group_id = button, scene_id = button}))
      queue_command (device, SceneControllerConf:Set({group_id = button+2, scene_id = button+2}))
    end
    device:set_field("switchConfigured", true)
  end
end

local function sync_switches (self, device)
  local devices = build_device_list (self, device, false)
  if (#devices ~= 0) then
    log.trace ("Syncing switch with ", devices[1].label, ", id:", devices[1].id)
    for button = 1, 2 do
      local switchState = devices[1]:get_latest_state (switchNames[button], "switch", "switch")
      local action = ((switchState == "on") and capabilities.switch.switch.on) or capabilities.switch.switch.off
      device:emit_component_event(device.profile.components[switchNames[button]], action())
      device:emit_component_event(device.profile.components[switchNames[button]], capabilities.switchLevel.level(devices[1]:get_latest_state (switchNames[button], "switchLevel", "level")))
    end
  else
    for button = 1, 2 do
      log.trace ("Initializing switch to base value (off and on")
      device:emit_component_event(device.profile.components[switchNames[button]], capabilities.switch.switch.off())
      device:emit_component_event(device.profile.components[switchNames[button]], capabilities.switchLevel.on())
    end
  end
end


local function device_added (driver, device)
  log.trace ("*** New device was added, device: ", device.label, ", id:", device.id)
  sync_switches(driver, device)
end

local function device_info_changed (driver, device, event, args)
  log.trace("*** Device info was changed for device:", device.label, ", id:", device.id)
  queue_command (device, Version:Get ({}))
-- check if Settings were changed.
  if (args.old_st_store.preferences.sync ~= device.preferences.sync) then
    if (device.preferences.sync) then
      sync_switches (driver, device)
    end
  end
end

local init_driver_handler = function(self, device)
  log.trace ("Driver was init'd for device:", device.id)
  queue_command (device, ManufacturerSpecific:Get ({}))
  set_associations (self, device)

  for button = 1, 2 do
    device:emit_component_event(device.profile.components[switchNames[button]], capabilities.switch.switch.off())
    device:emit_component_event(device.profile.components[switchNames[button]], capabilities.switchLevel.on())
  end
  update_LEDs (self, device)
  device:set_field("lastScene", nil)
  device:set_field("lastTime", os.time())
end

local driver_template = {
  NAME = "Leviton VRCS2",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler,
      [Basic.REPORT] = basic_report_handler
      },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_binary_report_handler
    },
    [cc.ASSOCIATION] = {
    --  [Association.Groupings_REPORT] = association_handler
      [0x06] = association_groupings_report_handler,
      [Association.REPORT] = association_report_handler
    },
    [cc.SCENE_CONTROLLER_CONF] = {
      [SceneControllerConf.REPORT] = scene_controller_handler,
      [SceneControllerConf.GET] = scene_controller_handler
    }, 
    [cc.SCENE_ACTUATOR_CONF] = {
      [SceneActuatorConf.GET] = scene_actuator_conf_get_handler,
      [SceneActuatorConf.REPORT] = scene_actuator_conf_report_handler
    },
    [cc.SCENE_ACTIVATION] = {
      [SceneActivation.SET] = scene_activation_handler
    },
  [cc.MANUFACTURER_PROPRIETARY] = {
    [0x00] = proprietary_handler
    },
  [cc.MANUFACTURER_SPECIFIC] = {
  --     -- GET
    [0x04] = proprietary_handler,
  --     -- REPORT
    [0x05] = proprietary_handler
    },
  [cc.VERSION] = {
    [Version.REPORT] = version_handler
    }
  },
    supported_capabilities = {
    capabilities.switch,
    capabilities.refresh
    },
    capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = capability_handle_on,
      [capabilities.switch.commands.off.NAME] = capability_handle_off,
      },
    },
    lifecycle_handlers = {
    init = init_driver_handler,
    added = device_added,
    infoChanged = device_info_changed

  },
  can_handle = can_handle_LEVITON_VRCS2_MRZ,

}

--[[
  The default handlers take care of the Command Classes and the translation to capability events 
  for most devices, but you can still define custom handlers to override them.
]]--

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local buttonSwitch = ZwaveDriver("Z-Wave Leviton 2-Button Scene Controller", driver_template)
buttonSwitch:run()
