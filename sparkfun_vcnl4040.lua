-- Read ambient light from a VCNL4040 and send it to a web service.
-- Registers are 16-bit little-endian and are accessed by writing the command
-- code as one transaction, then reading two bytes (lsb then msb) as another

-- Set this to the address of the web service that receives the readings
local SERVER_URL = "https://example.com/readings"

local VCNL4040_ADDRESS = 0x60

-- Sensor requires 3.3V power
device.power.set_vout(3.3)
device.sleep(0.1)

-- Probe the ID register (0x0C), which always reads 0x86 0x01
if not device.i2c.write(VCNL4040_ADDRESS, "\x0C").success then
    error("No response from address 0x60. Check the wiring and port")
end

local id = device.i2c.read(VCNL4040_ADDRESS, 2)

if not id.success then
    error("Failed to read the ID register")
end

print(string.format("ID register: 0x%02X 0x%02X", id.data:byte(1), id.data:byte(2)))

-- In the format, < is little-endian and I2 is a uint16_t
if string.unpack("<I2", id.data) ~= 0x0186 then
    error("Unexpected device ID. Expected 0x86 0x01")
end

-- ALS_CONF (0x00): 80ms integration time, interrupts off, ALS powered on. The
-- high byte is reserved and must stay 0. The sensor boots with the ALS shut
-- down, so this write is what actually starts it
device.i2c.write(VCNL4040_ADDRESS, "\x00\x00\x00")

-- Let the first 80ms integration complete
device.sleep(0.1)

while true do
    -- Read the raw counts from the ALS output register (0x09)
    device.i2c.write(VCNL4040_ADDRESS, "\x09")
    local result = device.i2c.read(VCNL4040_ADDRESS, 2)

    if result.success then
        local counts = string.unpack("<I2", result.data)

        -- At 80ms integration time each count is 0.1 lux
        local light = counts * 0.1

        print(string.format("ALS register: %d counts", counts))

        -- Send the value to the web service as JSON
        local body = json.encode {
            light = light
        }

        local post_response, err = network.post(SERVER_URL, body, {
            headers = { ["Content-Type"] = "application/json" }
        })

        if not post_response then
            print("Send failed: " .. err)
        end
    else
        print("ALS read failed")
    end

    -- Repeat every 2 seconds
    device.sleep(2)
end
