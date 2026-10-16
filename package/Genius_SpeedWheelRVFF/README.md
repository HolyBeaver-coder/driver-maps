# Genius SPEED WHEEL RV FF — адаптация драйвера под Windows 11 (26H2, сборка 26300.x) x64

Руль: **Genius Speed Wheel RV Force Feedback** (USB VID `0x0458`, PID `0x3017`),
родной драйвер — «Genius Game Driver release» от 30.05.2011 (поддержка только Vista x64 / Win7 x64).

В этой папке лежит **готовый пакет стороннего (unsigned → self-signed) драйвера** для
Windows 11 x64, собранный из распакованного установщика `VibrateGameDeviceDrivers40.msi`.

## Состав пакета

| Файл | Назначение |
|---|---|
| `HID_RF_3017.inf` | Исправленный INF: версия `10/16/2026,6.4.26300.1`, CRLF-формат, секции `.NT`/`.NTamd64` корректны |
| `dyncal64.sys` | Ядерный драйвер калибровки/ForceFeedback (upper filter для HIDClass) |
| `rfvibra64.dll`, `rfvibra264.dll` | COM-библиотеки effects-плагинов DirectInput FFB (CLSID из INF) |
| `rfcplsvr64.dll` | Панель свойств устройства (калибровка, настройки отдачи через «Игровые устройства») |
| `build_package.bat` | Скрипт автоматической сборки и подписи пакета (см. ниже) |
| `CalibrationData_AMD64.reg` *(в корне репо)* | Сохранённые калибровки (не обязателен) |

## Почему старый драйвер не ставится на Windows 11

1. **Каталог `.cat` подписан сертификатом 2007–2011 гг.** — он просрочен и больше не принимается
   политикой загрузки кода ядра x64.
2. Инсталлятор MSI использует устаревшие проверки версии ОС и 16‑битные компоненты (`instmsia/w`).
3. Сам бинарный код (`dyncal64.sys`) в x64-сборке совместим с NT 6.0+ и работает на Win10/11 —
   проблема только в **подписи**, а не в коде.

Поэтому путь адаптации: пересобрать пакет + создать новый каталог (`inf2cat`) + расписаться самим.

⚠️ **Важно про подпись:** Microsoft требует EV-сертификат и процедур attestation-подписи для
драйверов ядра (WHQL/Attestation). Без покупки сертификата ($400+/год) установка возможна только
в **Test Signing Mode**. Это безопасно для личной машины, но включённый test mode снижает
некоторые гарантии целостности системы (можно потом выключить).

---

## Шаг 0. Подготовка

1. Включите UEFI-параметры, если активен Secure Boot (тестовый режим его отключает сам при
   `testsigning on`, но на некоторых платах нужен Manual/Other OS). Либо просто помните:
   после включения Test Mode в правом нижнем углу будет водяной знак «Test Mode».
2. Установите **Windows SDK 11** (или WDK) — нужны `inf2cat.exe` и `signtool.exe`:
   https://developer.microsoft.com/windows/downloads/windows-sdk/
   (достаточно галочки «Windows SDK + Signing Tools»; инсталлировать можно поверх Win11).
3. Отключите «Core Isolation → Memory Integrity» (HVCI), **если** система откажется грузить
   неподписанный по новым политикам `.sys` (Win11 24H2+ иногда строже).
   *Средства безопасности Windows → Безопасность Windows → Безопасность ядра → Целостность памяти → Откл.*

## Шаг 1. Полная очистка старой установки

Выполните в PowerShell **от администратора**:

```powershell
# 1. Показать все спрятанные устройства HID/USB руля
pnputil /enum-drivers | Select-String -Pattern "3017|Rockfire|Padix|dyncal" -Context 3,1

# 2. Удалить старые пакеты драйверов Genius/Rockfire/Padix из хранилища
#    (подставьте Package ID вида oemXX.inf из вывода выше)
pnputil /delete-driver oem0.inf /uninstall /force

# 3. Выключить устройство и удалить его следы из реестра
Get-PnpDevice | Where-Object { $_.InstanceId -like "*VID_0458*PID_3017*" } | ForEach-Object {
    Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
    Remove-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
}

# 4. Очистить ключи старых OEM-джойстиков
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM\VID_0458&PID_3017" -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\System\CurrentControlSet\Control\MediaProperties\PrivateProperties\DirectInput\VID_0458&PID_3017*" -Recurse -ErrorAction SilentlyContinue

# 5. (Опционально) скрытые записи Device Instance
#    Диспетчер устройств → Вид → Показать скрытые устройства → удалить всё серое "SPEED WHEEL RV"
```

Отсоедините руль из USB и перезагрузитесь.

## Шаг 2. Сборка и подпись пакета (автоматически)

Запустите **от администратора** `build_package.bat` из этой папки. Он:

1. копирует файлы в `output\`;
2. создаёт self-signed сертификат кода `GeniusWheelTestCert` (5 лет, SHA-256);
3. вызывает `inf2cat /driver:output /os:10_x64,11_x64` → получает `HID_RF_3017.cat`;
4. подписывает каталог и INF через `signtool sign /sha1 <thumbprint> /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 ...`.

### Ручные команды (эквивалент скрипта)

```bat
:: сертификат
powershell -Command "New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=GeniusWheelTestCert' -CertStoreLocation Cert:\LocalMachine\My -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(5)"

:: экспорт .cer для доверия на целевой машине
powershell -Command "$c=dir Cert:\LocalMachine\My|?{$_.Subject -match 'GeniusWheelTestCert'}; Export-Certificate -Cert $c -FilePath genius.cer"

:: каталог
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x86\inf2cat.exe" /driver:"C:\path\to\output" /os:10_x64,11_x64 /verbose

:: подпись (подставьте thumbprint из `dir Cert:\LocalMachine\My`)
signtool sign /v /fd SHA256 /sha1 <THUMBPRINT> /tr http://timestamp.digicert.com /td SHA256 output\HID_RF_3017.cat
signtool sign /v /fd SHA256 /sha1 <THUMBPRINT> /tr http://timestamp.digicert.com /td SHA256 output\HID_RF_3017.inf
```

## Шаг 3. Установка на Windows 11

На **целевой машине** (та же или другая — берёте содержимое `output\` + `genius.cer`):

```bat
:: 1. Тестовый режим подписи (потребует перезагрузки)
bcdedit /set testsigning on
shutdown /r /t 0

:: 2. После загрузки — доверие нашему сертификату
certutil -addstore -f TrustedPublisher genius.cer
certutil -addstore -f Root genius.cer

:: 3. Установка пакета
pnputil /add-driver HID_RF_3017.inf /install
```

Либо через Диспетчер устройств: подключите руль → «Неизвестное устройство/HID» →
обновить драйвер → «Изменить параметры…» → «Указать…» → выбрать папку `output`.

## Шаг 4. Проверка работы

1. **Все кнопки/педали/KPKМ:** `joy.cpl` (Win+R → `joy.cpl`) → «Свойства» — проверяйте отклик
   12 кнопок, двух осей педалей, рукоятки КПП (POV/hat) и оси руля.
2. **Отдача (FFB):** там же вкладка «Проверить» / панель свойств устройства (её добавляет
   `rfcplsvr64.dll` через CLSID `{C3AE4040-…}`) — настройка Gain, Constant/Ramp/Spring/Damper.
   Быстрый тест: игра с поддержкой DirectInput FFB или утилита **Force Feedback Test** / `FFTest`.
3. Если устройство определилось как обычный HID без FFB-панели — значит `.sys` не загрузился:
   смотрите `C:\Windows\System32\drivers\etc\…` нет, лучше: Event Viewer → System, фильтр
   `Driver Services` / код 127/39, и статус службы `sc query dyncal64`.

## Известные ограничения / план Б

* Если `dyncal64.sys` всё же не грузится даже в test mode (крайне маловероятно — x64-модуль эпохи
  Vista SP1+, а требования по подписи решаются новым каталогом), используйте руль **штатным HID-драйвером
  Microsoft**: оси, 12 кнопок, POV и педали работают «из коробки»; теряется только фирменная
  отдача. Для эмуляции FFB в отдельных играх применяют `x360ce`/`DDraw`-прослойки (частично).
* Полный вариант без test mode — покупка EV-сертификата и submission в Microsoft Partner Center
  (Attestation signing). Для одного пользователя избыточно.
* Не удаляйте водяной знак Test Mode «косметическими» твикерами — это ломает политику загрузки.

## Как вернуть систему «как было»

```bat
bcdedit /set testsigning off
certutil -delstore TrustedPublisher "GeniusWheelTestCert"
certutil -delstore Root "GeniusWheelTestCert"
pnputil /delete-driver oemNN.inf /uninstall /force
```
