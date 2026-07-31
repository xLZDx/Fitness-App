# -*- coding: utf-8 -*-
"""Calves. 20 rows: 7 merge into the existing catalog, 13 authored here.

The folder is not the muscle here. `barbell_clean_and_press` and
`dumbbell_front_squat` sit in the calves tree but are a full-body lift and a
squat, so they carry their own muscle tags rather than the folder default --
the chart would otherwise highlight calves for a clean and press.

`donkey_calf_raise` keeps the public-domain text, which names a donkey calf
raise machine outright, so its equipment follows the text to
`calf_raise_machine` instead of being left bodyweight.
"""
ENTRIES = {
    'barbell_clean_and_press': {
        't': 'Barbell Clean and Press',
        'eq': 'barbell', 'm': ['quads', 'glutes', 'shoulders', 'traps'],
        'p': ['quads'], 'd': 'advanced', 'min': 8,
        'ru': 'Взятие штанги на грудь и жим',
        'rs': [
            'Встаньте, стопы на ширине плеч, колени внутри рук. Сохраняя спину прямой, согнитесь в коленях и тазобедренных суставах так, чтобы взяться за гриф на прямых руках прямым хватом чуть шире плеч. Локти разведены в стороны, гриф близко к голеням, плечи над грифом или чуть впереди него. Зафиксируйте прямую спину. Это исходное положение.',
            'Начните тянуть гриф, разгибая колени. Выводите таз вперёд и поднимайте плечи с той же скоростью, сохраняя угол наклона спины; продолжайте вести гриф строго вверх, близко к телу.',
            'Когда гриф проходит колени, мощно разогните голеностопы, колени и таз — движение похоже на прыжок. Одновременно продолжайте направлять гриф руками, делая шраг плечами и используя набранную инерцию, чтобы поднять гриф как можно выше. Гриф идёт близко к телу, локти остаются разведёнными.',
            'В верхней точке стопы отрываются от пола, и вы начинаете подсаживаться под гриф. Механика может немного меняться в зависимости от веса. Уходя под гриф, опускайтесь в присед.',
            'Когда гриф достигает предельной высоты, проверните локти вокруг грифа вперёд. Примите гриф на переднюю часть плеч, удерживая корпус вертикально и амортизируя вес сгибанием тазобедренных суставов и коленей.',
            'Выпрямитесь во весь рост, удерживая гриф в положении на груди.',
            'Не переставляя стопы, на выдохе выжмите гриф над головой. Подконтрольно опустите гриф.',
        ],
    },
    'donkey_calf_raise': {
        't': 'Donkey Calf Raise',
        'eq': 'calf_raise_machine', 'm': ['calves'],
        'ru': 'Подъёмы на носки в наклоне',
        'rs': [
            'Для этого упражнения нужен тренажёр для подъёмов на носки в наклоне. Подведите поясницу и таз под мягкий упор так, чтобы он ложился на область копчика.',
            'Возьмитесь руками за боковые рукояти и поставьте носки на платформу так, чтобы пятки свисали. Разверните носки прямо, внутрь или наружу в зависимости от того, какой участок мышцы нужно нагрузить, и выпрямите колени, не блокируя их. Это исходное положение.',
            'На выдохе поднимите пятки как можно выше, разгибая голеностопы и напрягая икры. Колени всё время остаются неподвижными — они не должны сгибаться. Задержитесь в сокращении на секунду, прежде чем начать движение вниз.',
            'На вдохе медленно вернитесь в исходное положение, опуская пятки и сгибая голеностопы, пока икры не растянутся.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_front_squat': {
        't': 'Dumbbell Front Squat',
        'eq': 'dumbbell', 'm': ['quads', 'glutes', 'hamstrings', 'calves'],
        'p': ['quads'], 'min': 8,
        'ru': 'Приседания с гантелями',
        'rs': [
            'Встаньте прямо, держа по гантели в каждой руке (ладони обращены к бёдрам).',
            'Поставьте стопы на ширине плеч, носки слегка развёрнуты наружу. Всё время держите голову поднятой — взгляд вниз нарушает равновесие — и сохраняйте прямую спину. Это исходное положение. Примечание: здесь используется описанная средняя постановка стоп, которая развивает мышцы в целом; при желании можно выбрать любую из трёх постановок из раздела о положении стоп.',
            'Медленно опускайте корпус, сгибая колени и сохраняя прямую осанку и поднятую голову. Опускайтесь, пока бёдра не станут параллельны полу. Подсказка: при правильном выполнении передняя часть коленей образует воображаемую вертикальную линию с носками. Если колени выходят за эту линию, нагрузка на коленный сустав избыточна и упражнение выполнено неверно.',
            'На выдохе поднимайте корпус, отталкиваясь от пола преимущественно пяткой, выпрямляя ноги и возвращаясь в исходное положение.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'sled_45_degree_calf_press': {
        't': 'Sled 45-Degree Calf Press',
        'eq': 'leg_press', 'm': ['calves'],
        'en': [
            'Sit in the 45-degree leg press and place the balls of your feet on the lower edge of the platform, hip width apart, with the heels hanging off.',
            'Press the platform up, release the safety catches and straighten the legs without locking the knees. This is the starting position.',
            'Push the platform away by extending the ankles as far as they will go as you breathe out, and hold the squeeze for a second.',
            'Let the platform come back slowly as you breathe in, until the heels drop below the toes and the calves are fully stretched.',
            'Repeat for the prescribed amount of repetitions, keeping the knees still throughout.',
        ],
        'ru': 'Жим носками в наклонном тренажёре',
        'rs': [
            'Сядьте в наклонный тренажёр для жима ногами и поставьте носки на нижний край платформы на ширине таза так, чтобы пятки свисали.',
            'Выжмите платформу вверх, снимите её со стопоров и выпрямите ноги, не блокируя колени. Это исходное положение.',
            'На выдохе оттолкните платформу, максимально разгибая голеностопы, и задержитесь в сокращении на секунду.',
            'На вдохе медленно позвольте платформе вернуться, пока пятки не опустятся ниже носков и икры полностью не растянутся.',
            'Выполните рекомендованное количество повторений, всё время сохраняя колени неподвижными.',
        ],
    },
    'stretching_calf_stretch_with_rope': {
        't': 'Calf Stretch with a Rope',
        'eq': None, 'm': ['calves'], 'stretch': True,
        'en': [
            'Sit on the floor with one leg straight in front of you and loop a rope around the ball of that foot, holding an end in each hand.',
            'Sit tall with the knee straight and the heel resting on the floor. This is the starting position.',
            'Pull gently on the rope so the toes draw back toward your shin, until you feel the stretch through the calf.',
            'Hold for 20 to 30 seconds, breathing steadily, then release and change legs.',
        ],
        'ru': 'Растяжка икры с верёвкой',
        'rs': [
            'Сядьте на пол, вытянув одну ногу перед собой, и накиньте верёвку на подушечку стопы, взяв концы в обе руки.',
            'Сядьте ровно: колено выпрямлено, пятка лежит на полу. Это исходное положение.',
            'Мягко потяните за верёвку, притягивая носок к голени, до ощущения растяжения в икре.',
            'Удерживайте 20–30 секунд, дыша ровно, затем отпустите и смените ногу.',
        ],
    },
    'stretching_calf_stretch_with_strap': {
        't': 'Lying Calf Stretch with a Strap',
        'eq': None, 'm': ['calves', 'hamstrings'], 'p': ['calves'],
        'stretch': True,
        'en': [
            'Lie on your back with one leg bent and that foot flat on the floor, and loop a strap around the ball of the other foot.',
            'Raise the strapped leg until it is roughly vertical, keeping the knee straight, and hold an end of the strap in each hand. This is the starting position.',
            'Pull the strap gently so the toes come toward your shin, until the calf and the back of the knee feel a steady stretch.',
            'Hold for 20 to 30 seconds without bouncing, then lower the leg and change sides.',
        ],
        'ru': 'Растяжка икры с ремнём лёжа',
        'rs': [
            'Лягте на спину, одну ногу согните и поставьте стопу на пол, а на подушечку стопы другой ноги накиньте ремень.',
            'Поднимите ногу с ремнём примерно до вертикали, не сгибая колено, и держите концы ремня в обеих руках. Это исходное положение.',
            'Мягко потяните ремень, притягивая носок к голени, пока в икре и под коленом не появится ровное растяжение.',
            'Удерживайте 20–30 секунд без рывков, затем опустите ногу и смените сторону.',
        ],
    },
    'stretching_circles_knee_stretch': {
        't': 'Knee Circles',
        'eq': None, 'm': ['calves', 'quads'], 'p': ['quads'], 'stretch': True,
        'en': [
            'Stand with your feet together, bend the knees slightly and rest your hands on top of them.',
            'Keep both feet flat on the floor and your back straight. This is the starting position.',
            'Draw slow circles with the knees, letting the knees and ankles travel through their full comfortable range.',
            'Complete 10 circles in one direction, then 10 in the other.',
        ],
        'ru': 'Круговые движения коленями',
        'rs': [
            'Встаньте, соединив стопы, слегка согните колени и положите на них ладони.',
            'Обе стопы плотно стоят на полу, спина прямая. Это исходное положение.',
            'Медленно описывайте коленями круги, проходя весь комфортный объём движения в коленях и голеностопах.',
            'Сделайте 10 кругов в одну сторону и 10 в другую.',
        ],
    },
    'stretching_feet_and_ankles_rotation_stretch': {
        't': 'Feet and Ankle Rotations',
        'eq': None, 'm': ['calves'], 'stretch': True,
        'en': [
            'Sit on a bench or a mat and lift one foot clear of the floor, straightening the knee as far as is comfortable.',
            'Hold the leg still so the movement happens at the ankle only. This is the starting position.',
            'Rotate the foot slowly through a full circle, leading with the big toe and using the whole range.',
            'Do 10 circles in each direction, then change legs.',
        ],
        'ru': 'Вращения стопами',
        'rs': [
            'Сядьте на скамью или коврик и оторвите одну стопу от пола, комфортно выпрямив колено.',
            'Нога остаётся неподвижной — движение происходит только в голеностопе. Это исходное положение.',
            'Медленно опишите стопой полный круг, ведя движение большим пальцем и проходя весь объём.',
            'Сделайте по 10 кругов в каждую сторону, затем смените ногу.',
        ],
    },
    'stretching_feet_and_ankles_stretch': {
        't': 'Feet and Ankle Stretch',
        'eq': None, 'm': ['calves'], 'stretch': True,
        'en': [
            'Kneel on a mat with the tops of your feet flat on the floor and sit back onto your heels.',
            'Keep the torso upright and your weight settled evenly on both shins. This is the starting position.',
            'Hold for 20 to 30 seconds to stretch the front of the ankles and the tops of the feet.',
            'Come up, tuck the toes under so they point forward, then sit back again for another 20 to 30 seconds to stretch the soles.',
        ],
        'ru': 'Растяжка стоп и голеностопов',
        'rs': [
            'Встаньте на колени на коврик, положив подъёмы стоп на пол, и сядьте на пятки.',
            'Корпус держите вертикально, вес распределён поровну между голенями. Это исходное положение.',
            'Удерживайте 20–30 секунд, растягивая переднюю поверхность голеностопов и подъёмы стоп.',
            'Приподнимитесь, подверните пальцы стоп вперёд и снова сядьте на пятки ещё на 20–30 секунд, растягивая подошвы.',
        ],
    },
    'stretching_peroneals_stretch': {
        't': 'Peroneals Stretch',
        'eq': None, 'm': ['calves'], 'stretch': True,
        'ru': 'Растяжка малоберцовых мышц',
        'rs': [
            'Сидя, накиньте ремень, верёвку или ленту на одну стопу. Это исходное положение.',
            'Выпрямите ногу и оторвите пятку от пола, затем потяните ремень так, чтобы стопа развернулась внутрь и её внутренний край тянулся к вам. Удерживайте 10–20 секунд, затем смените сторону.',
        ],
    },
    'stretching_seated_calf_stretch': {
        't': 'Seated Calf Stretch',
        'eq': None, 'm': ['calves'], 'stretch': True,
        'ru': 'Растяжка икры сидя',
        'rs': [
            'Сядьте прямо на коврик.',
            'Согните одно колено и поставьте стопу на пол, чтобы стабилизировать корпус.',
            'Выпрямите вторую ногу и потяните носок на себя.',
            'С помощью ленты, полотенца или рукой, если дотягиваетесь, притяните пальцы стопы к себе. Удерживайте 10–20 секунд, затем смените сторону.',
        ],
    },
    'stretching_stairs_calf_stretch': {
        't': 'Stairs Calf Stretch',
        'eq': None, 'm': ['calves'], 'stretch': True,
        'en': [
            'Stand on a step with the balls of both feet on the edge and the heels hanging over it, holding the rail for balance.',
            'Straighten the knees and take your weight evenly on both feet. This is the starting position.',
            'Let the heels sink below the level of the step until you feel a steady stretch through both calves.',
            'Hold for 20 to 30 seconds, then rise back up and repeat once with the knees slightly bent to reach the deeper soleus.',
        ],
        'ru': 'Растяжка икры на ступеньке',
        'rs': [
            'Встаньте на ступеньку так, чтобы подушечки стоп были на её краю, а пятки свисали; держитесь за перила для равновесия.',
            'Выпрямите колени и распределите вес поровну между стопами. Это исходное положение.',
            'Позвольте пяткам опуститься ниже уровня ступеньки до ровного растяжения в обеих икрах.',
            'Удерживайте 20–30 секунд, затем поднимитесь и повторите ещё раз со слегка согнутыми коленями, чтобы растянуть более глубокую камбаловидную мышцу.',
        ],
    },
    'stretching_standing_bench_calf_stretch': {
        't': 'Standing Bench Calf Stretch',
        'eq': 'adjustable_bench', 'm': ['calves'], 'stretch': True,
        'en': [
            'Stand facing a bench and place the ball of one foot on its edge with the heel low and that leg straight.',
            'Keep the other foot flat on the floor and hold the bench for balance. This is the starting position.',
            'Shift your weight gently forward over the front foot until the calf of that leg stretches.',
            'Hold for 20 to 30 seconds, then change legs.',
        ],
        'ru': 'Растяжка икры стоя у скамьи',
        'rs': [
            'Встаньте лицом к скамье и поставьте подушечку одной стопы на её край: пятка ниже носка, нога прямая.',
            'Вторая стопа стоит на полу, руками держитесь за скамью для равновесия. Это исходное положение.',
            'Плавно перенесите вес вперёд на переднюю ногу, пока не появится растяжение в её икре.',
            'Удерживайте 20–30 секунд, затем смените ногу.',
        ],
    },
    'dumbbell_single_leg_calf_raise': {
        't': 'Dumbbell Single-Leg Calf Raise',
        'eq': 'dumbbell', 'm': ['calves'],
        'ru': 'Подъём на носок одной ноги с гантелью',
        'rs': [
            'Держитесь за устойчивую опору для равновесия и встаньте одной стопой на гриф гантели — лучше на такую, у которой круглые диски: она катится, и вам приходится сильнее стабилизировать себя, что повышает эффективность упражнения.',
            'Слегка перекатите стопу вперёд, чтобы хорошо растянуть икру. Это исходное положение.',
            'Поднимитесь на носок, перекатывая стопу через гриф, до полного разгибания голеностопа. На этом движении делайте выдох. В верхней точке сильно напрягите икру и задержитесь на секунду. Подсказка: поднимаясь, слегка откатывайте гантель назад.',
            'На вдохе опускайтесь, слегка прокатывая гантель вперёд, чтобы получить лучшее растяжение.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_standing_calf_raise': {
        't': 'Dumbbell Standing Calf Raise',
        'eq': 'dumbbell', 'm': ['calves'],
        'ru': 'Подъёмы на носки с гантелями стоя',
        'rs': [
            'Встаньте прямо, удерживая по гантели в каждой руке вдоль тела. Поставьте подушечки стоп на устойчивую подставку высотой 5–8 сантиметров так, чтобы пятки свисали и касались пола. Это исходное положение.',
            'Направив носки прямо (для равномерной нагрузки), внутрь (акцент на внешнюю головку) или наружу (акцент на внутреннюю), на выдохе оторвите пятки от пола, напрягая икры. Задержитесь в верхней точке на секунду.',
            'На вдохе вернитесь в исходное положение, медленно опуская пятки.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
}
