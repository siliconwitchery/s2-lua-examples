device.power.set_vout(3.3)
device.sleep(1)


local CAP1203 = {}
CAP1203.ADDR = 0x28   -- SparkFun Qwiic CAP1203 fixed address

local cfg = {scl_pin="A1", sda_pin="A0", frequency=100}

local function write_reg(reg, value)
    device.i2c.write(CAP1203.ADDR, string.char(reg, value), cfg)
end

local function read_reg(reg)
    device.i2c.write(CAP1203.ADDR, string.char(reg), cfg)
    local result = device.i2c.read(CAP1203.ADDR, 1, cfg)

    if not result or not result.data or #result.data == 0 then
        return 0
    end

    return result.data:byte(1)
end

---------------------------------------------------------
-- Init CAP1203
---------------------------------------------------------
function CAP1203.init()
    write_reg(0x00, 0x00)
    device.sleep(0.05)

    write_reg(0x21, 0x07)
    write_reg(0x2A, 0x00)
    write_reg(0x1F, 0x40)
    write_reg(0x00, 0x00)

    device.sleep(0.05)
end

---------------------------------------------------------
-- Read touch status
---------------------------------------------------------
function CAP1203.getTouch()
    local status = read_reg(0x03)

    -- Clear interrupt so the sensor can detect new touches
    if status ~= 0 then
        write_reg(0x00, 0x00)
    end

    return status & 0x07
end


---------------------------------------------------------
-- MAIN TEST LOOP, this is very slow with the prints, would most likely get better feedback with a LED screen for example.
---------------------------------------------------------

print("Init CAP1203...")
CAP1203.init()

while true do
    local t = CAP1203.getTouch()

    if t ~= 0 then
        if (t & 0x01) ~= 0 then print("Pad 1 touched") end
        if (t & 0x02) ~= 0 then print("Pad 2 touched") end
        if (t & 0x04) ~= 0 then print("Pad 3 touched") end
    end

    device.sleep(0.1)
end
