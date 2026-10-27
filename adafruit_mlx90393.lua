-- Reads the raw magnetic field from an MLX90393 magnetometer (Adafruit
-- breakout, default address) and sends the X, Y and Z counts to a web service

-- Set this to the address of the web service that receives the readings
local SERVER_URL = "https://example.com/readings"

local MLX90393_ADDRESS = 0x18

-- Commands: the upper nibble is the command, the lower nibble the zyxt axis
-- select flags. 0x0E selects the Z, Y and X axes (no temperature)
local CMD_EX = 0x80 -- Exit mode
local CMD_RT = 0xF0 -- Reset
local CMD_SM = 0x30 -- Start single measurement
local CMD_RM = 0x40 -- Read measurement
local ZYX = 0x0E

-- Sensor requires 3.3V power
device.power.set_vout(3.3)
device.sleep(0.1)

-- Send a single byte command and read back the status byte plus any data.
-- Returns nil on failure
local function command(cmd, num_bytes)
    if not device.i2c.write(MLX90393_ADDRESS, string.char(cmd)).success then
        return nil
    end

    local response = device.i2c.read(MLX90393_ADDRESS, num_bytes)
    if not response.success then
        return nil
    end

    return response.data
end

-- Exit any running measurement mode before resetting. This also doubles as a
-- presence check since the MLX90393 has no ID register
local status = command(CMD_EX, 1)
if not status then
    error("No response from address 0x18. Check the wiring and port")
end
print(string.format("Exit command status: 0x%02X", status:byte(1)))
device.sleep(0.1)

status = command(CMD_RT, 1)
if not status then
    error("MLX90393 reset failed")
end
print(string.format("Reset command status: 0x%02X", status:byte(1)))
device.sleep(0.1)

while true do
    -- Start a single measurement of the Z, Y and X axes
    command(CMD_SM | ZYX, 1)

    -- Conversion completes well under 100ms with the default configuration
    device.sleep(0.1)

    -- Read back a status byte followed by two bytes per axis in X, Y, Z
    -- order. Bit 4 of the status byte flags an error
    local raw = command(CMD_RM | ZYX, 7)

    if not raw then
        print("Measurement read failed")
    elseif raw:byte(1) & 0x10 ~= 0 then
        print(string.format("Error flag set in status byte: 0x%02X", raw:byte(1)))
    else
        -- Starting at byte 2, after the status byte, read three values. In
        -- the format, > is big-endian and i2 is an int16_t
        local x, y, z = string.unpack(">i2 i2 i2", raw, 2)

        print(string.format("Status: 0x%02X, raw counts X: %d, Y: %d, Z: %d",
            raw:byte(1), x, y, z))

        -- Send the raw counts to the web service as JSON. Their scale in uT
        -- depends on the configured gain and resolution
        local body = json.encode {
            x = x,
            y = y,
            z = z
        }

        local post_response, err = network.post(SERVER_URL, body, {
            headers = { ["Content-Type"] = "application/json" }
        })

        if not post_response then
            print("Send failed: " .. err)
        end
    end

    device.sleep(2)
end
