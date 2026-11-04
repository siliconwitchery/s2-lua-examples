-- VU meter. A PDM microphone on PORTA lights a ring of 12 RGBW LEDs on B0
-- with the sound level. A rainbow swirls around the ring, faster when it's
-- loud, every LED fades out behind the meter, and loud peaks flash white

device.power.set_vout(3.3)

local LED_COUNT = 12

local colors = {}
local glows = {}

for index = 1, LED_COUNT do
    colors[index] = { 0, 0, 0, 0 }
    glows[index] = 0
end

-- The color wheel at full brightness in 72 steps, worked out once because the sums are too slow
-- to do for every LED in every block
local WHEEL = {}

for step = 0, 71 do
    local wheel = step / 12
    WHEEL[step + 1] = {
        math.max(0, math.min(math.abs(wheel - 3) - 1, 1)),
        math.max(0, math.min(2 - math.abs(wheel - 2), 1)),
        math.max(0, math.min(2 - math.abs(wheel - 4), 1)),
    }
end

local level = 0
local flash = 0
local rotation = 0 -- the LED the meter starts from, which drifts around the ring
local hue = 0 -- the color at the start of the meter, in steps around WHEEL

-- Each block of 160 samples is 10 ms of audio
device.pdm.assign_read_event(160, function(block)
    local sum = 0

    -- Unpacking eight samples a call takes a third of the time of one a call
    for position = 1, #block, 16 do
        local a, b, c, d, e, f, g, h = string.unpack("<i2i2i2i2i2i2i2i2", block, position)
        sum = sum + a * a + b * b + c * c + d * d + e * e + f * f + g * g + h * h
    end

    local rms = math.sqrt(sum / 160)
    local decibels = 20 * math.log(math.max(rms, 1) / 32768, 10)
    local target = (decibels + 55) / 35 * LED_COUNT -- -55 dBFS, just above a quiet room, lights no LEDs and -20 dBFS lights all of them

    -- Rise at once and fall by a quarter of an LED a block, so the ring doesn't flicker
    level = math.max(target, level - 0.25)

    local loudness = math.min(level / LED_COUNT, 1)

    if target > 0.9 * LED_COUNT then
        flash = 1
    end

    flash = flash * 0.9
    rotation = (rotation + 0.01 + 0.08 * loudness) % LED_COUNT
    hue = (hue + 0.072 + 0.432 * loudness) % 72

    for index = 1, LED_COUNT do
        local position = (index - 1 - rotation) % LED_COUNT
        local fill = level - position

        if fill > 1 then
            fill = 1
        end

        -- An LED lights as fast as the meter reaches it and fades by a tenth a block after
        local glow = glows[index] * 0.9

        if fill > glow then
            glow = fill
        end

        glows[index] = glow

        -- The meter spans half the color wheel, 36 steps, from start to end
        local rgb = WHEEL[(hue + position * 3) // 1 % 72 + 1]

        -- PORTA to PORTC share 100 mA, so the LEDs stay dim
        local brightness = glow * 24
        local color = colors[index]
        color[1] = (rgb[1] * brightness + 0.5) // 1
        color[2] = (rgb[2] * brightness + 0.5) // 1
        color[3] = (rgb[3] * brightness + 0.5) // 1
        color[4] = (flash * glow * 16 + 0.5) // 1
    end

    device.ws2812.write("B0", colors, { order = "GRBW" })
end)

-- device.sleep() hands over events only every 100 ms, which drops blocks
while true do
    device.sleep_ms(1)
end
