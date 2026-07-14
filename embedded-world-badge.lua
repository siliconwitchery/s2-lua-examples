-- Conference badge with an SSD1309 128x32 OLED (0x3C), an ST25DV NFC tag
-- (0x53) and an MCP9808 temperature sensor (0x18) on port F, plus an ENS160
-- air quality sensor on port E. The ENS160 also responds at 0x53, so it must
-- live on a different port to the NFC tag. The tag serves a URL, scans are
-- counted and shown on the display along with temperature and eCO2 warnings,
-- and everything is reported to Superstack every 10 minutes

local OLED_ADDRESS = 0x3C
local ST25DV_ADDRESS = 0x53
local MCP9808_ADDRESS = 0x18
local ENS160_ADDRESS = 0x53

local PORT_F = { port = "PORTF" }
local PORT_E = { port = "PORTE" }

-- URL served by the NFC tag. The https:// prefix is encoded in the NDEF record
local NFC_URL = "linkedin.com/in/siliconwitch"

-- Blink the readings on the display above these levels
local TEMPERATURE_WARNING = 26 -- C
local ECO2_WARNING = 1000 -- ppm

-- The main loop runs on a 0.1 second tick. After a scan the display stays on
-- for 200 ticks (20 seconds), showing a sleep countdown over the last 50, and
-- a report is sent to Superstack every 6000 ticks (10 minutes)
local TICK_SECONDS = 0.1
local POWER_SAVE_TICKS = 200
local COUNTDOWN_TICKS = 50
local DATA_LOG_TICKS = 6000

-- Charge the battery at 4.2V and up to 700mA, and power the devices at 3.3V
device.power.battery.set_charger_cv_cc(4.2, 700)
device.power.set_vout(3.3)

-- Give the devices time to boot
device.sleep(3)

-- SSD1309 display commands
local DISPLAY_OFF = "\xAE"
local DISPLAY_ON = "\xAF"
local SET_CLK = "\xD5\x80" -- default clock divider and oscillator frequency
local SET_MULTIPLEX = "\xA8\x1F" -- 32 rows
local SET_OFFSET = "\xD3\x00"
local SET_START_LINE = "\x40"
local EN_CHARGE_PUMP = "\x8D\x14" -- generate the panel voltage internally
local SET_MEMADDR_MODE = "\x20\x00" -- horizontal addressing
local SET_SEG_REMAP = "\xA0"
local SET_COMSCAN_DIR = "\xC0"
local SET_COMPIN_CONFIG = "\xDA\x02" -- sequential COM pins for a 32 row panel
local SET_CONTRAST = "\x81\xCF"
local SET_PRE_CHARGE = "\xD9\xF1"
local SET_VCOMH = "\xDB\x40"
local NORMAL_MODE = "\xA4" -- show the RAM contents rather than all pixels on
local SET_DISPLAY_NORMAL = "\xA6" -- non inverted

-- Commands and pixel data are prefixed with a control byte: 0x00 marks the
-- bytes that follow as commands, 0x40 marks them as display data
local function oled_command(command)
    return device.i2c.write(OLED_ADDRESS, "\x00" .. command, PORT_F)
end

local function oled_data(data)
    device.i2c.write(OLED_ADDRESS, "\x40" .. data, PORT_F)
end

-- Point the write window at the full display width across a range of pages,
-- where each page is an 8 pixel tall row. These window commands only apply
-- once the controller is in horizontal addressing mode
local function oled_set_window(first_page, last_page)
    oled_command("\x21\x00\x7F") -- columns 0 to 127
    oled_command("\x22" .. string.char(first_page, last_page))
end

local function oled_clear()
    oled_set_window(0, 3)

    for _ = 1, 4 do
        oled_data(string.rep("\x00", 128))
    end
end

-- Configure the controller for the 128x32 panel, leaving the panel itself
-- switched off
local function oled_init()
    oled_command(DISPLAY_OFF)
    oled_command(SET_CLK)
    oled_command(SET_MULTIPLEX)
    oled_command(SET_OFFSET)
    oled_command(SET_START_LINE)
    oled_command(EN_CHARGE_PUMP)
    oled_command(SET_MEMADDR_MODE)
    oled_command(SET_SEG_REMAP)
    oled_command(SET_COMSCAN_DIR)
    oled_command(SET_COMPIN_CONFIG)
    oled_command(SET_CONTRAST)
    oled_command(SET_PRE_CHARGE)
    oled_command(SET_VCOMH)
    oled_command(NORMAL_MODE)
    oled_command(SET_DISPLAY_NORMAL)
end

local function oled_power(on)
    oled_command(on and DISPLAY_ON or DISPLAY_OFF)
end

-- 5x7 pixel font, one column per byte
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

-- Write a line of text to one of the four display rows. Each glyph is 5
-- columns plus a 1 column gap, so 20 characters fill the width
local function oled_write_text(text, row)
    while #text < 20 do text = text .. " " end

    oled_set_window(row, row)

    local data = ""
    for i = 1, #text do
        local character = text:sub(i, i)
        data = data .. (font[character] or "\x00\x00\x00\x00\x00") .. "\x00"
    end

    oled_data(data)
end

-- Write text shifted down by a number of pixels so that it straddles rows 0
-- and 1, splitting each glyph column across the two pages
local function oled_write_text_offset(text, offset)
    while #text < 20 do text = text .. " " end

    local top = ""
    local bottom = ""

    for i = 1, #text do
        local character = text:sub(i, i)
        local glyph = font[character] or "\x00\x00\x00\x00\x00"

        for column = 1, 5 do
            local bits = glyph:byte(column)
            top = top .. string.char((bits << offset) & 0xFF)
            bottom = bottom .. string.char(bits >> (8 - offset))
        end

        top = top .. "\x00"
        bottom = bottom .. "\x00"
    end

    oled_set_window(0, 0)
    oled_data(top)

    oled_set_window(1, 1)
    oled_data(bottom)
end

-- Write an NDEF message to the start of the ST25DV user memory so that any
-- phone tapped against the antenna opens the URL
local function setup_nfc()
    local ndef = "\xE1\x40\x40\x00" -- capability container: NDEF magic, version 1.0 with open access, 512 bytes of memory
        .. "\x03" -- NDEF message TLV
        .. string.char(#NFC_URL + 5) -- message length: 5 byte record header plus the URL
        .. "\xD1\x01" -- single short record, well known type, type length 1
        .. string.char(#NFC_URL + 1) -- payload length: prefix code plus the URL
        .. "\x55\x03" -- type "U" for URI, prefix code 3 meaning https://
        .. NFC_URL
        .. "\xFE" -- terminator TLV

    -- The first two bytes are the 16 bit destination address in user memory
    if not device.i2c.write(ST25DV_ADDRESS, "\x00\x00" .. ndef, PORT_F).success then
        error("ST25DV not responding on port F")
    end
end

-- True when a phone's RF field has been seen since the last call. IT_STS is
-- a dynamic register at 0x2005 which clears itself once read, and bit 4 of
-- it latches whenever an RF field appears
local function read_phone()
    device.i2c.write(ST25DV_ADDRESS, "\x20\x05", PORT_F)

    local result = device.i2c.read(ST25DV_ADDRESS, 1, PORT_F)

    return result.success and (result.value & 0x10) ~= 0
end

-- Read the MCP9808 ambient temperature register (0x05). The reading is a 13
-- bit two's complement value in units of 0.0625C
local function read_temperature()
    local result = device.i2c.write_read(MCP9808_ADDRESS, "\x05", 2, PORT_F)
    if not result.success then
        return nil
    end

    local upper = result.data:byte(1)
    local lower = result.data:byte(2)

    -- The top three bits are alarm flags, and bit 4 is the sign
    local temperature = ((upper & 0x0F) * 256 + lower) / 16.0

    if upper & 0x10 ~= 0 then
        temperature = temperature - 256.0
    end

    return temperature
end

-- Put the ENS160 into gas sensing mode and give it a calibration point
local function init_ens160(temperature)
    -- The PART_ID register (0x00) always reads 0x0160
    local response = device.i2c.write_read(ENS160_ADDRESS, "\x00", 2, PORT_E)
    if not response.success or response.data ~= "\x60\x01" then
        error("ENS160 not found on port E")
    end

    -- Standard gas sensing operating mode (OPMODE register)
    device.i2c.write(ENS160_ADDRESS, "\x10\x02", PORT_E)

    -- The badge has no humidity sensor, so assume 50% relative humidity
    local humidity = 50

    -- TEMP_IN is Kelvin x 64 and RH_IN is %RH x 512, both little endian
    local temperature_calibration = math.floor(temperature + 273)
    local humidity_calibration = humidity << 9

    device.i2c.write(ENS160_ADDRESS, string.char(
        0x13,
        (temperature_calibration & 0x03) << 6,
        temperature_calibration >> 2), PORT_E)

    device.i2c.write(ENS160_ADDRESS, string.char(
        0x15,
        humidity_calibration & 0xFF,
        humidity_calibration >> 8), PORT_E)
end

-- Read the air quality index (1 to 5), TVOC in ppb and eCO2 in ppm, or nil
-- if a read fails or the sensor is not yet producing valid data
local function read_ens160()
    -- Bits 3:2 of the DATA_STATUS register (0x20) are the validity flag:
    -- 0 is normal operation, 1 is warm-up, 2 is initial start-up and 3 is
    -- invalid output. Only accept readings taken in normal operation
    local response = device.i2c.write_read(ENS160_ADDRESS, "\x20", 1, PORT_E)
    if not response.success or (response.value >> 2) & 0x03 ~= 0 then
        return nil
    end

    response = device.i2c.write_read(ENS160_ADDRESS, "\x21", 1, PORT_E)
    if not response.success then
        return nil
    end
    local aqi = response.value & 0x07

    response = device.i2c.write_read(ENS160_ADDRESS, "\x22", 2, PORT_E)
    if not response.success then
        return nil
    end
    local tvoc = string.byte(response.data, 1) | string.byte(response.data, 2) << 8

    response = device.i2c.write_read(ENS160_ADDRESS, "\x24", 2, PORT_E)
    if not response.success then
        return nil
    end
    local eco2 = string.byte(response.data, 1) | string.byte(response.data, 2) << 8

    return aqi, tvoc, eco2
end

-- The SSD1309 has no ID register, so check that it acknowledges a command
if not oled_command(DISPLAY_OFF).success then
    error("SSD1309 not responding on port F")
end

-- Configure the controller and clear its RAM while the panel is still off so
-- that it never shows uninitialized pixels. The clear has to come after the
-- init because the write window only works in horizontal addressing mode.
-- The panel then stays off (power save) until the first scan turns it on
oled_init()
oled_clear()

-- The MCP9808 manufacturer ID register (0x06) always reads 0x0054
local response = device.i2c.write_read(MCP9808_ADDRESS, "\x06", 2, PORT_F)
if not response.success or response.data ~= "\x00\x54" then
    error("MCP9808 not found on port F")
end

local temperature = read_temperature()
if not temperature then
    error("Failed to read the MCP9808")
end

init_ens160(temperature)
setup_nfc()

print("Badge running. NFC tag is serving https://" .. NFC_URL)

local phone_previously_present = false
local total_scans = 0

local power_save_counter = 0
local temperature_blink_count = 0
local eco2_blink_count = 0
local data_log_counter = 0

-- Air quality values stay nil until the ENS160 has warmed up and produced
-- its first valid reading, then hold the last valid reading
local aqi, tvoc, eco2

while true do
    -- Turn the display off once the power save countdown expires
    if power_save_counter == 1 then
        oled_power(false)
    end

    local phone_present = read_phone()

    local new_temperature = read_temperature()
    if new_temperature then
        temperature = new_temperature
    end

    local new_aqi, new_tvoc, new_eco2 = read_ens160()
    if new_aqi then
        aqi, tvoc, eco2 = new_aqi, new_tvoc, new_eco2
    end

    if phone_present then
        if not phone_previously_present then
            total_scans = total_scans + 1
            print("NFC scan number " .. total_scans)

            oled_power(true)
            oled_clear()
            oled_write_text(" Thanks for the scan!", 1)
            oled_write_text("    Total scans: " .. string.format("%d", total_scans), 3)

            -- Give the user a moment to see that the scan was registered
            device.sleep(1.5)

            oled_clear()
            power_save_counter = POWER_SAVE_TICKS
        end
        phone_previously_present = true
    else
        phone_previously_present = false

        if power_save_counter > COUNTDOWN_TICKS then
            oled_write_text_offset("   Silicon Witchery", 4)

            -- Blink the temperature at 1Hz while it is over the warning level
            if temperature > TEMPERATURE_WARNING then
                temperature_blink_count = temperature_blink_count + 1

                if temperature_blink_count % 10 < 5 then
                    oled_write_text("    Temp: " .. string.format("%0.2f", temperature) .. " *C", 2)
                else
                    oled_write_text(" ", 2)
                end
            else
                temperature_blink_count = 0
                oled_write_text("    Temp: " .. string.format("%0.2f", temperature) .. " *C", 2)
            end

            -- And the same for the eCO2 reading. The row stays blank until
            -- the ENS160 has produced a valid reading
            if eco2 then
                if eco2 > ECO2_WARNING then
                    eco2_blink_count = eco2_blink_count + 1

                    if eco2_blink_count % 10 < 5 then
                        oled_write_text("    eCO2: " .. string.format("%0.0f", eco2) .. " ppm", 3)
                    else
                        oled_write_text(" ", 3)
                    end
                else
                    eco2_blink_count = 0
                    oled_write_text("    eCO2: " .. string.format("%0.0f", eco2) .. " ppm", 3)
                end
            end

            power_save_counter = power_save_counter - 1
        elseif power_save_counter == COUNTDOWN_TICKS then
            oled_clear()
            power_save_counter = power_save_counter - 1
        elseif power_save_counter >= 1 then
            oled_write_text("    Goin' to sleep", 1)
            oled_write_text("        in " .. string.format("%d", power_save_counter // 10), 2)
            power_save_counter = power_save_counter - 1
        end
    end

    -- Report to Superstack every 10 minutes. The counter starts at zero so
    -- that the first report goes out right away, and the air quality fields
    -- are omitted until the ENS160 has produced a valid reading
    if data_log_counter == 0 then
        print(string.format(
            "%.2f C | %s | %d scans",
            temperature,
            eco2 and string.format("eCO2 %d ppm | TVOC %d ppb | AQI %d", eco2, tvoc, aqi)
                or "air quality warming up",
            total_scans))

        network.send_data {
            temperature = temperature,
            air_quality_index = aqi,
            carbon_dioxide = eco2,
            volatile_compounds = tvoc,
            total_scans = total_scans
        }

        data_log_counter = DATA_LOG_TICKS
    end

    data_log_counter = data_log_counter - 1

    device.sleep(TICK_SECONDS)
end
