-- Reads the ambient temperature from an MCP9808 sensor and sends it to a web
-- service every 5 seconds

-- Set this to the address of the web service that receives the readings
local SERVER_URL = "https://example.com/readings"

local MCP9808_ADDRESS = 0x18

-- Sensor requires 3.3V power. Let the rail settle before probing
device.power.set_vout(3.3)
device.sleep(0.1)

-- Probe the manufacturer ID register (0x06), which always reads 0x00 0x54
local id = device.i2c.write_read(MCP9808_ADDRESS, "\x06", 2)

if not id.success then
    error("No response from address 0x18. Check the wiring and port")
end

print(string.format("Manufacturer ID: 0x%02X 0x%02X", id.data:byte(1), id.data:byte(2)))

if id.data:byte(1) ~= 0x00 or id.data:byte(2) ~= 0x54 then
    error("Unexpected manufacturer ID. Expected 0x00 0x54")
end

while true do
    -- Read two bytes from the ambient temperature register (0x05)
    local result = device.i2c.write_read(MCP9808_ADDRESS, "\x05", 2)

    if result.success then
        local value = string.unpack(">I2", result.data) -- big-endian uint16_t

        -- The upper 3 bits are alert flags and bit 12 is the sign, leaving a
        -- 12 bit temperature in steps of 1/16th of a degree
        local temperature = (value & 0x0FFF) / 16.0

        -- Apply two's complement for temperatures below 0 C
        if value & 0x1000 ~= 0 then
            temperature = temperature - 256
        end

        print(string.format("Temperature register: 0x%04X (%.2f C)", value, temperature))

        -- Send the value to the web service as JSON
        local body = json.encode {
            temperature = temperature
        }

        local post_response, err = network.post(SERVER_URL, body, {
            headers = { ["Content-Type"] = "application/json" }
        })

        if not post_response then
            print("Send failed: " .. err)
        end
    end

    -- Repeat every 5 seconds
    device.sleep(5)
end
