-- Air quality monitor using an SHT45 (temperature / humidity) on port E and
-- an ENS160 (eCO2 / TVOC / AQI) on port F, with a fan relay on pin A0.
--
-- The SHT45 readings are fed into the ENS160 so its gas measurements are
-- compensated for ambient conditions. The fan switches on when the air gets
-- bad and off once it recovers, with hysteresis so it doesn't flap around
-- the thresholds. All readings are sent to Superstack

local SHT45_ADDRESS = 0x44
local ENS160_ADDRESS = 0x53

local SHT45_PORT = { port = "PORTE" }
local ENS160_PORT = { port = "PORTF" }

local FAN_PIN = "A0"

-- The fan turns on when either level rises above its on threshold, and off
-- again only once both have fallen below their off thresholds
local ECO2_FAN_ON = 800 -- ppm
local ECO2_FAN_OFF = 700
local TVOC_FAN_ON = 2200 -- ppb
local TVOC_FAN_OFF = 2000

-- Seconds between readings
local SAMPLE_INTERVAL = 3

-- Set the IO to 3.3V
device.power.set_vout(3.3)
device.sleep(0.1)

-- Start with the fan off to match the fan_running state below
device.digital.set_output(FAN_PIN, false)

-- Read register(s) from the ENS160
local function ens160_read(reg, len)
    local response = device.i2c.write_read(ENS160_ADDRESS, string.char(reg), len, ENS160_PORT)
    if not response.success then return nil end
    return response.data
end

-- Confirm the sensor is present by checking PART_ID (0x0160 little-endian)
local part_id = ens160_read(0x00, 2)
if not part_id or (string.byte(part_id, 1) | (string.byte(part_id, 2) << 8)) ~= 0x0160 then
    error("ENS160 not found on port F")
end

-- OPMODE 0x02 = standard gas sensing mode
if not device.i2c.write(ENS160_ADDRESS, "\x10\x02", ENS160_PORT).success then
    error("Failed to start ENS160 gas sensing")
end

-- Sensirion CRC-8: polynomial 0x31, initial value 0xFF
local function crc8(data)
    local crc = 0xFF
    for i = 1, #data do
        crc = crc ~ string.byte(data, i)
        for _ = 1, 8 do
            if crc & 0x80 ~= 0 then
                crc = ((crc << 1) & 0xFF) ~ 0x31
            else
                crc = (crc << 1) & 0xFF
            end
        end
    end
    return crc
end

-- Measure temperature and humidity in high precision mode
local function read_sht45()
    device.i2c.write(SHT45_ADDRESS, "\xFD", SHT45_PORT)
    device.sleep(0.01)
    local response = device.i2c.read(SHT45_ADDRESS, 6, SHT45_PORT)
    if not response.success then return nil end

    local d = response.data
    if crc8(d:sub(1, 2)) ~= string.byte(d, 3) or crc8(d:sub(4, 5)) ~= string.byte(d, 6) then
        return nil
    end

    local raw_temperature = (string.byte(d, 1) << 8) | string.byte(d, 2)
    local raw_humidity = (string.byte(d, 4) << 8) | string.byte(d, 5)

    local temperature = -45 + (175 * (raw_temperature / 65535))
    local humidity = -6 + (125 * (raw_humidity / 65535))

    if humidity < 0 then humidity = 0 end
    if humidity > 100 then humidity = 100 end

    return temperature, humidity
end

-- Feed the ambient conditions to the ENS160 so its gas measurements are
-- compensated. TEMP_IN (0x13) is Kelvin x 64 and RH_IN (0x15) is %RH x 512,
-- both little-endian
local function write_ens160_ambient(temperature, humidity)
    local kelvin = math.floor((temperature + 273.15) * 64 + 0.5)
    local rh = math.floor(humidity * 512 + 0.5)

    device.i2c.write(ENS160_ADDRESS, string.char(0x13, kelvin & 0xFF, (kelvin >> 8) & 0xFF), ENS160_PORT)
    device.i2c.write(ENS160_ADDRESS, string.char(0x15, rh & 0xFF, (rh >> 8) & 0xFF), ENS160_PORT)
end

-- Read the air quality data if a fresh measurement is ready. Returns the
-- readings (or nil) along with the validity flag from DEVICE_STATUS:
-- 0 = normal, 1 = warm-up, 2 = initial start-up, 3 = output invalid
local function read_ens160()
    local status = ens160_read(0x20, 1)
    if not status then return nil end

    local validity = (string.byte(status, 1) >> 2) & 0x03

    -- Skip the cycle when NEWDAT (bit 1) shows no new measurement, or when
    -- the sensor flags its output as invalid
    if string.byte(status, 1) & 0x02 == 0 or validity == 3 then
        return nil, validity
    end

    -- DATA_AQI, DATA_TVOC and DATA_ECO2 sit at consecutive registers 0x21-0x25
    local data = ens160_read(0x21, 5)
    if not data then return nil end

    local aqi = string.byte(data, 1) & 0x07
    local tvoc = string.byte(data, 2) | (string.byte(data, 3) << 8)
    local eco2 = string.byte(data, 4) | (string.byte(data, 5) << 8)

    return { aqi = aqi, tvoc = tvoc, eco2 = eco2 }, validity
end

local fan_running = false

-- Switch the fan with hysteresis, only touching the pin when the state changes
local function update_fan(eco2, tvoc)
    if fan_running then
        if eco2 < ECO2_FAN_OFF and tvoc < TVOC_FAN_OFF then
            fan_running = false
            device.digital.set_output(FAN_PIN, false)
        end
    elseif eco2 > ECO2_FAN_ON or tvoc > TVOC_FAN_ON then
        fan_running = true
        device.digital.set_output(FAN_PIN, true)
    end
end

print("Air quality monitor running")

local last_validity

while true do
    local temperature, humidity = read_sht45()

    if temperature then
        write_ens160_ambient(temperature, humidity)
    else
        print("SHT45 read failed")
    end

    local air, validity = read_ens160()

    -- Report warm-up states once when they change rather than every reading
    if validity and validity ~= last_validity then
        if validity == 1 then
            print("ENS160 warming up, readings may be inaccurate for a few minutes")
        elseif validity == 2 then
            print("ENS160 in initial start-up phase, readings may be inaccurate")
        elseif validity == 3 then
            print("ENS160 output invalid, skipping readings")
        elseif last_validity then
            print("ENS160 ready")
        end
        last_validity = validity
    end

    if air then
        update_fan(air.eco2, air.tvoc)

        -- Send the values to Superstack. Temperature and humidity are
        -- omitted if the SHT45 read failed this cycle
        network.send_data {
            temperature = temperature,
            humidity = humidity,
            air_quality_index = air.aqi,
            carbon_dioxide = air.eco2,
            volatile_compounds = air.tvoc,
            fan_running = fan_running
        }
    elseif not validity then
        print("ENS160 read failed")
    end

    device.sleep(SAMPLE_INTERVAL)
end
