-- Minimal example for the BMP280 barometric pressure sensor. See
-- weather-station.lua for a complete application built around this sensor

-- Set this to the address of the web service that receives the readings
local SERVER_URL = "https://example.com/readings"

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

-- Probe the chip ID register (0xD0), which always reads 0x58
local id = read_reg(0xD0)

if not id then
    error("No response from address 0x77. Check the wiring and port")
end

print(string.format("Chip ID: 0x%02X", string.byte(id, 1)))

if string.byte(id, 1) ~= 0x58 then
    error("Unexpected chip ID. Expected 0x58")
end

-- Soft reset
device.i2c.write(BMP280_ADDRESS, "\xE0\xB6")
device.sleep(0.1)

-- Read calibration data (24 bytes)
local cal = read_reg(0x88, 24)
if not cal then
    error("Failed to read calibration data")
end

-- Temperature then pressure calibration, twelve little-endian 16-bit words.
-- In the format, < is little-endian, I2 is a uint16_t and i2 is an int16_t,
-- so only T1 and P1 are unsigned
local T1, T2, T3, P1, P2, P3, P4, P5, P6, P7, P8, P9 =
    string.unpack("<I2 i2 i2 I2 i2 i2 i2 i2 i2 i2 i2 i2", cal)

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
        local press_msb, press_lsb, press_xlsb, temp_msb, temp_lsb, temp_xlsb = raw:byte(1, 6)
        local adc_P = (press_msb << 12) | (press_lsb << 4) | (press_xlsb >> 4)
        local adc_T = (temp_msb << 12) | (temp_lsb << 4) | (temp_xlsb >> 4)

        local temperature, pressure = compensate(adc_T, adc_P)

        print(string.format("Raw ADC: T=%d P=%d (%.2f C, %.2f hPa)", adc_T, adc_P, temperature, pressure))

        -- Send the values to the web service as JSON
        local body = json.encode {
            temperature = temperature,
            pressure = pressure
        }

        local post_response, err = network.post(SERVER_URL, body, {
            headers = { ["Content-Type"] = "application/json" }
        })

        if not post_response then
            print("Send failed: " .. err)
        end
    else
        print("Measurement read failed")
    end

    device.sleep(3)
end
