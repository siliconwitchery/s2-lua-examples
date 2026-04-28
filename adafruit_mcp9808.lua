local MCP9808_ADDRESS = 0x18

-- Sensor requires 3.3V power
device.power.set_vout(3.3)

while true do
    -- Read two bytes from the 0x05 register
    local result = device.i2c.write_read(MCP9808_ADDRESS, "\x05", 2)

    if result.success then
        print("Read 2 bytes from register 0x05")

        -- Convert the 16bit data into a temperature value
        local upper = result.data:byte(1)
        local lower = result.data:byte(2)
        local temperature = ((upper & 0x1F) * 256 + lower) / 16.0

        -- Send the value to Superstack
        network.send_data {
            temperature = temperature
        }
    end

    -- Repeat every 5 seconds
    device.sleep(5)
end
