# -*- coding: utf-8 -*-
"""Machine registry builder (defect round 3, 2026-07-30).

Expands the equipment catalog from 10 ids to the full registry of machines a
commercial gym actually contains, adds a Russian overlay for equipment (there
was none — the detail page showed English descriptions under a Russian UI),
emits the alias index that recognition resolves free-text machine names
against, and repairs the exercise->equipment assignments that put ab crunches
on the treadmill page (operator screenshots, 13:25).

Idempotent: rerunning produces the same files.

Outputs (all under mobile/assets/data/):
  equipment.json          - full registry, existing 10 ids preserved verbatim
  equipment.ru.json       - {id: {name, description}} overlay
  equipment_aliases.json  - {id: [lowercase aliases, en+ru]}
  exercises.json          - patched equipmentId reassignments + new cardio
                            exercises (treadmill / rowing machine)
  exercises.ru.json       - RU overlay entries for the new exercises
"""
from __future__ import annotations

import json
import collections
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / 'mobile' / 'assets' / 'data'

# ---------------------------------------------------------------------------
# Registry. (en name, ru name, category, en description, ru description,
# aliases en+ru — lowercase). The 10 pre-existing ids keep their JSON entry
# untouched; they appear here only to carry ru + aliases.
# ---------------------------------------------------------------------------
M = collections.OrderedDict()

def m(mid, en, ru, cat, den, dru, aliases):
    M[mid] = dict(en=en, ru=ru, cat=cat, den=den, dru=dru, aliases=aliases)

# --- existing ids (en description kept from equipment.json) ---
m('treadmill', 'Treadmill', 'Беговая дорожка', 'cardio', None,
  'Моторизованное беговое полотно с регулировкой скорости и наклона. Для разминки, ровного кардио и интервалов.',
  ['treadmill', 'running machine', 'беговая дорожка', 'дорожка', 'бегова дорожка'])
m('rowing_machine', 'Rowing machine', 'Гребной тренажёр', 'cardio', None,
  'Кардиотренажёр на всё тело: тяга ногами, затем руками. Низкоударный — подходит при чувствительных коленях.',
  ['rowing machine', 'rower', 'erg', 'ergometer', 'concept2', 'гребной тренажёр', 'гребля', 'гребной'])
m('squat_rack', 'Squat rack', 'Силовая рама', 'strength', None,
  'Рама со страховочными упорами для приседаний, жимов и тяг со штангой.',
  ['squat rack', 'power rack', 'power cage', 'half rack', 'rack', 'силовая рама', 'рама', 'стойка для приседаний', 'стойки'])
m('bench_press', 'Bench press station', 'Жим лёжа (стойка)', 'strength', None,
  'Скамья со стойками под штангу для жима лёжа.',
  ['bench press', 'bench press station', 'жим лёжа', 'жим лежа', 'стойка для жима'])
m('cable_machine', 'Cable machine', 'Блочный тренажёр (кроссовер)', 'strength', None,
  'Регулируемые блоки с тросами и сменными рукоятками — десятки движений на все группы мышц.',
  ['cable machine', 'cable crossover', 'crossover', 'functional trainer', 'cable station', 'dual pulley',
   'кроссовер', 'блочный тренажёр', 'блочная рама', 'блоки'])
m('leg_press', 'Leg press', 'Жим ногами', 'strength', None,
  'Платформа для жима ногами под углом — квадрицепсы и ягодичные без осевой нагрузки на спину.',
  ['leg press', '45 degree leg press', 'sled press', 'жим ногами', 'жим платформы', 'платформа'])
m('lat_pulldown', 'Lat pulldown', 'Верхняя тяга', 'strength', None,
  'Тяга рукояти сверху к груди — широчайшие и бицепсы.',
  ['lat pulldown', 'pulldown', 'lat machine', 'верхняя тяга', 'вертикальная тяга', 'тяга верхнего блока'])
m('barbell', 'Barbell', 'Штанга', 'free_weights', None,
  'Олимпийский гриф и диски: базовые многосуставные движения.',
  ['barbell', 'olympic bar', 'штанга', 'гриф'])
m('dumbbell', 'Dumbbells', 'Гантели', 'free_weights', None,
  'Пары гантелей разного веса — односторонняя работа и полная свобода траектории.',
  ['dumbbell', 'dumbbells', 'гантели', 'гантель', 'гантельный ряд'])
m('kettlebell', 'Kettlebell', 'Гиря', 'free_weights', None,
  'Гиря со смещённым центром тяжести: махи, рывки, турецкие подъёмы.',
  ['kettlebell', 'гиря', 'гири'])

# --- cardio ---
m('elliptical', 'Elliptical trainer', 'Эллиптический тренажёр', 'cardio',
  'Low-impact full-body cardio: gliding stride with moving handles.',
  'Низкоударное кардио на всё тело: скользящий шаг с подвижными рукоятями.',
  ['elliptical', 'elliptical trainer', 'cross trainer', 'эллипс', 'эллиптический тренажёр', 'орбитрек'])
m('exercise_bike', 'Exercise bike', 'Велотренажёр', 'cardio',
  'Stationary upright bike with adjustable resistance.',
  'Вертикальный велотренажёр с регулируемым сопротивлением.',
  ['exercise bike', 'stationary bike', 'upright bike', 'spin bike', 'indoor cycle',
   'велотренажёр', 'велотренажер', 'сайкл', 'велосипед'])
m('recumbent_bike', 'Recumbent bike', 'Горизонтальный велотренажёр', 'cardio',
  'Reclined stationary bike with back support — the gentlest cardio option.',
  'Велотренажёр с откинутой посадкой и опорой для спины — самое щадящее кардио.',
  ['recumbent bike', 'горизонтальный велотренажёр', 'горизонтальный велосипед'])
m('stair_climber', 'Stair climber', 'Степпер / лестница', 'cardio',
  'Rotating staircase or step pedals — climbing cardio for legs and glutes.',
  'Вращающаяся лестница или педали-степпер: кардио-подъём для ног и ягодиц.',
  ['stair climber', 'stairmaster', 'stepmill', 'stepper', 'степпер', 'лестница', 'клаймбер'])
m('air_bike', 'Air bike', 'Аэробайк', 'cardio',
  'Fan-resistance bike with moving handles; effort sets the resistance.',
  'Велотренажёр с вентилятором и подвижными рукоятями: чем сильнее крутишь, тем тяжелее.',
  ['air bike', 'assault bike', 'fan bike', 'airdyne', 'аэробайк', 'эйрбайк', 'ассолт байк'])
m('ski_erg', 'Ski erg', 'Лыжный тренажёр', 'cardio',
  'Standing pull-down ergometer that mimics double-pole skiing.',
  'Вертикальный эргометр, имитирующий одновременный лыжный ход.',
  ['ski erg', 'skierg', 'лыжный тренажёр', 'лыжи'])

# --- lower body machines ---
m('smith_machine', 'Smith machine', 'Машина Смита', 'strength',
  'Barbell fixed to vertical rails with hooks — guided squats and presses.',
  'Штанга в направляющих с крюками: приседания и жимы по фиксированной траектории.',
  ['smith machine', 'smith', 'машина смита', 'смит', 'тренажёр смита'])
m('hack_squat_machine', 'Hack squat machine', 'Гакк-машина', 'strength',
  'Angled sled with shoulder pads for guided squats.',
  'Наклонные салазки с упорами на плечи для приседаний по направляющим.',
  ['hack squat', 'hack squat machine', 'гакк', 'гакк-машина', 'гакк приседания'])
m('leg_extension', 'Leg extension machine', 'Разгибание ног', 'strength',
  'Seated machine that isolates the quadriceps by extending the knees.',
  'Сидя, разгибание коленей с валиком — изолированная работа квадрицепса.',
  ['leg extension', 'quad extension', 'разгибание ног', 'разгибания ног'])
m('leg_curl', 'Leg curl machine', 'Сгибание ног', 'strength',
  'Seated or lying machine that isolates the hamstrings by curling the knees.',
  'Сидя или лёжа, сгибание коленей с валиком — изолированная работа бицепса бедра.',
  ['leg curl', 'hamstring curl', 'seated leg curl', 'lying leg curl', 'сгибание ног', 'сгибания ног'])
m('hip_abductor_adductor', 'Hip abductor / adductor machine', 'Сведение / разведение ног', 'strength',
  'Seated machine working the outer or inner thigh against pads.',
  'Сидя, сведение или разведение бёдер с упорами — внешняя и внутренняя поверхность бедра.',
  ['hip abductor', 'hip adductor', 'abductor machine', 'adductor machine', 'thigh machine',
   'сведение ног', 'разведение ног', 'сведение разведение ног'])
m('glute_kickback_machine', 'Glute kickback machine', 'Отведение ноги назад (ягодичные)', 'strength',
  'Standing or kneeling machine for pressing one leg back against resistance.',
  'Отведение ноги назад с упором — прицельная работа ягодичных.',
  ['glute kickback', 'glute machine', 'kickback machine', 'ягодичный тренажёр', 'отведение ноги назад', 'махи ногой'])
m('calf_raise_machine', 'Calf raise machine', 'Подъёмы на носки (тренажёр)', 'strength',
  'Standing or seated machine loading heel raises for the calves.',
  'Подъёмы на носки стоя или сидя под нагрузкой — икроножные и камбаловидные.',
  ['calf raise', 'calf machine', 'standing calf raise', 'seated calf raise', 'икры', 'подъёмы на носки', 'голень тренажёр'])

# --- upper body machines ---
m('chest_press_machine', 'Chest press machine', 'Жим от груди (тренажёр)', 'strength',
  'Seated press with handles — chest, front delts and triceps on a guided path.',
  'Жим рукоятей сидя: грудь, передние дельты и трицепс по заданной траектории.',
  ['chest press', 'chest press machine', 'seated chest press', 'жим от груди', 'жим сидя', 'грудной жим'])
m('pec_deck', 'Pec deck / fly machine', 'Бабочка (пек-дек)', 'strength',
  'Seated fly machine bringing the arms together in front of the chest; many double as rear-delt flys.',
  'Сведение рук перед грудью сидя; во многих моделях — и разведение на задние дельты.',
  ['pec deck', 'pec dec', 'fly machine', 'butterfly machine', 'chest fly', 'rear delt fly',
   'бабочка', 'пек-дек', 'сведение рук'])
m('shoulder_press_machine', 'Shoulder press machine', 'Жим на плечи (тренажёр)', 'strength',
  'Seated overhead press with handles — delts and triceps on a guided path.',
  'Жим рукоятей вверх сидя: дельты и трицепс по заданной траектории.',
  ['shoulder press', 'shoulder press machine', 'overhead press machine', 'жим на плечи', 'жим вверх сидя', 'плечевой жим'])
m('seated_row_machine', 'Seated row machine', 'Горизонтальная тяга', 'strength',
  'Seated row — cable or lever — pulling handles to the torso for the mid-back.',
  'Тяга рукоятей к корпусу сидя (трос или рычаг) — середина спины и широчайшие.',
  ['seated row', 'cable row', 'row machine', 'leverage row', 'low row', 'high row',
   'горизонтальная тяга', 'тяга к поясу', 'рычажная тяга', 'нижняя тяга'])
m('t_bar_row', 'T-bar row', 'Т-гриф', 'strength',
  'Chest-supported or landmine lever row for the mid-back.',
  'Тяга Т-грифа (с упором в грудь или в угол) — середина спины.',
  ['t-bar row', 't bar row', 'landmine row', 'т-гриф', 'тяга т-грифа', 'т гриф'])
m('assisted_pullup_machine', 'Assisted pull-up machine', 'Гравитрон', 'strength',
  'Counterweighted platform that assists pull-ups and dips.',
  'Платформа с противовесом, помогающая подтягиваться и отжиматься на брусьях.',
  ['assisted pull-up', 'assisted pullup machine', 'gravitron', 'гравитрон', 'подтягивания с противовесом'])
m('pullup_bar', 'Pull-up bar', 'Турник', 'bodyweight',
  'Fixed bar for pull-ups and hanging work.',
  'Перекладина для подтягиваний и висов.',
  ['pull-up bar', 'pullup bar', 'chin-up bar', 'турник', 'перекладина'])
m('dip_station', 'Dip station', 'Брусья', 'bodyweight',
  'Parallel bars for dips and leg raises.',
  'Параллельные брусья для отжиманий и подъёмов ног.',
  ['dip station', 'dip bars', 'parallel bars', 'брусья'])
m('preacher_curl_bench', 'Preacher curl bench', 'Скамья Скотта', 'strength',
  'Angled arm pad that isolates the biceps during curls.',
  'Наклонная подставка под плечи, изолирующая бицепс при сгибаниях.',
  ['preacher curl', 'preacher bench', 'scott bench', 'скамья скотта', 'пюпитр'])
m('bicep_curl_machine', 'Biceps curl machine', 'Сгибание рук (тренажёр)', 'strength',
  'Seated machine curl with pads — guided biceps isolation.',
  'Сгибание рук сидя с упором — изолированная работа бицепса по направляющим.',
  ['bicep curl machine', 'arm curl machine', 'сгибание рук', 'бицепс-машина'])
m('tricep_extension_machine', 'Triceps extension machine', 'Разгибание рук (тренажёр)', 'strength',
  'Seated machine press-down or extension isolating the triceps.',
  'Разгибание рук сидя — изолированная работа трицепса по направляющим.',
  ['tricep extension machine', 'tricep machine', 'разгибание рук', 'трицепс-машина'])
m('ab_crunch_machine', 'Ab crunch machine', 'Тренажёр для пресса', 'strength',
  'Seated crunch against resistance with feet anchored.',
  'Скручивания сидя с сопротивлением и фиксацией ног.',
  ['ab crunch machine', 'ab machine', 'crunch machine', 'abdominal machine', 'тренажёр для пресса', 'пресс-машина', 'скручивания сидя'])
m('rotary_torso_machine', 'Rotary torso machine', 'Ротация корпуса (тренажёр)', 'strength',
  'Seated twist against resistance for the obliques.',
  'Повороты корпуса сидя с сопротивлением — косые мышцы живота.',
  ['rotary torso', 'torso rotation', 'twist machine', 'ротация корпуса', 'повороты корпуса'])
m('back_extension', 'Back extension bench', 'Гиперэкстензия', 'strength',
  '45-degree or horizontal bench for extending the lower back and glutes.',
  'Наклонная или горизонтальная скамья для разгибаний корпуса — поясница и ягодичные.',
  ['back extension', 'hyperextension', 'roman chair back extension', 'ghd', 'glute ham developer',
   'гиперэкстензия', 'экстензия', 'разгибание спины'])
m('captains_chair', "Captain's chair", 'Стойка для подъёма ног', 'bodyweight',
  'Upright frame with forearm pads for hanging leg raises.',
  'Вертикальная стойка с упорами под предплечья для подъёмов ног.',
  ['captains chair', 'leg raise station', 'knee raise station', 'vertical knee raise',
   'стойка для пресса', 'подъём ног в упоре', 'подъемы ног'])

# --- benches / free weights / functional ---
m('adjustable_bench', 'Bench (flat / adjustable)', 'Скамья (прямая / регулируемая)', 'free_weights',
  'Flat or incline-adjustable bench for dumbbell and bodyweight work.',
  'Прямая или регулируемая скамья для работы с гантелями и собственным весом.',
  ['bench', 'flat bench', 'adjustable bench', 'incline bench', 'weight bench', 'utility bench',
   'скамья', 'лавка', 'наклонная скамья', 'скамейка'])
m('ez_curl_bar', 'EZ curl bar', 'EZ-гриф', 'free_weights',
  'Cambered bar that eases wrist position for curls and extensions.',
  'Изогнутый гриф, разгружающий запястья при сгибаниях и разгибаниях.',
  ['ez bar', 'ez curl bar', 'curl bar', 'ez-гриф', 'изогнутый гриф', 'кривой гриф'])
m('weight_plates', 'Weight plates', 'Диски', 'free_weights',
  'Plates for loading bars and machines; usable alone for raises and carries.',
  'Диски для штанг и тренажёров; сами по себе — для подъёмов и переносок.',
  ['weight plates', 'plates', 'bumper plates', 'диски', 'блины'])
m('resistance_bands', 'Resistance bands', 'Резиновые ленты', 'functional',
  'Elastic bands of graded resistance for assistance, warm-ups and isolation.',
  'Эластичные ленты разной жёсткости: помощь, разминка, изоляция.',
  ['resistance band', 'resistance bands', 'bands', 'ленты', 'резинки', 'эспандер'])
m('trx', 'Suspension trainer (TRX)', 'Петли TRX', 'functional',
  'Suspended straps for bodyweight rows, presses and core work.',
  'Подвесные петли для тяг, жимов и работы на корпус с собственным весом.',
  ['trx', 'suspension trainer', 'suspension straps', 'петли trx', 'петли', 'подвесные петли'])
m('medicine_ball', 'Medicine ball', 'Медбол', 'functional',
  'Weighted ball for throws, slams and core work.',
  'Утяжелённый мяч для бросков, слэмов и работы на корпус.',
  ['medicine ball', 'med ball', 'slam ball', 'wall ball', 'медбол', 'медицинский мяч', 'слэмбол'])
m('battle_ropes', 'Battle ropes', 'Канаты', 'functional',
  'Heavy ropes anchored to a point — waves and slams for conditioning.',
  'Тяжёлые канаты с якорем: волны и удары для выносливости.',
  ['battle ropes', 'battle rope', 'канаты', 'канат'])
m('plyo_box', 'Plyo box', 'Плиобокс', 'functional',
  'Sturdy box for jumps, step-ups and elevated work.',
  'Устойчивый бокс для запрыгиваний, зашагиваний и упражнений с опорой.',
  ['plyo box', 'jump box', 'plyometric box', 'box', 'плиобокс', 'бокс для запрыгиваний', 'тумба'])
m('punching_bag', 'Punching bag', 'Боксёрская груша', 'functional',
  'Heavy bag for striking work and conditioning.',
  'Тяжёлый мешок для ударной работы и выносливости.',
  ['punching bag', 'heavy bag', 'boxing bag', 'груша', 'боксёрская груша', 'мешок'])
m('foam_roller', 'Foam roller', 'Массажный ролл', 'functional',
  'Firm roller for self-myofascial release and mobility work.',
  'Жёсткий ролл для самомассажа и мобильности.',
  ['foam roller', 'roller', 'ролл', 'массажный ролик', 'валик'])

# --- existing ids added to equipment.json after this generator was last run
# (2026-08-03): kept M in sync so a future run does not crash on the
# 'existing <= M' assertion, and so equipment.ru.json / equipment_aliases.json
# stay reproducible from source instead of only living in the JSON output.
# en/ru/aliases copied verbatim from the shipped files; nothing here changes
# what is already on disk. ---
m('stability_ball', 'Stability ball', 'Фитбол', 'functional', None,
  'Надувной мяч как нестабильная опора для пресса, таза и спины.',
  ['balance ball', 'exercise ball', 'stability ball', 'swiss ball', 'yoga ball',
   'гимнастический мяч', 'мяч для фитнеса', 'фитбол', 'швейцарский мяч'])
m('skipping_rope', 'Skipping rope', 'Скакалка', 'cardio', None,
  'Скакалка для прыжковых интервалов, разминки и общей выносливости.',
  ['jump rope', 'skipping rope', 'speed rope', 'прыгалка', 'скакалка'])
m('ab_wheel', 'Ab wheel', 'Ролик для пресса', 'functional', None,
  'Колесо с двумя рукоятями для раскатов на пресс и корпус.',
  ['ab roller', 'ab wheel', 'abdominal wheel', 'wheel rollout',
   'гимнастический ролик', 'колесо для пресса', 'ролик для пресса'])
m('parallettes', 'Parallettes', 'Брусья-паралетки', 'bodyweight', None,
  'Низкие параллельные брусья для отжиманий, уголка и стоек.',
  ['paralettes', 'parallette', 'parallettes', 'push up handles', 'push-up bars',
   'брусья-паралетки', 'паралетки', 'упоры для отжиманий'])

# --- new ids, 2026-08-03 batch 3: the 15 machine types that came out of
# looking at the poster for every one of the 44 vendor exercises that could
# not resolve to any of the 52 -- not external stock photos or names, real
# equipment already visible in our own licensed clips
# (core/EQUIPMENT_GAP_ITEMS_2026-08-03.csv is the per-exercise trail). 37 of
# the 44 belong to these 15; the other 4 groups (vertical pole, push-up
# blocks, aerobic step, outdoor air walker) stay out -- each is either a
# judgement call against an existing id or a different (outdoor) context,
# left for a deliberate decision rather than folded in here. ---
m('seated_dip_machine', 'Seated dip machine', 'Тренажёр для отжиманий (сидя)', 'strength',
  'Seated, plate-loaded lever machine that presses down against resistance -- chest, shoulders and triceps.',
  'Сидя, рычажный тренажёр с отягощением для дожима вниз -- грудь, плечи и трицепс.',
  ['seated dip machine', 'chest dip machine', 'triceps dip machine', 'dip machine',
   'lever dip machine', 'sitting dip machine', 'тренажёр для отжиманий',
   'дожимной тренажёр', 'трицепс машина сидя'])
m('multi_hip_machine', 'Multi hip machine', 'Мульти-хип машина', 'strength',
  'Standing lever machine with a leg strap for hip flexion, extension, abduction and adduction against a weight stack.',
  'Стоя, рычажный тренажёр с креплением на ногу для сгибания, разгибания, отведения и приведения бедра под нагрузкой.',
  ['multi hip machine', 'multi-hip', 'hip machine', 'standing hip machine',
   'glute extension machine', 'мульти-хип', 'тренажёр для бедра стоя',
   'тренажёр для ягодичных стоя'])
m('lateral_raise_machine', 'Lateral raise machine', 'Тренажёр для разведения рук (плечи)', 'strength',
  'Seated machine with arm pads that raises the arms out to the sides against resistance -- isolates the shoulders.',
  'Сидя, тренажёр с упорами для рук, поднимающий руки в стороны под нагрузкой -- изоляция дельт.',
  ['lateral raise machine', 'machine lateral raise', 'shoulder lateral machine',
   'delt machine', 'тренажёр для дельт', 'разведение рук тренажёр', 'махи в стороны тренажёр'])
m('sissy_squat_machine', 'Sissy squat machine', 'Тренажёр для сисси-приседа', 'strength',
  'Frame with an ankle brace that lets the body lean back on straight hips while the knees bend -- isolates the quads.',
  'Рама с упором для голеней, позволяющая отклоняться назад с прямым тазом и сгибать колени -- изоляция квадрицепса.',
  ['sissy squat machine', 'sissy squat frame', 'sissy squat bench', 'quad isolator',
   'тренажёр сисси-присед', 'рама для сисси-приседа'])
m('agility_ladder', 'Agility ladder', 'Координационная лестница', 'functional',
  'Flat floor ladder used for fast footwork, speed and coordination drills.',
  'Плоская лестница на полу для отработки быстрой работы ног, скорости и координации.',
  ['agility ladder', 'speed ladder', 'coordination ladder', 'footwork ladder',
   'координационная лестница', 'скоростная лестница', 'лестница для ног'])
m('mini_trampoline', 'Mini trampoline', 'Мини-батут', 'cardio',
  'Small round trampoline for low-impact jumping cardio.',
  'Небольшой круглый батут для низкоударного прыжкового кардио.',
  ['mini trampoline', 'rebounder', 'fitness trampoline', 'jump trampoline',
   'мини-батут', 'батут', 'ребаундер'])
m('balance_board', 'Balance board', 'Балансборд', 'functional',
  'Unstable board that tilts or rocks, used to train ankle and core stability.',
  'Неустойчивая доска, которая наклоняется или качается -- тренировка устойчивости голеностопа и корпуса.',
  ['balance board', 'wobble board', 'stability board', 'rocker board',
   'балансборд', 'доска для баланса', 'балансировочная доска'])
m('yoga_blocks', 'Yoga blocks', 'Йога-блоки', 'functional',
  'Firm rectangular blocks that extend your reach or support a pose in stretching and yoga.',
  'Плотные прямоугольные блоки, которые продлевают досягаемость руки или поддерживают позу при растяжке и йоге.',
  ['yoga block', 'yoga blocks', 'foam block', 'pilates block', 'йога-блок',
   'йога-блоки', 'блок для йоги'])
m('weighted_sled', 'Weighted sled', 'Сани с отягощением', 'functional',
  'Loaded sled pushed or dragged across the floor for full-body conditioning.',
  'Нагруженные сани, которые толкают или тянут по полу -- кондиционная нагрузка на всё тело.',
  ['weighted sled', 'sled', 'prowler', 'drag sled', 'push sled', 'сани',
   'сани с грузом', 'проулер'])
m('ab_mat', 'Ab mat', 'Валик для пресса', 'functional',
  'Small padded wedge placed under the lower back to increase range of motion on sit-ups and crunches.',
  'Небольшой мягкий валик под поясницу -- увеличивает амплитуду при скручиваниях и подъёмах корпуса.',
  ['ab mat', 'ab pad', 'sit-up pad', 'core pad', 'валик для пресса', 'подушка для пресса'])
m('bosu_ball', 'Bosu ball', 'Босу (полусфера)', 'functional',
  'Half-dome balance trainer, flat side up or down, used for unstable-surface strength and balance work.',
  'Тренажёр-полусфера для баланса, плоской стороной вверх или вниз -- силовая работа и баланс на нестабильной опоре.',
  ['bosu ball', 'bosu', 'half dome trainer', 'balance dome', 'босу', 'полусфера', 'босу мяч'])
m('sliding_disc', 'Sliding discs', 'Слайдеры (диски для скольжения)', 'functional',
  'Small flat discs placed under hands or feet that glide on the floor, adding an unstable, low-impact resistance element.',
  'Небольшие плоские диски под руки или ноги, скользящие по полу -- нестабильная, низкоударная нагрузка.',
  ['sliding disc', 'sliding discs', 'gliding disc', 'core sliders', 'slider', 'sliders',
   'слайдеры', 'диски для скольжения', 'глайдинг диски'])
m('sandbag', 'Sandbag', 'Сэндбэг', 'functional',
  'Flexible, shifting-weight bag used for cleans, carries and full-body strength work.',
  'Мягкая сумка с сыпучим грузом для тяг, переносок и силовой работы на всё тело.',
  ['sandbag', 'sand bag', 'strongman sandbag', 'сэндбэг', 'мешок с песком'])
m('gymnastic_rings', 'Gymnastic rings', 'Гимнастические кольца', 'bodyweight',
  'Suspended rings for dips, rows and holds that add instability to bodyweight training.',
  'Подвесные кольца для отжиманий, тяг и удержаний -- нестабильная опора для тренировки с собственным весом.',
  ['gymnastic rings', 'rings', 'ring training', 'suspended rings',
   'гимнастические кольца', 'кольца'])
m('tyre', 'Tyre', 'Покрышка', 'functional',
  'Large vehicle tyre flipped, dragged or struck with a sledgehammer for full-body strength and conditioning.',
  'Большая покрышка, которую переворачивают, тащат или бьют кувалдой -- силовая и кондиционная работа на всё тело.',
  ['tyre', 'tire', 'truck tyre', 'tractor tyre', 'sledgehammer',
   'покрышка', 'шина', 'кувалда'])

# ---------------------------------------------------------------------------
# Exercise repairs: title -> correct equipmentId (None = bodyweight).
# The old catalog parked these on 'treadmill' / 'rowing_machine'.
# ---------------------------------------------------------------------------
REASSIGN = {
    'Ab Crunch Machine': 'ab_crunch_machine',
    'Cable Crunch': 'cable_machine',
    'Bosu Ball Cable Crunch With Side Bends': 'cable_machine',
    'Barbell Walking Lunge': 'barbell',
    'Bodyweight Walking Lunge': None,
    'Bench Sprint': 'plyo_box',
    'Narrow Stance Hack Squats': 'hack_squat_machine',
    'Leverage High Row': 'seated_row_machine',
    'Leverage Iso Row': 'seated_row_machine',
    'Lying T-Bar Row': 't_bar_row',
    'Inverted Row with Straps': 'trx',
    'Bodyweight Mid Row': None,
}

# ---------------------------------------------------------------------------
# New hand-authored cardio exercises (frames: none — no imagery fabricated).
# ---------------------------------------------------------------------------
NEW_EXERCISES = [
    dict(
        id='treadmill_warmup_walk', equipmentId='treadmill',
        title='Warm-up Walk', ru_title='Разминочная ходьба',
        muscles=['quads', 'hamstrings', 'glutes', 'calves'], primary=['quads'],
        difficulty='beginner', minutes=8, contra=[],
        steps=[
            'Step onto the belt and start at an easy walking speed (3-4 km/h).',
            'Walk tall: shoulders relaxed, eyes forward, arms swinging naturally.',
            'Raise the speed slightly every couple of minutes until you feel warm.',
            'Finish when your breathing is elevated but you can still talk easily.'],
        ru_steps=[
            'Встаньте на полотно и начните с лёгкой ходьбы (3-4 км/ч).',
            'Идите с прямой спиной: плечи расслаблены, взгляд вперёд, руки работают естественно.',
            'Каждые пару минут слегка увеличивайте скорость, пока не почувствуете разогрев.',
            'Заканчивайте, когда дыхание участилось, но говорить ещё легко.']),
    dict(
        id='treadmill_incline_walk', equipmentId='treadmill',
        title='Incline Walk', ru_title='Ходьба в гору',
        muscles=['glutes', 'hamstrings', 'quads', 'calves'], primary=['glutes'],
        difficulty='beginner', minutes=15, contra=[],
        steps=[
            'Set a comfortable walking speed, then raise the incline to 6-10%.',
            'Do not hold the handrails — pumping your arms keeps the load honest.',
            'Take slightly shorter steps and drive through the heel and glutes.',
            'Lower the incline gradually for the last two minutes to cool down.'],
        ru_steps=[
            'Выставьте комфортную скорость ходьбы, затем поднимите наклон до 6-10%.',
            'Не держитесь за поручни — работа руками сохраняет честную нагрузку.',
            'Шагайте чуть короче обычного, проталкиваясь через пятку и ягодичные.',
            'Последние две минуты плавно снижайте наклон, чтобы остыть.']),
    dict(
        id='treadmill_steady_run', equipmentId='treadmill',
        title='Steady-State Run', ru_title='Бег в ровном темпе',
        muscles=['quads', 'hamstrings', 'glutes', 'calves', 'core'], primary=['quads'],
        difficulty='intermediate', minutes=20, contra=['knee'],
        steps=[
            'Warm up with 3-4 minutes of brisk walking or light jogging.',
            'Settle into a pace where you could still speak in short sentences.',
            'Keep a light, quick step — land under your hips, not out in front.',
            'Slow to a walk for the final 2-3 minutes instead of stopping abruptly.'],
        ru_steps=[
            'Разомнитесь 3-4 минутами быстрой ходьбы или лёгкой трусцы.',
            'Выйдите на темп, в котором можете говорить короткими фразами.',
            'Шаг лёгкий и частый — стопа приземляется под тазом, а не впереди.',
            'Последние 2-3 минуты перейдите на шаг, не останавливайтесь резко.']),
    dict(
        id='treadmill_intervals', equipmentId='treadmill',
        title='Run Intervals', ru_title='Беговые интервалы',
        muscles=['quads', 'hamstrings', 'glutes', 'calves', 'core'], primary=['quads'],
        difficulty='intermediate', minutes=12, contra=['knee'],
        steps=[
            'Warm up with 4 minutes of easy jogging.',
            'Run 1 minute noticeably fast — hard, but with controlled form.',
            'Recover with 1-2 minutes of walking or easy jogging.',
            'Repeat 5-8 rounds, then cool down with 3 minutes of walking.'],
        ru_steps=[
            'Разомнитесь 4 минутами лёгкой трусцы.',
            'Бегите 1 минуту заметно быстро — тяжело, но с контролем техники.',
            'Восстановитесь 1-2 минутами ходьбы или лёгкой трусцы.',
            'Повторите 5-8 кругов и закончите 3 минутами ходьбы.']),
    dict(
        id='rowing_steady', equipmentId='rowing_machine',
        title='Steady Row', ru_title='Гребля в ровном темпе',
        muscles=['lats', 'back', 'quads', 'hamstrings', 'glutes', 'core'], primary=['lats'],
        difficulty='beginner', minutes=15, contra=['lower_back'],
        steps=[
            'Strap in, sit tall, and grip the handle with straight wrists.',
            'Drive with the legs first, then lean back slightly and pull to the lower ribs.',
            'Return in reverse: arms out, hinge forward, then bend the knees.',
            'Hold a calm rhythm around 20-24 strokes per minute.'],
        ru_steps=[
            'Зафиксируйте стопы, сядьте с прямой спиной, возьмите рукоять с прямыми запястьями.',
            'Сначала толкайтесь ногами, затем слегка отклонитесь и дотяните рукоять к нижним рёбрам.',
            'Возврат в обратном порядке: руки вперёд, наклон корпуса, потом сгибаются колени.',
            'Держите спокойный ритм — около 20-24 гребков в минуту.']),
    dict(
        id='rowing_intervals', equipmentId='rowing_machine',
        title='Row Intervals', ru_title='Гребные интервалы',
        muscles=['lats', 'back', 'quads', 'hamstrings', 'glutes', 'core'], primary=['lats'],
        difficulty='intermediate', minutes=12, contra=['lower_back'],
        steps=[
            'Warm up with 3 minutes of easy rowing.',
            'Row hard for 1 minute — the split time drops, the form does not.',
            'Paddle lightly for 1 minute to recover.',
            'Repeat 5-8 rounds, then cool down with 2 minutes of easy strokes.'],
        ru_steps=[
            'Разомнитесь 3 минутами лёгкой гребли.',
            'Гребите мощно 1 минуту — темп растёт, техника не ломается.',
            'Восстановитесь 1 минутой очень лёгкой гребли.',
            'Повторите 5-8 кругов и закончите 2 минутами спокойных гребков.']),
]

MUSCLE_VOCAB = {'adductors', 'back', 'biceps', 'calves', 'chest', 'core',
                'forearms', 'glutes', 'hamstrings', 'lats', 'lower_back',
                'quads', 'shoulders', 'traps', 'triceps'}


def main() -> None:
    equipment = json.loads((ROOT / 'equipment.json').read_text('utf-8'))
    exercises = json.loads((ROOT / 'exercises.json').read_text('utf-8'))
    ru_overlay = json.loads((ROOT / 'exercises.ru.json').read_text('utf-8'))

    # -- equipment.json: keep the 10 existing entries verbatim, append new --
    existing = {e['id']: e for e in equipment}
    assert set(existing) <= set(M), 'registry must cover every existing id'
    out_equipment = list(equipment)
    for mid, row in M.items():
        if mid in existing:
            continue
        assert row['den'], f'{mid}: new entry needs an EN description'
        out_equipment.append({
            'id': mid,
            'name': row['en'],
            'manufacturer': 'Any',
            'category': row['cat'],
            'description': row['den'],
        })

    # -- equipment.ru.json --
    out_ru = {mid: {'name': row['ru'], 'description': row['dru']}
              for mid, row in M.items()}

    # -- equipment_aliases.json (names are also aliases; all lowercase) --
    out_aliases = {}
    seen = {}
    for mid, row in M.items():
        aliases = sorted({a.strip().lower()
                          for a in row['aliases'] + [row['en'], row['ru']]})
        for a in aliases:
            assert a not in seen, f'alias {a!r} claimed by {seen.get(a)} and {mid}'
            seen[a] = mid
        out_aliases[mid] = aliases

    # -- exercises.json: reassign + append new --
    by_title = {e['title']: e for e in exercises}
    for title, target in REASSIGN.items():
        assert title in by_title, f'reassign target missing: {title}'
        by_title[title]['equipmentId'] = target
    known_ids = {e['id'] for e in exercises}
    for spec in NEW_EXERCISES:
        assert set(spec['muscles']) <= MUSCLE_VOCAB, spec['id']
        assert spec['equipmentId'] in M, spec['id']
        entry = {
            'id': spec['id'],
            'title': spec['title'],
            'equipmentId': spec['equipmentId'],
            'muscles': spec['muscles'],
            'primaryMuscles': spec['primary'],
            'difficulty': spec['difficulty'],
            'durationMinutes': spec['minutes'],
            'summary': spec['steps'][0],
            'steps': spec['steps'],
            'frames': [],
            'contraindications': spec['contra'],
        }
        if spec['id'] in known_ids:  # idempotent rerun
            exercises = [e for e in exercises if e['id'] != spec['id']]
        exercises.append(entry)
        ru_overlay[spec['id']] = {
            'title': spec['ru_title'],
            'steps': spec['ru_steps'],
        }

    def dump(path, data):
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=1) + '\n', 'utf-8')

    dump(ROOT / 'equipment.json', out_equipment)
    dump(ROOT / 'equipment.ru.json', out_ru)
    dump(ROOT / 'equipment_aliases.json', out_aliases)
    dump(ROOT / 'exercises.json', exercises)
    dump(ROOT / 'exercises.ru.json', ru_overlay)

    # -- report --
    per = collections.Counter(e.get('equipmentId') for e in exercises)
    print(f'equipment: {len(out_equipment)} ids '
          f'({len(out_equipment) - len(existing)} new)')
    print(f'aliases: {sum(len(v) for v in out_aliases.values())} '
          f'across {len(out_aliases)} ids')
    print(f"treadmill exercises now: "
          f"{[e['title'] for e in exercises if e.get('equipmentId') == 'treadmill']}")
    print(f"rowing exercises now: "
          f"{[e['title'] for e in exercises if e.get('equipmentId') == 'rowing_machine']}")
    print(f'exercises total: {len(exercises)}; bodyweight: {per[None]}')


if __name__ == '__main__':
    main()
