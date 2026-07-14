-- Read ambient light from a VCNL4040 and send it to Superstack.
-- Registers are 16-bit little-endian: write [reg, lsb, msb], reads return lsb then msb

local VCNL4040_ADDRESS = 0x60

-- Sensor requires 3.3V power
device.power.set_vout(3.3)
device.sleep(0.1)

-- The ID register (0x0C) always reads 0x0186
local id = device.i2c.write_read(VCNL4040_ADDRESS, "\x0C", 2)
if not id.success or (id.data:byte(1) | (id.data:byte(2) << 8)) ~= 0x0186 then
    error("VCNL4040 not found")
end

-- ALS_CONF (0x00): 80ms integration time, interrupts off, ALS powered on
device.i2c.write(VCNL4040_ADDRESS, "\x00\x00\x00")

-- Let the first 80ms integration complete
device.sleep(0.1)

while true do
    -- Read the raw counts from the ALS output register (0x09)
    local result = device.i2c.write_read(VCNL4040_ADDRESS, "\x09", 2)

    if result.success then
        local counts = result.data:byte(1) | (result.data:byte(2) << 8)

        -- At 80ms integration time each count is 0.1 lux
        local light = counts * 0.1

        print(string.format("Light: %.1f lux", light))

        -- Send the value to Superstack
        network.send_data {
            light = light
        }
    end

    -- Repeat every 2 seconds
    device.sleep(2)
end
