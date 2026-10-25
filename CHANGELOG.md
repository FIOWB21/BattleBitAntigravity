# Changelog

Все заметные изменения проекта документируются в этом файле по шагам плана (`docs/STEPS.md`).

## [step-0.5] — 2026-10-25

### Добавлено
- Класс `InputActions` (`src/core/input_actions.gd`) с 33 `StringName`-константами для всех действий игрока и списком `ALL_ACTIONS`.
- Модульный тест `tests/unit/test_input_actions.gd`, проверяющий наличие всех 33 констант `InputActions` в `InputMap` и привязку событий ввода.

### Изменено
- В `project.godot` (секция `[input]`) зарегистрированы 33 действия игрока (`move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `crouch`, `prone`, `lean_left`, `lean_right`, `fire`, `aim`, `reload`, `switch_weapon_next`, `switch_weapon_prev`, `slot_1`…`slot_5`, `use_gadget`, `interact`, `melee`, `throw_grenade`, `scoreboard`, `chat`, `voice`, `map`, `pause_menu`, `squad_menu`, `spot`, `vehicle_seat_next`, `vehicle_exit`).
- В `ARCHITECTURE.md` отражено использование `InputActions` (`res://src/core/input_actions.gd`) для обращения к `InputMap`.

## [step-0.4] — 2026-10-25

### Добавлено
- Автолоад `Events` (`src/autoload/events.gd`) — глобальная шина сигналов (`player_spawned`, `player_died`, `settings_changed`).
- Автолоад `Game` (`src/autoload/game.gd`) — состояние приложения (`MENU`/`IN_GAME`) и автоопределение флагов `is_dedicated` и `is_server` по `OS.has_feature("dedicated_server")` и аргументу `--server`.
- Автолоад `Log` (`src/autoload/log.gd`) — уровни `DEBUG`/`INFO`/`WARN`/`ERROR`, фильтрация `min_level`, префиксы времени и роли `[SERVER]/[CLIENT]`.
- Автолоад `Settings` (`src/autoload/settings.gd`) — управление `ConfigFile` (`user://settings.cfg`), геттеры/сеттеры с дефолтами для чувствительности, FOV, громкости и графики.
- Автолоад-заглушка `Net` (`src/autoload/net.gd`) с `TODO` для фазы 6.
- Модульные тесты `tests/unit/test_autoloads.gd` для проверки `Settings`, `Log`, `Game`, `Events` и `Net`.

### Изменено
- Зарегистрированы автолоады `Events`, `Game`, `Log`, `Settings`, `Net` в `project.godot`.
- Заполнена таблица автолоадов в `ARCHITECTURE.md`.

## [step-0.3] — 2026-10-25

### Добавлено
- Тестовый мини-раннер `tools/run_tests.gd` с перехватом ошибок через `Logger` Godot 4.7 и подсчётом `assert`-ов.
- Базовый класс модульных тестов `GutTest` (`addons/gut/test.gd`) и обёртка командной строки `addons/gut/gut_cmdln.gd`.
- Скрипт дымовой проверки сцен `tools/scene_smoke.gd` для рекурсивной проверки загрузки и инстанцирования `.tscn` в `src/` и `tests/`.
- Скрипты единой проверки проекта `tools/check.sh` и `tools/check.ps1`.
- Тривиальный модульный тест `tests/unit/test_sanity.gd`.

### Изменено
- В `ARCHITECTURE.md` зафиксировано решение по тестовой инфраструктуре для Godot 4.7.2.

## [step-0.2] — 2026-10-25

### Добавлено
- Документ `ASSETS.md` с таблицей учёта ассетов (`Файл | Источник | Автор | Лицензия | Дата`).
- Документ `BLOCKERS.md` для фиксации блокеров разработки.
- Полная таблица всех 138 шагов из `docs/STEPS.md` в `PROGRESS.md` (шаги `0.1` и `0.2` отмечены `DONE`, текущий шаг `0.3`).

## [step-0.1] — 2026-10-25

### Добавлено
- Конфигурация проекта `project.godot` для Godot `4.7.2.stable.official.ed1daf0bf` (`Frontline`, 1920×1080, `canvas_items`, рендерер `forward_plus`, физика `Jolt Physics`, 60 Гц, `max_fps = 0`).
- Имена 8 слоёв 3D-физики (`world`, `players`, `hitboxes`, `projectiles`, `vehicles`, `triggers`, `destructible`, `debris`).
- Конфигурационные файлы репозитория: `.gitignore`, `.gitattributes` (LF + Git LFS для `png`, `glb`, `ogg`, `wav`), `.editorconfig`.
- Иерархия пустых каталогов проекта (`tools/`, `addons/`, `tests/`, `src/`, `assets/`, `builds/`) с файлами `.gdkeep`.
- Документ `ARCHITECTURE.md` с таблицей ADR, версией движка и слоями физики.
