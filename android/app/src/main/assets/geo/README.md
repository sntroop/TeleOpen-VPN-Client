# Geo-базы для xray (geoip.dat / geosite.dat)

Сюда нужно положить ДВА файла, иначе фичи «Блокировать рекламу» и
маршрут по стране (Регион) работать не будут (приложение не упадёт —
правила просто не применятся, в vpn_debug.log будет «отсутствует в assets»):

  geoip.dat
  geosite.dat

Источник (проверенный, совместим с xray-core):
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest
    - geoip.dat
    - geosite.dat

Скачать (пример):
  curl -L -o geoip.dat   https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
  curl -L -o geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

После добавления файлов APK вырастет на ~12-15 МБ. Натив копирует их в
filesDir при первом старте VPN (см. HysteriaTunVpnService.copyGeoAssets) —
именно там их ищет xray (initCoreEnv(assetsDir=filesDir)).

Правило блокировки рекламы использует категорию `geosite:category-ads-all`,
маршрут по стране — `geoip:<код>` (напр. geoip:ru). Обе категории есть в
базах Loyalsoldier.
