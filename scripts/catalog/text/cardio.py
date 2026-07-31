# -*- coding: utf-8 -*-
"""Cardio. 20 rows: 3 dropped as duplicate clips, 3 merge, 14 authored here.

The folder default `['quads', 'core']` is wrong for this tree and is not used:
battle ropes are a shoulder and forearm exercise, jumping rope is calves, the
bridge pose stretches glutes and lower back. Every row carries its own tags.

`jump_rope` keeps a null equipmentId. A skipping rope is a real implement and
the movement needs one, but there is no id for it in equipment.json, and
pointing it at `battle_ropes` because both are called a rope would put it on
the wrong machine page. It is listed in UNSURE.txt for that reason.
"""
ENTRIES = {
    'burpee': {
        't': 'Burpee',
        'eq': None, 'm': ['quads', 'chest', 'core', 'shoulders'],
        'p': ['quads'], 'd': 'intermediate',
        'en': [
            'Stand with your feet shoulder width apart and your arms at your sides.',
            'Squat down and place both hands on the floor just outside your feet, then jump the feet back into a push-up position with the body in a straight line.',
            'Lower your chest to the floor and press back up, keeping the hips level with the shoulders.',
            'Jump the feet back under your hips, then drive through the legs into a jump with the arms overhead.',
            'Land softly with the knees bent and move straight into the next repetition.',
        ],
        'ru': 'Бёрпи',
        'rs': [
            'Встаньте, стопы на ширине плеч, руки вдоль тела.',
            'Присядьте и поставьте ладони на пол чуть шире стоп, затем прыжком отведите ноги назад в упор лёжа, вытянув тело в одну линию.',
            'Опустите грудь к полу и отожмитесь обратно, удерживая таз на одной линии с плечами.',
            'Прыжком подтяните стопы обратно под таз и, оттолкнувшись ногами, выпрыгните вверх, вытянув руки над головой.',
            'Приземлитесь мягко на согнутые колени и сразу переходите к следующему повторению.',
        ],
    },
    'elliptical': {
        't': 'Elliptical Trainer Workout',
        'eq': 'elliptical', 'm': ['quads', 'glutes', 'hamstrings', 'calves'],
        'p': ['quads'], 'min': 15,
        'en': [
            'Step onto the elliptical, set your feet flat in the middle of the pedals and take hold of the moving handles.',
            'Stand tall with the chest up and the core braced, then start the stride and pick a resistance you can hold for the whole session.',
            'Push and pull through the handles in time with the legs, keeping the heels down and the movement smooth rather than bouncing.',
            'Hold a steady pace for the planned time, or alternate one minute hard with two minutes easy for intervals.',
            'Ease the resistance down for the last two minutes to cool off, and step off only once the pedals have stopped.',
        ],
        'ru': 'Занятие на эллиптическом тренажёре',
        'rs': [
            'Встаньте на эллиптический тренажёр, поставьте стопы плотно в середину педалей и возьмитесь за подвижные рукояти.',
            'Держите корпус прямо, грудь развёрнутой, живот подтянутым; начните движение и подберите сопротивление, которое сможете удерживать всё занятие.',
            'Толкайте и тяните рукояти в такт ногам, не отрывая пятки и двигаясь плавно, без подпрыгиваний.',
            'Держите ровный темп запланированное время или чередуйте минуту интенсивной работы с двумя минутами лёгкой.',
            'За две минуты до конца снизьте сопротивление, чтобы восстановиться, и сходите с тренажёра только после остановки педалей.',
        ],
    },
    'jump_rope': {
        't': 'Jump Rope',
        'eq': None, 'm': ['calves', 'quads', 'shoulders'], 'p': ['calves'],
        'min': 10,
        'en': [
            'Hold a handle in each hand with the rope behind your heels and your elbows close to your sides.',
            'Stand tall with the feet together and the knees soft. This is the starting position.',
            'Turn the rope with the wrists rather than the arms, and hop just high enough to clear it — a couple of centimetres is enough.',
            'Land on the balls of the feet with the knees slightly bent, and keep the rhythm even.',
            'Skip for the planned time or number of turns, resting whenever the rhythm breaks down.',
        ],
        'ru': 'Прыжки со скакалкой',
        'rs': [
            'Возьмите по рукояти в каждую руку, скакалка лежит за пятками, локти прижаты к бокам.',
            'Встаньте прямо, стопы вместе, колени мягкие. Это исходное положение.',
            'Вращайте скакалку кистями, а не руками, и подпрыгивайте ровно настолько, чтобы её пропустить — достаточно пары сантиметров.',
            'Приземляйтесь на подушечки стоп со слегка согнутыми коленями и держите ровный ритм.',
            'Прыгайте запланированное время или количество оборотов, отдыхая, как только ритм сбивается.',
        ],
    },
    'jump_step_up': {
        't': 'Jump Step-Up',
        'eq': 'plyo_box', 'm': ['quads', 'glutes', 'calves'], 'p': ['quads'],
        'd': 'intermediate',
        'en': [
            'Stand facing a sturdy box or step about one foot\'s distance away, arms at your sides.',
            'Place one whole foot on the box with the knee bent and leave the other foot on the floor. This is the starting position.',
            'Drive hard through the top leg and jump straight up off the box, swapping the legs in the air.',
            'Land softly with the other foot on the box and the first foot back on the floor, absorbing the landing with a bent knee.',
            'Keep alternating for the prescribed amount of repetitions, and stop the set once the landings stop being quiet.',
        ],
        'ru': 'Зашагивания на бокс в прыжке',
        'rs': [
            'Встаньте лицом к устойчивому боксу или степу примерно на расстоянии одной стопы, руки вдоль тела.',
            'Поставьте одну стопу целиком на бокс, согнув колено; вторая стопа остаётся на полу. Это исходное положение.',
            'Мощно оттолкнитесь верхней ногой и выпрыгните вверх, меняя ноги в воздухе.',
            'Приземлитесь мягко: вторая стопа — на боксе, первая — на полу; погасите приземление сгибанием колена.',
            'Продолжайте чередовать ноги нужное количество повторений и завершите подход, как только приземления перестанут быть тихими.',
        ],
    },
    'jumping_jack': {
        't': 'Jumping Jack',
        'eq': None, 'm': ['calves', 'shoulders', 'quads'], 'p': ['calves'],
        'en': [
            'Stand upright with your feet together and your arms hanging at your sides.',
            'Brace the core and keep the knees soft. This is the starting position.',
            'Jump the feet out to a little wider than shoulder width while sweeping the arms out and overhead.',
            'Jump the feet back together and bring the arms back down in one continuous movement.',
            'Repeat at a steady rhythm for the prescribed time or amount of repetitions.',
        ],
        'ru': 'Прыжки «джампинг-джек»',
        'rs': [
            'Встаньте прямо, стопы вместе, руки опущены вдоль тела.',
            'Подтяните живот, колени держите мягкими. Это исходное положение.',
            'Прыжком расставьте стопы чуть шире плеч, одновременно разводя руки в стороны и вверх.',
            'Прыжком верните стопы вместе, опустив руки; движение должно быть непрерывным.',
            'Повторяйте в ровном ритме запланированное время или количество повторений.',
        ],
    },
    'running': {
        't': 'Running',
        'eq': None, 'm': ['quads', 'hamstrings', 'glutes', 'calves'],
        'p': ['quads'], 'min': 20,
        'en': [
            'Start with five minutes of brisk walking or easy jogging to warm the legs up.',
            'Run with the torso tall and the shoulders relaxed, elbows bent to about 90 degrees, letting the arms swing forward and back rather than across the body.',
            'Land with the foot under your hips rather than out in front, and keep the cadence quick and light.',
            'Hold a pace at which you could still speak in short sentences, for the planned distance or time.',
            'Finish with five minutes of easy walking to bring the heart rate down.',
        ],
        'ru': 'Бег',
        'rs': [
            'Начните с пяти минут быстрой ходьбы или лёгкого бега трусцой, чтобы разогреть ноги.',
            'Бегите с прямым корпусом и расслабленными плечами, локти согнуты примерно под прямым углом; руки двигаются вперёд-назад, а не поперёк тела.',
            'Ставьте стопу под таз, а не далеко перед собой, и держите частый лёгкий шаг.',
            'Держите темп, при котором вы всё ещё можете говорить короткими фразами, запланированное расстояние или время.',
            'Закончите пятью минутами спокойной ходьбы, чтобы пульс успел снизиться.',
        ],
    },
    'stationary_bike': {
        't': 'Stationary Bike',
        'eq': 'exercise_bike', 'm': ['quads', 'hamstrings', 'calves'],
        'p': ['quads'], 'min': 15,
        'en': [
            'Set the saddle height so that your knee stays slightly bent when the pedal is at its lowest point.',
            'Sit with your hands resting on the bars, the back straight and the balls of the feet over the pedal axles. This is the starting position.',
            'Pedal smoothly at a comfortable resistance for five minutes to warm up.',
            'Raise the resistance to your working level and hold a cadence of roughly 80 to 90 revolutions per minute for the planned time.',
            'Drop the resistance for the last five minutes and pedal easily to cool down.',
        ],
        'ru': 'Велотренажёр',
        'rs': [
            'Отрегулируйте высоту сиденья так, чтобы в нижней точке педали колено оставалось слегка согнутым.',
            'Сядьте, положив руки на руль; спина прямая, подушечки стоп — над осями педалей. Это исходное положение.',
            'Крутите педали плавно на комфортном сопротивлении пять минут, чтобы разогреться.',
            'Поднимите сопротивление до рабочего и держите темп примерно 80–90 оборотов в минуту запланированное время.',
            'За последние пять минут снизьте сопротивление и крутите педали легко, чтобы восстановиться.',
        ],
    },
    'treadmill_running': {
        't': 'Treadmill Running',
        'eq': 'treadmill', 'm': ['quads', 'hamstrings', 'glutes', 'calves'],
        'p': ['quads'], 'min': 20,
        'ru': 'Бег на беговой дорожке',
        'rs': [
            'Встаньте на беговую дорожку и выберите нужный режим в меню. На большинстве дорожек есть ручной режим или готовые программы. Обычно можно ввести возраст и вес, чтобы оценить расход калорий. Наклон полотна меняет интенсивность работы.',
            'Дорожка удобна, даёт нагрузку на сердце и сосуды и обычно бьёт по суставам меньше, чем бег по улице. Человек весом около 68 кг сожжёт более 450 калорий за 30 минут бега со скоростью примерно 13 км/ч. Держите правильную осанку и беритесь за поручни только при необходимости — например, когда сходите с дорожки или измеряете пульс.',
        ],
    },
    'stretching_bridge_pose_setu_bandhasana': {
        't': 'Bridge Pose',
        'eq': None, 'm': ['glutes', 'lower_back', 'hamstrings'],
        'p': ['glutes'], 'stretch': True,
        'en': [
            'Lie on your back with the knees bent, the feet flat on the floor hip width apart and the heels close to your glutes.',
            'Rest the arms alongside the body with the palms down and press the shoulders gently into the mat. This is the starting position.',
            'Press through the heels and lift the hips until the body forms a straight line from the shoulders to the knees, keeping the chin off the chest.',
            'Hold for 20 to 30 seconds, breathing steadily, then lower the spine to the floor one vertebra at a time.',
        ],
        'ru': 'Поза моста',
        'rs': [
            'Лягте на спину, согните колени и поставьте стопы на пол на ширине таза, пятки ближе к ягодицам.',
            'Руки лежат вдоль тела ладонями вниз, плечи мягко прижаты к коврику. Это исходное положение.',
            'Оттолкнитесь пятками и поднимите таз так, чтобы тело вытянулось в прямую линию от плеч до коленей; подбородок не прижимайте к груди.',
            'Удерживайте 20–30 секунд, дыша ровно, затем опускайте позвоночник на пол позвонок за позвонком.',
        ],
    },
    'stretching_flexion_leg_sit_up': {
        't': 'Flexion Leg Sit-Up',
        'eq': None, 'm': ['core'], 'stretch': True,
        'en': [
            'Lie on your back with the knees bent and the feet flat on the floor, arms reaching along your sides.',
            'Draw the navel in toward the spine so the lower back stays in contact with the floor. This is the starting position.',
            'Curl the head, shoulders and upper back off the floor as you breathe out, reaching the hands past the knees.',
            'Lower slowly one vertebra at a time as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Скручивания с согнутыми ногами',
        'rs': [
            'Лягте на спину, согните колени и поставьте стопы на пол, руки вытяните вдоль тела.',
            'Подтяните живот к позвоночнику так, чтобы поясница оставалась прижатой к полу. Это исходное положение.',
            'На выдохе оторвите от пола голову, плечи и верх спины, вытягивая руки за колени.',
            'На вдохе медленно опуститесь на пол позвонок за позвонком и выполните рекомендованное количество повторений.',
        ],
    },
    'stretching_front_toe_touch': {
        't': 'Front Toe Touch',
        'eq': None, 'm': ['hamstrings', 'lower_back'], 'p': ['hamstrings'],
        'stretch': True,
        'en': [
            'Stand tall with the feet together and the knees straight but not locked.',
            'Let the arms hang and lengthen the spine upward. This is the starting position.',
            'Hinge forward from the hips and reach your hands toward your toes, letting the head hang heavy.',
            'Hold for 20 to 30 seconds where the hamstrings feel a steady pull, then bend the knees and roll up slowly.',
        ],
        'ru': 'Наклон к носкам стоя',
        'rs': [
            'Встаньте прямо, стопы вместе, колени выпрямлены, но не заблокированы.',
            'Руки свободно свисают, позвоночник вытянут вверх. Это исходное положение.',
            'Наклонитесь вперёд от тазобедренных суставов и тянитесь руками к носкам, позволив голове свободно свисать.',
            'Удерживайте 20–30 секунд там, где задняя поверхность бедра ощущает ровное натяжение, затем согните колени и медленно поднимитесь.',
        ],
    },
    'stretching_plyo_side_lunge_stretch': {
        't': 'Plyometric Side Lunge Stretch',
        'eq': None, 'm': ['adductors', 'quads', 'glutes'], 'p': ['adductors'],
        'd': 'intermediate', 'stretch': True,
        'en': [
            'Stand with the feet wide apart and the toes pointing forward, hands together in front of your chest.',
            'Shift your weight onto one leg, bending that knee and pushing the hips back while the other leg stays straight.',
            'Feel the stretch along the inner thigh of the straight leg and hold the bottom position for a moment.',
            'Push off the bent leg and spring across to the other side, landing softly in the mirror-image position.',
            'Keep alternating sides for the prescribed amount of repetitions.',
        ],
        'ru': 'Боковые выпады в прыжке',
        'rs': [
            'Встаньте, широко расставив стопы, носки смотрят вперёд, ладони соединены перед грудью.',
            'Перенесите вес на одну ногу, сгибая её колено и отводя таз назад; вторая нога остаётся прямой.',
            'Почувствуйте растяжение по внутренней поверхности бедра прямой ноги и задержитесь в нижней точке на мгновение.',
            'Оттолкнитесь согнутой ногой и перенеситесь на другую сторону, мягко приземлившись в зеркальное положение.',
            'Продолжайте чередовать стороны нужное количество повторений.',
        ],
    },
    'stretching_single_leg_stretch_bent_knee': {
        't': 'Single Leg Stretch - Bent Knee',
        'eq': None, 'm': ['core', 'glutes'], 'p': ['core'], 'stretch': True,
        'en': [
            'Lie on your back, curl the head and shoulders off the mat and draw one knee in toward your chest.',
            'Hold the bent knee with both hands and extend the other leg out at about 45 degrees, keeping the lower back pressed down. This is the starting position.',
            'Switch legs in a controlled scissor, drawing the other knee in and extending the first leg out as you breathe out.',
            'Keep alternating for the prescribed amount of repetitions, then lower the head and both feet to the mat.',
        ],
        'ru': 'Поочерёдное подтягивание колена лёжа',
        'rs': [
            'Лягте на спину, оторвите голову и плечи от коврика и подтяните одно колено к груди.',
            'Обхватите согнутое колено обеими руками, вторую ногу вытяните вперёд под углом около 45 градусов, прижимая поясницу к полу. Это исходное положение.',
            'Подконтрольно смените ноги «ножницами»: на выдохе подтяните другое колено и вытяните первую ногу.',
            'Продолжайте чередовать ноги нужное количество повторений, затем опустите голову и обе стопы на коврик.',
        ],
    },
    'stretching_single_straight_leg_stretch': {
        't': 'Single Straight Leg Stretch',
        'eq': None, 'm': ['core', 'hamstrings'], 'p': ['core'], 'stretch': True,
        'en': [
            'Lie on your back with the head and shoulders curled off the mat and both legs straight, one raised toward the ceiling.',
            'Hold the raised leg behind the calf or thigh, keeping both knees straight and the lower back pressed into the mat. This is the starting position.',
            'Pulse the raised leg gently toward you twice, then scissor the legs and repeat with the other leg.',
            'Keep the movement flowing for the prescribed amount of repetitions, then lower both legs under control.',
        ],
        'ru': 'Поочерёдное подтягивание прямой ноги лёжа',
        'rs': [
            'Лягте на спину, оторвав голову и плечи от коврика; обе ноги прямые, одна поднята к потолку.',
            'Придерживайте поднятую ногу за голень или бедро, не сгибая колени и прижимая поясницу к коврику. Это исходное положение.',
            'Дважды мягко потяните поднятую ногу к себе, затем смените ноги «ножницами» и повторите с другой ногой.',
            'Сохраняйте непрерывность движения нужное количество повторений, затем подконтрольно опустите обе ноги.',
        ],
    },
}
