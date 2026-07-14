-- Reads the three touch pads on a SparkFun Qwiic CAP1203 and sends the pad
-- states to Superstack whenever they change

local CAP1203_ADDRESS = 0x28

-- Sensor requires 3.3V power
device.power.set_vout(3.3)
device.sleep(0.1)

-- Check the product ID register (0xFD), which always reads 0x6D on a CAP1203
local response = device.i2c.write_read(CAP1203_ADDRESS, "\xFD", 1)
if not response.success or response.data:byte(1) ~= 0x6D then
    error("CAP1203 not found")
end

-- Multiple touch config (0x2A): disable blocking so that simultaneous
-- touches on different pads are all reported
device.i2c.write(CAP1203_ADDRESS, "\x2A\x00")

-- Main control (0x00): clear the INT bit so touch detection starts fresh
device.i2c.write(CAP1203_ADDRESS, "\x00\x00")

print("CAP1203 running")

local last_pads = 0

while true do
    -- Sensor input status (0x03): bits 0-2 are pads 1-3
    local result = device.i2c.write_read(CAP1203_ADDRESS, "\x03", 1)

    if result.success then
        local pads = result.data:byte(1) & 0x07

        -- The status bits latch after a touch ends, so clear the INT bit to
        -- let them update again
        if pads ~= 0 then
            device.i2c.write(CAP1203_ADDRESS, "\x00\x00")
        end

        if pads ~= last_pads then
            last_pads = pads

            print(string.format("Pads: 1=%s 2=%s 3=%s",
                pads & 0x01 ~= 0, pads & 0x02 ~= 0, pads & 0x04 ~= 0))

            network.send_data {
                pad_1 = pads & 0x01 ~= 0,
                pad_2 = pads & 0x02 ~= 0,
                pad_3 = pads & 0x04 ~= 0
            }
        end
    end

    device.sleep(0.1)
end
