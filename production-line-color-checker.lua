AS7343_I2C_ADDRESS = 0x39

-- Set the IO to 3.3V
device.power.set_vout(3.3)

-- Configure the color sensor
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x10")
device.i2c.write(AS7343_I2C_ADDRESS, "\x80\x81")
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")
device.i2c.write(AS7343_I2C_ADDRESS, "\xD6\x62")
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")
device.i2c.write(AS7343_I2C_ADDRESS, "\x80\x83")
device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")

-- Read the sensor periodically
while true do
    resp = device.i2c.write(AS7343_I2C_ADDRESS, "\xCD\x80")
    device.sleep(0.1)
    device.i2c.write(AS7343_I2C_ADDRESS, "\xBF\x00")

    resp = device.i2c.write_read(AS7343_I2C_ADDRESS, "\x95", 36)
    device.i2c.write(AS7343_I2C_ADDRESS, "\xCD\x00")

    network.send_data {
        ["450nm"] = string.byte(resp.data, 1) << 8 | string.byte(resp.data, 2),
        ["555nm"] = string.byte(resp.data, 3) << 8 | string.byte(resp.data, 4),
        ["600nm"] = string.byte(resp.data, 5) << 8 | string.byte(resp.data, 6),
        ["855nm"] = string.byte(resp.data, 7) << 8 | string.byte(resp.data, 8),
        ["425nm"] = string.byte(resp.data, 13) << 8 | string.byte(resp.data, 14),
        ["475nm"] = string.byte(resp.data, 15) << 8 | string.byte(resp.data, 16),
        ["515nm"] = string.byte(resp.data, 17) << 8 | string.byte(resp.data, 18),
        ["640nm"] = string.byte(resp.data, 19) << 8 | string.byte(resp.data, 20),
        ["405nm"] = string.byte(resp.data, 25) << 8 | string.byte(resp.data, 26),
        ["690nm"] = string.byte(resp.data, 27) << 8 | string.byte(resp.data, 28),
        ["745nm"] = string.byte(resp.data, 29) << 8 | string.byte(resp.data, 30),
        ["550nm"] = string.byte(resp.data, 31) << 8 | string.byte(resp.data, 32),
    }

    device.sleep(1)
end
