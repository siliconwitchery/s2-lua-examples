-- Minimal example for the BMP280 barometric pressure sensor. See
-- weather-station.lua for a complete application built around this sensor

local BMP280_ADDRESS = 0x77 -- 0x76 if the SDO pin is pulled low

-- Sensor requires 3.3V power
device.power.set_vout(3.3)
device.sleep(0.1)

-- Read register(s)
local function read_reg(reg, len)
    local response = device.i2c.write_read(BMP280_ADDRESS, string.char(reg), len or 1)
    if not response.success then return nil end
    return response.data
end

-- The chip ID register (0xD0) should return 0x58
local id = read_reg(0xD0)
if not id or string.byte(id, 1) ~= 0x58 then
    error("BMP280 not found")
end

-- Soft reset
device.i2c.write(BMP280_ADDRESS, "\xE0\xB6")
device.sleep(0.1)

-- Read calibration data (24 bytes)
local cal = read_reg(0x88, 24)
if not cal then
    error("Failed to read calibration data")
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

-- Normal mode, temperature and pressure oversampling x1
device.i2c.write(BMP280_ADDRESS, "\xF4\x27")
device.sleep(0.1)

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

while true do
    -- Raw pressure and temperature, 20 bits each across 6 bytes
    local raw = read_reg(0xF7, 6)

    if raw then
        local adc_P = (string.byte(raw, 1) * 65536 + string.byte(raw, 2) * 256 + string.byte(raw, 3)) // 16
        local adc_T = (string.byte(raw, 4) * 65536 + string.byte(raw, 5) * 256 + string.byte(raw, 6)) // 16

        local temperature, pressure = compensate(adc_T, adc_P)

        print(string.format("Temperature: %.2f C | Pressure: %.2f hPa", temperature, pressure))

        -- Send the values to Superstack
        network.send_data {
            temperature = temperature,
            pressure = pressure
        }
    else
        print("Read error")
    end

    device.sleep(3)
end
