-- Reads bus voltage, current and power from an Adafruit INA237 breakout
-- connected to port E, and sends the values to Superstack

local INA237_ADDRESS = 0x40

local PORT = { port = "PORTE" }

-- Current per LSB when scaled for a 10A maximum measurable current
local CURRENT_LSB = 10 / 32768

-- The Adafruit breakout has a 15 mOhm shunt resistor
local SHUNT_OHMS = 0.015

-- Sensor requires 3.3V power
device.power.set_vout(3.3)

-- The manufacturer ID register should always read "TI" (0x54 0x49)
local response = device.i2c.write_read(INA237_ADDRESS, "\x3E", 2, PORT)

if not response.success or response.data ~= "TI" then
    error("INA237 not found on port E")
end

-- SHUNT_CAL = 819.2e6 * CURRENT_LSB * R_SHUNT per the datasheet. This scales
-- the current and power registers to the shunt fitted on the board
local shunt_cal = math.floor(819.2e6 * CURRENT_LSB * SHUNT_OHMS)

device.i2c.write(INA237_ADDRESS, string.char(0x02, (shunt_cal >> 8) & 0xFF, shunt_cal & 0xFF),
    PORT)

-- ADC config: continuous bus voltage, shunt and temperature, 16x averaging
device.i2c.write(INA237_ADDRESS, "\x01\xFB\x6A", PORT)

print("INA237 configured. Reading periodically")

while true do
    local voltage_reg = device.i2c.write_read(INA237_ADDRESS, "\x05", 2, PORT)
    local current_reg = device.i2c.write_read(INA237_ADDRESS, "\x07", 2, PORT)
    local power_reg = device.i2c.write_read(INA237_ADDRESS, "\x08", 3, PORT)

    if voltage_reg.success and current_reg.success and power_reg.success then
        -- Bus voltage is 3.125mV per LSB
        local voltage = ((string.byte(voltage_reg.data, 1) << 8) | string.byte(voltage_reg.data, 2)) * 3.125e-3

        -- Current is a signed 16 bit value of CURRENT_LSB amps per LSB
        local raw_current = (string.byte(current_reg.data, 1) << 8) | string.byte(current_reg.data, 2)
        if raw_current > 32767 then
            raw_current = raw_current - 65536
        end
        local current = raw_current * CURRENT_LSB

        -- Power is a 24 bit value of 0.2 * CURRENT_LSB watts per LSB
        local raw_power = (string.byte(power_reg.data, 1) << 16) |
            (string.byte(power_reg.data, 2) << 8) |
            string.byte(power_reg.data, 3)
        local power = raw_power * 0.2 * CURRENT_LSB

        print(string.format("%.3fV | %.3fA | %.3fW", voltage, current, power))

        -- Send the values to Superstack
        network.send_data {
            voltage = voltage,
            current = current,
            power = power
        }
    else
        print("Sensor read error")
    end

    device.sleep(3)
end
