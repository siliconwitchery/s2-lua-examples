device.power.battery.set_charger_cv_cc(4.2, 700)
device.power.set_vout(3.3)
device.sleep(3)

local LCD_ADDR = 0x3C
local ST25_ADDR = 0x53
local MCP_ADDR = 0x18
local ENS160_ADDR = 0x53

local DISPLAY_OFF = "\xAE"
local DISPLAY_ON = "\xAF"
local SET_CLK = "\xD5\x80"
local SET_MULTIPLEX = "\xA8\x1F"
local SET_OFFSET = "\xD3\x00"
local SET_START_LINE = "\x40"
local EN_CHARGE_PUMP = "\x8D\x14"
local SET_MEMADDR_MODE = "\x20\x00"
local SET_SEG_REMAP = "\xA0"
local SET_COMSCAN_DIR = "\xC0"
local SET_COMPIN_CONFIG = "\xDA\x02"
local SET_CONTRAST = "\x81\xCF"
local SET_PRE_CHARGE = "\xD9\xF1"
local SET_VCOMH = "\xDB\x40"
local NORMAL_MODE = "\xA4"
local SET_DISPLAY_NORMAL = "\xA6"
local SET_DISPLAY_INVERT = "\xA7"

---------------------------
-- Helper function to send LCD command
---------------------------
local function lcd_cmd(i2c_addr, c, port)
    device.i2c.write(i2c_addr, "\x00" .. c, { port=port, frequency=100 })
end

---------------------------
-- Helper function for general I2C writes
---------------------------
local function i2c_write(i2c_addr, data, port)
    device.i2c.write(i2c_addr, data, { port=port, frequency=100 })
end

---------------------------
-- Clear LCD function
---------------------------
local function lcd_clear()
    lcd_cmd(LCD_ADDR, "\x21\x00\x7F", "PORTF")
    lcd_cmd(LCD_ADDR, "\x22\x00\x03", "PORTF")

    local blank = "\x40" .. string.rep("\x00", 128)

    for i = 1, 4 do
        i2c_write(LCD_ADDR, blank, "PORTF")
    end
end

---------------------------
-- init function LCD
---------------------------
local function lcd_init()
    lcd_cmd(LCD_ADDR, DISPLAY_OFF, "PORTF")
    lcd_cmd(LCD_ADDR, SET_CLK, "PORTF")
    lcd_cmd(LCD_ADDR, SET_MULTIPLEX, "PORTF")
    lcd_cmd(LCD_ADDR, SET_OFFSET, "PORTF")
    lcd_cmd(LCD_ADDR, SET_START_LINE, "PORTF")
    lcd_cmd(LCD_ADDR, EN_CHARGE_PUMP, "PORTF")
    lcd_cmd(LCD_ADDR, SET_MEMADDR_MODE, "PORTF")
    lcd_cmd(LCD_ADDR, SET_SEG_REMAP, "PORTF")
    lcd_cmd(LCD_ADDR, SET_COMSCAN_DIR, "PORTF")
    lcd_cmd(LCD_ADDR, SET_COMPIN_CONFIG, "PORTF")
    lcd_cmd(LCD_ADDR, SET_CONTRAST, "PORTF")
    lcd_cmd(LCD_ADDR, SET_PRE_CHARGE, "PORTF")
    lcd_cmd(LCD_ADDR, SET_VCOMH, "PORTF")
    lcd_cmd(LCD_ADDR, NORMAL_MODE, "PORTF")
    lcd_cmd(LCD_ADDR, SET_DISPLAY_NORMAL, "PORTF")
    lcd_cmd(LCD_ADDR, DISPLAY_ON, "PORTF")
end

---------------------------
-- Fonts for LCD screen
---------------------------
local font = {
    ["0"] = "\x3E\x51\x49\x45\x3E",
    ["1"] = "\x00\x42\x7F\x40\x00",
    ["2"] = "\x42\x61\x51\x49\x46",
    ["3"] = "\x21\x41\x45\x4B\x31",
    ["4"] = "\x18\x14\x12\x7F\x10",
    ["5"] = "\x27\x45\x45\x45\x39",
    ["6"] = "\x3C\x4A\x49\x49\x30",
    ["7"] = "\x01\x71\x09\x05\x03",
    ["8"] = "\x36\x49\x49\x49\x36",
    ["9"] = "\x06\x49\x49\x29\x1E",
    ["C"] = "\x3E\x41\x41\x41\x22",
    ["G"] = "\x3E\x41\x41\x49\x7A",
    ["O"] = "\x3E\x41\x41\x41\x3E",
    ["S"] = "\x46\x49\x49\x49\x31",
    ["T"] = "\x01\x01\x7F\x01\x01",
    ["V"] = "\x1F\x20\x40\x20\x1F",
    ["W"] = "\x3F\x40\x38\x40\x3F",
    ["a"] = "\x20\x54\x54\x54\x78",
    ["c"] = "\x38\x44\x44\x44\x20",
    ["e"] = "\x38\x54\x54\x54\x18",
    ["f"] = "\x08\x7E\x09\x01\x02",
    ["h"] = "\x7F\x08\x04\x04\x78",
    ["i"] = "\x00\x44\x7D\x40\x00",
    ["k"] = "\x7F\x10\x28\x44\x00",
    ["l"] = "\x00\x41\x7F\x40\x00",
    ["m"] = "\x7C\x04\x18\x04\x78",
    ["n"] = "\x7C\x08\x04\x04\x78",
    ["o"] = "\x38\x44\x44\x44\x38",
    ["p"] = "\x7C\x14\x14\x14\x08",
    ["r"] = "\x7C\x08\x04\x04\x08",
    ["s"] = "\x48\x54\x54\x54\x20",
    ["t"] = "\x04\x3F\x44\x40\x20",
    ["u"] = "\x3C\x40\x40\x20\x7C",
    ["y"] = "\x0C\x50\x50\x50\x3C",
    [" "] = "\x00\x00\x00\x00\x00",
    ["*"] = "\x06\x09\x09\x06\x00",
    ["."] = "\x00\x60\x60\x00\x00",
    [":"] = "\x00\x36\x36\x00\x00",
    ["'"] = "\x00\x00\x07\x00\x00",
    ["!"] = "\x00\x00\x5F\x00\x00",
    ["%"] = "\x23\x13\x08\x64\x62"
}

---------------------------
-- Function to write text to lcd
---------------------------
local function lcd_write_text(text, row)
    row = row or 0
    while #text < 20 do text = text .. " " end

    lcd_cmd(LCD_ADDR, "\x21\x00\x7F", "PORTF")
    lcd_cmd(LCD_ADDR, "\x22" .. string.char(row) .. string.char(row), "PORTF")

    local out = "\x40"
    for i = 1, #text do
        local ch = text:sub(i,i)
        out = out .. (font[ch] or "\x00\x00\x00\x00\x00") .. "\x00"
    end

    i2c_write(LCD_ADDR, out, "PORTF")
end

local function toggle_lcd(state)
    if state == "OFF" then
        lcd_cmd(LCD_ADDR, DISPLAY_OFF, "PORTF")
    elseif state == "ON" then
        lcd_cmd(LCD_ADDR, DISPLAY_ON, "PORTF") 
    end
end

---------------------------
-- setup NFC sensor
---------------------------
local function setup_NFC()
    local url = "linkedin.com/in/siliconwitch"
    local ndef = "\xE1\x40\x40\x00"
               .. "\x03"
               .. string.char(#url + 5)
               .. "\xD1\x01"
               .. string.char(#url + 1)
               .. "\x55\x03"
               .. url
               .. "\xFE"

    i2c_write(ST25_ADDR, "\x00\x00" .. ndef, "PORTF")
end

---------------------------
-- function to write LCD text "in between row 0 and 1"
---------------------------
local function lcd_write_text_offset(text, offset)
    while #text < 20 do text = text .. " " end

    local top = "\x40"
    local bot = "\x40"

    for i = 1, #text do
        local ch = text:sub(i,i)
        local glyph = font[ch] or "\x00\x00\x00\x00\x00"

        for col = 1, 5 do
            local byte = glyph:byte(col)
            top = top .. string.char((byte << offset) & 0xFF)
            bot = bot .. string.char(byte >> (8 - offset))
        end
        top = top .. "\x00"
        bot = bot .. "\x00"
    end

    lcd_cmd(LCD_ADDR, "\x21\x00\x7F", "PORTF")
    lcd_cmd(LCD_ADDR, "\x22\x00\x00", "PORTF")
    i2c_write(LCD_ADDR, top, "PORTF")

    lcd_cmd(LCD_ADDR, "\x21\x00\x7F", "PORTF")
    lcd_cmd(LCD_ADDR, "\x22\x01\x01", "PORTF")
    i2c_write(LCD_ADDR, bot, "PORTF")
end

---------------------------
-- read NFC sensor - if phone is present
---------------------------
local function read_phone()
    local reg_lo_dyn = 0x05
    local reg_hi_dyn = 0x20
    local present = false

    i2c_write(ST25_ADDR, string.char(reg_hi_dyn, reg_lo_dyn), "PORTF")

    local result = device.i2c.read(ST25_ADDR, 1, { port="PORTF", frequency=100 })

    if result.success then
        if (result.value & 0x10) ~= 0 then
            present = true
        end
    end

    return present
end

---------------------------
-- read temp sensor
---------------------------
local function read_temp()
    i2c_write(MCP_ADDR, "\x05", "PORTF")

    local result = device.i2c.read(0x18, 2, { port="PORTF", frequency=100 })
    local upper = result.data:byte(1)
    local lower = result.data:byte(2)

    return ((upper & 0x1F) * 256 + lower) / 16.0
end

---------------------------
-- init air quality sensor
---------------------------
local function init_ENS160(temperature)
    local humidity = 50
    local temperature_calibration = math.floor(temperature + 273)
    local humidity_calibration = math.floor(humidity) << 9

    i2c_write(ENS160_ADDR, "\x10\x02", "PORTE")

    i2c_write(ENS160_ADDR, string.char(
        0x13,
        (temperature_calibration & 0x02) << 6,
        temperature_calibration >> 2), "PORTE")

    i2c_write(ENS160_ADDR, string.char(
        0x15,
        humidity_calibration & 0xff,
        humidity_calibration >> 8), "PORTE")
end

---------------------------
-- read air quality sensor
---------------------------
local function read_ENS160(temperature)
    local response

    response = device.i2c.write_read(ENS160_ADDR, "\x21", 1, { port="PORTE" })
    local aqi = response.value & 0x07

    response = device.i2c.write_read(ENS160_ADDR, "\x22", 2, { port="PORTE" })
    local tvoc = string.byte(response.data, 1) | string.byte(response.data, 2) << 8

    response = device.i2c.write_read(ENS160_ADDR, "\x24", 2, { port="PORTE" })
    local eco2 = string.byte(response.data, 1) | string.byte(response.data, 2) << 8

    return {aqi, tvoc, eco2}
end

---------------------------
-- main code
---------------------------
lcd_clear()
lcd_init()
lcd_clear()

local phone_prev = false
local power_save_counter = 0
local power_save_duration = 200 -- 20 sec active for test (600 for 1 min)
local total_scans = 0

local eco2_warning = 1000
local eco2_blink_count = 0

local temp_warning = 26
local temp_blink_count = 0

local data_log_ceiling = 6000 -- 10 mins
local data_log_timer = 0

local temp = read_temp()
init_ENS160(temp)
setup_NFC()
toggle_lcd("OFF") -- start off in powersaving mode

while true do

    if power_save_counter == 1 then
        toggle_lcd("OFF")
    end

    local phone_present = read_phone()
    temp = read_temp()

    local ens160_values = read_ENS160(temp)

    if phone_present then
        if not phone_prev then
            total_scans = total_scans + 1
            toggle_lcd("ON")
            lcd_clear()
            lcd_write_text(" Thanks for the scan!", 1)
            lcd_write_text("    Total scans: " .. string.format(total_scans), 3)
            
            device.sleep(1.5) -- give the user some time to see that the scan was successful
            
            lcd_clear()
            power_save_counter = power_save_duration
        end
        phone_prev = true
    else
        phone_prev = false
        
        if power_save_counter > 50 then -- only write to screen if it is ON
            lcd_write_text_offset("   Silicon Witchery", 4)
            
            if temp > temp_warning then
                temp_blink_count = temp_blink_count + 1
                
                if temp_blink_count % 10 < 5 then -- blink if temp is over threshold
                    lcd_write_text("    Temp: " .. string.format("%0.2f", temp) .. " *C", 2)
                else
                    lcd_write_text(" ", 2)
                end
            else
                temp_blink_counter = 0
                lcd_write_text("    Temp: " .. string.format("%0.2f", temp) .. " *C", 2)
            end
            
            if ens160_values[3] > eco2_warning then 
                eco2_blink_count = eco2_blink_count + 1
                
                if eco2_blink_count % 10 < 5 then -- blink if eco2 is over threshold
                    lcd_write_text("    eCO2: " .. string.format("%0.0f", ens160_values[3]) .. " ppm", 3)
                else
                    lcd_write_text(" ", 3)
                end
            else
                eco2_blink_count = 0
                lcd_write_text("    eCO2: " .. string.format("%0.0f", ens160_values[3]) .. " ppm", 3)
            end
            power_save_counter = power_save_counter - 1
        else
            if power_save_counter == 50 then
                lcd_clear()
                power_save_counter = power_save_counter - 1
            elseif power_save_counter < 1 then
                lcd_clear()
            else
                lcd_write_text("    Goin' to sleep", 1) 
                lcd_write_text("        in " .. string.format((power_save_counter / 10)), 2)
                power_save_counter = power_save_counter - 1
            end
        end
    end
    
    if data_log_timer == 0 then -- send log data every 10 min
        -- report values
        network.send_data{
            temperature = temp,
            eCO2 = ens160_values[3],
            TVOC = ens160_values[2],
            AQI = ens160_values[1]
        } 
        data_log_timer = data_log_ceiling
    end
    
    data_log_timer = data_log_timer - 1

    device.sleep(0.1)
end