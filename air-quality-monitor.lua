local SHT45_I2C_ADDRESS = 0x44
local ENS160_I2C_ADDRESS = 0x53

-- Enable gas sensing mode on the air quality monitor
device.i2c.write(ENS160_I2C_ADDRESS, "\x10\x02", { port = "PORTF" })

print("Reading temperature, humidity, AIQ, eCO2 and TVOC periodically")

-- Read the sensor periodically
while true do
    -- Measure the temperature and humidity
    device.i2c.write(SHT45_I2C_ADDRESS, "\xFD", { port = "PORTE" })
    device.sleep(0.01)
    response = device.i2c.read(SHT45_I2C_ADDRESS, 6, { port = "PORTE" })

    local raw_temperature = (string.byte(response.data, 1) << 8) | string.byte(response.data, 2)
    local raw_humidity = (string.byte(response.data, 4) << 8) | string.byte(response.data, 5)

    local temperature = -45 + (175 * (raw_temperature / 65535));
    local humidity = -6 + (125 * (raw_humidity / 65535));

    -- Provide calibration to the air quality sensor
    temperature_calibration = math.floor(temperature) + 273
    humidity_calibration = math.floor(humidity) << 9

    device.i2c.write(ENS160_I2C_ADDRESS, string.char(
            0x13,
            (temperature_calibration & 0x02) << 6,
            temperature_calibration >> 2),
        { port = "PORTF" })
    device.i2c.write(ENS160_I2C_ADDRESS, string.char(
            0x15,
            humidity_calibration & 0xff,
            humidity_calibration >> 8),
        { port = "PORTF" })

    -- Read the air quality sensor
    response = device.i2c.write_read(ENS160_I2C_ADDRESS, "\x21", 1, { port = "PORTF" })
    local aqi = response.value & 0x07

    response = device.i2c.write_read(ENS160_I2C_ADDRESS, "\x22", 2, { port = "PORTF" })
    local tvoc = string.byte(response.data, 1) | string.byte(response.data, 2) << 8

    response = device.i2c.write_read(ENS160_I2C_ADDRESS, "\x24", 2, { port = "PORTF" })
    local eco2 = string.byte(response.data, 1) | string.byte(response.data, 2) << 8

    -- Turn the fan on or off based on CO2 and TVOC levels
    if eco2 > 800 or tvoc > 2200 then
        device.digital.set_output("A0", true)
    else
        device.digital.set_output("A0", false)
    end

    -- Send the values to Superstack
    network.send_data {
        air_quality_index = aqi,
        carbon_dioxide = eco2,
        volatile_compounds = tvoc,
        humidity = humidity
    }

    -- Sleep for a few seconds
    device.sleep(3)
end
