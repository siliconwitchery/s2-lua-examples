local INA237_ADDRESS = 0x40

-- Set the IO to 3.3V
device.power.set_vout(3.3)

-- Check for device
print("Starting power sensor")

local response = device.i2c.write_read(INA237_ADDRESS, "\x3E", 2, { port = 'PORTE' })

if not response.success then
    error("Device not found")
end

if string.byte(response.data, 1) ~= 0x54 or string.byte(response.data, 2) ~= 0x49 then
    error("Incorrect manufacturer ID")
end

-- Current resolution
local current_lsb = (10 / 32768)

-- Set shunt calibration register
local shunt_cal = 819.2e6 * current_lsb * 0.015

local shunt_cal_uint16 = math.floor(shunt_cal) % 0x10000

local shunt_cal_uint16_low_byte = shunt_cal_uint16 % 0x100
local shunt_cal_uint16_high_byte = math.floor(shunt_cal_uint16 / 0x100)

device.i2c.write(INA237_ADDRESS, string.char(0x02, shunt_cal_uint16_high_byte, shunt_cal_uint16_low_byte),
    { port = 'PORTE' })

-- Set ADC config register (AVG=16, everything else is default)
device.i2c.write(INA237_ADDRESS, "\x01\xFB\x6A", { port = 'PORTE' })

-- Read sensor and send the data periodically
print("Sensor configured. Reading periodically")

while true do
    -- Read bus voltage
    response = device.i2c.write_read(INA237_ADDRESS, "\x05", 2, { port = 'PORTE' })

    local voltage_uint16 = (string.byte(response.data, 1) << 8) | string.byte(response.data, 2)
    local voltage = voltage_uint16 * 3.125e-3

    -- Read current
    response = device.i2c.write_read(INA237_ADDRESS, "\x07", 2, { port = 'PORTE' })

    local current_int16 = (string.byte(response.data, 1) << 8) | string.byte(response.data, 2)
    local current = current_int16 * current_lsb

    -- Read power
    response = device.i2c.write_read(INA237_ADDRESS, "\x08", 3, { port = 'PORTE' })

    local power_int24 = (string.byte(response.data, 1) << 16) | (string.byte(response.data, 2) << 8) |
        string.byte(response.data, 3)
    local power = power_int24 * current_lsb * 0.2

    -- Send data
    network.send_data {
        voltage = voltage,
        current = current,
        power = power
    }

    device.sleep(3)
end
