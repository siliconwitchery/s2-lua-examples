device.power.set_vout(3.3)
device.sleep(1)

local MLX = {}
MLX.addr = 0x18   -- Adafruit default address

-- Commands
local CMD_SM = 0x30
local CMD_RM = 0x40
local CMD_RT = 0xF0
local CMD_EX = 0x80

-- Adafruit uses ZYX only (no temperature)
local FLAG_X = 0x02
local FLAG_Y = 0x04
local FLAG_Z = 0x08
local ZYX = FLAG_Z + FLAG_Y + FLAG_X   -- 0x0E

local function write_read(cmd, rx_len)
    device.i2c.write(MLX.addr, string.char(cmd))

    local r = device.i2c.read(MLX.addr, rx_len)

    if not r.success then return nil end
    return r.data
end

local function to_int16(hi, lo)
    local v = hi * 256 + lo
    if v >= 32768 then v = v - 65536 end
    return v
end

function MLX.init()
    write_read(CMD_RT, 1)
    device.sleep(0.5)
    write_read(CMD_EX, 1)
    device.sleep(0.5)
end

function MLX.readXYZ()
    -- Start measurement
    write_read(CMD_SM + ZYX, 1)
    device.sleep(0.5)

    -- Read measurement
    local raw = write_read(CMD_RM + ZYX, 1 + 6)
    if not raw then return nil end

    return {
        x = to_int16(raw:byte(2), raw:byte(3)),
        y = to_int16(raw:byte(4), raw:byte(5)),
        z = to_int16(raw:byte(6), raw:byte(7))
    }
end

MLX.init()

while true do
    local d = MLX.readXYZ()
    if d then
        print(string.format("X:%d Y:%d Z:%d", d.x, d.y, d.z))
    else
        print("I2C read failed")
    end
    device.sleep(1)
end
