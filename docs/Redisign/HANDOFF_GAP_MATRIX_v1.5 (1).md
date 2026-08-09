# Fitness App — Figma vs Dev Completion Matrix — v1.5

## Главный вывод

Полностью завершённый кликабельный Figma prototype не является обязательным
условием для начала Flutter-разработки.

Dev-агенту достаточно:

- утверждённой дизайн-системы;
- готовых ключевых экранов;
- списка flow и states;
- product decisions;
- Figma links / PNG reference;
- существующей логики repository.

Оставшиеся Figma-токены нужно тратить только на визуально критичные пробелы,
которые нельзя надёжно восстановить из уже утверждённых patterns.

---

## Категории

### A — Dev может закрыть полностью без новых Figma-экранов

#### D3 — Home completion

- weekly calendar;
- milestones block;
- recovery horizontal scroll;
- scroll affordance;
- empty/loading/error states;
- safe-area и responsive corrections.

Основание: Home visual language, cards, typography и hierarchy уже утверждены.
Dev должен собрать недостающие блоки из существующих components/tokens.

#### D4 — Scanner completion

- scan history;
- saved machine cards;
- offline fallback state;
- unknown equipment flow;
- route wiring;
- retry/error/permission states.

В текущем repository Scanner уже содержит recognition history, а
visual-equipment layer содержит cloud recognizer, local fallback и history.
Задача dev — сохранить behaviour и привести UI к новому design system.

#### D6 — Navigation and summary consolidation

- entry point TechCoach из Exercise Page после появления страницы;
- route/argument wiring в `/form-check`;
- устранение параллельных WorkoutDone и WorkoutSummary;
- redirect/compatibility migration;
- сохранение workout results;
- tests.

Product decision требуется по Q26, но новый Figma flow не обязателен.

Рекомендуемый default:

- WorkoutSummary становится каноническим экраном;
- старый WorkoutDone удаляется после переноса всей логики или временно
  становится thin compatibility wrapper;
- никогда не поддерживать два независимых итоговых экрана.

#### D8 — AI Coach integrations

- contextual entry из Scan result;
- entry из Equipment page;
- entry из Recovery;
- context payload;
- loading/offline/error/cache states;
- navigation and analytics wiring.

Использовать уже существующий AI Coach sheet/component pattern.
Не создавать новый визуальный язык.

#### D9 — Implementation completion

- Android safe areas;
- iOS safe areas/navigation gestures/modal behaviour;
- Dynamic Island/notch handling;
- accessibility semantics;
- large text integration;
- reduced-motion behaviour;
- offline states;
- full route wiring happy path;
- Rest Timer navigation;
- screenshot/golden comparison.

Это преимущественно implementation и validation, а не новый дизайн.

#### General — Rest Timer

Если Rest Timer frame уже есть, dev должен:

- связать Complete Set → Rest Timer;
- реализовать skip / +30 sec / pause / ready;
- background/lifecycle behaviour;
- возврат к следующему set;
- убрать dead screen type, который никуда не ведёт.

Новая Figma-работа не нужна.

---

### B — Dev может реализовать, но желательно иметь минимальный Figma anchor

#### D7 — Progress charts

- Strength progression;
- Volume;
- Consistency;
- Muscle load.

Dev может реализовать настоящие charts и data states, используя текущую
Progress layout и design tokens.

Минимально желательно от Figma:

- один итоговый Progress screen;
- выбранный тип каждого графика;
- legends/axes/period selector;
- empty/loading state;
- semantic colours.

Если Figma-токены закончились, dev получает право сделать первый pass по
описанию ниже и передать emulator screenshots на визуальный review.

Recommended chart defaults:

- Strength: line chart по выбранному упражнению;
- Volume: weekly bars;
- Consistency: calendar/weekly completion bars;
- Muscle load: anatomical map или horizontal ranked bars;
- без 3D, misleading smoothing и fake percentages.

#### D9 — Light Theme

Полный Light Theme можно построить dev-агентом из semantic tokens, но это
содержит визуальные решения.

Предпочтительный вариант при малом бюджете Figma:

- не проектировать все экраны заново;
- утвердить только light semantic palette;
- показать 3 anchor screens:
  - Home;
  - Scanner result;
  - Workout Player или Exercise Page.

Если даже это невозможно, dev создаёт первый light-theme pass, после чего
пользователь утверждает реальные emulator screenshots.

#### D9 — Platform adaptations

Dev может реализовать:

- safe areas;
- Android back/predictive back;
- iOS swipe-back;
- platform permission dialogs;
- modal behaviour;
- keyboard/insets.

Figma нужен только если Android и iOS должны визуально существенно отличаться.
Для общего brand UI с нативным behaviour отдельные полные iOS frames не нужны.

---

### C — Стоит закончить в Figma до соответствующего dev gate

#### D5 / General — Exercise Page

Это единственный критический экран, полностью отсутствующий в утверждённом
наборе.

Минимальный Figma scope:

1. Exercise Page — loaded state.
2. Media area с poster → animation/video state.
3. Название, primary/secondary muscles.
4. Equipment, level, suitability.
5. «Почему рекомендовано тебе».
6. Три коротких шага техники.
7. Common errors.
8. Restrictions/safety.
9. Previous performance/history.
10. Actions:
    - Start Exercise;
    - Add to Workout;
    - Тренер по технике;
    - AI Coach.
11. Loading state.
12. Media unavailable state.
13. Long Russian text / large text state.
14. Entry to TechCoach.

Не требуется делать десятки variants. Одного canonical screen плюс 2–3
critical states достаточно.

После этого dev создаёт отдельный route, page, providers mapping и tests.

---

## Что Figma уже не обязана доделывать

- полный кликабельный happy path на 22 шага;
- каждую offline/error ветку как отдельный connected prototype;
- Android и iOS версии каждого экрана;
- все accessibility combinations;
- реальные chart calculations;
- scanner backend states;
- route wiring;
- rest timer lifecycle;
- AI context payload;
- consolidation старых Flutter screens.

Эти задачи принадлежат dev implementation и validation.

---

## Минимальный последний запрос к Figma

Использовать остаток tokens только на:

1. Exercise Page canonical screen.
2. Exercise Page critical states.
3. TechCoach entry placement.
4. При возможности — light semantic palette и 1–3 anchor screens.

После этого заморозить дизайн и передать dev-агенту.
