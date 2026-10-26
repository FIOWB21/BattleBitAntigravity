# ARCHITECTURE

## Решения (ADR)

| Область | Решение | Комментарий |
| --- | --- | --- |
| Движок | Godot `4.7.2.stable.official.ed1daf0bf` (standard build, не .NET) | Проверено через `$GODOT --version` на шаге 0.1 |
| Язык | GDScript (строгая типизация) | C++/GDExtension только для доказанных узких мест (Фаза 13) |
| Рендер | Forward+ (`forward_plus`) для ПК | Опции Mobile/Compatibility не поддерживаются |
| Физика | Jolt Physics (`Jolt Physics`) | Настроено в `physics/3d/physics_engine` |
| Тик физики | 60 Гц | Сетевая отправка состояния 30 Гц |
| Сглаживание камеры и физики | `physics/common/physics_interpolation=true`, `Camera3D` в режиме `PHYSICS_INTERPOLATION_MODE_OFF` | `Player` и `Head` интерполируются движком на 60 Гц, а `Camera3D` обновляется в `_process` по `head.get_global_transform_interpolated().origin` + покадровым `yaw`/`pitch` и `CameraEffects`, исключая конфликт тиковой интерполяции с обзором мыши на 144+ FPS |
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
- **`DebugConsole` (`res://src/ui/debug_console.gd`)** — `RefCounted`-реестр и парсер команд (`commands: Dictionary` вида `name -> Callable`), предоставляющий встроенные команды `help`, `fps <n>`, `net_sim <ping_ms> <loss_%>`, `god`, `noclip`, `damage <n>` (отладочный локальный урон: `damage_target` → `Game.debug["local_health_component"]` → `HealthComponent` узла `Player`).

## HUD

- **`HUD` (`res://src/ui/hud/hud.tscn`, `res://src/ui/hud/hud.gd`, генератор `res://tools/gen_hud.gd`)** — `CanvasLayer` (слой `10`) с прицелом-точкой, полоской/текстом здоровья, индикатором стойки и заглушкой боезапаса. Обновляется только по сигналам: `bind_player(player)` подписывает HUD на `HealthComponent.health_changed`/`died` и `StanceController.stance_changed`. Опроса в `_process` нет. При добавлении в сцену рядом с узлом `Player` HUD сам привязывается к нему (`_auto_bind_from_parent`).

## Данные оружия

- **`WeaponData` (`src/weapons/weapon_data.gd`)** — типизированный `Resource` с категориями и режимами огня, параметрами урона, боезапаса, обращения и необязательными ссылками на модели/звук. `cooldown()` переводит RPM в секунды; `damage_at(distance)` линейно интерполирует урон между `range_near` и `range_far`, ограничивая его на крайних дистанциях.
- **`src/weapons/data/*.tres`** — по одному временному профилю для `AR`, `SMG`, `LMG`, `DMR`, `SNIPER`, `SHOTGUN`, `PISTOL`, `LAUNCHER`; уникальные `id` имеют префикс `sample_`. Значения временные; на шаге 2.2 профили используются отдельным автоматом `Weapon`, без подключения к `Player`.

## Машина состояний оружия

- **`Weapon` (`src/weapons/weapon.gd`, `Node3D`)** — состояния `IDLE`, `FIRING`, `RELOADING`, `SWITCHING_IN`, `SWITCHING_OUT`, `BLOCKED`; явный вызов `simulate(inp: PlayerInput, blocked: bool)` раз в тик. Повторные и старые `inp.tick` игнорируются; пропущенные тики не воспроизводятся автоматически.
- Частота `ticks_per_second` берётся из `Engine.physics_ticks_per_second` и фиксируется на время симуляции. Интервалы из `WeaponData` округляются вверх до целого тика (минимум один): `next_fire_tick`, `reload_end_tick`, `switch_end_tick`. `Timer`, системное время и покадровые массивы не используются.
- `BTN_FIRE`/`BTN_RELOAD` читаются из `PlayerInput`; режимы `SEMI` и `BURST` требуют нового нажатия. Начатая очередь завершается после отпускания спуска. `cycle_fire_mode()` перебирает только разрешённые профилем режимы и отменяет остаток очереди, сохраняя задержку выстрела.
- `blocked` вычисляется вызывающей симуляцией движения (спринт/лестница/падение), запрещает начало стрельбы/перезарядки и отменяет очередь. Уже начатая перезарядка завершается по своему сроку; при сохраняющейся блокировке оружие затем переходит в `BLOCKED`.
- Боезапас: магазин `mag_size`, резерв `mag_size * reserve_mags`; перенос патронов только в конце `reload_time` либо `reload_empty_time`. `switch_out()` отменяет перезарядку без переноса патронов; после убирания оружие остаётся заблокированным до `switch_in()`. Обе смены используют имеющийся `draw_time`; команды отсчитываются от последнего обработанного тика и вызываются после него.
- Симуляция и команды разрешены только серверному `MultiplayerAPI` (включая офлайн-сервер); сетевой клиент не меняет состояние. Сигналы `fired(tick)`, `reload_started`, `reload_finished`, `ammo_changed(magazine, reserve)` отделены от представления. Лучи, урон, модели и интеграция с игроком на этом шаге не добавляются.

## Хитскан-стрельба и урон (шаг 2.3)

- **`WeaponHitscan` (`src/weapons/weapon_hitscan.gd`)** — компонент `Node3D`, связывающий сигнал `Weapon.fired(tick)` с существующим `HitscanQuery`. `setup()` кеширует оружие, идентификатор атакующего и RID тела/хитбоксов стрелка; повторная настройка заменяет подписку. `simulate(inp, aim, blocked)` передаёт ввод автомату оружия. Трассировка и применение урона разрешены только серверному `MultiplayerAPI`, включая офлайн-сервер.
- `Player.step_simulation()` передаёт оптическую позу камеры симуляции: `head.global_position`, `inp.yaw`, ограниченный `inp.pitch` и крен наклона. Поза не читает интерполированную камеру рендера и косметические `CameraEffects`. Оружие блокируется при спринте, в воздухе и после смерти. В сцену игрока и генератор добавлены `Weapon` с временным AR-профилем и `WeaponHitscan`.
- На один `fired` выполняется `WeaponData.pellets` лучей длиной `hitscan_range` (по умолчанию 1000 м). Конус задаёт максимальное отклонение от оптической оси, распределение равномерно по телесному углу. С шага 2.4 конус и направления вычисляет `WeaponHandling`, описанный ниже; каждый луч получает seed от атакующего, тика и номера дробины. Одинаковые ввод и мир дают одинаковые направления.
- **`DamageCalc.compute(weapon, distance, zone)` (`src/weapons/damage_calc.gd`)** — чистая функция: `weapon.damage_at(distance) × zone.damage_mult`, без изменения ресурсов, зоны или здоровья. Источник множителя — попавший `HitboxZone`; `WeaponData.headshot_mult`/`limb_mult` дополнительно не умножаются. Дистанция измеряется от начала луча до точки пересечения, геометрия мира останавливает луч.
- **`DamageEvent` (`src/weapons/damage_event.gd`)** — снимок одного попадания: `attacker` (идентификатор), `target` (сущность), `zone`, `damage`, `weapon` (id ресурса), `distance`, `point`. Положительный рассчитанный урон локально передаётся в `HealthComponent.apply_damage(damage, attacker, zone)`; затем испускается `damage_applied(event)`. `shot_traced` сообщает результат каждой дробины, включая промах и стену. Расход патрона остаётся ответственностью автомата `Weapon`: один патрон на все дробины выстрела.
- Внешние ассеты не добавлены. Необязательное пробитие поверхностей пропущено; параметр `penetration` пока не участвует в трассировке. Сетевой транспорт событий не добавлен.

## Отдача и динамический разброс (шаг 2.4)

- **`WeaponHandling` (`src/weapons/weapon_handling.gd`)** — чистое состояние `RefCounted`: накопленная отдача в градусах (`Vector2`: pitch вверх / yaw), добавочный разброс, индекс паттерна и последние принятые тик/выстрел. `advance(tick, ticks_per_second)` восстанавливает разброс со временем, отдачу — после `recoil_pause`; повторные/старые тики игнорируются. Пропущенные тики учитываются как прошедший интервал, без создания пропущенных выстрелов.
- На подтверждённый `Weapon.fired` после трассировки один раз вызывается `apply_shot()`: берётся следующий `recoil_pattern[i]`, после исчерпания — `recoil_fallback_deg` плюс ограниченный шум. Seed шума зависит от атакующего и тика с отдельным каналом; количество дробин не влияет на отдачу. Пауза сбрасывает индекс паттерна. `Weapon.configured` сбрасывает состояние при `setup()` оружия; повторная привязка хитскана заменяет подписки и сбрасывает обработку.
- `spread_degrees()` вычисляет `(base + bloom + speed * move_factor) * stance_mult` с ограничением `spread_max_deg`: `base` выбирается между `spread_hip_deg` и `spread_ads_deg`, в ADS добавка от стрельбы и движения умножается на `spread_ads_extra_mult`. Присяд и положение лёжа используют собственные множители. `bloom` растёт только после выстрела до `spread_max_bloom_deg`, затем линейно убывает. `spread_direction()` использует кешированный `RandomNumberGenerator`, seed от атакующего/тика/дробины и равномерный по телесному углу конус вокруг переданной оси.
- `Player` передаёт фактическую горизонтальную скорость и текущую стойку; ADS читается из уже существующего `PlayerInput.BTN_AIM`. `WeaponHitscan` применяет накопленную отдачу к позе симуляции до трассировки. Импульс текущего выстрела влияет на камеру и следующий выстрел. Камера использует ту же `aim_rotation()` с ограничением pitch ±89°, затем добавляет косметические `CameraEffects`; настройка косметики не отключает отдачу. `LocalInputReader` и `Head` сохраняют исходные углы: движение мыши компенсирует накопленное смещение.
- Все параметры находятся в `WeaponData` и восьми временных профилях `src/weapons/data/*.tres`. Новых узлов/автолоадов, сетевого транспорта и внешних ассетов нет. Клиентский `MultiplayerAPI` не выполняет авторитетную симуляцию, не трассирует лучи и не добавляет отдачу. Применяется существующая офлайн-серверная интеграция; визуальное оружие, анимация/FOV ADS сюда не входят.
- 19 тестов в `tests/unit/test_weapon_handling.gd` и `tests/unit/test_weapon_handling_integration.gd`: паттерн/шум и seed, независимость от RNG разброса, пауза/восстановление, пропуски/повторы тиков, рост/предел/затухание разброса, скорость/стойки/ADS, 8192 направления в повёрнутых конусах, компенсация, один импульс на дробовик, отсутствие импульсов при блокировке/перезарядке/на клиенте, сброс настройки и совпадение камеры с осью следующего выстрела на полигоне. Оценка ощущений остаётся обязательной ручной приёмкой.

## Жизненный цикл хитбоксов

- `PlayerHitboxes` однократно находит или создаёт зоны и кеширует ссылки на зоны и формы. Формы из сцены дублируются только при первой инициализации, чтобы каждый экземпляр владел своим ресурсом; для новых зон формы создаются сразу без лишнего дублирования. Повторные `setup()`, `_ready()` и обновления стойки используют те же формы и RID. Обновление геометрии не выполняет поиск узлов и не создаёт формы или массив зон заново.

## Тренировочные мишени

- **`TargetDummy` (`res://src/maps/testbed/target_dummy.tscn`, `res://src/maps/testbed/target_dummy.gd`, генератор `res://tools/gen_target_dummy.gd`)** — `Node3D` без физического тела: `HealthComponent` + `PlayerHitboxes` (стойка `STAND`, слой `hitboxes`) + узел `Visuals`. Режимы: стоячий или патруль по `waypoints` со скоростью `move_speed` (`set_patrol_path`). При `died` хитбоксы отключаются, визуал скрывается, через `respawn_delay` (3 с) вызывается `HealthComponent.reset()`. Логика шага вынесена в `step(delta)` и вызывается из `_physics_process`, поэтому тестируется детерминированно.

## Генерация сцен и полигон (`Testbed`)

- **Генераторы сцен (`tools/gen_*.gd`)** — сцены создаются воспроизводимыми headless-скриптами (`PackedScene.pack()` + `ResourceSaver.save()`).
- **Тестовый полигон (`res://src/maps/testbed/testbed.tscn`, генератор `res://tools/gen_testbed.gd`)** — уровень 200×200 м с процедурным шейдером метровой сетки (`res://src/maps/testbed/grid_1m.gdshader`), окружением `WorldEnvironment`, солнцем `DirectionalLight3D`, точкой спавна `PlayerSpawn`, препятствиями для тестирования передвижения (стены 1.0–3.0 м, рампы 15°/30°/45°, лестница 0.2 м, коридор 0.8 м, туннель 1.0 м) и стрельбищем (`ShootingRange`, мишени на 10/25/50/100/200 м), узлом `Targets` с 5 экземплярами `TargetDummy` (3 стоячие, 2 патрульные), а также `HUD` и `DebugOverlay`. Все коллайдеры находятся на физическом слое `world` (`1`).

## Поток данных: ввод → симуляция → представление

1. **Ввод (`PlayerInput`, `LocalInputReader`)** — структура ввода за один физический тик (`res://src/player/player_input.gd`: направления `move`, углы взгляда `yaw`/`pitch`, битовая маска кнопок `buttons`, номер тика `tick`). На клиенте-владельце `LocalInputReader` (`res://src/player/local_input_reader.gd`) собирает `PlayerInput` из глобального `Input` исключительно через `StringName`-константы `InputActions` (`res://src/core/input_actions.gd`), накапливает `yaw` и ограничивает `pitch` диапазоном `±89°` с учётом `sensitivity` и `invert_y` из `Settings`.
2. **Симуляция (`PlayerStance`, `StanceController`, `PlayerMotor`, `MovementConfig`, `HealthComponent`, `HitboxConfig`, `HitboxZone`, `PlayerHitboxes`, `HitscanQuery`, `Player`)** — детерминированный расчёт стоек, наклонов, бега, прыжка, подъёма на ступени, приземления, здоровья и хитбоксов по `PlayerInput`, ресурсу параметров `MovementConfig` (`res://src/player/movement_config.gd`, `res://src/player/default_movement.tres`) и `delta` (60 Гц) без прямых обращений к `Input.*`. Компонент `StanceController` (`res://src/player/stance_controller.gd`, перечисление `PlayerStance` в `res://src/player/player_stance.gd`) управляет стойками `STAND` / `CROUCH` / `PRONE` (высота капсулы `1.8` / `1.2` / `0.5` м, высота камеры `1.65` / `1.05` / `0.35` м, фиксация ступней через `CollisionShape3D.position.y = height * 0.5`), проверяет препятствия над головой через `CharacterBody3D.test_move(...)`, выполняет подъём `PRONE -> CROUCH -> STAND` за `0.6` с и рассчитывает наклоны (`BTN_LEAN_L`/`BTN_LEAN_R`, `±15°` и смещение головы `±0.4` м) с проверкой стены через переиспользуемый `PhysicsRayQueryParameters3D`. `PlayerMotor.simulate(body, inp, cfg, stance, delta)` (`res://src/player/player_motor.gd`) разрешает спринт только вперёд (`sprint_min_forward_dot = 0.5`) в стойке `STAND`, управляет опциональной выносливостью (`stamina_enabled = false` по умолчанию), поддерживает `coyote_time = 0.1` с, выполняет автоподъём на ступени до `0.35` м (`test_move` вверх → вперёд → вниз с переиспользуемым `KinematicCollision3D` без вертикального подпрыгивания) и при приземлении вычисляет урон от падения при вертикальной скорости ниже `−12` м/с (`MovementConfig.calculate_fall_damage`). Универсальный узел `HealthComponent` (`res://src/core/health_component.gd`) хранит `max_health`, `current`, `is_dead`, обрабатывает `apply_damage(amount, source_id, zone)`, `heal(amount)`, `reset()` и опциональную регенерацию (`regen_delay`, `regen_rate`, отключена по умолчанию), испуская сигналы `health_changed`, `damaged`, `died`. Зона попадания `HitboxZone` (`res://src/player/hitbox_zone.gd`, `Area3D` на физическом слое `hitboxes` = `4`, `collision_mask = 0`, `monitoring = false`) хранит `zone` (`HEAD`, `TORSO`, `ARMS`, `LEGS`), множитель урона `damage_mult` из ресурса `HitboxConfig` (`res://src/player/hitbox_config.gd`, `res://src/player/default_hitboxes.tres`) и ссылку на `HealthComponent` владельца. Узел `PlayerHitboxes` (`res://src/player/player_hitboxes.gd`) создаёт набор зон по размеру капсулы (`HeadZone` — `SphereShape3D`, `TorsoZone`/`LeftArmZone`/`RightArmZone`/`LegsZone` — `BoxShape3D`) и динамически подстраивает их под высоту капсулы, высоту головы и смещение наклона `lean_offset` в текущей стойке. Метод `HitscanQuery.cast(from, to, exclude)` (`res://src/weapons/hitscan_query.gd`) трассирует луч с `collide_with_areas = true`, `collide_with_bodies = true` и маской `world + hitboxes` (`5`) через переиспользуемый `PhysicsRayQueryParameters3D`, возвращая `HitResult` (`res://src/weapons/hit_result.gd`: `hit`, `position`/`point`, `normal`, `zone`, `damage_mult`, `target`, `health_component`, `hitbox`, `entity`, `collider`, `rid`). Сцена игрока `res://src/player/player.tscn` (`Player`, генератор `res://tools/gen_player.gd`) представляет `CharacterBody3D` на слое `players` (`2`) с маской `world` (`1`), капсулой `1.8 × 0.35` м и узлами `Head`/`Camera3D`/`CameraEffects`, `StanceController`, `HealthComponent` и `Hitboxes`. Игровая логика (урон, смерть, захват, боезапас) авторитетна на сервере.
3. **Представление (`Camera3D`, `CameraEffects`)** — глобальная физическая интерполяция (`physics/common/physics_interpolation=true`) сглаживает перемещение `Player` и `Head` между тиками 60 Гц, тогда как `Camera3D` (`physics_interpolation_mode = OFF`) каждый кадр рендера (`_process`) берёт интерполированную мировую позицию головы `get_global_transform_interpolated() * head.position`, актуальные углы `yaw`/`pitch`, угол крена наклона `head.rotation.z` и чисто визуальное смещение/покачивание из узла `CameraEffects` (`res://src/player/camera_effects.gd`, отключается настройкой `camera_effects` в `Settings`). Захват курсора (`MOUSE_MODE_CAPTURED`) выполняется при старте локального игрока и освобождается по `InputActions.PAUSE_MENU` (`Esc`).

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
