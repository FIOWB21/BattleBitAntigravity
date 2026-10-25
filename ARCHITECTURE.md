# ARCHITECTURE

## Решения (ADR)

| Область | Решение | Комментарий |
| --- | --- | --- |
| Движок | Godot `4.7.2.stable.official.ed1daf0bf` (standard build, не .NET) | Проверено через `$GODOT --version` на шаге 0.1 |
| Язык | GDScript (строгая типизация) | C++/GDExtension только для доказанных узких мест (Фаза 13) |
| Рендер | Forward+ (`forward_plus`) для ПК | Опции Mobile/Compatibility не поддерживаются |
| Физика | Jolt Physics (`Jolt Physics`) | Настроено в `physics/3d/physics_engine` |
| Тик физики | 60 Гц | Сетевая отправка состояния 30 Гц |
| Сеть | `ENetMultiplayerPeer` (UDP), High-level Multiplayer API, свой слой предсказания | Без сторонних сетевых аддонов |
| Модель авторитета | Сервер решает всё: урон, смерти, захват, спавн | Клиент отправляет только ввод (`PlayerInput`) |
| Стрельба | Hitscan (серверный, с компенсацией лага) для винтовок/пистолетов; снаряды для гранат/ракет/танка | |
| Данные | `Resource` (`.tres`) для оружия, классов, карт, режимов | Никаких магических чисел в логике |
| Тесты | Собственный мини-раннер `tools/run_tests.gd` + базовый класс `GutTest` (`addons/gut/test.gd`) и обёртка `addons/gut/gut_cmdln.gd` | Полная совместимость с Godot 4.7.2 (`Logger`), строгая типизация, поддержка `assert_*` и встроенного `assert()` |
| Террейн | Свой чанковый heightmap-меш | Terrain3D — только при подтверждённой совместимости с 4.7 |
| Персонаж | `Skeleton3D` + `AnimationTree`, анимации CC0 | Лицензии фиксируются в `ASSETS.md` |
| Боты | `NavigationServer3D` + конечный автомат | Фаза 10 |
| Хранилище | `ConfigFile`/JSON локально | Бэкенд-аккаунты — вне MVP |

## Слои физики (3D)

| № | Имя (`layer_names/3d_physics`) | Битовая маска | Назначение |
| --- | --- | --- | --- |
| 1 | `world` | `1` (`1 << 0`) | Статичная геометрия, террейн |
| 2 | `players` | `2` (`1 << 1`) | Капсулы игроков (движение) |
| 3 | `hitboxes` | `4` (`1 << 2`) | Хитбоксы тела/головы (только для лучей стрельбы) |
| 4 | `projectiles` | `8` (`1 << 3`) | Гранаты, ракеты |
| 5 | `vehicles` | `16` (`1 << 4`) | Техника |
| 6 | `triggers` | `32` (`1 << 5`) | Зоны захвата, пикапы, зоны спавна |
| 7 | `destructible` | `64` (`1 << 6`) | Разрушаемые объекты |
| 8 | `debris` | `128` (`1 << 7`) | Обломки (не коллизят с игроками) |

## Автолоады и их ответственность

| Автолоад | Путь | Ответственность |
| --- | --- | --- |
| `Events` | `res://src/autoload/events.gd` | Глобальная шина событий (`player_spawned`, `player_died`, `settings_changed`) |
| `Game` | `res://src/autoload/game.gd` | Глобальное состояние приложения (`State.MENU`, `State.IN_GAME`), флаги роли (`is_server`, `is_dedicated` по `OS.has_feature("dedicated_server")` и `--server`) и словарь отладочных параметров `debug` (`ping_ms`, `loss_percent`, `god`, `noclip`, `player_position`, `max_fps`) |
| `Log` | `res://src/autoload/log.gd` | Глобальный логгер с уровнями `DEBUG`, `INFO`, `WARN`, `ERROR`, фильтрацией по `min_level` и префиксом времени и роли `[SERVER]/[CLIENT]` |
| `Settings` | `res://src/autoload/settings.gd` | Хранение и загрузка пользовательских настроек в `user://settings.cfg` (`ConfigFile`: чувствительность, FOV, громкость, графика) с дефолтами и отправкой `Events.settings_changed` |
| `Net` | `res://src/autoload/net.gd` | Каркас сетевого менеджера (заглушка с `TODO` до фазы 6) |

## Отладочный оверлей и консоль

- **`DebugOverlay` (`res://src/ui/debug_overlay.tscn`, `res://src/ui/debug_overlay.gd`)** — слой `CanvasLayer` с панелью телеметрии `StatsPanel` (FPS, кадр в мс, память в MiB, число узлов, позиция локального игрока и пинг из `Game.debug`, переключение по `F3`) и панелью консоли `ConsolePanel` (переключение по `` ` `` / `KEY_QUOTELEFT`).
- **`DebugConsole` (`res://src/ui/debug_console.gd`)** — `RefCounted`-реестр и парсер команд (`commands: Dictionary` вида `name -> Callable`), предоставляющий встроенные команды `help`, `fps <n>`, `net_sim <ping_ms> <loss_%>`, `god`, `noclip`.

## Генерация сцен и полигон (`Testbed`)

- **Генераторы сцен (`tools/gen_*.gd`)** — сцены создаются воспроизводимыми headless-скриптами (`PackedScene.pack()` + `ResourceSaver.save()`).
- **Тестовый полигон (`res://src/maps/testbed/testbed.tscn`, генератор `res://tools/gen_testbed.gd`)** — уровень 200×200 м с процедурным шейдером метровой сетки (`res://src/maps/testbed/grid_1m.gdshader`), окружением `WorldEnvironment`, солнцем `DirectionalLight3D`, точкой спавна `PlayerSpawn`, препятствиями для тестирования передвижения (стены 1.0–3.0 м, рампы 15°/30°/45°, лестница 0.2 м, коридор 0.8 м, туннель 1.0 м) и стрельбищем (`ShootingRange`, мишени на 10/25/50/100/200 м). Все коллайдеры находятся на физическом слое `world` (`1`).

## Поток данных: ввод → симуляция → представление

1. **Ввод (`PlayerInput`, `LocalInputReader`)** — структура ввода за один физический тик (`res://src/player/player_input.gd`: направления `move`, углы взгляда `yaw`/`pitch`, битовая маска кнопок `buttons`, номер тика `tick`). На клиенте-владельце `LocalInputReader` (`res://src/player/local_input_reader.gd`) собирает `PlayerInput` из глобального `Input` исключительно через `StringName`-константы `InputActions` (`res://src/core/input_actions.gd`).
2. **Симуляция (`PlayerMotor`, `MovementConfig`, `Player`)** — детерминированный расчёт движения в `PlayerMotor.simulate(body, inp, cfg, stance, delta)` (`res://src/player/player_motor.gd`) по `PlayerInput`, ресурсу параметров `MovementConfig` (`res://src/player/movement_config.gd`, `res://src/player/default_movement.tres`) и `delta` (60 Гц) без прямых обращений к `Input.*`. Сцена игрока `res://src/player/player.tscn` (`Player`, генератор `res://tools/gen_player.gd`) представляет `CharacterBody3D` на слое `players` (`2`) с маской `world` (`1`), капсулой `1.8 × 0.35` м и узлами `Head`/`Camera3D`. Игровая логика (урон, смерть, захват, боезапас) авторитетна на сервере.
3. **Представление** — интерполяция визуала, камера, анимации, звуки и частицы (только косметика, не влияет на симуляцию).

## Сетевая модель

- Выделенный headless-сервер (`ENetMultiplayerPeer`) + клиенты.
- Клиент предсказывает собственное перемещение и выполняет сверку (reconciliation) с серверными снапшотами.
- Удалённые сущности отображаются через буфер интерполяции.

## Соглашения по именованию

- Файлы и каталоги: `snake_case`
- Классы (`class_name`): `PascalCase`
- Константы и элементы `enum`: `UPPER_SNAKE`
- Сигналы: глаголы в прошедшем времени (`health_changed`, `player_died`)
- Приватные поля и методы: префикс `_` (`_velocity`, `_apply_recoil()`)
- Отступы: табы (`\t`), переводы строк `LF`
