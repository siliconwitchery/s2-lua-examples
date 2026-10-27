-- Reads bus voltage, current and power from an Adafruit INA237 breakout
-- connected to port E, and sends the values to a web service

-- Set this to the address of the web service that receives the readings
local SERVER_URL = "https://example.com/readings"

local INA237_ADDRESS = 0x40

local PORT = { port = "PORTE" }

-- Current per LSB when scaled for a 10A maximum measurable current
local CURRENT_LSB = 10 / 32768

-- The Adafruit breakout has a 15 mOhm shunt resistor
local SHUNT_OHMS = 0.015

-- Sensor requires 3.3V power
device.power.set_vout(3.3)

-- Probe the manufacturer ID register (0x3E), which always reads "TI"
local response = device.i2c.write_read(INA237_ADDRESS, "\x3E", 2, PORT)

if not response.success then
    error("No response from address 0x40 on port E. Check the wiring")
end

print(string.format("Manufacturer ID: 0x%02X 0x%02X", response.data:byte(1), response.data:byte(2)))

if response.data ~= "TI" then
    error("Unexpected manufacturer ID. Expected 0x54 0x49")
end

-- SHUNT_CAL = 819.2e6 * CURRENT_LSB * R_SHUNT per the datasheet. This scales
-- the current and power registers to the shunt fitted on the board
local shunt_cal = math.floor(819.2e6 * CURRENT_LSB * SHUNT_OHMS)

-- Register 0x02 then the value. In the format, > is big-endian, B is a
-- uint8_t and I2 is a uint16_t
device.i2c.write(INA237_ADDRESS, string.pack(">B I2", 0x02, shunt_cal), PORT)

-- ADC config: continuous bus voltage, shunt and temperature, 16x averaging
device.i2c.write(INA237_ADDRESS, "\x01\xFB\x6A", PORT)

print("INA237 configured. Reading periodically")

while true do
    local voltage_reg = device.i2c.write_read(INA237_ADDRESS, "\x05", 2, PORT)
    local current_reg = device.i2c.write_read(INA237_ADDRESS, "\x07", 2, PORT)
    local power_reg = device.i2c.write_read(INA237_ADDRESS, "\x08", 3, PORT)

    if voltage_reg.success and current_reg.success and power_reg.success then
        -- Bus voltage is 3.125mV per LSB
        local voltage_word = string.unpack(">I2", voltage_reg.data)
        local voltage = voltage_word * 3.125e-3

        -- Current is a signed 16 bit value of CURRENT_LSB amps per LSB, so
        -- the same two bytes are read again as an int16_t (i2)
        local current_word = string.unpack(">I2", current_reg.data)
        local current = string.unpack(">i2", current_reg.data) * CURRENT_LSB

        -- Power is a 24 bit value of 0.2 * CURRENT_LSB watts per LSB
        local raw_power = (string.byte(power_reg.data, 1) << 16) |
            (string.byte(power_reg.data, 2) << 8) |
            string.byte(power_reg.data, 3)
        local power = raw_power * 0.2 * CURRENT_LSB

        print(string.format("VBUS: 0x%04X (%.3f V) | CURRENT: 0x%04X (%.3f A) | POWER: 0x%06X (%.3f W)",
            voltage_word, voltage, current_word, current, raw_power, power))

        -- Send the values to the web service as JSON
        local body = json.encode {
            voltage = voltage,
            current = current,
            power = power
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
