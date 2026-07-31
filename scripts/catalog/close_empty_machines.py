# -*- coding: utf-8 -*-
"""A1 (2026-07-31): close the 11 registry machines that still have zero
curated exercises.

Why they were empty is not a gap in the upstream source -- it is a line I
wrote. `import_free_exercise_db.py:63` restricts the import to
strength/plyometrics/powerlifting/olympic-weightlifting, which drops the whole
`cardio` category (14 entries). Those 14 are exactly the elliptical, the
stationary bike, the stair machines and the rowing/treadmill entries. I then
told the operator "the source has nothing for the elliptical", which was
wrong: `Elliptical Trainer` is right there, with two photos and instructions.

The rest were lost to name matching, not category: "Battling Ropes" does not
contain the alias "battle ropes"; pull-ups resolve to the bodyweight bucket
rather than to the bar they hang from; nothing maps "Russian Twist" onto a
rotary torso machine.

So this script does not change the general importer's policy -- it names the
specific upstream entries that belong to the specific empty machines, which is
a judgement per row rather than a rule, and writes them straight into the
catalog with hand-written Russian.

Two machines have no upstream entry at all (`air_bike`, `ski_erg`); those are
hand-authored below, the same way the treadmill and rower were in round 3.

Run: python scripts/catalog/close_empty_machines.py
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = Path('D:/Temp/claude/free_exercise_db.json')
DATA = ROOT / 'mobile' / 'assets' / 'data'

IMG_BASE = ('https://raw.githubusercontent.com/yuhonas/free-exercise-db/'
            'main/exercises/')

# Upstream name -> our machine id. Each verified by reading the upstream
# instructions against the registry entry, not guessed from the title.
OVERRIDE = {
    'Elliptical Trainer': 'elliptical',
    'Stairmaster': 'stair_climber',
    'Step Mill': 'stair_climber',
    'Bicycling, Stationary': 'exercise_bike',
    'Recumbent Bike': 'recumbent_bike',
    'Battling Ropes': 'battle_ropes',
    'Rope Climb': 'battle_ropes',
    'Pullups': 'pullup_bar',
    'Chin-Up': 'pullup_bar',
    'Muscle Up': 'pullup_bar',
    'One Arm Chin-Up': 'pullup_bar',
    'Scapular Pull-Up': 'pullup_bar',
    'Kipping Muscle Up': 'pullup_bar',
    'Hanging Leg Raise': 'captains_chair',
    'Hanging Pike': 'captains_chair',
    'Knee/Hip Raise On Parallel Bars': 'captains_chair',
    'Russian Twist': 'rotary_torso_machine',
    'Cable Russian Twists': 'rotary_torso_machine',
    'Seated Barbell Twist': 'rotary_torso_machine',
    'Front Plate Raise': 'weight_plates',
    'Plate Pinch': 'weight_plates',
    'Plate Twist': 'weight_plates',
    'Reverse Plate Curls': 'weight_plates',
}

MUSCLE_MAP = {
    'abdominals': 'core', 'abductors': 'adductors', 'adductors': 'adductors',
    'biceps': 'biceps', 'calves': 'calves', 'chest': 'chest',
    'forearms': 'forearms', 'glutes': 'glutes', 'hamstrings': 'hamstrings',
    'lats': 'lats', 'lower back': 'lower_back', 'middle back': 'back',
    'neck': None, 'quadriceps': 'quads', 'shoulders': 'shoulders',
    'traps': 'traps', 'triceps': 'triceps',
}

# Our own instructions, in both languages, three steps each.
#
# The upstream prose is deliberately not shipped. It runs to five or seven
# steps of the "Tip: at the end of the movement your knees will be over your
# chest" variety, and the catalog holds a hard invariant that the Russian step
# count matches the English one -- so pairing verbose upstream English with a
# concise Russian translation would either break that invariant or force
# padding the Russian with filler. Writing both sides keeps them equal by
# construction and reads better besides. The source is public domain, so
# adapting rather than reproducing is allowed; the photographs are still
# theirs and are still used and credited.
EN = {
    'Elliptical Trainer': [
        'Step onto the pedals and take hold of the moving handles.',
        'Set the resistance and start moving - your feet trace a long oval '
        'and never leave the pedals.',
        'Keep your torso upright rather than leaning on the handles.',
    ],
    'Stairmaster': [
        'Step onto the stairs and hold the rails without putting weight on them.',
        'Set the pace and climb, straightening the leg fully at the top.',
        'Stay upright instead of hunching over the console.',
    ],
    'Step Mill': [
        'Step onto the moving stairs and hold the rails for balance.',
        'Climb at the set pace, placing the whole foot on each step.',
        'Do not lean your weight on the rails - it takes the work off your legs.',
    ],
    'Bicycling, Stationary': [
        'Set the saddle so your leg is almost straight at the bottom.',
        'Set the resistance and pedal at an even pace.',
        'Keep your back neutral instead of collapsing onto the bars.',
    ],
    'Recumbent Bike': [
        'Sit back against the rest and set the distance to the pedals.',
        'Pedal at an even pace with a resistance you can hold.',
        'Leave a small bend in the knee at full extension.',
    ],
    'Battling Ropes': [
        'Take an end in each hand, stand in a quarter squat, feet hip width.',
        'Raise and drop the arms alternately to send waves down the ropes.',
        'Work with the whole body rather than only the arms; keep the back flat.',
    ],
    'Rope Climb': [
        'Grip the rope as high as you can reach and clamp it between your feet.',
        'Pull up, tuck the knees, re-clamp higher and stand through the legs.',
        'Come down under control, hand over hand, rather than sliding.',
    ],
    'Pullups': [
        'Take an overhand grip a little wider than the shoulders and hang.',
        'Pull the shoulder blades down and together until the chin clears the bar.',
        'Lower under control to straight arms.',
    ],
    'Chin-Up': [
        'Take an underhand grip at shoulder width and hang.',
        'Pull with the elbows driving down and back until the chin clears the bar.',
        'Lower slowly rather than dropping.',
    ],
    'Muscle Up': [
        'Hang from the bar with an overhand grip and build a small swing.',
        'Pull hard and drive the chest over the bar, rolling the wrists over.',
        'Press to straight arms, then reverse the path down.',
    ],
    'One Arm Chin-Up': [
        'Take the bar with one hand and tuck the other behind your back.',
        'Pull until the chin clears the bar without letting the torso rotate.',
        'Lower under control, then match the reps on the other arm.',
    ],
    'Scapular Pull-Up': [
        'Hang from the bar with straight arms and relaxed shoulders.',
        'Without bending the arms, pull the shoulder blades down and together.',
        'Return to a free hang. The movement is short and comes only from '
        'the shoulder blades.',
    ],
    'Kipping Muscle Up': [
        'Hang from the bar and set up a pendulum with the whole body.',
        'On the forward swing pull hard and drive the chest over the bar.',
        'Press to straight arms, then come down and damp the swing.',
    ],
    'Hanging Leg Raise': [
        'Hang from a bar or brace on the parallel bars with the torso still.',
        'Raise straight legs to horizontal by curling the pelvis upward.',
        'Lower slowly without swinging.',
    ],
    'Hanging Pike': [
        'Hang from the bar with an overhand grip.',
        'Raise straight legs toward the bar, folding at the hips.',
        'Lower under control to a full hang.',
    ],
    'Knee/Hip Raise On Parallel Bars': [
        'Brace your forearms and back against the frame, legs hanging free.',
        'Draw the knees to the chest by curling the pelvis up.',
        'Lower slowly without pushing off the backrest.',
    ],
    'Russian Twist': [
        'Sit with the knees bent and lean back to about forty-five degrees.',
        'Rotate the torso left and right, letting the hands follow.',
        'Keep the back flat - the rotation comes from the torso, not the arms.',
    ],
    'Cable Russian Twists': [
        'Sit side-on to a low pulley and take the handle in both hands.',
        'Lean back and rotate the torso away from the pulley and back.',
        'Move the hands with the torso, keeping them on the line of the chest.',
    ],
    'Seated Barbell Twist': [
        'Sit on a bench with the bar across your shoulders and feet flat.',
        'Rotate the torso left and right through a comfortable range.',
        'Keep the hips still - the movement belongs to the upper back.',
    ],
    'Front Plate Raise': [
        'Hold a plate by its edges with both hands, arms down in front.',
        'Raise the plate to eye level with straight arms.',
        'Lower slowly without help from the torso.',
    ],
    'Plate Pinch': [
        'Hold two plates smooth sides out and pinch them with the fingers.',
        'Hold them at your side for as long as you can.',
        'Set the plates down under control rather than dropping them.',
    ],
    'Plate Twist': [
        'Sit with the knees bent and hold a plate in both hands at the chest.',
        'Lean back and rotate the torso with the plate left and right.',
        'Keep the back flat and the movement smooth.',
    ],
    'Reverse Plate Curls': [
        'Hold a plate by its edges with both hands, arms hanging down.',
        'Bend the elbows to bring the plate to chest height, upper arms still.',
        'Lower slowly to straight arms.',
    ],
}

RU = {
    'Elliptical Trainer': ('Эллиптический тренажёр', [
        'Встаньте на педали и возьмитесь за подвижные рукоятки.',
        'Задайте сопротивление и начните движение — стопы описывают вытянутый овал, не отрываясь от педалей.',
        'Держите корпус прямо, не наваливайтесь на рукоятки. Дышите ровно.',
    ]),
    'Stairmaster': ('Степпер', [
        'Встаньте на ступени и возьмитесь за поручни, не перенося на них вес.',
        'Задайте темп и шагайте, полностью распрямляя ногу в верхней точке.',
        'Держите корпус вертикально, не сутультесь над панелью.',
    ]),
    'Step Mill': ('Лестничный тренажёр', [
        'Зайдите на движущиеся ступени и возьмитесь за поручни для равновесия.',
        'Шагайте в заданном темпе, ставя стопу на ступень целиком.',
        'Не опирайтесь на поручни всем весом — это снимает нагрузку с ног.',
    ]),
    'Bicycling, Stationary': ('Велотренажёр', [
        'Отрегулируйте седло так, чтобы в нижней точке нога почти распрямлялась.',
        'Задайте сопротивление и крутите педали в ровном темпе.',
        'Держите спину нейтральной, не заваливайтесь на руль.',
    ]),
    'Recumbent Bike': ('Горизонтальный велотренажёр', [
        'Сядьте в кресло, спина прижата к спинке, отрегулируйте расстояние до педалей.',
        'Крутите педали в ровном темпе, сопротивление по самочувствию.',
        'Не выпрямляйте ногу до конца — оставляйте небольшой угол в колене.',
    ]),
    'Battling Ropes': ('Канаты', [
        'Возьмите концы канатов, встаньте в полуприсед, стопы на ширине плеч.',
        'Поочерёдно поднимайте и опускайте руки, посылая по канатам волны.',
        'Работайте всем корпусом, а не только руками. Держите спину прямой.',
    ]),
    'Rope Climb': ('Лазание по канату', [
        'Возьмитесь за канат как можно выше и зажмите его стопами.',
        'Подтянитесь, подтяните колени, снова зажмите канат выше и распрямите ноги.',
        'Спускайтесь контролируемо, перехватывая руками, а не съезжая.',
    ]),
    'Pullups': ('Подтягивания', [
        'Возьмитесь за перекладину хватом сверху чуть шире плеч, повисните.',
        'Сведите лопатки и подтянитесь, пока подбородок не окажется выше перекладины.',
        'Опуститесь контролируемо до полного выпрямления рук.',
    ]),
    'Chin-Up': ('Подтягивания обратным хватом', [
        'Возьмитесь за перекладину хватом снизу на ширине плеч, повисните.',
        'Подтянитесь, ведя локти вниз и назад, до подбородка над перекладиной.',
        'Опуститесь медленно, не бросая тело вниз.',
    ]),
    'Muscle Up': ('Выход силой', [
        'Повисните на перекладине хватом сверху, чуть раскачайте корпус.',
        'Мощно подтянитесь и переведите грудь над перекладиной, перекатывая кисти.',
        'Дожмите руки до прямых, затем опуститесь тем же путём.',
    ]),
    'One Arm Chin-Up': ('Подтягивание на одной руке', [
        'Возьмитесь за перекладину одной рукой, вторую уберите за спину.',
        'Подтянитесь до подбородка над перекладиной, не разворачивая корпус.',
        'Опуститесь контролируемо. Выполните столько же на другой руке.',
    ]),
    'Scapular Pull-Up': ('Подтягивание лопатками', [
        'Повисните на перекладине на прямых руках, плечи расслаблены.',
        'Не сгибая рук, опустите и сведите лопатки — тело поднимется на несколько сантиметров.',
        'Вернитесь в свободный вис. Движение короткое, работают только лопатки.',
    ]),
    'Kipping Muscle Up': ('Выход силой с раскачкой', [
        'Повисните на перекладине и задайте маятник корпусом.',
        'На движении вперёд мощно подтянитесь и переведите грудь над перекладиной.',
        'Дожмите руки, затем опуститесь, гася раскачку.',
    ]),
    'Hanging Leg Raise': ('Подъём ног в висе', [
        'Повисните на перекладине или упритесь в брусья, корпус неподвижен.',
        'Поднимите прямые ноги до горизонтали, скручивая таз вверх.',
        'Опустите ноги медленно, не раскачиваясь.',
    ]),
    'Hanging Pike': ('Подъём ног к перекладине', [
        'Повисните на перекладине хватом сверху.',
        'Поднимите прямые ноги к перекладине, складываясь в тазобедренном суставе.',
        'Опустите ноги под контролем до полного виса.',
    ]),
    'Knee/Hip Raise On Parallel Bars': ('Подъём коленей в упоре на брусьях', [
        'Упритесь предплечьями и спиной в тренажёр, ноги свободно висят.',
        'Подтяните колени к груди, скручивая таз вверх.',
        'Опустите ноги медленно, не отталкиваясь от спинки.',
    ]),
    'Russian Twist': ('Русский поворот', [
        'Сядьте, согните колени, отклоните корпус назад до угла около 45 градусов.',
        'Разворачивайте корпус влево и вправо, ведя руки за собой.',
        'Держите спину прямой — поворот идёт от корпуса, а не от рук.',
    ]),
    'Cable Russian Twists': ('Русский поворот на блоке', [
        'Сядьте боком к нижнему блоку, возьмите рукоять двумя руками.',
        'Отклоните корпус назад и разворачивайте его от блока и обратно.',
        'Двигайте руки вместе с корпусом, не отрывая их от линии груди.',
    ]),
    'Seated Barbell Twist': ('Повороты корпуса сидя со штангой', [
        'Сядьте на скамью, положите гриф на плечи, стопы плотно на полу.',
        'Разворачивайте корпус влево и вправо в комфортной амплитуде.',
        'Таз остаётся неподвижным — работает только грудной отдел.',
    ]),
    'Front Plate Raise': ('Подъём блина перед собой', [
        'Возьмите блин двумя руками по краям, руки внизу перед бёдрами.',
        'Поднимите блин прямыми руками до уровня глаз.',
        'Опустите медленно, не помогая корпусом.',
    ]),
    'Plate Pinch': ('Удержание блинов щипковым хватом', [
        'Возьмите два блина гладкими сторонами наружу и сожмите пальцами.',
        'Держите их на прямой руке вдоль тела столько, сколько сможете.',
        'Опустите блины контролируемо, не роняя на ноги.',
    ]),
    'Plate Twist': ('Повороты с блином', [
        'Сядьте, согните колени, возьмите блин двумя руками перед грудью.',
        'Отклоните корпус назад и разворачивайте его вместе с блином влево и вправо.',
        'Держите спину прямой, движение плавное.',
    ]),
    'Reverse Plate Curls': ('Сгибание рук с блином обратным хватом', [
        'Возьмите блин двумя руками по краям, руки опущены.',
        'Сгибая локти, поднимите блин к груди, не двигая плечами.',
        'Опустите медленно до полного выпрямления рук.',
    ]),
}

# No upstream entry exists for these two machines.
HAND_AUTHORED = [
    {
        'id': 'air_bike_intervals', 'equipmentId': 'air_bike',
        'title': 'Air Bike Intervals',
        'ru_title': 'Интервалы на эйр-байке',
        'muscles': ['quads', 'hamstrings', 'shoulders', 'core'],
        'primaryMuscles': ['quads'],
        'difficulty': 'intermediate', 'durationMinutes': 12,
        'summary': 'Short all-out efforts on the fan bike with full recoveries.',
        'ru_summary': 'Короткие ускорения на эйр-байке с полным восстановлением.',
        'steps': [
            'Set the seat so your leg is almost straight at the bottom of the pedal stroke.',
            'Warm up for three minutes at an easy pace, using both arms and legs.',
            'Work hard for 20 seconds, then pedal easily for 90 seconds. Repeat six times.',
            'Finish with two minutes of easy pedalling.',
        ],
        'ru_steps': [
            'Отрегулируйте седло так, чтобы в нижней точке нога почти распрямлялась.',
            'Разомнитесь три минуты в спокойном темпе, работая и руками, и ногами.',
            'Работайте изо всех сил 20 секунд, затем крутите легко 90 секунд. Повторите шесть раз.',
            'Закончите двумя минутами спокойной работы.',
        ],
    },
    {
        'id': 'air_bike_steady', 'equipmentId': 'air_bike',
        'title': 'Air Bike Steady Effort',
        'ru_title': 'Ровная работа на эйр-байке',
        'muscles': ['quads', 'hamstrings', 'shoulders'],
        'primaryMuscles': ['quads'],
        'difficulty': 'beginner', 'durationMinutes': 15,
        'summary': 'A conversational-pace effort on the fan bike.',
        'ru_summary': 'Работа на эйр-байке в темпе, при котором можно говорить.',
        'steps': [
            'Sit tall, shoulders relaxed, hands on the moving handles.',
            'Pedal at a pace you could hold a conversation at for fifteen minutes.',
            'Keep the effort even — the fan gets harder the faster you go, so do not start too fast.',
        ],
        'ru_steps': [
            'Сядьте прямо, плечи расслаблены, руки на подвижных рукоятках.',
            'Крутите в темпе, при котором вы смогли бы разговаривать, пятнадцать минут.',
            'Держите ровное усилие: сопротивление растёт с темпом, поэтому не начинайте слишком быстро.',
        ],
    },
    {
        'id': 'ski_erg_intervals', 'equipmentId': 'ski_erg',
        'title': 'Ski Erg Intervals',
        'ru_title': 'Интервалы на лыжном тренажёре',
        'muscles': ['lats', 'triceps', 'core', 'shoulders'],
        'primaryMuscles': ['lats'],
        'difficulty': 'intermediate', 'durationMinutes': 12,
        'summary': 'Repeated hard pulls with recoveries between them.',
        'ru_summary': 'Повторные мощные протяжки с восстановлением между ними.',
        'steps': [
            'Stand tall, grip the handles above your head, feet under your hips.',
            'Hinge at the hips and pull the handles down past your thighs, finishing with straight arms.',
            'Stand back up and reset. Work for 30 seconds, rest for 60, repeat eight times.',
        ],
        'ru_steps': [
            'Встаньте прямо, возьмите рукоятки над головой, стопы под тазом.',
            'Наклонитесь в тазобедренном суставе и протяните рукоятки вниз мимо бёдер до прямых рук.',
            'Выпрямитесь и вернитесь в исходное. Работайте 30 секунд, отдыхайте 60, повторите восемь раз.',
        ],
    },
    {
        'id': 'ski_erg_steady', 'equipmentId': 'ski_erg',
        'title': 'Ski Erg Steady Pull',
        'ru_title': 'Ровная работа на лыжном тренажёре',
        'muscles': ['lats', 'triceps', 'core'],
        'primaryMuscles': ['lats'],
        'difficulty': 'beginner', 'durationMinutes': 10,
        'summary': 'A continuous, even-paced pull to build endurance.',
        'ru_summary': 'Непрерывная работа в ровном темпе на выносливость.',
        'steps': [
            'Grip the handles overhead with a tall spine and soft knees.',
            'Drive the handles down using your lats and your body weight, not just your arms.',
            'Return smoothly to the top and continue at an even pace for ten minutes.',
        ],
        'ru_steps': [
            'Возьмите рукоятки над головой, спина прямая, колени мягкие.',
            'Тяните рукоятки вниз широчайшими и весом тела, а не только руками.',
            'Плавно возвращайтесь вверх и работайте в ровном темпе десять минут.',
        ],
    },
]


def main() -> None:
    upstream = {e['name']: e for e in json.loads(UPSTREAM.read_text('utf-8'))}
    ex_path = DATA / 'exercises.json'
    ru_path = DATA / 'exercises.ru.json'
    exercises = json.loads(ex_path.read_text('utf-8'))
    ru_map = json.loads(ru_path.read_text('utf-8'))
    known = {e['id'] for e in exercises}

    added = 0
    for name, machine in OVERRIDE.items():
        src = upstream.get(name)
        if src is None:
            raise SystemExit(f'upstream entry vanished: {name}')
        if name not in RU or name not in EN:
            raise SystemExit(f'no hand-written text for: {name}')
        if len(EN[name]) != len(RU[name][1]):
            raise SystemExit(f'step counts differ for: {name}')
        slug = 'fedb_' + src['id'].lower()
        if slug in known:
            continue
        muscles = []
        for m in src.get('primaryMuscles', []) + src.get('secondaryMuscles', []):
            mapped = MUSCLE_MAP.get(m)
            if mapped and mapped not in muscles:
                muscles.append(mapped)
        primary = [MUSCLE_MAP.get(m) for m in src.get('primaryMuscles', [])]
        primary = [m for m in primary if m]
        steps = EN[name]
        exercises.append({
            'id': slug,
            'title': src['name'],
            'equipmentId': machine,
            'muscles': muscles or ['core'],
            'primaryMuscles': primary or (muscles[:1] or ['core']),
            'difficulty': src.get('level', 'beginner'),
            'durationMinutes': 8,
            'summary': steps[0] if steps else src['name'],
            'steps': steps,
            'frames': [],
            'imageUrls': [IMG_BASE + i for i in src.get('images', [])],
            'contraindications': [],
        })
        ru_title, ru_steps = RU[name]
        ru_map[slug] = {
            'title': ru_title,
            'summary': ru_steps[0],
            'steps': ru_steps,
        }
        known.add(slug)
        added += 1

    for e in HAND_AUTHORED:
        if e['id'] in known:
            continue
        exercises.append({
            'id': e['id'], 'title': e['title'],
            'equipmentId': e['equipmentId'],
            'muscles': e['muscles'], 'primaryMuscles': e['primaryMuscles'],
            'difficulty': e['difficulty'],
            'durationMinutes': e['durationMinutes'],
            # The catalog holds `summary == steps.first` as an invariant, and
            # the Russian overlay relies on it to keep the two in step.
            'summary': e['steps'][0], 'steps': e['steps'],
            'frames': [], 'imageUrls': [], 'contraindications': [],
        })
        ru_map[e['id']] = {
            'title': e['ru_title'], 'summary': e['ru_steps'][0],
            'steps': e['ru_steps'],
        }
        added += 1

    ex_path.write_text(
        json.dumps(exercises, ensure_ascii=False, indent=1) + '\n', 'utf-8')
    ru_path.write_text(
        json.dumps(ru_map, ensure_ascii=False, indent=1) + '\n', 'utf-8')

    eq = json.loads((DATA / 'equipment.json').read_text('utf-8'))
    counts = Counter(e.get('equipmentId') for e in exercises)
    still_empty = [q['id'] for q in eq if counts.get(q['id'], 0) == 0]
    print(f'added {added}; exercises now {len(exercises)}')
    print(f'machines with zero exercises: {len(still_empty)} {still_empty}')


if __name__ == '__main__':
    main()
