-- Weather station using an SHT45 (temperature / humidity) and a BMP280
-- (barometric pressure) connected to port A.
--
-- Along with the live readings, the app keeps a rolling history of the
-- pressure and watches its trend to forecast the weather. The thresholds
-- follow the standard meteorological rules of thumb for the 3 hour pressure
-- tendency: a fall of more than 1.5 hPa means deteriorating weather, more
-- than 3 hPa means rain is likely, and more than 6 hPa (or a fast fall on
-- top of already low pressure) is a strong storm signal. The data collected
-- is sent to Superstack

local SHT45_ADDRESS = 0x44

local PORT = { port = "PORTA" }

-- Set this to your elevation in meters so that the pressure can be converted
-- to its sea level equivalent. The forecast thresholds assume sea level values
local ALTITUDE_M = 0

-- Seconds between readings, and readings averaged into each history point.
-- Together these give one pressure history point per minute
local SAMPLE_INTERVAL = 10
local SAMPLES_PER_POINT = 6

-- Set the IO to 3.3V
device.power.set_vout(3.3)
device.sleep(0.1)

-- The BMP280 can sit at 0x77 or 0x76 depending on the SDO pin. Find it by
-- checking for its chip ID (0x58)
local BMP280_ADDRESS

for _, address in ipairs({ 0x77, 0x76 }) do
    local response = device.i2c.write_read(address, "\xD0", 1, PORT)
    if response.success and string.byte(response.data, 1) == 0x58 then
        BMP280_ADDRESS = address
        break
    end
end

if not BMP280_ADDRESS then
    error("BMP280 not found on port A")
end

-- Read register(s) from the BMP280
local function read_reg(reg, len)
    local response = device.i2c.write_read(BMP280_ADDRESS, string.char(reg), len or 1, PORT)
    if not response.success then return nil end
    return response.data
end

-- Soft reset
device.i2c.write(BMP280_ADDRESS, "\xE0\xB6", PORT)
device.sleep(0.1)

-- Read calibration data (24 bytes)
local cal = read_reg(0x88, 24)
if not cal then
    error("Failed to read BMP280 calibration data")
end

-- Unsigned 16-bit
local function u16(lo, hi)
    return string.byte(cal, lo) + string.byte(cal, hi) * 256
end

-- Signed 16-bit
local function s16(lo, hi)
    local v = u16(lo, hi)
    if v > 32767 then v = v - 65536 end
    return v
end

-- Temperature calibration
local T1 = u16(1, 2)
local T2 = s16(3, 4)
local T3 = s16(5, 6)

-- Pressure calibration
local P1 = u16(7, 8)
local P2 = s16(9, 10)
local P3 = s16(11, 12)
local P4 = s16(13, 14)
local P5 = s16(15, 16)
local P6 = s16(17, 18)
local P7 = s16(19, 20)
local P8 = s16(21, 22)
local P9 = s16(23, 24)

-- IIR filter x4 to smooth out door slams and gusts, which matters when we are
-- looking for hPa scale changes over hours
device.i2c.write(BMP280_ADDRESS, "\xF5\x08", PORT)

-- Compensation algorithm (Bosch datasheet)
local function compensate(adc_T, adc_P)
    -- Temperature compensation
    local var1 = (adc_T / 16384.0 - T1 / 1024.0) * T2
    local var2 = ((adc_T / 131072.0 - T1 / 8192.0) ^ 2) * T3
    local t_fine = var1 + var2
    local temp = t_fine / 5120.0

    -- Pressure compensation
    var1 = t_fine / 2.0 - 64000.0
    var2 = var1 * var1 * P6 / 32768.0
    var2 = var2 + var1 * P5 * 2.0
    var2 = var2 / 4.0 + P4 * 65536.0
    var1 = (P3 * var1 * var1 / 524288.0 + P2 * var1) / 524288.0
    var1 = (1.0 + var1 / 32768.0) * P1

    local press = 0
    if var1 ~= 0 then
        press = 1048576.0 - adc_P
        press = (press - var2 / 4096.0) * 6250.0 / var1
        var1 = P9 * press * press / 2147483648.0
        var2 = press * P8 / 32768.0
        press = press + (var1 + var2 + P7) / 16.0
    end

    return temp, press / 100.0 -- hPa
end

-- Trigger a one shot measurement and return temperature and pressure
local function read_bmp280()
    -- Forced mode, temperature oversampling x2, pressure oversampling x16
    device.i2c.write(BMP280_ADDRESS, "\xF4\x55", PORT)
    device.sleep(0.05)

    local raw = read_reg(0xF7, 6)
    if not raw then return nil end

    local adc_P = (string.byte(raw, 1) * 65536 + string.byte(raw, 2) * 256 + string.byte(raw, 3)) // 16
    local adc_T = (string.byte(raw, 4) * 65536 + string.byte(raw, 5) * 256 + string.byte(raw, 6)) // 16

    return compensate(adc_T, adc_P)
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
    device.i2c.write(SHT45_ADDRESS, "\xFD", PORT)
    device.sleep(0.01)
    local response = device.i2c.read(SHT45_ADDRESS, 6, PORT)
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

-- Convert the station pressure to its sea level equivalent using the
-- international barometric formula
local function sea_level_pressure(pressure, temperature)
    return pressure /
        (1 - 0.0065 * ALTITUDE_M / (temperature + 0.0065 * ALTITUDE_M + 273.15)) ^ 5.257
end

-- Dew point using the Magnus formula
local function dew_point(temperature, humidity)
    local gamma = (17.62 * temperature) / (243.12 + temperature) + math.log(humidity / 100)
    return (243.12 * gamma) / (17.62 - gamma)
end

-- Rolling pressure history, one point per minute, 3 hours deep
local history = {}
local HISTORY_MAX = 181

-- Pressure change compared to a number of minutes ago, or nil if we don't
-- have enough history yet
local function tendency(minutes)
    if #history <= minutes then return nil end
    return history[#history] - history[#history - minutes]
end

-- Forecast from the sea level pressure and its 1 and 3 hour tendencies.
-- Returns a severity level from 0 (settled) to 4 (storm) and a description
local function forecast(pressure, change_1h, change_3h)
    local falling_fast_1h = change_1h ~= nil and change_1h <= -1.2
    local falling_fast_3h = change_3h ~= nil and change_3h <= -3.0

    if (change_3h ~= nil and change_3h <= -6.0) or (falling_fast_1h and pressure <= 1000) then
        return 4, "Storm warning: pressure falling very fast"
    end

    if falling_fast_3h or falling_fast_1h then
        if pressure <= 1006 then
            return 4, "Storm likely: fast fall from already low pressure"
        end
        return 3, "Rain likely soon: pressure falling fast"
    end

    if change_3h ~= nil and change_3h <= -1.5 then
        return 2, "Deteriorating: pressure falling steadily"
    end

    if change_3h ~= nil and change_3h >= 1.5 then
        return 1, "Improving: pressure rising"
    end

    -- Pressure is steady, or we don't have enough history yet
    if pressure >= 1022 then return 0, "Settled and fair" end
    if pressure <= 1000 then return 2, "Staying unsettled" end
    return 1, "No significant change"
end

print("Weather station running. Forecasts improve after 3 hours of data")

local accumulated_pressure = 0
local accumulated_samples = 0

while true do
    local temperature, humidity = read_sht45()
    local _, pressure = read_bmp280()

    if temperature and pressure then
        local sea_level = sea_level_pressure(pressure, temperature)
        local dew = dew_point(temperature, humidity)

        -- Average readings into one history point per minute
        accumulated_pressure = accumulated_pressure + sea_level
        accumulated_samples = accumulated_samples + 1

        if accumulated_samples >= SAMPLES_PER_POINT then
            table.insert(history, accumulated_pressure / accumulated_samples)
            if #history > HISTORY_MAX then
                table.remove(history, 1)
            end
            accumulated_pressure = 0
            accumulated_samples = 0
        end

        local change_1h = tendency(60)
        local change_3h = tendency(180)

        local level, description = forecast(sea_level, change_1h, change_3h)

        print(string.format(
            "%.2f C | %.1f %%RH | dew %.1f C | %.2f hPa (sea level) | 3h change: %s | %s",
            temperature, humidity, dew, sea_level,
            change_3h and string.format("%+.2f hPa", change_3h) or "n/a",
            description))

        -- Send the values to Superstack. The tendencies are omitted until
        -- enough history has been collected
        network.send_data {
            temperature = temperature,
            humidity = humidity,
            dew_point = dew,
            pressure = pressure,
            sea_level_pressure = sea_level,
            pressure_change_1h = change_1h,
            pressure_change_3h = change_3h,
            forecast_level = level,
            forecast = description
        }
    else
        print("Sensor read error")
    end

    device.sleep(SAMPLE_INTERVAL)
end
