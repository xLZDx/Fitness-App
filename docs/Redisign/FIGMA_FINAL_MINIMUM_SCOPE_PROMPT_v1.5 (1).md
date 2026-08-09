# Figma — Final Minimum Scope Before Development — v1.5

Большая часть Fitness App design уже завершена. Не продолжай строить полный
prototype и не трать tokens на route wiring, offline branches или одинаковые
platform copies.

Выполни только один критический недостающий дизайн-блок:

# Exercise Page

Это отдельный экран упражнения, открываемый из Equipment Page, Search,
Programs и Workout context.

## Обязательный loaded state

Покажи:

1. Hero media:
   - poster до запуска;
   - состояние проигрывания анатомической animation/video;
   - play/pause;
   - mute/sound при наличии;
   - media unavailable fallback.

2. Название упражнения.

3. Primary и secondary muscles.

4. Equipment, level, movement category.

5. Personal suitability:
   - «Подходит тебе»;
   - «Подходит с ограничениями»;
   - понятная причина.

6. Блок «Почему рекомендовано тебе».

7. Техника:
   - сначала 3 главных шага;
   - полная инструкция раскрывается.

8. Common mistakes:
   - короткие пункты;
   - problem area highlight только при необходимости.

9. Restrictions / safety notes.

10. Previous performance/history:
    - последний вес;
    - repetitions/sets;
    - last performed date;
    - personal record при наличии;
    - empty state без fake data.

11. Основные действия:
    - «Начать упражнение»;
    - «Добавить в тренировку»;
    - «Тренер по технике»;
    - «Спросить AI Coach».

`Тренер по технике` должен быть видимым contextual action рядом с техникой
или основным action area, а не спрятан в overflow menu.

## Critical states

Подготовь только:

- loaded;
- loading/skeleton;
- media unavailable;
- no history;
- restriction warning;
- large Russian text / text scale 1.6.

## Light theme — optional only if tokens remain

Не перерисовывай всё приложение.

Создай только:

- light semantic colour palette;
- Exercise Page light;
- Home light;
- один camera/workout anchor light.

## Handoff

Отметь frames Ready for development и добавь annotations:

- route intent;
- source of media;
- expanded/collapsed behaviour;
- TechCoach entry;
- AI Coach entry;
- loading/error rules;
- sticky CTA behaviour;
- accessibility notes.

После этого STOP. Другие экраны не добавлять.
