-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- WeatherLog Script for DCS World
-- Version 1.0
-- By funkyfranky (2018)
-- 
-- Features:
-- ---------
-- * Weather data at all airbases (including FARPs and ships) of the current map.
-- * Logging of temperature, QFE pressure, wind direction and strength, wind strength classification according to Beaufort scale.
-- * Output in JSON format for further posprocessing.
-- * Use of pure DCS API functions, i.e. no MIST, MOOSE or other framework required to be loaded additionally.
-- * Works with static and dynamic weather.
-- * Works with all current and future maps (Caucasus, NTTR, Normandy, PG, ...)
-- 
-- Prerequisite:
-- ------------
-- * IMPORTANT: The Script needs to write a file to the hard drive. So comment out the line
--   sanitizeModule('io')
--   Inn your "MissionScripting.lua" file located in your DCS installation directory, subdirectory "\scripts\".
-- * Recent version of DCS. Any version >1.5.X should work.
-- 
-- Load the script:
-- ----------------
-- 1.) Download the script and save it anywhere on your hard drive.
-- 2.) Open your mission in the mission editor.
-- 3.) At a new trigger:
--     * TYPE   "4 MISSION START"
--     * ACTION "DO SCRIPT FILE"
--     * OPEN --> Browse to the location where you saved the script and click OK.
-- 4.) Save the mission and start it.
-- 5.) Have fun :)

-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Weathermark Table.
weatherlog={}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- User settings. Choose main key phrase and default unit system.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Output file name. Can be found in your DCS installtion root directory.
weatherlog.FileName="WeatherLog.json"

--- Time interval in seconds when weather data is updated. 
weatherlog.ReportInterval=30

--- Enable/disable debug mode: Write full weather data to dcs.log file.
weatherlog.DebugMode=false

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Script part: Do not change anything below unless you know what you are doing.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- If true, the output file is created and data is appended over the whole mission.
--- If false, only the last data is stored and overwritten with new data.
--- NOTE: Strangely, reopening the file in write mode "a" causes a the script to crash (nothing in the dcs.log however).
---       So leave this to false for now! 
weatherlog.AppendData=false

--- Version
weatherlog.Version="1.0"
weatherlog.id="WeatherLog: "

--- Version info.
env.info(weatherlog.id..string.format("Loading version v%s", weatherlog.Version))
env.info(weatherlog.id..string.format("Output file     = %s", weatherlog.FileName))
env.info(weatherlog.id..string.format("Append data     = %s", tostring(weatherlog.AppendData)))
env.info(weatherlog.id..string.format("Report Interval = %d seconds", weatherlog.ReportInterval))

--- Init file open as false!
weatherlog.fileopen=false

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Report function: Writes data to file
------------------------------------------------------------------------------------------------------------------------------------------------------------- 

function weatherlog._WeatherReport()
  
  -- Coalitions.
  local coalitions={0,1,2}
  
  -- Data table.
  local weatherdata={}
  
  -- Loop over all coalitions.
  for _,Coalition in pairs(coalitions) do
  
    -- Get all airbases of this coalition.
    local airbases=coalition.getAirbases(Coalition)
    
    -- Loop over airbases.
    for _,airbase in pairs(airbases) do
    
      -- Get position of airbase.
      local vec3=airbase:getPoint()
      
      -- Get name of airbase.
      local airbasename=airbase:getName()
      
      -- Get atmospheric data at airbase.
      local T,QFE,QNH,Wdir,Wvel=weatherlog._WeatherData(vec3)
      
      -- Get wind classification according to Beauford scale.
      local WindBFS, WindBFC=weatherlog._BeaufortScale(Wvel)
      
      -- Add data to table.
      table.insert(weatherdata, {Airbase=airbasename, Coalition=Coalition, Temperature=T, QFE=QFE, QNH=QNH, WindDirection=Wdir, WindVelocity=Wvel, WindBeaufortScale=WindBFS, WindBeaufortClass=WindBFC})
          
    end
  end
  
  -- Write data for file.
  weatherlog._WriteData(weatherdata)
  
  -- Call function again...
  return timer.getTime() + weatherlog.ReportInterval
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Write data to file
------------------------------------------------------------------------------------------------------------------------------------------------------------- 

function weatherlog._WriteData(weatherdata)
  
  -- Get current time in seconds.
  local Time=timer.getAbsTime()

  -- Clock HH:MM:SS+D
  local Clock=weatherlog._SecondsToClock(Time)
  
  -- Gather available data.
  local text=string.format("{\n")
  text=text..string.format(' "Time": %d,\n', Time)
  text=text..string.format(' "Clock": "%s",\n', Clock)
  for _,weather in pairs(weatherdata) do
    text=text..string.format(' "Airbase": "%s",\n', weather.Airbase)
    text=text..string.format(" {\n")
    text=text..string.format(' \t"Coalition": %d,\n', weather.Coalition)
    text=text..string.format(' \t"Temperature": %.3f,\n', weather.Temperature)
    text=text..string.format(' \t"QFE": %.3f,\n', weather.QFE)
    text=text..string.format(' \t"QNH": %.3f,\n', weather.QNH)
    text=text..string.format(' \t"WindDirection": %.3f,\n', weather.WindDirection)
    text=text..string.format(' \t"WindVelocity": %.3f,\n', weather.WindVelocity)
    text=text..string.format(' \t"WindBeaufordScale": %d,\n', weather.WindBeaufortScale)
    text=text..string.format(' \t"WindBeaufordClass": "%s",\n', weather.WindBeaufortClass)
    text=text..(" }\n")
  end
  text=text..string.format("}\n\n")
  
  -- Debug output to DCS log file.
  if weatherlog.DebugMode then
    env.info(weatherlog.id.."\n"..text)
  end
  
  -- Set write mode.
  local WriteMode="w"
  if weatherlog.AppendData and weatherlog.fileopen then
    WriteMode="a"
  end
  
  -- Open file.
  local File = io.open(weatherlog.FileName, WriteMode)
  
  -- Write data.
  File:write(text)
    
  -- Close file
  File:close()
  
  -- Info to dcs.log file
  env.info(weatherlog.id..string.format("Updated weather data at mission time %s", Clock))
  --env.info(weatherlog.id..string.format("write mode = %s", WriteMode))
  
  -- File was opened once.
  weatherlog.fileopen=true
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Gather weather data.
------------------------------------------------------------------------------------------------------------------------------------------------------------- 

--- Weather Report. Report pressure QFE/QNH, temperature, wind at certain location.
function weatherlog._WeatherData(vec3)
  
  -- Get Temperature [K] and Pressure [Pa] at vec3.
  local T,Pqfe=atmosphere.getTemperatureAndPressure({x=vec3.x, y=vec3.y+1, z=vec3.z})
  
  -- Get pressure at sea level.
  local _,Pqnh=atmosphere.getTemperatureAndPressure({x=vec3.x, y=0, z=vec3.z})
  
  -- Temperature unit conversion: Kelvin to Celsius
  T=T-273.15
  
  -- Convert pressure from Pascal to hecto Pascal.
  Pqfe=Pqfe/100
  Pqnh=Pqnh/100
   
  -- Get wind direction and speed.
  local WindDirection,WindVelocity=weatherlog._GetWind(vec3)
  
  -- Return data.
  return T,Pqfe,Pqnh,WindDirection,WindVelocity
end


--- Returns the wind direction (from) and strength.
function weatherlog._GetWind(vec3)

  -- Get wind velocity vector.
  local windvec3  = atmosphere.getWind({x=vec3.x, y=vec3.y+1, z=vec3.z})
  local direction = math.deg(math.atan2(windvec3.z, windvec3.x))
  
  if direction < 0 then
    direction = direction + 360
  end
  
  -- Convert TO direction to FROM direction. 
  if direction > 180 then
    direction = direction-180
  else
    direction = direction+180
  end
  
  -- Calc 2D strength.
  local strength=math.sqrt((windvec3.x)^2+(windvec3.z)^2)
  
  -- Return wind direction and strength km/h.
  return direction, strength, windvec3
end

-- Beaufort scale: returns Beaufort number and wind description as a function of wind speed in m/s.
function weatherlog._BeaufortScale(speed)
  local bn=nil
  local bd=nil
  if speed<0.51 then
    bn=0
    bd="Calm"
  elseif speed<2.06 then
    bn=1
    bd="Light Air"
  elseif speed<3.60 then
    bn=2
    bd="Light Breeze"
  elseif speed<5.66 then
    bn=3
    bd="Gentle Breeze"
  elseif speed<8.23 then
    bn=4
    bd="Moderate Breeze"
  elseif speed<11.32 then
    bn=5
    bd="Fresh Breeze"
  elseif speed<14.40 then
    bn=6
    bd="Strong Breeze"
  elseif speed<17.49 then
    bn=7
    bd="Moderate Gale"
  elseif speed<21.09 then
    bn=8
    bd="Fresh Gale"
  elseif speed<24.69 then
    bn=9
    bd="Strong Gale"
  elseif speed<28.81 then
    bn=10
    bd="Storm"
  elseif speed<32.92 then
    bn=11
    bd="Violent Storm"
  else
    bn=12
    bd="Hurricane"
  end
  return bn,bd
end

--- Convert time in seconds to hours, minutes and seconds.
-- @param #number seconds Time in seconds, e.g. from timer.getAbsTime() function.
-- @return #string Time in format Hours:Minutes:Seconds+Days (HH:MM:SS+D).
function weatherlog._SecondsToClock(seconds)
  
  -- Nil check.
  if seconds==nil then
    return nil
  end
  
  -- Seconds
  local seconds = tonumber(seconds)
  
  -- Seconds of this day.
  local _seconds=seconds%(60*60*24)

  if seconds <= 0 then
    return nil
  else
    local hours = string.format("%02.f", math.floor(_seconds/3600))
    local mins  = string.format("%02.f", math.floor(_seconds/60 - (hours*60)))
    local secs  = string.format("%02.f", math.floor(_seconds - hours*3600 - mins *60))
    local days  = string.format("%d", seconds/(60*60*24))
    return hours..":"..mins..":"..secs.."+"..days
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Start scheduler.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

weatherlog._WeatherReport()
weatherlog.timerID=timer.scheduleFunction(weatherlog._WeatherReport, {}, timer.getTime() + weatherlog.ReportInterval)

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------------------------