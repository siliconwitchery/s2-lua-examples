-- Reads the 12 wavelength channels of an AS7343 spectral sensor (e.g. the
-- SparkFun Qwiic AS7343 board) once per second and sends them to Superstack

local AS7343_I2C_ADDRESS = 0x39

-- Sensor requires 3.3V power
device.power.set_vout(3.3)

-- CFG0: set the REG_BANK bit to access the registers below 0x80
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x10")

-- ID: check the chip identification register (0x81 for the AS7343). It sits
-- below 0x80, so it must be read while REG_BANK is set
local id = device.i2c.write_read(AS7343_I2C_ADDRESS, "\x5A", 1)
if not id.success or string.byte(id.data, 1) ~= 0x81 then
    error("AS7343 not found")
end

-- ENABLE: set PON to power up the sensor core. Bit 7 of the value is a
-- reserved bit kept from the vendor init sequence
device.i2c.write(AS7343_I2C_ADDRESS, "\x80\x81")

-- CFG0: clear REG_BANK to access the registers at 0x80 and above
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")

-- CFG20: select the 18 channel auto-SMUX readout, where one measurement
-- automatically cycles the multiplexer through every photodiode channel
device.i2c.write(AS7343_I2C_ADDRESS, "\xD6\x62")

-- The vendor init sequence rewrites CFG0 after each step to keep REG_BANK
-- cleared
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")

-- ENABLE: set SP_EN along with PON to start spectral measurements
device.i2c.write(AS7343_I2C_ADDRESS, "\x80\x83")
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")

-- Channel data is 16 bits, low byte first
local function channel(data, offset)
    return string.byte(data, offset) | string.byte(data, offset + 1) << 8
end

while true do
    -- LED: turn on the white illumination LED connected to the LDR pin
    device.i2c.write(AS7343_I2C_ADDRESS, "\xCD\x80")

    -- Let the three auto-SMUX measurement cycles complete under the LED
    device.sleep(0.1)

    -- CFG0: make sure REG_BANK is still cleared before reading the data
    device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")

    -- Read all 18 channels (36 bytes) starting from DATA_0
    local response = device.i2c.write_read(AS7343_I2C_ADDRESS, "\x95", 36)

    -- LED: turn the illumination LED back off
    device.i2c.write(AS7343_I2C_ADDRESS, "\xCD\x00")

    if response.success then
        local data = response.data

        print(string.format("450nm: %d | 550nm: %d | 640nm: %d",
            channel(data, 1), channel(data, 31), channel(data, 19)))

        -- The auto-SMUX readout is three cycles of six channels each:
        --   cycle 1: FZ 450nm, FY 555nm, FXL 600nm, NIR 855nm, VIS, FD
        --   cycle 2: F2 425nm, F3 475nm, F4 515nm, F6 640nm,  VIS, FD
        --   cycle 3: F1 405nm, F7 690nm, F8 745nm, F5 550nm,  VIS, FD
        -- The byte offsets skip the VIS (visible) and FD (flicker detection)
        -- words at the end of each cycle
        network.send_data {
            ["450nm"] = channel(data, 1),
            ["555nm"] = channel(data, 3),
            ["600nm"] = channel(data, 5),
            ["855nm"] = channel(data, 7),
            ["425nm"] = channel(data, 13),
            ["475nm"] = channel(data, 15),
            ["515nm"] = channel(data, 17),
            ["640nm"] = channel(data, 19),
            ["405nm"] = channel(data, 25),
            ["690nm"] = channel(data, 27),
            ["745nm"] = channel(data, 29),
            ["550nm"] = channel(data, 31),
        }
    end

    -- Repeat every second
    device.sleep(1)
end
