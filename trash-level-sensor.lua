VL53L0X_I2C_ADDRESS = 0x29

-- Set the IO to 3.3V
device.power.set_vout(3.3)

-- Enable battery charging
device.power.battery.set_charger_cv_cc(4.2, 500)

-- I2C helper functions: write 8bit, read 16bit, write bytes, etc
function r8(address)
    return device.i2c.write_read(VL53L0X_I2C_ADDRESS, string.char(address), 1).value
end

function w8(address, data)
    device.i2c.write(VL53L0X_I2C_ADDRESS, string.char(address, data))
end

function r16(address)
    local r = device.i2c.write_read(VL53L0X_I2C_ADDRESS, string.char(address), 2)
    return (string.byte(r.data, 1) << 8) | string.byte(r.data, 2)
end

function w16(address, data)
    device.i2c.write(VL53L0X_I2C_ADDRESS, string.char(address, data >> 8, data & 0xFF))
end

function wn(address, ...)
    device.i2c.write(VL53L0X_I2C_ADDRESS, string.char(address, ...))
end

--
function mclks_to_us(timeout_period_mclks, vcsel_period_pclks)
    local macro_period_ns = (((2304 * (vcsel_period_pclks) * 1655) + 500) / 1000)
    return ((timeout_period_mclks * macro_period_ns) + (macro_period_ns / 2)) / 1000
end

function us_to_mclks(timeout_period_us, vcsel_period_pclks)
    local macro_period_ns = (((2304 * (vcsel_period_pclks) * 1655) + 500) / 1000)
    return (((timeout_period_us * 1000) + (macro_period_ns / 2)) / macro_period_ns)
end

------------------------------------------------------------------------------------

-- Switch to high IO voltage
w8(0x89, r8(0x89) | 0x01)

-- Set I2C standard mode
w8(0x88, 0x00)

-- Some kind of internal default settings
w8(0x80, 0x01)
w8(0xFF, 0x01)
w8(0x00, 0x00)
local stop = r8(0x91)
w8(0x00, 0x01)
w8(0xFF, 0x00)
w8(0x80, 0x00)

-- Disable SIGNAL_RATE_MSRC and SIGNAL_RATE_PRE_RANGE limit checks
w8(0x60, r8(0x60) | 0x12)

-- Set final range signal rate limit to 0.25 million counts per second
w16(0x44, 0.25 * (1 << 7))

-- End of system sequence config
w8(0x01, 0xFF)

-- Get reference SPAD count and type
w8(0x80, 0x01)
w8(0xFF, 0x01)
w8(0x00, 0x00)
w8(0xFF, 0x06)
w8(0x83, r8(0x83) | 0x04)
w8(0xFF, 0x07)
w8(0x81, 0x01)
w8(0x80, 0x01)
w8(0x94, 0x6b)
w8(0x83, 0x00)
while (r8(0x83) == 0x00) do end
w8(0x83, 0x01)

tmp = r8(0x92)
spad_count = tmp & 0x7f
spad_type_is_aperture = (tmp >> 7) & 0x01
w8(0x81, 0x00)
w8(0xFF, 0x06)
w8(0x83, r8(0x83) & ~0x04)
w8(0xFF, 0x01)
w8(0x00, 0x01)
w8(0xFF, 0x00)
w8(0x80, 0x00)

-- Get reference SPAD map
ref_spad_map = {}
local r = device.i2c.write_read(VL53L0X_I2C_ADDRESS, '\xB0', 6).data
for i = 1, 6 do
    ref_spad_map[i] = string.byte(r, i)
end

w8(0xFF, 0x01)
w8(0x4F, 0x00)
w8(0x4E, 0x2C)
w8(0xFF, 0x00)
w8(0xB6, 0xB4)

-- Enable them
first_spad = 0
if spad_type_is_aperture == 1 then
    first_spad = 12
end

spads_enabled = 0

for i = 0, 47 do
    if i < first_spad or spads_enabled == spad_count then
        local byte_idx = math.floor(i / 8) + 1
        ref_spad_map[byte_idx] = ref_spad_map[byte_idx] & (~(1 << (i % 8)))
    else
        if ((ref_spad_map[math.floor(i / 8) + 1] >> (i % 8)) & 0x1) ~= 0 then
            spads_enabled = spads_enabled + 1
        end
    end
end

device.i2c.write(VL53L0X_I2C_ADDRESS,
    string.char(0xB0, ref_spad_map[1], ref_spad_map[2], ref_spad_map[3], ref_spad_map[4], ref_spad_map[5],
        ref_spad_map[6]))

-- Default sensor tuning settings
w8(0xFF, 0x01)
w8(0x00, 0x00)
w8(0xFF, 0x00)
w8(0x09, 0x00)
w8(0x10, 0x00)
w8(0x11, 0x00)
w8(0x24, 0x01)
w8(0x25, 0xFF)
w8(0x75, 0x00)
w8(0xFF, 0x01)
w8(0x4E, 0x2C)
w8(0x48, 0x00)
w8(0x30, 0x20)
w8(0xFF, 0x00)
w8(0x30, 0x09)
w8(0x54, 0x00)
w8(0x31, 0x04)
w8(0x32, 0x03)
w8(0x40, 0x83)
w8(0x46, 0x25)
w8(0x60, 0x00)
w8(0x27, 0x00)
w8(0x50, 0x06)
w8(0x51, 0x00)
w8(0x52, 0x96)
w8(0x56, 0x08)
w8(0x57, 0x30)
w8(0x61, 0x00)
w8(0x62, 0x00)
w8(0x64, 0x00)
w8(0x65, 0x00)
w8(0x66, 0xA0)
w8(0xFF, 0x01)
w8(0x22, 0x32)
w8(0x47, 0x14)
w8(0x49, 0xFF)
w8(0x4A, 0x00)
w8(0xFF, 0x00)
w8(0x7A, 0x0A)
w8(0x7B, 0x00)
w8(0x78, 0x21)
w8(0xFF, 0x01)
w8(0x23, 0x34)
w8(0x42, 0x00)
w8(0x44, 0xFF)
w8(0x45, 0x26)
w8(0x46, 0x05)
w8(0x40, 0x40)
w8(0x0E, 0x06)
w8(0x20, 0x1A)
w8(0x43, 0x40)
w8(0xFF, 0x00)
w8(0x34, 0x03)
w8(0x35, 0x44)
w8(0xFF, 0x01)
w8(0x31, 0x04)
w8(0x4B, 0x09)
w8(0x4C, 0x05)
w8(0x4D, 0x04)
w8(0xFF, 0x00)
w8(0x44, 0x00)
w8(0x45, 0x20)
w8(0x47, 0x08)
w8(0x48, 0x28)
w8(0x67, 0x00)
w8(0x70, 0x04)
w8(0x71, 0x01)
w8(0x72, 0xFE)
w8(0x76, 0x00)
w8(0x77, 0x00)
w8(0xFF, 0x01)
w8(0x0D, 0x01)
w8(0xFF, 0x00)
w8(0x80, 0x01)
w8(0x01, 0xF8)
w8(0xFF, 0x01)
w8(0x8E, 0x01)
w8(0x00, 0x01)
w8(0xFF, 0x00)
w8(0x80, 0x00)

-- Set interrupt config - new sample ready
w8(0x0A, 0x04)
w8(0x84, r8(0x84) & (~0x10))
w8(0x0B, 0x01)

-- Calculate timeouts
local code = r8(0x01)
enables = {
    tcc = (code >> 4) & 0x1,
    dss = (code >> 3) & 0x1,
    msrc = (code >> 2) & 0x1,
    pre_range = (code >> 6) & 0x1,
    final_range = (code >> 7) & 0x1
}

timeouts = {}
timeouts.pre_range_vcsel_period_pclks = ((r8(0x50) + 1) << 1)

timeouts.msrc_dss_tcc_mclks = r8(0x46) + 1
timeouts.msrc_dss_tcc_us = mclks_to_us(timeouts.msrc_dss_tcc_mclks,
    timeouts.pre_range_vcsel_period_pclks)

local reg_val = r16(0x51)
timeouts.pre_range_mclks = ((reg_val & 0x00FF) << ((reg_val & 0xFF00) >> 8)) + 1
timeouts.pre_range_us = mclks_to_us(timeouts.pre_range_mclks, timeouts.pre_range_vcsel_period_pclks)

timeouts.final_range_vcsel_period_pclks = ((r8(0x70) + 1) << 1)

reg_val = r16(0x71)
timeouts.final_range_mclks = ((reg_val & 0x00FF) << ((reg_val & 0xFF00) >> 8)) + 1

if enables.pre_range > 0 then
    timeouts.final_range_mclks = timeouts.final_range_mclks - timeouts.pre_range_mclks
end

timeouts.final_range_us = mclks_to_us(timeouts.final_range_mclks,
    timeouts.final_range_vcsel_period_pclks)

-- Get measurement budget
measurement_budget_us = 1910 + 960

if enables.tcc > 0 then
    measurement_budget_us = measurement_budget_us + timeouts.msrc_dss_tcc_us + 590
end

if enables.dss > 0 then
    measurement_budget_us = measurement_budget_us + (2 * (timeouts.msrc_dss_tcc_us + 690))
else
    if enables.msrc > 0 then
        measurement_budget_us = measurement_budget_us + timeouts.msrc_dss_tcc_us + 660
    end
end

if enables.pre_range > 0 then
    measurement_budget_us = measurement_budget_us + timeouts.pre_range_us + 660
end

if enables.final_range > 0 then
    measurement_budget_us = measurement_budget_us + timeouts.final_range_us + 550
end

w8(0x01, 0xE8)

-- set measurement budget
if measurement_budget_us < 20000 then
    return false
end

local used_budget_us = 1320 + 960

if enables.tcc > 0 then
    used_budget_us = used_budget_us + (timeouts.msrc_dss_tcc_us + 590)
end

if enables.dss > 0 then
    used_budget_us = used_budget_us + 2 * (timeouts.msrc_dss_tcc_us + 690)
else
    if enables.msrc > 0 then
        used_budget_us = used_budget_us + (timeouts.msrc_dss_tcc_us + 660)
    end
end

if enables.pre_range > 0 then
    used_budget_us = used_budget_us + (timeouts.pre_range_us + 660)
end

if enables.final_range > 0 then
    used_budget_us = used_budget_us + 550

    final_range_timeout_us = measurement_budget_us - used_budget_us;

    final_range_timeout_mclks = us_to_mclks(final_range_timeout_us,
        timeouts.final_range_vcsel_period_pclks)

    if enables.pre_range then
        final_range_timeout_mclks = final_range_timeout_mclks + timeouts.pre_range_mclks
    end

    local ls_byte = 0
    local ms_byte = 0
    local encoded_timeout = 0

    if final_range_timeout_mclks > 0 then
        ls_byte = math.floor(final_range_timeout_mclks - 1)

        while ((ls_byte & 0xFFFFFF00) > 0) do
            ls_byte = ls_byte >> 1
            ms_byte = ms_byte + 1
        end

        encoded_timeout = (ms_byte << 8) | (ls_byte & 0xFF)
    end

    w16(0x71, encoded_timeout)
end

-- Perform voltage calibration
w8(0x01, 0x01)
w8(0x00, 0x01 | 0x40)
while ((r8(0x13) & 0x07) == 0) do
end
w8(0x0B, 0x01)
w8(0x00, 0x00)

-- Perform phase calibration
w8(0x01, 0x02)
w8(0x00, 0x01)
while ((r8(0x13) & 0x07) == 0) do
end
w8(0x0B, 0x01)
w8(0x00, 0x00)

-- Restore sequence config
w8(0x01, 0xE8)
print("Initialized")

while true do
    w8(0x80, 0x01);
    w8(0xFF, 0x01);
    w8(0x00, 0x00);
    w8(0x91, stop);
    w8(0x00, 0x01);
    w8(0xFF, 0x00);
    w8(0x80, 0x00);
    w8(0x00, 0x01);
    r8(0x00)

    -- Read range in mm
    while (r8(0x13) & 0x07 == 0) do
    end
    local resp = device.i2c.write_read(VL53L0X_I2C_ADDRESS, "\x14", 12)
    distance_mm = (string.byte(resp.data, 11) << 8) | string.byte(resp.data, 12)

    -- Clear system interrupt
    w8(0x0B, 0x01)

    -- Convert to cm and adjust mechnical offset
    local distance_cm = (distance_mm - 10) / 10

    network.send_data {
        trash_level = distance_cm
    }

    device.sleep(1)
end
