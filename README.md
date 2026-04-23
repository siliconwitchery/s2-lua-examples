# Lua examples

| Name | Description | Sensors used |
|------|-------------|--------------|
| adafruit_bmp280.lua | Code for reading temperature and air pressure using a barometric sensor. | [BMP280](https://cdn-shop.adafruit.com/datasheets/BST-BMP280-DS001-11.pdf) - [Adafruit](https://www.adafruit.com/product/2651?srsltid=AfmBOoraqYWN2NrbF4Is_Y9qTXpsZ8oj2GNg16er-wD4ysnpkAzkiN6R) |
| adafruit_mlx90393.lua | Code for measuring magnetic field strength in three axes (X, Y, Z). | [MLX90393](https://cdn-learn.adafruit.com/assets/assets/000/069/600/original/MLX90393-Datasheet-Melexis.pdf?1547824268) - [Adafruit](https://www.adafruit.com/product/4022?srsltid=AfmBOopjxDPTyKOXGkLhLE0XirPPD5sTp8w4_ma70AiPDry1OR9kTE-j) |
| air-quality-monitor | An indoor air monitoring system that measures temperature, humidity, AQI, CO₂, and TVOC, and automatically controls a fan based on air quality levels. The data collected is sent to Superstack | [SHT45](https://cdn-shop.adafruit.com/product-files/5665/5665_Datasheet_SHT4x.pdf) - [Adafruit](https://www.adafruit.com/product/5665?srsltid=AfmBOorWyh2e7zfRAgB8LQBmid6XSM7FY27HXKOwKky2K6FxIgsPkaEY), [ENS160](https://cdn.sparkfun.com/assets/3/c/7/5/5/SC-001224-DS-7-ENS160-Datasheet.pdf) - [Sparkfun](https://www.sparkfun.com/sparkfun-indoor-air-quality-sensor-ens160-qwiic.html) |
| embedded-world-badge.lua | Code for a wearable conference badge featuring temperature and eCO₂ measurements, NFC functionality, and a transparent display. The data collected is sent to Superstack | *Adafruit MCP9808*, *Adafruit ST25DV16*, *Sparkfun ENS160*, *Sparkfun transparent OLED display* |
| power-meter.lua | A system that measures voltage, current, and power consumption and sends the data to Superstack. | *Adafruit INA237* |
| production-line-color-checker.lua | A project that measures light intensity at different wavelengths using a color sensor and sends the data to Superstack. | *Sparkfun AS7343* |
| sparkfun_cap1203.lua | Code for the Sparkfun CAP1203 slider sensor. Detects touches on three different pads. | *Sparkfun CAP1203* |
| sparkfun_vcnl4040.lua | Code for the Sparkfun VCNL4040 sensor. Measures ALS (Ambient light source). | *Sparkfun VCNL4040* |
| trash-level-sensor.lua | A project that measures how full a trash can is using a distance sensor. The system calculates the distance from the sensor to the trash and sends the data to Superstack. | *Adafruit VL53L0X* |
