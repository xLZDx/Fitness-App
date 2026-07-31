# -*- coding: utf-8 -*-
"""Trapezius. 7 rows: 1 merges into the existing catalog, 6 authored here.

`dumbbell_incline_shrug` carries no `en` from upstream on purpose. The Jaccard
matcher paired it with the plain "Dumbbell Shrug" instructions, which open with
"Stand erect" -- the incline shrug is done face down on a bench, so the matched
text describes a different exercise and is replaced rather than translated.
"""
ENTRIES = {
    'barbell_shrug': {
        't': 'Barbell Shrug',
        'eq': 'barbell', 'm': ['traps', 'forearms'], 'p': ['traps'],
        'ru': 'Шраги со штангой',
        'rs': [
            'Встаньте прямо, ноги на ширине плеч, держите штангу перед собой прямым хватом (ладони обращены к бёдрам). Подсказка: руки чуть шире плеч; для надёжного хвата можно использовать лямки. Это исходное положение.',
            'На выдохе поднимите плечи как можно выше и задержитесь в сокращении на секунду. Подсказка: не пытайтесь тянуть штангу бицепсами.',
            'На вдохе медленно вернитесь в исходное положение.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_shrug': {
        't': 'Dumbbell Shrug',
        'eq': 'dumbbell', 'm': ['traps', 'forearms'], 'p': ['traps'],
        'ru': 'Шраги с гантелями',
        'rs': [
            'Встаньте прямо, держа по гантели в каждой руке (ладони обращены к корпусу), руки опущены по бокам.',
            'На выдохе поднимите гантели, максимально подняв плечи. Задержитесь в верхней точке на секунду. Подсказка: руки всё время остаются прямыми. Не помогайте себе бицепсами — двигаться должны только плечи.',
            'Опустите гантели обратно в исходное положение.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_incline_shrug': {
        't': 'Dumbbell Incline Shrug',
        'eq': 'dumbbell', 'm': ['traps', 'shoulders'], 'p': ['traps'],
        'en': [
            'Set an adjustable bench to a shallow incline and lie face down on it, chest against the pad, holding a dumbbell in each hand at arm\'s length.',
            'Let your shoulders drop toward the floor until you feel the trapezius stretch. This is the starting position.',
            'Keeping the arms straight, shrug the shoulders up and slightly back toward your ears as you breathe out, and hold the squeeze for a second.',
            'Lower the dumbbells under control as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Шраги с гантелями лёжа на наклонной скамье',
        'rs': [
            'Установите скамью под небольшим наклоном и лягте на неё грудью вниз, удерживая по гантели в каждой руке на прямых руках.',
            'Позвольте плечам опуститься вниз до ощущения растяжения трапеций. Это исходное положение.',
            'Не сгибая руки, на выдохе поднимите плечи вверх и слегка назад, к ушам, и задержитесь в сокращении на секунду.',
            'На вдохе подконтрольно опустите гантели и выполните рекомендованное количество повторений.',
        ],
    },
    'lever_shrug': {
        't': 'Machine Shrug',
        'eq': None, 'm': ['traps', 'forearms'], 'p': ['traps'],
        'en': [
            'Load the shrug machine and take the handles at your sides with your arms straight, standing or seated tall with your chest up.',
            'Let the weight pull your shoulders down until the trapezius is stretched. This is the starting position.',
            'Drive your shoulders straight up toward your ears as you breathe out, keeping the arms straight and the chin level, and hold the top for a second.',
            'Lower under control as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Шраги в тренажёре',
        'rs': [
            'Установите вес, возьмитесь за рукояти по бокам на прямых руках; встаньте или сядьте ровно, грудь развёрнута.',
            'Позвольте весу опустить плечи вниз до растяжения трапеций. Это исходное положение.',
            'На выдохе поднимите плечи строго вверх, к ушам, не сгибая руки и не опуская подбородок, и задержитесь на секунду.',
            'На вдохе подконтрольно опустите плечи и выполните рекомендованное количество повторений.',
        ],
    },
    'scapula_dips': {
        't': 'Scapular Dip',
        'eq': 'dip_station', 'm': ['traps', 'shoulders'], 'p': ['traps'],
        'en': [
            'Support yourself on parallel bars with your arms locked straight and let your shoulders rise toward your ears.',
            'Keep the elbows straight for the whole set — the movement happens at the shoulder blades only. This is the starting position.',
            'Pull the shoulder blades down and together so your body rises a few centimetres without the arms bending, and hold for a second.',
            'Let the shoulders travel back up toward your ears under control, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Лопаточные отжимания на брусьях',
        'rs': [
            'Займите упор на брусьях: руки выпрямлены и зафиксированы, плечи подняты к ушам.',
            'Локти остаются прямыми весь подход — работают только лопатки. Это исходное положение.',
            'Опустите и сведите лопатки так, чтобы корпус поднялся на несколько сантиметров без сгибания рук, и задержитесь на секунду.',
            'Подконтрольно позвольте плечам подняться обратно к ушам и выполните рекомендованное количество повторений.',
        ],
    },
    'stretching_neck_side_stretch': {
        't': 'Neck Side Stretch',
        'eq': None, 'm': ['traps'], 'stretch': True,
        'ru': 'Боковое растяжение шеи',
        'rs': [
            'Расслабьте плечи и мягко наклоните голову к плечу.',
            'Усильте растяжение лёгким нажатием ладони на боковую поверхность головы.',
        ],
    },
}
