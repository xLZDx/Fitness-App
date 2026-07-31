# -*- coding: utf-8 -*-
"""Forearms. 9 rows: 2 dropped as unidentified, 7 authored here.

Two upstream matches are replaced rather than translated. Free Exercise DB
paired `barbell_reverse_wrist_curl_over_grip` and
`dumbbell_seated_neutral_wrist_curl` with BICEPS curls -- both matched texts
say "contracting the biceps ... until the bar is at shoulder level", which is
not a wrist curl at all. The English for those two is written here.
"""
ENTRIES = {
    'barbell_reverse_wrist_curl_over_grip': {
        't': 'Barbell Reverse Wrist Curl - Overhand Grip',
        'eq': 'barbell', 'm': ['forearms'],
        'en': [
            'Sit on the end of a bench holding a barbell with an overhand grip, hands shoulder width apart, and rest your forearms along your thighs with the wrists free beyond the knees.',
            'Let the wrists drop as far as they comfortably go, palms still facing down. This is the starting position.',
            'Keeping the forearms flat on the thighs, lift the backs of the hands toward the ceiling as you breathe out, and hold the top for a second.',
            'Lower the bar slowly back to the stretched position as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Разгибания запястий со штангой прямым хватом',
        'rs': [
            'Сядьте на край скамьи, возьмите штангу прямым хватом на ширине плеч и положите предплечья на бёдра так, чтобы кисти свободно свисали за коленями.',
            'Опустите кисти вниз до комфортного предела, ладони по-прежнему смотрят вниз. Это исходное положение.',
            'Не отрывая предплечья от бёдер, на выдохе поднимите тыльную сторону ладоней к потолку и задержитесь в верхней точке на секунду.',
            'На вдохе медленно опустите штангу в растянутое положение и выполните рекомендованное количество повторений.',
        ],
    },
    'barbell_standing_back_wrist_curl': {
        't': 'Barbell Standing Behind-the-Back Wrist Curl',
        'eq': 'barbell', 'm': ['forearms'],
        'ru': 'Сгибания запястий со штангой за спиной стоя',
        'rs': [
            'Встаньте прямо и удерживайте штангу за спиной на прямых руках прямым хватом (ладони обращены назад, от ягодиц), кисти на ширине плеч.',
            'Смотрите прямо перед собой, стопы на ширине плеч. Это исходное положение.',
            'На выдохе медленно поднимите штангу, сгибая кисти по дуге к потолку. Примечание: в этом упражнении двигаются только кисти.',
            'Задержитесь в сокращении на секунду и на вдохе опустите штангу в исходное положение.',
            'Выполните рекомендованное количество повторений.',
            'Закончив, опустите штангу на стойку или на пол, сгибая колени. Подсказка: проще всего снимать её со стоек или принимать из рук напарника.',
        ],
    },
    'dumbbell_behind_back_wrist_curl': {
        't': 'Dumbbell Behind-the-Back Wrist Curl',
        'eq': 'dumbbell', 'm': ['forearms'],
        'en': [
            'Stand upright holding a dumbbell in each hand behind your glutes at arm\'s length, palms facing back, feet shoulder width apart.',
            'Let the dumbbells roll toward your fingers so the wrists extend fully. This is the starting position.',
            'Curl the wrists up toward the ceiling as you breathe out, moving nothing but the hands, and squeeze for a second at the top.',
            'Lower the dumbbells back under control as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Сгибания запястий с гантелями за спиной',
        'rs': [
            'Встаньте прямо, удерживая по гантели в каждой руке за спиной на прямых руках, ладони обращены назад, стопы на ширине плеч.',
            'Позвольте гантелям скатиться к пальцам, полностью разогнув кисти. Это исходное положение.',
            'На выдохе согните кисти к потолку, двигая только ладонями, и задержитесь в верхней точке на секунду.',
            'На вдохе подконтрольно опустите гантели и выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_over_bench_wrist_curl': {
        't': 'Dumbbell Over-Bench Reverse Wrist Curl',
        'eq': 'dumbbell', 'm': ['forearms'],
        'ru': 'Разгибания запястий с гантелями на скамье',
        'rs': [
            'Положите две гантели с одной стороны горизонтальной скамьи.',
            'Опуститесь на оба колена лицом к скамье.',
            'Возьмите обе гантели прямым хватом (ладони вниз) и положите предплечья на скамью так, чтобы кисти свисали с края.',
            'На выдохе поднимите кисти вверх.',
            'На вдохе медленно опустите кисти в исходное положение.',
            'Предплечья остаются неподвижными: в этом упражнении двигаются только кисти.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_seated_neutral_wrist_curl': {
        't': 'Dumbbell Seated Neutral Wrist Curl',
        'eq': 'dumbbell', 'm': ['forearms'],
        'en': [
            'Sit on the end of a bench with a dumbbell in each hand, elbows close to the torso and palms facing each other.',
            'Rest your forearms on your thighs with the wrists hanging free beyond the knees, thumbs pointing up. This is the starting position.',
            'Keeping the forearms still, bend the wrists so the thumbs travel toward the ceiling as you breathe out, and hold for a second.',
            'Lower the hands slowly to the stretched position as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Сгибания запястий с гантелями нейтральным хватом сидя',
        'rs': [
            'Сядьте на край скамьи, взяв по гантели в каждую руку; локти прижаты к корпусу, ладони обращены друг к другу.',
            'Положите предплечья на бёдра так, чтобы кисти свободно свисали за коленями, большие пальцы направлены вверх. Это исходное положение.',
            'Не двигая предплечьями, на выдохе согните кисти так, чтобы большие пальцы шли к потолку, и задержитесь на секунду.',
            'На вдохе медленно опустите кисти в растянутое положение и выполните рекомендованное количество повторений.',
        ],
    },
    'stretching_side_wrist_pull_stretch': {
        't': 'Side Wrist Pull Stretch',
        'eq': None, 'm': ['forearms', 'shoulders'], 'p': ['forearms'],
        'stretch': True,
        'ru': 'Боковое растяжение запястья',
        'rs': [
            'Растяжение удобнее выполнять стоя. Заведите левую руку через среднюю линию тела и возьмитесь правой рукой за левое запястье на уровне бёдер. Начните с согнутой левой руки.',
            'Медленно выпрямите руку, потяните её и поднимите до уровня плеча. Растяжение должно ощущаться в спине, а не в плечах; не тяните плечевой сустав слишком сильно. Смените сторону.',
        ],
    },
    'stretching_wrist_circles': {
        't': 'Wrist Circles',
        'eq': None, 'm': ['forearms'], 'stretch': True,
        'ru': 'Вращения кистями',
        'rs': [
            'Встаньте прямо, стопы на ширине плеч. Поднимите руки в стороны до полного выпрямления, параллельно полу, на уровне плеч. Подсказка: корпус и руки образуют букву «Т», ладони обращены вниз. Это исходное положение.',
            'Удерживая всё тело неподвижным, начните вращать обе кисти вперёд по кругу. Подсказка: представьте, что рисуете круги ладонями, как кистью. Дышите ровно.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
}
