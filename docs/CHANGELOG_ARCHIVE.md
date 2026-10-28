# Changelog: ранние шаги

Архив записей; актуальные изменения — в [CHANGELOG.md](../CHANGELOG.md).

## [step-2.3] — 2026-10-26

### Добавлено
- `DamageCalc`: чистый расчёт дистанционного урона по множителю попавшего хитбокса. `DamageEvent`: атакующий, цель, зона, урон, id оружия, дистанция и точка попадания.
- `WeaponHitscan`: обработка `fired`, статический воспроизводимый разброс, отдельный луч на каждую дробину, исключение тела и хитбоксов стрелка, локальное применение урона к `HealthComponent`, сигналы `shot_traced` и `damage_applied`. Трассировка и урон запрещены сетевому клиенту; стены останавливают лучи. Необязательное пробитие пропущено.
- `tests/unit/test_damage_calc.gd` и `tests/unit/test_weapon_hitscan.gd`: 15 тестов на чистоту расчёта, зоны, дистанцию, AR (4 попадания в торс / 2 в голову на 10 м), сумму дробин (8 × 12 = 96 на 5 м), ненулевой разброс, воспроизводимость, препятствия/промах, дальность, исключение стрелка, повторные тики, блокировку, клиентский запрет и стрельбу игрока на полигоне.

### Изменено
- `WeaponData.hitscan_range`: настраиваемая максимальная дальность луча, по умолчанию 1000 м.
- `Player`, `player.tscn` и `tools/gen_player.gd`: подключены оружие с временным AR-профилем и хитскан; поза камеры симуляции передаётся после движения и обновления углов. Стрельба блокируется спринтом, воздухом и смертью; сохранена совместимость тестового компонента-записывателя урона.
- Проверка: `tools/check.sh` — 106 тестов, 4410 проверок, 0 ошибок; генератор игрока и загрузка всех сцен проходят; headless-полигон 180 кадров без ошибок/предупреждений Godot. Лимиты файлов/функций соблюдены, внешних ассетов нет. Визуальная проверка мышью и FPS требуют человека.

## [step-2.2] — 2026-10-26

### Добавлено
- `Weapon` (`src/weapons/weapon.gd`): автомат шести состояний, `simulate(PlayerInput, blocked)`, целочисленные сроки выстрела/перезарядки/смены оружия, режимы SEMI/AUTO/BURST и переключение между разрешёнными режимами `WeaponData`.
- Сигналы `fired(tick)`, `reload_started`, `reload_finished`, `ammo_changed(magazine, reserve)`; расход и перенос боезапаса только серверной симуляцией, без лучей и урона. Блокировка отменяет очередь; убирание оружия отменяет перезарядку без расхода резерва.
- `tests/unit/test_weapon_timing.gd` и `tests/unit/test_weapon_states.gd`: 20 тестов на 600 RPM / 60 тиков / 10 выстрелов, очереди по три, отпускание спуска, смену режима, границы перезарядки и смены оружия, блокировку, повторные тики, воспроизводимость и запрет симуляции сетевым клиентом.
- Проверка: `tools/check.sh` — 91 тест, 4307 проверок, 0 ошибок; headless-запуск полигона на 180 кадров без ошибок и предупреждений Godot. Лимиты файлов/функций соблюдены; внешних ассетов и изменений старого кода нет.

## [step-2.1] — 2026-10-26

### Добавлено
- `WeaponData` (`src/weapons/weapon_data.gd`): категории и режимы огня, параметры урона/боезапаса/обращения/представления, `cooldown()` и линейный `damage_at(distance)` с ограничением по дистанции.
- Восемь временных профилей в `src/weapons/data/`: `ar.tres`, `smg.tres`, `lmg.tres`, `dmr.tres`, `sniper.tres`, `shotgun.tres`, `pistol.tres`, `launcher.tres`. Внешние ассеты не используются.
- `tests/unit/test_weapon_data.gd`: граничные дистанции, интерполяция, перевод RPM в секунды, загрузка всех категорий и уникальность идентификаторов.
- `tests/unit/test_hitbox_cache.gd`: неизменность ресурсов форм и RID на 120 обновлениях, повторные `setup()`/`_ready()`, независимость форм игроков.

### Исправлено
- `PlayerHitboxes` (`src/player/player_hitboxes.gd`): повторный поиск узлов, пересоздание массива зон и дублирование пяти форм при каждом обновлении. Инициализация выполняется однократно, формы сохраняются на всё время жизни компонента; при создании новых зон устранено лишнее начальное дублирование форм.

## [step-1.8] — 2026-10-26

### Добавлено
- Тренировочная мишень `TargetDummy` (`src/maps/testbed/target_dummy.gd`), сцена `src/maps/testbed/target_dummy.tscn` и генератор `tools/gen_target_dummy.gd`: `HealthComponent`, хитбоксы `PlayerHitboxes`, процедурный визуал (капсула + сфера), стоячий режим и патруль по точкам (`set_patrol_path(points, speed)`), отключение хитбоксов и скрытие при смерти, респавн через `respawn_delay = 3.0` с. Сигналы `health_changed`, `died`, `respawned`.
- Базовый HUD `HUD` (`src/ui/hud/hud.gd`), сцена `src/ui/hud/hud.tscn` и генератор `tools/gen_hud.gd`: полоска и текст здоровья, прицел-точка, индикатор стойки (`STAND`/`CROUCH`/`PRONE`), заглушка боезапаса (`set_ammo`). Подписан на `HealthComponent.health_changed`/`died` и `StanceController.stance_changed`, `_process` не используется.
- Консольная команда `damage <n>` в `DebugConsole` (`src/ui/debug_console.gd`): сигнал `damage_requested`, цель — `damage_target`, иначе `Game.debug["local_health_component"]`, иначе `HealthComponent` узла `Player`.
- Тесты `tests/unit/test_target_dummy_and_hud.gd`.

### Изменено
- `tools/gen_testbed.gd` и `src/maps/testbed/testbed.tscn`: добавлены узел `Targets` с 5 мишенями (3 стоячие, 2 патрульные), `HUD` и `DebugOverlay`.
- `src/player/player.gd`: локальный игрок регистрирует свой `HealthComponent` в `Game.debug["local_health_component"]` и снимает регистрацию в `_exit_tree`.

## [step-1.7] — 2026-10-26

### Добавлено
- Ресурс конфигурации хитбоксов `HitboxConfig` (`src/player/hitbox_config.gd`) и базовый профиль `src/player/default_hitboxes.tres` с множителями урона по зонам (`head_mult = 2.0`, `torso_mult = 1.0`, `arms_mult = 0.8`, `legs_mult = 0.75`) и габаритами зон.
- Узел зоны попадания `HitboxZone` (`src/player/hitbox_zone.gd`, `Area3D` на слое `hitboxes = 4`, `collision_mask = 0`, `monitoring = false`) с зонами `HEAD`, `TORSO`, `ARMS`, `LEGS`, полем `damage_mult`, ссылкой `health_component` (`owner_health`) и методом `apply_damage(...)`.
- Узел набора хитбоксов игрока `PlayerHitboxes` (`src/player/player_hitboxes.gd`), создающий зоны `HeadZone` (`SphereShape3D`), `TorsoZone`, `LeftArmZone`, `RightArmZone`, `LegsZone` (`BoxShape3D`) и подгоняющий их размеры и координаты под текущую стойку (`STAND`, `CROUCH`, `PRONE`) и смещение наклона `lean_offset`.
- Класс результата попадания `HitResult` (`src/weapons/hit_result.gd`) и трассировщик лучей `HitscanQuery` (`src/weapons/hitscan_query.gd`) с методом `HitscanQuery.cast(from, to, exclude) -> HitResult` (`collide_with_areas = true`, `collide_with_bodies = true`, маска `world + hitboxes = 5`).
- Модульные и интеграционные тесты `tests/unit/test_hitboxes.gd` (множители и слои `HitboxZone`, попадания в голову/торс/руки/ноги и пол на `testbed.tscn`, адаптация зон к стойкам `STAND`/`CROUCH`/`PRONE` и наклону, исключение `exclude` и отсутствие помех движению игрока).

### Изменено
- В `src/player/player.gd`, `tools/gen_player.gd` и `src/player/player.tscn` интегрирован узел `Hitboxes` (`PlayerHitboxes`) с синхронизацией размеров и позиций зон в `step_simulation` и методом `get_hitscan_exclude_rids()`.

## [step-1.6] — 2026-10-26

### Добавлено
- Компонент здоровья `HealthComponent` (`src/core/health_component.gd`) с сигналами `health_changed(current, max_value)`, `damaged(amount, source_id, zone)`, `died(killer_id)`, методами `apply_damage(...)` (и алиасом `take_damage(...)`), `heal(amount)`, `reset()` для респавна и опциональной регенерацией (`regen_enabled = false`, `regen_delay = 5.0`, `regen_rate = 0.0`, метод `step_regen(delta)`).
- Модульные тесты `tests/unit/test_health_component.gd` (нанесение урона, смерть ровно один раз, игнорирование урона мёртвому, ограничение лечения `max_health`, `reset()` при респавне, опциональная регенерация и интеграция в `player.tscn`).

### Изменено
- В `tools/gen_player.gd`, `src/player/player.tscn` и `src/player/player.gd` добавлен дочерний узел `HealthComponent` и вызов `apply_damage(...)` при уроне от падения.

## [step-1.5] — 2026-10-26

### Добавлено
- В `MovementConfig` (`src/player/movement_config.gd`) и `src/player/default_movement.tres` добавлены параметры спринта и опциональной выносливости (`sprint_min_forward_dot = 0.5`, `stamina_enabled = false`, `max_stamina = 100.0`, `stamina_drain_rate = 20.0`, `stamina_regen_rate = 15.0`, `stamina_regen_delay = 1.0`), `coyote_time = 0.1`, автоподъёма на ступени (`step_height = 0.35`, `step_probe_distance = 0.08`) и расчёта урона от падения (`fall_damage_min_speed = 12.0`, `fall_damage_scale = 10.0`, `fall_damage_max = 100.0`, метод `calculate_fall_damage(vertical_velocity)`).
- В `PlayerMotor` (`src/player/player_motor.gd`) реализованы:
  - ограничение спринта направлением вперёд (`move_dir.y >= sprint_min_forward_dot`) и запрет спринта в `CROUCH` / `PRONE`;
  - система опциональной выносливости (`stamina`, `is_sprinting`) с бесконечным спринтом по умолчанию (`stamina_enabled = false`);
  - окно `coyote_time` (`0.1` с) для одиночного прыжка после схода с уступа;
  - детерминированный автоподъём на ступени до `0.35` м (`test_move` вверх → вперёд → вниз с переиспользуемым `KinematicCollision3D`) без вертикальных подпрыгиваний;
  - фиксация приземления (`landed_this_tick`) и расчёт `last_fall_damage` при вертикальной скорости ниже `−12` м/с.
- В `Player` (`src/player/player.gd`) добавлены сигнал `fall_damaged(amount)`, поле `last_fall_damage` и метод `apply_fall_damage(amount)` с локальной передачей урона в узел `HealthComponent` (`take_damage`).
- Модульные тесты `tests/unit/test_player_step_fall_sprint.gd` (значения в `MovementConfig`, спринт только вперёд и запрет в присяде/лёжа, расход и восстановление выносливости, `coyote_time = 0.1` с, подъём на ступень `0.35` м и блокировка `0.50` м, пробежка по лестнице на `testbed.tscn` без подпрыгиваний, падение с `2` м без урона и с `8` м с уроном).

## [step-1.4] — 2026-10-25

### Добавлено
- Класс перечисления стоек `PlayerStance` (`src/player/player_stance.gd`) со значениями `STAND = 0`, `CROUCH = 1`, `PRONE = 2`.
- Компонент управления стойками и наклонами `StanceController` (`src/player/stance_controller.gd`):
  - плавное изменение высоты капсулы (`1.8` / `1.2` / `0.5` м) и высоты `Head` (`1.65` / `1.05` / `0.35` м) с фиксацией нижней точки капсулы на уровне ступней (`CollisionShape3D.position.y = height * 0.5`) и клонированием `CapsuleShape3D` на экземпляр игрока;
  - проверка препятствий над головой перед подъёмом в более высокую стойку через `CharacterBody3D.test_move(...)` и вертикальный луч;
  - двухэтапный подъём из положения лёжа в положение стоя (`PRONE -> CROUCH -> STAND`) за `0.6` с (`0.3` с до `CROUCH` + `0.3` с до `STAND`);
  - наклоны влево/вправо (`BTN_LEAN_L` / `BTN_LEAN_R`) на `±15°` и смещение головы `±0.4` м с проверкой стены через переиспользуемый `PhysicsRayQueryParameters3D`.
- Модульные тесты `tests/unit/test_player_stance.gd` (неизменность высоты ступней при смене стоек, запрет прыжка лёжа, подъём `PRONE -> CROUCH -> STAND` за `0.6` с, блокировка подъёма под низким потолком, проползание в туннеле `1.0` м на `testbed.tscn` с блокировкой подъёма внутри, наклоны `±15°`/`±0.4` м и ограничение у стены).

### Изменено
- В `MovementConfig` (`src/player/movement_config.gd`) и `src/player/default_movement.tres` добавлены параметры высот капсулы и камеры по стойкам, длительности переходов (`stance_step_time = 0.2`, `prone_to_stand_time = 0.6`) и наклонов (`lean_angle_deg = 15.0`, `lean_offset = 0.4`, `lean_speed = 10.0`, `lean_wall_margin = 0.25`).
- В `PlayerMotor` (`src/player/player_motor.gd`) запрещены прыжок и спринт при активных кнопках приседа/лёжа или вне стойки `PlayerStance.STAND`.
- В `Player` (`src/player/player.gd`), `tools/gen_player.gd` и `src/player/player.tscn` интегрирован узел `StanceController`, высота `Head` в стойке стоя обновлена до `1.65` м, а в `update_camera_visuals` учтены локальное смещение `Head` и крен `Head.rotation.z`.

## [step-1.3] — 2026-10-25

### Добавлено
- Обзор мышью в `LocalInputReader` (`src/player/local_input_reader.gd`): методы `apply_mouse_delta(...)` и `handle_input_event(...)`, накопление `yaw`, жёсткое ограничение `pitch` в пределах `±89°` (`MAX_PITCH_DEG = 89.0`), чтение чувствительности (`sensitivity`) и инверсии оси Y (`invert_y`) из `Settings`.
- Новые настройки в `Settings` (`src/autoload/settings.gd`): `invert_y` (по умолчанию `false`), `camera_effects` (по умолчанию `true`) и ограничение `fov` диапазоном `60.0–120.0` (по умолчанию `90.0`).
- Узел процедурных визуальных эффектов камеры `CameraEffects` (`src/player/camera_effects.gd`): расчёт дыхания в покое и покачивания головы (head bob) при движении по земле без влияния на физическую симуляцию, отключение через `Settings`.
- Модульные тесты `tests/unit/test_player_camera.gd` (накопление `yaw`, кламп `pitch` в `±89°`, чувствительность и `invert_y`, диапазон `FOV` `60–120`, захват и освобождение курсора по `Esc`, физическая интерполяция и переключение `CameraEffects`).

### Изменено
- В `project.godot` включена физическая интерполяция `physics/common/physics_interpolation=true`.
- В `Player` (`src/player/player.gd`), `tools/gen_player.gd` и `src/player/player.tscn` добавлен узел `Head/CameraEffects`, настроена синхронизация `Camera3D.fov` с `Settings`, захват курсора (`MOUSE_MODE_CAPTURED`) и освобождение по `InputActions.PAUSE_MENU` (`Esc`), а также сглаживание `Camera3D` (`PHYSICS_INTERPOLATION_MODE_OFF`) через `head.get_global_transform_interpolated().origin`.
- В `tools/gen_testbed.gd` и `src/maps/testbed/testbed.tscn` добавлен спавн экземпляра `Player` в точке `PlayerSpawn`.

## [step-1.2] — 2026-10-25

### Добавлено
- Структура ввода одного физического тика `PlayerInput` (`src/player/player_input.gd`) с флагами кнопок (`BTN_JUMP` … `BTN_LEAN_R`), полями `tick`, `move`, `yaw`, `pitch`, `buttons` и методом `pressed(btn)`.
- Ресурс конфигурации параметров передвижения `MovementConfig` (`src/player/movement_config.gd`) и базовый профиль `src/player/default_movement.tres` (ходьба 4.0 м/с, бег 6.5 м/с, присед 2.0 м/с, лёжа 0.8 м/с, ускорение на земле 40.0 м/с² и в воздухе 10.0 м/с², высота прыжка 1.1 м, гравитация 15.0 м/с², максимальный угол склона 45°).
- Чистый мотор симуляции перемещения `PlayerMotor` (`src/player/player_motor.gd`, метод `simulate(...)`), зависящий только от состояния тела, `PlayerInput`, `MovementConfig`, `stance` и `delta`.
- Сборщик клиентского ввода `LocalInputReader` (`src/player/local_input_reader.gd`) на базе `InputActions`.
- Скрипт `Player` (`src/player/player.gd`), генератор `tools/gen_player.gd` и сцена `src/player/player.tscn` (`CharacterBody3D`, капсула 1.8 м × 0.35 м, `Head`, `Camera3D`, слой `players` = 2, маска `world` = 1).
- Модульные тесты `tests/unit/test_player_motor.gd` (проверка торможения до 0, разгона до целевой скорости за 1 с, высоты прыжка ±5% и прохождения склона 45° на полигоне).

## [step-1.1] — 2026-10-25

### Добавлено
- Процедурный шейдер метровой разметки `src/maps/testbed/grid_1m.gdshader` в мировых координатах (шаг 1 м и 10 м).
- Генератор полигона `tools/gen_testbed.gd` и сгенерированная сцена `src/maps/testbed/testbed.tscn`: пол 200×200 м, `WorldEnvironment` (небо + ambient), `DirectionalLight3D` с тенями, маркер `PlayerSpawn`, препятствия на слое физики `world` (`1`) — стены 1.0/1.5/2.0/3.0 м, рампы 15°/30°/45°, лестница (10 ступеней по 0.2 м), коридор шириной 0.8 м, туннель высотой 1.0 м и площадка со стрельбищем (`ShootingRange`, мишени на 10/25/50/100/200 м).
- Модульные тесты `tests/unit/test_testbed.gd` для проверки структуры, размеров, материалов, высот препятствий и физических слоёв полигона.

## [step-0.6] — 2026-10-25

### Добавлено
- Сцена отладочного оверлея `src/ui/debug_overlay.tscn` и скрипт `DebugOverlay` (`src/ui/debug_overlay.gd`) на базе `CanvasLayer`: отображение FPS, времени кадра (ms), памяти (MiB), числа узлов, позиции локального игрока (заглушка) и пинга (заглушка), переключение оверлея по `F3` и консоли по `` ` `` (`KEY_QUOTELEFT`).
- Класс отладочной консоли и парсера команд `DebugConsole` (`src/ui/debug_console.gd`) с регистрацией команд через словарь `name -> Callable` и встроенными командами `help`, `fps <n>`, `net_sim <ping_ms> <loss_%>`, `god`, `noclip`.
- Словарь `Game.debug` и метод `Game.reset_debug()` в `src/autoload/game.gd`.
- Модульные тесты `tests/unit/test_debug_overlay.gd` для парсера команд, всех встроенных команд консоли и переключения оверлея/консоли.

### Исправлено
- В `tools/scene_smoke.gd` точка входа заменена с `_init()` на `_initialize()`, чтобы проверка загрузки `.tscn`-сцен выполнялась после регистрации автолоадов в `SceneTree`.

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
