-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- ========================================================================================================================= --
-- For information on how to implement and distribute your custom UDP protocol, please check https://go.beamng.com/protocols --
-- ========================================================================================================================= --

-- generic outgauge implementation based on LiveForSpeed
local M = {}

local hasShiftLights = false
local function init()
  local shiftLightControllers = controller.getControllersByType("shiftLights")
  hasShiftLights = shiftLightControllers and #shiftLightControllers > 0
end

local function reset() end
local function getAddress()        return settings.getValue("protocols_outgauge_address") end        -- return "127.0.0.1"
local function getPort()           return 4568 end           -- return 4567
local function getMaxUpdateRate()  return settings.getValue("protocols_outgauge_maxUpdateRate") end  -- return 60

local function isPhysicsStepUsed()
  return false -- use graphics step. performance cost is ok. the update rate could reach UP TO min(getMaxUpdateRate(), graphicsFramerate)
  --return true-- use physics step. performance cost is big. the update rate could reach UP TO min(getMaxUpdateRate(), 2000 Hz)
end

local function getStructDefinition()
  -- the original protocol documentation can be found at LFS/docs/InSim.txt
  return [[
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////// IMPORTANT: if you modify this definition, also update the docs at https://go.beamng.com/protocols /////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    unsigned       time;            // time in milliseconds (to check order) // N/A, hardcoded to 0
    char           car[4];          // Car name // N/A, fixed value of "beam"
    unsigned short flags;           // Info (see OG_x below)
    char           gear;            // Reverse:0, Neutral:1, First:2...
    char           plid;            // Unique ID of viewed player (0 = none) // N/A, hardcoded to 0
    float          speed;           // M/S
    float          rpm;             // RPM
    float          turbo;           // BAR
    float          engTemp;         // C
    float          fuel;            // 0 to 1
    float          oilPressure;     // BAR // N/A, hardcoded to 0
    float          oilTemp;         // C
    unsigned       dashLights;      // Dash lights available (see DL_x below)
    unsigned       showLights;      // Dash lights currently switched on
    float          throttle;        // 0 to 1
    float          brake;           // 0 to 1
    float          clutch;          // 0 to 1
    char           display1[16];    // Usually Fuel // N/A, hardcoded to ""
    char           display2[16];    // Usually Settings // N/A, hardcoded to ""
    int            id;              // optional - only if OutGauge ID is specified
    char           gearExt;         // M = semi-automatic, S = sport mode, P = park, A = automatic, C = common
    float          cruiseSpeed;     // M/S
    unsigned       cruiseMode;      // Inactive:0, Active:1
    float          fuelCapacity;    // L
  ]]
end

--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////// IMPORTANT: if you modify this definition, also update the docs at https://go.beamng.com/protocols /////////
--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- OG_x - bits for flags
local OG_SHIFT =     1  -- key // N/A
local OG_CTRL  =     2  -- key // N/A
local OG_TURBO =  8192  -- show turbo gauge
local OG_KM    = 16384  -- if not set - user prefers MILES
local OG_BAR   = 32768  -- if not set - user prefers PSI

--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////// IMPORTANT: if you modify this definition, also update the docs at https://go.beamng.com/protocols /////////
--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- DL_x - bits for dashLights and showLights
local DL_SHIFT        = 2 ^ 0    -- shift light
local DL_FULLBEAM     = 2 ^ 1    -- full beam
local DL_HANDBRAKE    = 2 ^ 2    -- handbrake
local DL_PITSPEED     = 2 ^ 3    -- pit speed limiter // N/A
local DL_TC           = 2 ^ 4    -- tc active or switched off
local DL_SIGNAL_L     = 2 ^ 5    -- left turn signal
local DL_SIGNAL_R     = 2 ^ 6    -- right turn signal
local DL_SIGNAL_ANY   = 2 ^ 7    -- shared turn signal // N/A
local DL_OILWARN      = 2 ^ 8    -- oil pressure warning
local DL_BATTERY      = 2 ^ 9    -- battery warning
local DL_ABS          = 2 ^ 10   -- abs active or switched off
local DL_SPARE        = 2 ^ 11   -- N/A
local DL_LOWBEAM      = 2 ^ 12   -- low beam
local DL_ESC          = 2 ^ 13   -- esc active or switched off
local DL_CHECKENGINE  = 2 ^ 14   -- check engine
local DL_CLUTCHTEMP   = 2 ^ 15   -- clutch temp
local DL_FOGLIGHTS    = 2 ^ 16   -- fog lights
local DL_BRAKETEMP    = 2 ^ 17   -- brake temp
local DL_TIREFLAT_FL  = 2 ^ 18   -- front left tire deflated
local DL_TIREFLAT_FR  = 2 ^ 19   -- front right tire deflated
local DL_TIREFLAT_RL  = 2 ^ 20   -- rear left tire deflated
local DL_TIREFLAT_RR  = 2 ^ 21   -- rear right tire deflated
local DL_RADIATOR     = 2 ^ 22   -- radiator warning

local function fillStruct(o, dtSim)
  if not electrics.values.watertemp then
    -- vehicle not completly initialized, skip sending package
    return
  end

  o.time = 0 -- not used atm
  o.car = "beam"
  o.flags = OG_KM + OG_BAR + (electrics.values.turboBoost and OG_TURBO or 0)
  o.gear = electrics.values.gearIndex + 1 -- reverse = 0 here
  o.plid = 0
  o.speed = electrics.values.wheelspeed or electrics.values.airspeed
  o.rpm = electrics.values.rpm or 0
  o.turbo = (electrics.values.turboBoost or 0) / 14.504
  o.engTemp = electrics.values.watertemp or 0
  o.fuel = electrics.values.fuel or 0
  o.oilPressure = 0 -- TODO
  o.oilTemp = electrics.values.oiltemp or 0

  -- the lights
  o.dashLights = bit.bor(o.dashLights, DL_FULLBEAM ) if electrics.values.highbeam      ~= 0 then o.showLights = bit.bor(o.showLights, DL_FULLBEAM ) end
  o.dashLights = bit.bor(o.dashLights, DL_HANDBRAKE) if electrics.values.parkingbrake  ~= 0 then o.showLights = bit.bor(o.showLights, DL_HANDBRAKE) end
  o.dashLights = bit.bor(o.dashLights, DL_SIGNAL_L ) if electrics.values.signal_left_input  ~= 0 then o.showLights = bit.bor(o.showLights, DL_SIGNAL_L ) end
  o.dashLights = bit.bor(o.dashLights, DL_SIGNAL_R ) if electrics.values.signal_right_input ~= 0 then o.showLights = bit.bor(o.showLights, DL_SIGNAL_R ) end
  if electrics.values.hasABS then
    o.dashLights = bit.bor(o.dashLights, DL_ABS    ) if electrics.values.absActive     ~= 0 then o.showLights = bit.bor(o.showLights, DL_ABS      ) end
  end
  o.dashLights = bit.bor(o.dashLights, DL_OILWARN  ) if electrics.values.oil           ~= 0 then o.showLights = bit.bor(o.showLights, DL_OILWARN  ) end
  o.dashLights = bit.bor(o.dashLights, DL_BATTERY  ) if electrics.values.engineRunning == 0 then o.showLights = bit.bor(o.showLights, DL_BATTERY  ) end

  if electrics.values.hasTCS then
    o.dashLights = bit.bor(o.dashLights, DL_TC ) if electrics.values.tcs ~= 0 then o.showLights = bit.bor(o.showLights, DL_TC ) end
  end

  if hasShiftLights then
    o.dashLights = bit.bor(o.dashLights, DL_SHIFT  ) if electrics.values.shouldShift        then o.showLights = bit.bor(o.showLights, DL_SHIFT    ) end
  end
  o.dashLights = bit.bor(o.dashLights, DL_LOWBEAM ) if electrics.values.lowbeam        ~= 0 then o.showLights = bit.bor(o.showLights, DL_LOWBEAM  ) end

  if electrics.values.hasESC then
    o.dashLights = bit.bor(o.dashLights, DL_ESC ) if electrics.values.esc ~= 0 then o.showLights = bit.bor(o.showLights, DL_ESC ) end
  end

  o.dashLights = bit.bor(o.dashLights, DL_CHECKENGINE ) if electrics.values.checkengine == true then o.showLights = bit.bor(o.showLights, DL_CHECKENGINE ) end
  o.dashLights = bit.bor(o.dashLights, DL_FOGLIGHTS ) if electrics.values.fog ~= 0 then o.showLights = bit.bor(o.showLights, DL_FOGLIGHTS ) end

  if powertrain then
    local clutch = powertrain.getDevice("clutch")
    if clutch and clutch.clutchTemperature and clutch.clutchWarningTemp then
      o.dashLights = bit.bor(o.dashLights, DL_CLUTCHTEMP)
      if clutch.clutchTemperature >= clutch.clutchWarningTemp then
        o.showLights = bit.bor(o.showLights, DL_CLUTCHTEMP)
      end
    end
  end

  o.throttle = electrics.values.throttle
  o.brake = electrics.values.brake
  o.clutch = electrics.values.clutch
  o.display1 = "" -- TODO
  o.display2 = "" -- TODO
  o.id = 0 -- TODO

  local gearString = electrics.values.gear or ""
  local firstChar = string.sub(gearString, 1, 1)

  if firstChar == "M" then
    o.gearExt = string.byte("M") -- Semi automatic "Mn" mode
  elseif firstChar == "P" then
    o.gearExt = string.byte("P") -- Parking gear
  elseif firstChar == "S" then
    o.gearExt = string.byte("S") -- Automatic "Sn" sport mode
  elseif tonumber(firstChar) ~= nil then
    o.gearExt = string.byte("N") -- None
  else
    o.gearExt = string.byte("A") -- Automatic
  end

  o.cruiseSpeed = electrics.values.cruiseControlTarget or 0
  o.cruiseMode = electrics.values.cruiseControlActive == nil and 0
    or electrics.values.cruiseControlActive == 0 and 0
    or 1

  o.fuelCapacity = electrics.values.fuelCapacity

  local brakeOverheat = false
  local wheelNames = {}
  local tireFlatBits = {
    FL = DL_TIREFLAT_FL,
    FR = DL_TIREFLAT_FR,
    RL = DL_TIREFLAT_RL,
    RR = DL_TIREFLAT_RR
  }

  for i, wheel in pairs(wheels.wheels) do
    if wheel and wheel.name then
      table.insert(wheelNames, wheel.name)

      local bitFlag = tireFlatBits[wheel.name]
      if bitFlag then
        o.dashLights = bit.bor(o.dashLights, bitFlag)
        if wheel.isTireDeflated then
          o.showLights = bit.bor(o.showLights, bitFlag)
        end
      end
    end
  end

  for _, name in ipairs(wheelNames) do
    local damage = damageTracker.getDamage("wheels", "brakeOverHeat" .. name)
    if (type(damage) == "number" and damage > 0) or (type(damage) == "boolean" and damage) then
      brakeOverheat = true
      break
    end
  end

  o.dashLights = bit.bor(o.dashLights, DL_BRAKETEMP ) if brakeOverheat == true then o.showLights = bit.bor(o.showLights, DL_BRAKETEMP ) end

  o.dashLights = bit.bor(o.dashLights, DL_RADIATOR)
  if (damageTracker.getDamage("engine", "radiatorLeak") == true) then
    o.showLights = bit.bor(o.showLights, DL_RADIATOR)
  end
end

M.init = init
M.reset = reset
M.getAddress = getAddress
M.getPort = getPort
M.getMaxUpdateRate = getMaxUpdateRate
M.getStructDefinition = getStructDefinition
M.fillStruct = fillStruct
M.isPhysicsStepUsed = isPhysicsStepUsed

return M
