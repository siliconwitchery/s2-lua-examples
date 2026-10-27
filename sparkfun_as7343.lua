-- Reads the 12 wavelength channels of an AS7343 spectral sensor (e.g. the
-- SparkFun Qwiic AS7343 board) once per second and sends them to a web
-- service

-- Set this to the address of the web service that receives the readings
local SERVER_URL = "https://example.com/readings"

local AS7343_I2C_ADDRESS = 0x39

-- Sensor requires 3.3V power
device.power.set_vout(3.3)

-- CFG0: set the REG_BANK bit to access the registers below 0x80
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x10")

-- Probe the chip identification register (0x5A), which always reads 0x81 on
-- an AS7343. It sits below 0x80, so it must be read while REG_BANK is set
local id = device.i2c.write_read(AS7343_I2C_ADDRESS, "\x5A", 1)

if not id.success then
    error("No response from address 0x39. Check the wiring and port")
end

print(string.format("ID register: 0x%02X", string.byte(id.data, 1)))

if string.byte(id.data, 1) ~= 0x81 then
    error("Unexpected chip ID. Expected 0x81")
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
        -- Each channel is a little-endian uint16_t, so channel n starts at
        -- byte 2n - 1
        local channels = {}

        for n = 1, 18 do
            channels[n] = string.unpack("<I2", response.data, 2 * n - 1)
        end

        print(string.format("Counts: 450nm=%d 550nm=%d 640nm=%d",
            channels[1], channels[16], channels[10]))

        -- The auto-SMUX readout is three cycles of six channels each:
        --   cycle 1: FZ 450nm, FY 555nm, FXL 600nm, NIR 855nm, VIS, FD
        --   cycle 2: F2 425nm, F3 475nm, F4 515nm, F6 640nm,  VIS, FD
        --   cycle 3: F1 405nm, F7 690nm, F8 745nm, F5 550nm,  VIS, FD
        -- The indices skip the VIS (visible) and FD (flicker detection)
        -- words at the end of each cycle. Send them to the web service as JSON
        local body = json.encode {
            ["450nm"] = channels[1],
            ["555nm"] = channels[2],
            ["600nm"] = channels[3],
            ["855nm"] = channels[4],
            ["425nm"] = channels[7],
            ["475nm"] = channels[8],
            ["515nm"] = channels[9],
            ["640nm"] = channels[10],
            ["405nm"] = channels[13],
            ["690nm"] = channels[14],
            ["745nm"] = channels[15],
            ["550nm"] = channels[16],
        }

        local post_response, err = network.post(SERVER_URL, body, {
            headers = { ["Content-Type"] = "application/json" }
        })

        if not post_response then
            print("Send failed: " .. err)
        end
    else
        print("Data read failed")
    end

    -- Repeat every second
    device.sleep(1)
end
