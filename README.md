# 🐺 Shacalizator

**iOS-приложение для шакализации изображений** — намеренная деградация качества фото с 5 уровнями интенсивности.

SwiftUI • iOS 26+ • Полностью оффлайн

---

## Возможности

- 📷 Выбор фото из галереи через PhotosPicker
- 🎚 5 уровней шакализации (от лёгкого до адского)
- 🔄 Сравнение оригинала и результата
- 💾 Сохранение в Фото
- 📤 Поделиться через Share Sheet
- 🔒 Всё работает локально, фото никуда не отправляются

### Уровни шакализации

| Уровень | JPEG | Downscale | Пережатие | Эффекты |
|---------|------|-----------|-----------|---------|
| 🌤 Лёгкий шакал | 55–65% | 85% | 1× | Лёгкий шум |
| ☁️ Средний шакал | 35–45% | 70% | 2× | Шум, blur |
| ⚡ Жёсткий шакал | 18–25% | 50% | 3× | Пиксели, sharpen |
| 🔥 Легендарный | 5–12% | 35% | 5× | Всё + постеризация |
| 🌀 Адский шакал | 1–5% | 25% | 9× | Тотальное уничтожение |

---

## 📦 Как получить unsigned IPA (без Mac!)

Весь процесс — с Windows, через GitHub Actions.

### Шаг 1 — Создать репозиторий на GitHub

1. Зайди на [github.com/new](https://github.com/new)
2. Имя репозитория: `Shacalizator` (или любое)
3. Оставь **Public** или **Private** — оба варианта работают
4. **Не** ставь галочки на README, .gitignore и т.д.
5. Нажми **Create repository**

### Шаг 2 — Загрузить проект

Открой **PowerShell** (или терминал) в папке проекта и выполни:

```powershell
cd C:\Users\vov75\Desktop\SHACALIZATOR

git init
git add .
git commit -m "Initial commit: Shacalizator iOS app"
git branch -M main
git remote add origin https://github.com/ТВОЙ_ЛОГИН/Shacalizator.git
git push -u origin main
```

> ⚠️ Замени `ТВОЙ_ЛОГИН` на свой GitHub username.

### Шаг 3 — Запустить сборку

1. Открой свой репозиторий на GitHub
2. Перейди во вкладку **Actions** (вверху)
3. Слева найди workflow **"Build unsigned IPA"**
4. Нажми на него
5. Нажми кнопку **"Run workflow"** → **"Run workflow"**

![Actions Tab](https://docs.github.com/assets/cb-15465/mw-1440/images/help/actions/actions-tab.webp)

### Шаг 4 — Скачать IPA

1. Подожди 3–5 минут, пока сборка завершится (зелёная галочка ✅)
2. Нажми на завершённый workflow run
3. Внизу страницы найди раздел **Artifacts**
4. Нажми на **Shacalizator_unsigned_ipa** — скачается ZIP
5. Распакуй ZIP — внутри будет `Shacalizator_unsigned.ipa`

> 🎉 Готово! У тебя unsigned IPA, который можно подписать своим сертификатом.

---

## Подписывание IPA

IPA **не подписан** — это сделано намеренно. Для установки на устройство подпиши его:

- **AltStore / Sideloadly** — подпись через Apple ID
- **Собственный сертификат** — через `codesign` / `ldid`
- **Enterprise** — через MDM/enterprise provisioning

---

## Структура проекта

```
SHACALIZATOR/
├── .github/workflows/
│   └── build_unsigned_ipa.yml    ← GitHub Actions workflow
├── scripts/
│   └── package_unsigned_ipa.sh   ← Скрипт упаковки в IPA
├── Shacalizator.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/
│       └── Shacalizator.xcscheme ← Shared scheme для CI
├── Shacalizator/
│   ├── ShacalizatorApp.swift
│   ├── ContentView.swift
│   ├── ImageProcessor.swift
│   ├── ShacalPreset.swift
│   ├── SaveManager.swift
│   ├── PhotoPickerView.swift
│   ├── Components/
│   │   ├── EmptyStateView.swift
│   │   ├── PresetCardView.swift
│   │   ├── ImageComparisonView.swift
│   │   ├── ToastView.swift
│   │   └── GlassBackgroundModifier.swift
│   ├── Assets.xcassets/
│   └── Info.plist
├── build_unsigned_ipa.sh         ← Скрипт для локальной сборки (Mac)
└── README.md
```

---

## Локальная сборка (macOS)

Если есть Mac с Xcode:

```bash
chmod +x build_unsigned_ipa.sh
./build_unsigned_ipa.sh
```

Результат: `Shacalizator_unsigned.ipa` в корне.

---

## Технологии

- Swift 5 / SwiftUI
- iOS 17.0+ deployment target (для широкой совместимости и стабильности)
- PhotosUI, CoreImage, ImageIO
- @Observable (Observation framework)
- Glass-morphism UI
- Без сторонних зависимостей

---

## FAQ

**Q: Workflow падает с ошибкой "scheme not found"**
A: Убедись, что файл `Shacalizator.xcodeproj/xcshareddata/xcschemes/Shacalizator.xcscheme` закоммичен в репозиторий.

**Q: Ошибка "No iphoneos SDK"**
A: Runner может не иметь нужной версии SDK. Попробуй изменить `runs-on` в workflow на `macos-latest`.

**Q: Сборка прошла, но IPA пустой**
A: Проверь логи шага "Package unsigned IPA" — там будет подробная верификация.

---

## Лицензия

Приватный проект. Все права защищены.
