-- VL53L0X time-of-flight distance sensor on the default I2C port. The init
-- flow is ported from ST's reference driver and its order is load-bearing

local VL53L0X_ADDRESS = 0x29

-- Sensor requires 3.3V power
device.power.set_vout(3.3)

-- Give the sensor time to boot
device.sleep(0.1)

local function r8(reg)
    return device.i2c.write_read(VL53L0X_ADDRESS, string.char(reg), 1).value
end

local function w8(reg, data)
    device.i2c.write(VL53L0X_ADDRESS, string.char(reg, data))
end

local function r16(reg)
    local response = device.i2c.write_read(VL53L0X_ADDRESS, string.char(reg), 2)
    return (string.byte(response.data, 1) << 8) | string.byte(response.data, 2)
end

local function w16(reg, data)
    device.i2c.write(VL53L0X_ADDRESS, string.char(reg, data >> 8, data & 0xFF))
end

-- Poll a register until one of the masked bits is set, erroring out after
-- roughly a second rather than hanging forever
local function wait_for_bits(reg, mask, message)
    for _ = 1, 100 do
        if (r8(reg) & mask) ~= 0 then
            return
        end
        device.sleep(0.01)
    end
    error(message)
end

-- Convert sequence step timeouts between macro clock periods and microseconds
local function mclks_to_us(timeout_mclks, vcsel_period_pclks)
    local macro_period_ns = ((2304 * vcsel_period_pclks * 1655) + 500) / 1000
    return ((timeout_mclks * macro_period_ns) + (macro_period_ns / 2)) / 1000
end

local function us_to_mclks(timeout_us, vcsel_period_pclks)
    local macro_period_ns = ((2304 * vcsel_period_pclks * 1655) + 500) / 1000
    return ((timeout_us * 1000) + (macro_period_ns / 2)) / macro_period_ns
end

-- The model ID register always reads 0xEE
if r8(0xC0) ~= 0xEE then
    error("VL53L0X not found")
end

-- Use 2.8V IO mode since the IO is powered at 3.3V
w8(0x89, r8(0x89) | 0x01)

-- Set I2C standard mode
w8(0x88, 0x00)

-- Enter the driver's internal config mode and grab the stop variable, which
-- is needed to trigger every measurement later
w8(0x80, 0x01)
w8(0xFF, 0x01)
w8(0x00, 0x00)
local stop_variable = r8(0x91)
w8(0x00, 0x01)
w8(0xFF, 0x00)
w8(0x80, 0x00)

-- Disable the SIGNAL_RATE_MSRC and SIGNAL_RATE_PRE_RANGE limit checks
w8(0x60, r8(0x60) | 0x12)

-- Set the final range signal rate limit to 0.25 MCPS (9.7 fixed point)
w16(0x44, 0.25 * (1 << 7))

w8(0x01, 0xFF) -- SYSTEM_SEQUENCE_CONFIG

-- Read the reference SPAD count and type from NVM
w8(0x80, 0x01)
w8(0xFF, 0x01)
w8(0x00, 0x00)
w8(0xFF, 0x06)
w8(0x83, r8(0x83) | 0x04)
w8(0xFF, 0x07)
w8(0x81, 0x01)
w8(0x80, 0x01)
w8(0x94, 0x6B)
w8(0x83, 0x00)
wait_for_bits(0x83, 0xFF, "Timeout reading SPAD info")
w8(0x83, 0x01)

local spad_info = r8(0x92)
local spad_count = spad_info & 0x7F
local spad_type_is_aperture = (spad_info >> 7) & 0x01

w8(0x81, 0x00)
w8(0xFF, 0x06)
w8(0x83, r8(0x83) & ~0x04)
w8(0xFF, 0x01)
w8(0x00, 0x01)
w8(0xFF, 0x00)
w8(0x80, 0x00)

-- Read the current reference SPAD map (GLOBAL_CONFIG_SPAD_ENABLES_REF_0)
local ref_spad_map = {}
local response = device.i2c.write_read(VL53L0X_ADDRESS, "\xB0", 6)
for i = 1, 6 do
    ref_spad_map[i] = string.byte(response.data, i)
end

w8(0xFF, 0x01)
w8(0x4F, 0x00) -- DYNAMIC_SPAD_REF_EN_START_OFFSET
w8(0x4E, 0x2C) -- DYNAMIC_SPAD_NUM_REQUESTED_REF_SPAD
w8(0xFF, 0x00)
w8(0xB6, 0xB4) -- GLOBAL_CONFIG_REF_EN_START_SELECT

-- Enable only the number of reference SPADs the NVM asked for. Aperture
-- SPADs start at index 12 in the map
local first_spad = 0
if spad_type_is_aperture == 1 then
    first_spad = 12
end

local spads_enabled = 0

for i = 0, 47 do
    if i < first_spad or spads_enabled == spad_count then
        local byte_index = i // 8 + 1
        ref_spad_map[byte_index] = ref_spad_map[byte_index] & ~(1 << (i % 8))
    elseif ((ref_spad_map[i // 8 + 1] >> (i % 8)) & 0x01) ~= 0 then
        spads_enabled = spads_enabled + 1
    end
end

device.i2c.write(VL53L0X_ADDRESS, string.char(0xB0,
    ref_spad_map[1], ref_spad_map[2], ref_spad_map[3],
    ref_spad_map[4], ref_spad_map[5], ref_spad_map[6]))

-- ST's mandatory default tuning blob. The values are undocumented but must
-- be written in exactly this order
local DEFAULT_TUNING = {
    { 0xFF, 0x01 }, { 0x00, 0x00 }, { 0xFF, 0x00 }, { 0x09, 0x00 },
    { 0x10, 0x00 }, { 0x11, 0x00 }, { 0x24, 0x01 }, { 0x25, 0xFF },
    { 0x75, 0x00 }, { 0xFF, 0x01 }, { 0x4E, 0x2C }, { 0x48, 0x00 },
    { 0x30, 0x20 }, { 0xFF, 0x00 }, { 0x30, 0x09 }, { 0x54, 0x00 },
    { 0x31, 0x04 }, { 0x32, 0x03 }, { 0x40, 0x83 }, { 0x46, 0x25 },
    { 0x60, 0x00 }, { 0x27, 0x00 }, { 0x50, 0x06 }, { 0x51, 0x00 },
    { 0x52, 0x96 }, { 0x56, 0x08 }, { 0x57, 0x30 }, { 0x61, 0x00 },
    { 0x62, 0x00 }, { 0x64, 0x00 }, { 0x65, 0x00 }, { 0x66, 0xA0 },
    { 0xFF, 0x01 }, { 0x22, 0x32 }, { 0x47, 0x14 }, { 0x49, 0xFF },
    { 0x4A, 0x00 }, { 0xFF, 0x00 }, { 0x7A, 0x0A }, { 0x7B, 0x00 },
    { 0x78, 0x21 }, { 0xFF, 0x01 }, { 0x23, 0x34 }, { 0x42, 0x00 },
    { 0x44, 0xFF }, { 0x45, 0x26 }, { 0x46, 0x05 }, { 0x40, 0x40 },
    { 0x0E, 0x06 }, { 0x20, 0x1A }, { 0x43, 0x40 }, { 0xFF, 0x00 },
    { 0x34, 0x03 }, { 0x35, 0x44 }, { 0xFF, 0x01 }, { 0x31, 0x04 },
    { 0x4B, 0x09 }, { 0x4C, 0x05 }, { 0x4D, 0x04 }, { 0xFF, 0x00 },
    { 0x44, 0x00 }, { 0x45, 0x20 }, { 0x47, 0x08 }, { 0x48, 0x28 },
    { 0x67, 0x00 }, { 0x70, 0x04 }, { 0x71, 0x01 }, { 0x72, 0xFE },
    { 0x76, 0x00 }, { 0x77, 0x00 }, { 0xFF, 0x01 }, { 0x0D, 0x01 },
    { 0xFF, 0x00 }, { 0x80, 0x01 }, { 0x01, 0xF8 }, { 0xFF, 0x01 },
    { 0x8E, 0x01 }, { 0x00, 0x01 }, { 0xFF, 0x00 }, { 0x80, 0x00 }
}

for _, setting in ipairs(DEFAULT_TUNING) do
    w8(setting[1], setting[2])
end

-- Interrupt on new sample ready, GPIO active low
w8(0x0A, 0x04)             -- SYSTEM_INTERRUPT_CONFIG_GPIO
w8(0x84, r8(0x84) & ~0x10) -- GPIO_HV_MUX_ACTIVE_HIGH
w8(0x0B, 0x01)             -- SYSTEM_INTERRUPT_CLEAR

-- Work out the current measurement timing budget from the enabled sequence
-- steps and their timeouts, following ST's driver
local sequence_config = r8(0x01)
local enables = {
    tcc = (sequence_config >> 4) & 0x1,
    dss = (sequence_config >> 3) & 0x1,
    msrc = (sequence_config >> 2) & 0x1,
    pre_range = (sequence_config >> 6) & 0x1,
    final_range = (sequence_config >> 7) & 0x1
}

local pre_range_vcsel_period_pclks = (r8(0x50) + 1) << 1
local msrc_dss_tcc_mclks = r8(0x46) + 1
local msrc_dss_tcc_us = mclks_to_us(msrc_dss_tcc_mclks, pre_range_vcsel_period_pclks)

local reg_val = r16(0x51)
local pre_range_mclks = ((reg_val & 0x00FF) << ((reg_val & 0xFF00) >> 8)) + 1
local pre_range_us = mclks_to_us(pre_range_mclks, pre_range_vcsel_period_pclks)

local final_range_vcsel_period_pclks = (r8(0x70) + 1) << 1

reg_val = r16(0x71)
local final_range_mclks = ((reg_val & 0x00FF) << ((reg_val & 0xFF00) >> 8)) + 1

if enables.pre_range > 0 then
    final_range_mclks = final_range_mclks - pre_range_mclks
end

local final_range_us = mclks_to_us(final_range_mclks, final_range_vcsel_period_pclks)

local measurement_budget_us = 1910 + 960

if enables.tcc > 0 then
    measurement_budget_us = measurement_budget_us + msrc_dss_tcc_us + 590
end

if enables.dss > 0 then
    measurement_budget_us = measurement_budget_us + 2 * (msrc_dss_tcc_us + 690)
elseif enables.msrc > 0 then
    measurement_budget_us = measurement_budget_us + msrc_dss_tcc_us + 660
end

if enables.pre_range > 0 then
    measurement_budget_us = measurement_budget_us + pre_range_us + 660
end

if enables.final_range > 0 then
    measurement_budget_us = measurement_budget_us + final_range_us + 550
end

-- Disable MSRC and TCC, then reapply the same budget so the final range
-- timeout gets recalculated for the new sequence
w8(0x01, 0xE8) -- SYSTEM_SEQUENCE_CONFIG

if measurement_budget_us < 20000 then
    error("Measurement timing budget too low")
end

local used_budget_us = 1320 + 960

if enables.tcc > 0 then
    used_budget_us = used_budget_us + msrc_dss_tcc_us + 590
end

if enables.dss > 0 then
    used_budget_us = used_budget_us + 2 * (msrc_dss_tcc_us + 690)
elseif enables.msrc > 0 then
    used_budget_us = used_budget_us + msrc_dss_tcc_us + 660
end

if enables.pre_range > 0 then
    used_budget_us = used_budget_us + pre_range_us + 660
end

if enables.final_range > 0 then
    used_budget_us = used_budget_us + 550

    local final_range_timeout_us = measurement_budget_us - used_budget_us
    local final_range_timeout_mclks = us_to_mclks(final_range_timeout_us,
        final_range_vcsel_period_pclks)

    if enables.pre_range > 0 then
        final_range_timeout_mclks = final_range_timeout_mclks + pre_range_mclks
    end

    -- Encode the timeout as (LSB << MSB) + 1
    local ls_byte = 0
    local ms_byte = 0
    local encoded_timeout = 0

    if final_range_timeout_mclks > 0 then
        ls_byte = math.floor(final_range_timeout_mclks - 1)

        while (ls_byte & 0xFFFFFF00) > 0 do
            ls_byte = ls_byte >> 1
            ms_byte = ms_byte + 1
        end

        encoded_timeout = (ms_byte << 8) | (ls_byte & 0xFF)
    end

    w16(0x71, encoded_timeout)
end

-- Single reference calibration: VHV first, then phase
w8(0x01, 0x01)        -- SYSTEM_SEQUENCE_CONFIG: VHV calibration only
w8(0x00, 0x01 | 0x40) -- SYSRANGE_START with the VHV init flag
wait_for_bits(0x13, 0x07, "Timeout during VHV calibration")
w8(0x0B, 0x01)        -- SYSTEM_INTERRUPT_CLEAR
w8(0x00, 0x00)

w8(0x01, 0x02) -- SYSTEM_SEQUENCE_CONFIG: phase calibration only
w8(0x00, 0x01)
wait_for_bits(0x13, 0x07, "Timeout during phase calibration")
w8(0x0B, 0x01)
w8(0x00, 0x00)

-- Restore the sequence config
w8(0x01, 0xE8)

print("VL53L0X initialized")

while true do
    -- Start a single shot measurement. The stop variable restores internal
    -- driver state before each trigger
    w8(0x80, 0x01)
    w8(0xFF, 0x01)
    w8(0x00, 0x00)
    w8(0x91, stop_variable)
    w8(0x00, 0x01)
    w8(0xFF, 0x00)
    w8(0x80, 0x00)
    w8(0x00, 0x01) -- SYSRANGE_START
    r8(0x00)       -- Read back once, as the reference driver flow does

    -- Wait for the sample, then read the result registers. The range in mm
    -- sits in the last two bytes. Out of range reads as 8190 or 8191
    wait_for_bits(0x13, 0x07, "Timeout waiting for measurement")
    local result = device.i2c.write_read(VL53L0X_ADDRESS, "\x14", 12)
    local distance = (string.byte(result.data, 11) << 8) | string.byte(result.data, 12)

    w8(0x0B, 0x01) -- SYSTEM_INTERRUPT_CLEAR

    print(string.format("Distance: %d mm", distance))

    -- Send the value to Superstack
    network.send_data {
        distance = distance
    }

    device.sleep(1)
end
