<h1>Lua examples</h1>

<table>
  <tr>
    <th>Name</th>
    <th style="width: 220px;">Description</th>
    <th style="width: 420px;">Sensors used</th>
  </tr>

  <tr>
    <td>adafruit_bmp280.lua</td>
    <td>Code for reading temperature and air pressure using a barometric sensor.</td>
    <td><a href="https://cdn-shop.adafruit.com/datasheets/BST-BMP280-DS001-11.pdf">BMP280</a>📖 <a href="https://www.adafruit.com/product/2651?srsltid=AfmBOoraqYWN2NrbF4Is_Y9qTXpsZ8oj2GNg16er-wD4ysnpkAzkiN6R">Adafruit</a>🛍️</td>
  </tr>

  <tr>
    <td>adafruit_mlx90393.lua</td>
    <td>Code for measuring magnetic field strength in three axes (X, Y, Z).</td>
    <td><a href="https://cdn-learn.adafruit.com/assets/assets/000/069/600/original/MLX90393-Datasheet-Melexis.pdf?1547824268">MLX90393</a>📖 <a href="https://www.adafruit.com/product/4022?srsltid=AfmBOopjxDPTyKOXGkLhLE0XirPPD5sTp8w4_ma70AiPDry1OR9kTE-j">Adafruit</a>🛍️</td>
  </tr>

  <tr>
    <td>air-quality-monitor</td>
    <td>An indoor air monitoring system that measures temperature, humidity, AQI, CO₂, and TVOC, and automatically controls a fan based on air quality levels.<br>The data collected is sent to Superstack</td>
    <td>
      <a href="https://cdn-shop.adafruit.com/product-files/5665/5665_Datasheet_SHT4x.pdf">SHT45</a>📖 <a href="https://www.adafruit.com/product/5665?srsltid=AfmBOorWyh2e7zfRAgB8LQBmid6XSM7FY27HXKOwKky2K6FxIgsPkaEY">Adafruit</a>🛍️
      <br><br>
      <a href="https://cdn.sparkfun.com/assets/3/c/7/5/5/SC-001224-DS-7-ENS160-Datasheet.pdf">ENS160</a>📖 <a href="https://www.sparkfun.com/sparkfun-indoor-air-quality-sensor-ens160-qwiic.html">Sparkfun</a>🛍️
    </td>
  </tr>

  <tr>
    <td>embedded-world-badge.lua</td>
    <td>Code for a wearable conference badge featuring temperature and eCO₂ measurements, NFC functionality, and a transparent display.<br>The data collected is sent to Superstack</td>
    <td>
      <a href="https://cdn-shop.adafruit.com/datasheets/MCP9808.pdf">MCP9808</a>📖 <a href="https://www.adafruit.com/product/5027?srsltid=AfmBOooIMlDLNxRbp4RMq2Xds395YErlxbsYYVWF63tG9pdh4838VK8O">Adafruit</a>🛍️
      <br><br>
      <a href="https://cdn-learn.adafruit.com/assets/assets/000/093/906/original/st25dv04k.pdf?1596828496">ST25DV16</a>📖 <a href="https://www.adafruit.com/product/4701?srsltid=AfmBOoqhA-Lszc8EXEQm3fnSwnoGMusgyu_MKNSdJGGNTn70inD_m4CF">Adafruit</a>🛍️
      <br><br>
      <a href="https://cdn.sparkfun.com/assets/3/c/7/5/5/SC-001224-DS-7-ENS160-Datasheet.pdf">ENS160</a>📖 <a href="https://www.sparkfun.com/sparkfun-indoor-air-quality-sensor-ens160-qwiic.html">Sparkfun</a>🛍️
      <br><br>
      <a href="https://www.hpinfotech.ro/SSD1309.pdf">SSD1309</a>📖 <a href="https://github.com/sparkfun/Qwiic_Transparent_Graphical_OLED">Sparkfun</a>🛍️
    </td>
  </tr>

  <tr>
    <td>power-meter.lua</td>
    <td>A system that measures voltage, current, and power consumption and sends the data to Superstack.</td>
    <td><a href="https://cdn-learn.adafruit.com/assets/assets/000/137/300/original/ina237.pdf?1748875460">INA237</a>📖 <a href="https://www.adafruit.com/product/6340?srsltid=AfmBOoreuCNAASTZz_V2s1VwFtXVk0KtzLX2sKhoezjLfQvAjDtYZHtb">Adafruit</a>🛍️</td>
  </tr>

  <tr>
    <td>production-line-color-checker.lua</td>
    <td>A project that measures light intensity at different wavelengths using a color sensor and sends the data to Superstack.</td>
    <td><a href="https://cdn.sparkfun.com/assets/e/f/3/6/c/AS7343_DS001046_6-00.pdf">AS7343</a>📖 <a href="https://www.sparkfun.com/sparkfun-spectral-sensor-as7343-qwiic.html">Sparkfun</a>🛍️</td>
  </tr>

  <tr>
    <td>sparkfun_cap1203.lua</td>
    <td>Code for the Sparkfun CAP1203 slider sensor. Detects touches on three different pads.</td>
    <td><a href="https://cdn.sparkfun.com/assets/c/9/f/2/c/CAP1203_Data_Sheet.pdf">CAP1203</a>📖 <a href="https://www.sparkfun.com/sparkfun-capacitive-touch-slider-cap1203-qwiic.html">Sparkfun</a>🛍️</td>
  </tr>

  <tr>
    <td>sparkfun_vcnl4040.lua</td>
    <td>Code for the Sparkfun VCNL4040 sensor. Measures ALS (Ambient light source).</td>
    <td><a href="https://cdn.sparkfun.com/assets/2/3/8/f/c/VCNL4040_Datasheet.pdf">VCNL4040</a>📖 <a href="https://www.sparkfun.com/sparkfun-proximity-sensor-breakout-20cm-vcnl4040-qwiic.html">Sparkfun</a>🛍️</td>
  </tr>

  <tr>
    <td>trash-level-sensor.lua</td>
    <td>A project that measures how full a trash can is using a distance sensor. The system calculates the distance from the sensor to the trash and sends the data to Superstack.</td>
    <td><a href="https://learn.adafruit.com/adafruit-vl53l0x-micro-lidar-distance-sensor-breakout/downloads">VL53L0X</a>📖 <a href="https://www.adafruit.com/product/3317?srsltid=AfmBOoqX-2CYbaFwCknfs0ttgeJiUrAHdr1wQvrcn7IWFy00Y8obsGdo">Adafruit</a>🛍️</td>
  </tr>

</table>
