# PROGRESS

Текущий шаг: 2.3 (DONE)
Последний завершённый: 2.3

| Шаг | Статус | Дата | Заметки |
|---|---|---|---|
| 0.1 | DONE | 2026-10-25 | Создан project.godot (Godot 4.7.2, Forward+, Jolt, 60 Гц, 8 слоёв физики), .gitignore, .gitattributes, .editorconfig, структура каталогов и ARCHITECTURE.md |
| 0.2 | DONE | 2026-10-25 | Созданы ASSETS.md и BLOCKERS.md, заполнена таблица всех 138 шагов в PROGRESS.md, проверены AGENTS.md, ARCHITECTURE.md, docs/STEPS.md и обновлён CHANGELOG.md |
| 0.3 | DONE | 2026-10-25 | Созданы мини-раннер `tools/run_tests.gd`, базовый класс `GutTest` (`addons/gut/test.gd`), `addons/gut/gut_cmdln.gd`, `tools/scene_smoke.gd`, `tools/check.sh`, `tools/check.ps1` и тест `tests/unit/test_sanity.gd` |
| 0.4 | DONE | 2026-10-25 | Созданы и зарегистрированы автолоады `Events`, `Game`, `Log`, `Settings`, `Net` и модульные тесты `tests/unit/test_autoloads.gd` |
| 0.5 | DONE | 2026-10-25 | Объявлены 33 действия `InputMap` в `project.godot`, создан класс констант `InputActions` (`src/core/input_actions.gd`) и тест `tests/unit/test_input_actions.gd` |
| 0.6 | DONE | 2026-10-25 | Созданы сцена `src/ui/debug_overlay.tscn` (`DebugOverlay`, F3), консоль (`KEY_QUOTELEFT`) и парсер/реестр команд `DebugConsole` (`src/ui/debug_console.gd`), словарь `Game.debug` и тесты `tests/unit/test_debug_overlay.gd` |
| 1.1 | DONE | 2026-10-25 | Созданы шейдер разметки 1 м `src/maps/testbed/grid_1m.gdshader`, генератор `tools/gen_testbed.gd`, сцена полигона `src/maps/testbed/testbed.tscn` (пол 200×200 м, рампы 15°/30°/45°, лестница 0.2 м, стены 1.0/1.5/2.0/3.0 м, коридор 0.8 м, туннель 1.0 м, стрельбище 10/25/50/100/200 м, `WorldEnvironment`, `DirectionalLight3D`, `PlayerSpawn`) и тесты `tests/unit/test_testbed.gd` |
| 1.2 | DONE | 2026-10-25 | Созданы `PlayerInput` (`src/player/player_input.gd`), `MovementConfig` (`src/player/movement_config.gd`) + `src/player/default_movement.tres`, `PlayerMotor` (`src/player/player_motor.gd`), `LocalInputReader` (`src/player/local_input_reader.gd`), `Player` (`src/player/player.gd`, `src/player/player.tscn`, генератор `tools/gen_player.gd`) и тесты `tests/unit/test_player_motor.gd` |
| 1.3 | DONE | 2026-10-25 | Реализованы обзор мышью в `LocalInputReader` (накопление `yaw`, кламп `pitch` ±89°, `sensitivity` и `invert_y` из `Settings`), `Camera3D` на `Head` с `FOV` 60–120 (дефолт 90), захват курсора и освобождение по `Esc` (`pause_menu`), физическая интерполяция `physics/common/physics_interpolation=true` со сглаживанием через `get_global_transform_interpolated()`, визуальный узел `CameraEffects` (`src/player/camera_effects.gd`) и тесты `tests/unit/test_player_camera.gd` |
| 1.4 | DONE | 2026-10-25 | Созданы `PlayerStance` (`src/player/player_stance.gd`) и `StanceController` (`src/player/stance_controller.gd`): стойки `STAND`/`CROUCH`/`PRONE` с высотой капсулы `1.8`/`1.2`/`0.5` м и камеры `1.65`/`1.05`/`0.35` м, плавные переходы без смещения ступней, проверка потолка (`test_move`), подъём из `PRONE` в `STAND` через `CROUCH` за `0.6` с, запрет прыжка лёжа, наклоны `±15°` и `±0.4` м с проверкой стены и тесты `tests/unit/test_player_stance.gd` |
| 1.5 | DONE | 2026-10-26 | Реализованы спринт только вперёд (`sprint_min_forward_dot = 0.5`, запрет в `CROUCH`/`PRONE`), опциональная выносливость (`stamina_enabled = false` по умолчанию), `coyote_time = 0.1` с, автоподъём на ступени до `0.35` м (`test_move` вверх → вперёд → вниз без подпрыгиваний), расчёт и локальное применение урона от падения при скорости ниже `−12` м/с (`MovementConfig.calculate_fall_damage`, передача в `HealthComponent`) и тесты `tests/unit/test_player_step_fall_sprint.gd` |
| 1.6 | DONE | 2026-10-26 | Создан `HealthComponent` (`src/core/health_component.gd`) с сигналами `health_changed`, `damaged`, `died`, методами `apply_damage`, `heal`, `reset`, опциональной регенерацией (`regen_delay`, `regen_rate`, отключена по умолчанию), интеграцией в `Player` (`src/player/player.tscn`) и тестами `tests/unit/test_health_component.gd` |
| 1.7 | DONE | 2026-10-26 | Созданы `HitboxConfig` (`src/player/hitbox_config.gd`, `src/player/default_hitboxes.tres`), `HitboxZone` (`src/player/hitbox_zone.gd`, `Area3D` на слое `hitboxes = 4`, `monitoring = false`, зоны `HEAD`/`TORSO`/`ARMS`/`LEGS`, `damage_mult`, ссылка на `HealthComponent`), `PlayerHitboxes` (`src/player/player_hitboxes.gd`, подстройка зон под стойку и наклон), `HitResult` (`src/weapons/hit_result.gd`) и `HitscanQuery.cast` (`src/weapons/hitscan_query.gd`, маска `world + hitboxes`), интеграция в `Player` (`src/player/player.tscn`) и тесты `tests/unit/test_hitboxes.gd` |
| 1.8 | DONE | 2026-10-26 | Созданы `TargetDummy` (`src/maps/testbed/target_dummy.gd`, `src/maps/testbed/target_dummy.tscn`, генератор `tools/gen_target_dummy.gd`): стоячий режим и патруль по точкам, `HealthComponent`, `PlayerHitboxes`, респавн через `3.0` с. Базовый `HUD` (`src/ui/hud/hud.gd`, `src/ui/hud/hud.tscn`, генератор `tools/gen_hud.gd`): полоска здоровья, прицел-точка, индикатор стойки, заглушка патронов; обновляется по сигналам, без `_process`. Добавлена консольная команда `damage <n>` в `DebugConsole`. На `testbed.tscn` размещены 5 мишеней (3 стоячие + 2 движущиеся), `HUD` и `DebugOverlay`. Тесты: `tests/unit/test_target_dummy_and_hud.gd`. Тег `phase-1-done` ждёт ручной пробежки (🧑) |
| 2.1 | DONE | 2026-10-26 | Создан `WeaponData` (`src/weapons/weapon_data.gd`) с `cooldown()` и `damage_at(distance)`, восемь временных профилей категорий в `src/weapons/data/` и `tests/unit/test_weapon_data.gd`. Исправлен `PlayerHitboxes`: однократная инициализация и кеширование зон/форм, без повторного поиска узлов и дублирования форм при обновлениях. Добавлен `tests/unit/test_hitbox_cache.gd` (120 обновлений, повторные setup/ready, независимость экземпляров). `tools/check.sh`: 71 тест, 2976 проверок, 0 ошибок; headless-полигон 180 кадров без ошибок/предупреждений. Новых известных проблем нет; значения профилей временные |
| 2.2 | DONE | 2026-10-26 | Создан `Weapon` (`src/weapons/weapon.gd`, `Node3D`): шесть состояний, сроки в тиках симуляции, SEMI/AUTO/BURST, смена режима, блокировка, смена оружия, перезарядка и сигналы `fired`, `reload_started`, `reload_finished`, `ammo_changed`. Добавлены `tests/unit/test_weapon_timing.gd` и `tests/unit/test_weapon_states.gd` (20 новых тестов). `tools/check.sh`: 91 тест, 4307 проверок, 0 ошибок; headless-полигон 180 кадров без ошибок/предупреждений. Приёмка: 600 RPM за 60 тиков — 10 сигналов `fired`, очереди по 3, стрельба при перезарядке запрещена. Новых известных проблем нет; лучи и подключение оружия к игроку в шаг не входят |
| 2.3 | DONE | 2026-10-26 | Созданы `DamageCalc`, `DamageEvent`, `WeaponHitscan`: лучи по `fired`, воспроизводимый статический разброс, `pellets`, исключение стрелка, дистанционный урон по множителю хитбокса и локальное применение к `HealthComponent`. Оружие AR подключено к `Player`, сцене и генератору; добавлен `WeaponData.hitscan_range`. 15 новых тестов. `tools/check.sh`: 106 тестов, 4410 проверок, 0 ошибок; генератор и smoke проходят; headless-полигон 180 кадров без ошибок/предупреждений. Приёмка: AR 10 м — торс 4 попадания, голова 2; дробовик 5 м — 8 дробин, 96 урона, один патрон. Необязательное пробитие не реализовано |
| 2.4 | TODO | | |
| 2.5 | TODO | | |
| 2.6 | TODO | | |
| 2.7 | TODO | | |
| 2.8 | TODO | | |
| 2.9 | TODO | | |
| 2.10 | TODO | | |
| 2.11 | TODO | | |
| 2.12 | TODO | | |
| 2.13 | TODO | | |
| 3.1 | TODO | | |
| 3.2 | TODO | | |
| 3.3 | TODO | | |
| 3.4 | TODO | | |
| 4.1 | TODO | | |
| 4.2 | TODO | | |
| 4.3 | TODO | | |
| 4.4 | TODO | | |
| 4.5 | TODO | | |
| 4.6 | TODO | | |
| 4.7 | TODO | | |
| 4.8 | TODO | | |
| 4.9 | TODO | | |
| 4.10 | TODO | | |
| 4.11 | TODO | | |
| 4.12 | TODO | | |
| 4.13 | TODO | | |
| 4.14 | TODO | | |
| 5.1 | TODO | | |
| 5.2 | TODO | | |
| 5.3 | TODO | | |
| 5.4 | TODO | | |
| 5.5 | TODO | | |
| 5.6 | TODO | | |
| 5.7 | TODO | | |
| 5.8 | TODO | | |
| 5.9 | TODO | | |
| 5.10 | TODO | | |
| 5.11 | TODO | | |
| 6.1 | TODO | | |
| 6.2 | TODO | | |
| 6.3 | TODO | | |
| 6.4 | TODO | | |
| 6.5 | TODO | | |
| 6.6 | TODO | | |
| 6.7 | TODO | | |
| 6.8 | TODO | | |
| 6.9 | TODO | | |
| 6.10 | TODO | | |
| 7.1 | TODO | | |
| 7.2 | TODO | | |
| 7.3 | TODO | | |
| 7.4 | TODO | | |
| 7.5 | TODO | | |
| 7.6 | TODO | | |
| 7.7 | TODO | | |
| 7.8 | TODO | | |
| 7.9 | TODO | | |
| 8.1 | TODO | | |
| 8.2 | TODO | | |
| 8.3 | TODO | | |
| 8.4 | TODO | | |
| 8.5 | TODO | | |
| 8.6 | TODO | | |
| 8.7 | TODO | | |
| 8.8 | TODO | | |
| 8.9 | TODO | | |
| 8.10 | TODO | | |
| 9.1 | TODO | | |
| 9.2 | TODO | | |
| 9.3 | TODO | | |
| 9.4 | TODO | | |
| 9.5 | TODO | | |
| 9.6 | TODO | | |
| 10.1 | TODO | | |
| 10.2 | TODO | | |
| 10.3 | TODO | | |
| 10.4 | TODO | | |
| 10.5 | TODO | | |
| 10.6 | TODO | | |
| 10.7 | TODO | | |
| 10.8 | TODO | | |
| 10.9 | TODO | | |
| 11.1 | TODO | | |
| 11.2 | TODO | | |
| 11.3 | TODO | | |
| 11.4 | TODO | | |
| 11.5 | TODO | | |
| 11.6 | TODO | | |
| 11.7 | TODO | | |
| 11.8 | TODO | | |
| 11.9 | TODO | | |
| 11.10 | TODO | | |
| 12.1 | TODO | | |
| 12.2 | TODO | | |
| 12.3 | TODO | | |
| 12.4 | TODO | | |
| 12.5 | TODO | | |
| 13.1 | TODO | | |
| 13.2 | TODO | | |
| 13.3 | TODO | | |
| 13.4 | TODO | | |
| 13.5 | TODO | | |
| 13.6 | TODO | | |
| 13.7 | TODO | | |
| 13.8 | TODO | | |
| 14.1 | TODO | | |
| 14.2 | TODO | | |
| 14.3 | TODO | | |
| 14.4 | TODO | | |
| 14.5 | TODO | | |
| 14.6 | TODO | | |
| 14.7 | TODO | | |
| 14.8 | TODO | | |
| 15.1 | TODO | | |
| 15.2 | TODO | | |
| 15.3 | TODO | | |
| 15.4 | TODO | | |
| 15.5 | TODO | | |
| 15.6 | TODO | | |
| 15.7 | TODO | | |

## Известные проблемы
- Шаг 2.3: автоматические критерии приёмки проверены, включая стрельбу `PlayerInput → Weapon.fired → смерть TargetDummy` на полигоне, ненулевой разброс дробовика, препятствия и запрет клиентского урона. 🧑 Требуется проверка человеком: запустить полигон, проверить прицеливание мышью и стрельбу ЛКМ по стоячим/движущимся мишеням, смерть и респавн. Визуальная проверка и оценка FPS не проводились; выполнен headless-запуск с анализом лога. Урон применяется локально в офлайн-сервере, сетевой транспорт не добавлен. Пробитие опционально и пропущено. Шаг 2.4 не начат.
- Шаг 2.2: критерии приёмки проверены автоматически; визуальные изменения отсутствуют. Полигон запущен headless на 180 кадров, лог без ошибок/предупреждений Godot. Графика и FPS вручную не оценивались; ручная проверка Фазы 1 ниже сохраняется. Следующий шаг не начат.
- Шаг 2.1: критерии приёмки проверены автоматически; графика и FPS вручную не оценивались. Сохраняется указанная ниже ручная проверка Фазы 1. Следующий шаг не начат.
- Шаг 1.8: при открытой консоли (`` ` ``) курсор остаётся захваченным, а нажатия WASD продолжают двигать игрока. Блокировку ввода при открытой консоли нужно делать позже, вместе с UI/меню.
- Шаг 1.8: у `TargetDummy` нет физического тела, только хитбоксы, поэтому игрок проходит сквозь мишени. Для тренировочных мишеней это допустимо.
- Шаг 1.8: команда `damage <n>` выполняется локально, без сервера. Это отладочный инструмент офлайн-фазы; авторитетный урон появится в фазе 4.

## Замечания по итогам Фазы 1 (`phase-1-done`)
- Автотесты покрывают: разгон и торможение, прыжок, склон 45°, лестницу 0.2 м, туннель 1.0 м, наклоны у стен, урон от падения, хитбоксы, 5 мишеней `TargetDummy`, обновление `HUD` по сигналам и команду `damage <n>`.
- 🧑 Требуется проверка человеком: пробежать полигон 5 минут, оценить камеру, переходы стоек и читаемость HUD, записать замечания сюда. После этого поставить тег `phase-1-done`.
