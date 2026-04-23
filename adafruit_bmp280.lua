device.power.set_vout(3.3)
device.sleep(1)

local ADDR = 0x77

-- I2C configuration
local cfg = {
    scl_pin = "A1",
    sda_pin = "A0",
    frequency = 100
}

-- Read register(s)
local function read_reg(reg, len)
    local ok = device.i2c.write(ADDR, string.char(reg), cfg)
    if not ok then return nil end
    local r = device.i2c.read(ADDR, len or 1, cfg)
    if not r.success then return nil end
    return r.data
end

-- Write register
local function write_reg(reg, val)
    return device.i2c.write(ADDR, string.char(reg, val), cfg)
end

---------------------------------------------------------
-- Read chip ID for debug
---------------------------------------------------------
--local id = read_reg(0xD0)
--local chip_id = id and string.byte(id) or -1
--print(string.format("Chip ID: 0x%02X", chip_id))

--if chip_id ~= 0x58 and chip_id ~= 0x60 then
--    print("Error: No BMP280/BME280 detected")
--    return
--end

---------------------------------------------------------
-- Soft reset
---------------------------------------------------------
write_reg(0xE0, 0xB6)
device.sleep(0.1)

---------------------------------------------------------
-- Read calibration data (24 bytes)
---------------------------------------------------------
local cal = read_reg(0x88, 24)
if not cal then
    print("Failed to read calibration data")
    return
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

print("Calibration OK")

---------------------------------------------------------
-- Configure sensor: normal mode, oversampling x1
---------------------------------------------------------
write_reg(0xF4, 0x27) -- osrs_t=1, osrs_p=1, normal mode
write_reg(0xF5, 0x00) -- filter off, shortest standby time
device.sleep(0.1)

---------------------------------------------------------
-- Compensation algorithm (Bosch datasheet)
---------------------------------------------------------
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

---------------------------------------------------------
-- Main loop
---------------------------------------------------------
while true do
    -- Read raw pressure + temperature (6 bytes)
    local raw = read_reg(0xF7, 6)
    if raw then
        local pm  = string.byte(raw, 1)
        local pl  = string.byte(raw, 2)
        local pxl = string.byte(raw, 3)
        local tm  = string.byte(raw, 4)
        local tl  = string.byte(raw, 5)
        local txl = string.byte(raw, 6)

        local adc_P = (pm * 65536 + pl * 256 + pxl) // 16
        local adc_T = (tm * 65536 + tl * 256 + txl) // 16

        local temp, press = compensate(adc_T, adc_P)
        print(string.format("Temp: %.2f °C | Pressure: %.2f hPa", temp, press))
    else
        print("Read error")
    end

    device.sleep(0.5)
end

