# Changelog

Все заметные изменения проекта документируются в этом файле по шагам плана (`docs/STEPS.md`).

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
