-- Bit-bang I2C on A0 (SDA) and A1 (SCL) with OPEN-DRAIN

device.power.set_vout(3.3)
device.sleep(1)

local SDA = "A0"
local SCL = "A1"

local function i2c_delay()
    device.sleep(0.0002)
end

-- OPEN-DRAIN IMPLEMENTATION

local function sda_high()
    device.digital.get_input(SDA, {pull="PULL_UP"})
end

local function sda_low()
    device.digital.set_output(SDA, false)
end

local function scl_high()
    device.digital.get_input(SCL, {pull="PULL_UP"})
end

local function scl_low()
    device.digital.set_output(SCL, false)
end

local function sda_read()
    return device.digital.get_input(SDA, {pull="PULL_UP"})
end

-- START / STOP
local function i2c_start()
    sda_high()
    scl_high()
    i2c_delay()
    sda_low()
    i2c_delay()
    scl_low()
end

local function i2c_stop()
    sda_low()
    scl_high()
    i2c_delay()
    sda_high()
    i2c_delay()
end

-- WRITE BYTE
local function i2c_write_byte(b)
    for i = 7, 0, -1 do
        if (b >> i) & 1 == 1 then sda_high() else sda_low() end
        i2c_delay()
        scl_high()
        i2c_delay()
        scl_low()
    end

    sda_high()
    i2c_delay()
    scl_high()
    local ack = not sda_read()
    scl_low()
    return ack
end

-- READ BYTE
local function i2c_read_byte(ack)
    local value = 0
    sda_high()

    for i = 7, 0, -1 do
        scl_high()
        i2c_delay()
        if sda_read() then value = value | (1 << i) end
        scl_low()
        i2c_delay()
    end

    if ack then sda_low() else sda_high() end
    i2c_delay()
    scl_high()
    i2c_delay()
    scl_low()
    sda_high()

    return value
end

-- VCNL4040 REGISTER ACCESS
local VCNL_ADDR = 0x60

local function vcnl_read_register(reg)
    i2c_start()
    i2c_write_byte(VCNL_ADDR << 1)
    i2c_write_byte(reg)
    i2c_start()
    i2c_write_byte((VCNL_ADDR << 1) | 1)
    local lsb = i2c_read_byte(true)
    local msb = i2c_read_byte(false)
    i2c_stop()
    return msb * 256 + lsb
end

local function vcnl_write_register(reg, lsb, msb)
    i2c_start()
    i2c_write_byte(VCNL_ADDR << 1)
    i2c_write_byte(reg)
    i2c_write_byte(lsb)
    i2c_write_byte(msb)
    i2c_stop()
end

local function vcnl_init()
    print("Init VCNL4040...")

    -- ALS_CONF: ALS enable, 16-bit, 100ms integration
    vcnl_write_register(0x00, 0x00, 0x10)

    print("Init done.")
end

local function vcnl_read_als()
    return vcnl_read_register(0x09)
end

-- TEST PROGRAM
vcnl_init()

-- CHECK ID
local id = vcnl_read_register(0x0C)
print(string.format("ID: %.2f", id))

-- This example only makes use of the ALS values
while true do
    local als = vcnl_read_als()

    print(string.format("ALS: %.2f", als))

    device.sleep(1)
end

