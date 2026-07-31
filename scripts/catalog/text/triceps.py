# -*- coding: utf-8 -*-
"""Triceps. 28 rows: 7 merge into the existing catalog, 21 authored here.

Six upstream matches are replaced rather than translated, because the matched
text describes a different setup from the one the title names:

  band_overhead_triceps_extension     matched a SLED extension
  band_triceps_pushdown               matched a CABLE pushdown
  cable_pushdown_rope_attachment      matched a lying lat pullover
  cable_rope_high_pulley_...          matched the LOW-pulley version, which the
                                      row next to it already carries
  dumbbell_lying_alternate_extension  matched a both-arms-together extension
  stretching_kneeling_triceps_ext.    matched a cable exercise, not a stretch
"""
ENTRIES = {
    'band_overhead_triceps_extension': {
        't': 'Band Overhead Triceps Extension',
        'eq': 'resistance_bands', 'm': ['triceps'],
        'en': [
            'Anchor a resistance band low behind you, or stand on the middle of it, and take an end in each hand.',
            'Raise both hands above your head with the elbows pointing up and bent, palms facing each other, and step forward until the band is under tension. This is the starting position.',
            'Extend through the elbows to straighten the arms overhead as you breathe out, keeping the upper arms still so only the forearms move.',
            'Bend the elbows slowly to let the hands return behind your head as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Разгибания рук из-за головы с резиновой лентой',
        'rs': [
            'Закрепите ленту внизу за собой или встаньте на её середину и возьмите по концу в каждую руку.',
            'Поднимите обе руки над головой: локти направлены вверх и согнуты, ладони обращены друг к другу. Сделайте шаг вперёд, чтобы лента натянулась. Это исходное положение.',
            'На выдохе разогните локти, выпрямив руки над головой; плечи остаются неподвижными, двигаются только предплечья.',
            'На вдохе медленно согните локти, опуская кисти за голову, и выполните рекомендованное количество повторений.',
        ],
    },
    'band_side_triceps_pushdown': {
        't': 'Band Side Triceps Pushdown',
        'eq': 'resistance_bands', 'm': ['triceps'],
        'en': [
            'Anchor a resistance band above head height at your side and stand side-on to it, taking the free end in the near hand.',
            'Pin that elbow against your ribs with the forearm angled up toward the anchor and the palm facing down. This is the starting position.',
            'Push the hand down and across toward your hip until the arm is straight, breathing out and keeping the upper arm pinned.',
            'Let the band draw the forearm back up under control as you breathe in, and repeat for the prescribed amount of repetitions before changing sides.',
        ],
        'ru': 'Разгибание руки с лентой у бока',
        'rs': [
            'Закрепите ленту выше уровня головы сбоку от себя, встаньте к ней боком и возьмите свободный конец ближней рукой.',
            'Прижмите локоть к рёбрам, предплечье направлено вверх к точке крепления, ладонь смотрит вниз. Это исходное положение.',
            'На выдохе разогните руку, ведя кисть вниз и к бедру до полного выпрямления; плечо остаётся прижатым.',
            'На вдохе подконтрольно позвольте ленте вернуть предплечье вверх и выполните рекомендованное количество повторений, затем смените сторону.',
        ],
    },
    'band_triceps_pushdown': {
        't': 'Band Triceps Pushdown',
        'eq': 'resistance_bands', 'm': ['triceps'],
        'en': [
            'Anchor a resistance band above head height and take the free end in both hands with an overhand grip.',
            'Stand upright a step back from the anchor with the elbows tucked against your ribs and the forearms angled up. This is the starting position.',
            'Push the hands down until the arms are straight beside your thighs, breathing out and keeping the upper arms still.',
            'Let the band pull the forearms back up slowly as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Разгибания рук с лентой вниз',
        'rs': [
            'Закрепите ленту выше уровня головы и возьмитесь за свободный конец обеими руками прямым хватом.',
            'Встаньте прямо в шаге от точки крепления, локти прижаты к рёбрам, предплечья направлены вверх. Это исходное положение.',
            'На выдохе разогните руки, опустив кисти вдоль бёдер до полного выпрямления; плечи остаются неподвижными.',
            'На вдохе медленно позвольте ленте поднять предплечья и выполните рекомендованное количество повторений.',
        ],
    },
    'cable_lying_triceps_extension': {
        't': 'Cable Lying Triceps Extension',
        'eq': 'cable_machine', 'm': ['triceps'],
        'ru': 'Разгибания рук на нижнем блоке лёжа',
        'rs': [
            'Лягте на горизонтальную скамью и возьмитесь узким прямым хватом за прямую рукоять нижнего блока. Подсказка: проще всего, если рукоять подаст напарник, когда вы уже легли.',
            'Выпрямите руки и расположите рукоять над корпусом: руки и корпус образуют прямой угол. Это исходное положение.',
            'Согните локти и опустите рукоять, удерживая плечи неподвижными и не разводя локти, пока рукоять не коснётся лба. На этом движении делайте вдох.',
            'Напрягая трицепсы, верните рукоять в исходное положение. На этом движении делайте выдох.',
            'Задержитесь на секунду в сокращении и выполните рекомендованное количество повторений.',
        ],
    },
    'cable_overhead_triceps_extension_rope_attachment': {
        't': 'Cable Overhead Triceps Extension - Rope',
        'eq': 'cable_machine', 'm': ['triceps'],
        'ru': 'Разгибания рук из-за головы с канатной рукоятью',
        'rs': [
            'Закрепите канатную рукоять на нижнем блоке.',
            'Взявшись за канат обеими руками, выпрямите руки прямо над головой нейтральным хватом (ладони обращены друг к другу). Локти прижаты к голове, руки перпендикулярны полу, костяшки направлены в потолок. Это исходное положение.',
            'Медленно опустите канат за голову, удерживая плечи неподвижными. На этом движении делайте вдох и остановитесь, когда трицепсы полностью растянутся.',
            'На выдохе вернитесь в исходное положение, напрягая трицепсы.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'cable_pushdown_rope_attachment': {
        't': 'Cable Rope Pushdown',
        'eq': 'cable_machine', 'm': ['triceps'],
        'en': [
            'Attach a rope to a high pulley and take one end in each hand with a neutral grip, palms facing each other.',
            'Stand upright a short step back from the stack with the elbows tucked against your ribs and the forearms angled up. This is the starting position.',
            'Push the rope down until the arms are straight, spreading the two ends apart at the bottom as you breathe out and squeeze the triceps for a second.',
            'Let the forearms rise back to the starting position slowly as you breathe in, keeping the upper arms still, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Разгибания рук на верхнем блоке с канатной рукоятью',
        'rs': [
            'Закрепите канатную рукоять на верхнем блоке и возьмите по концу в каждую руку нейтральным хватом, ладони обращены друг к другу.',
            'Встаньте прямо в полушаге от стойки, локти прижаты к рёбрам, предплечья направлены вверх. Это исходное положение.',
            'На выдохе разогните руки вниз до полного выпрямления, разводя концы каната в стороны в нижней точке, и на секунду напрягите трицепсы.',
            'На вдохе медленно позвольте предплечьям вернуться в исходное положение, не двигая плечами, и выполните рекомендованное количество повторений.',
        ],
    },
    'cable_rope_high_pulley_overhead_triceps_extension': {
        't': 'Cable High-Pulley Overhead Rope Extension',
        'eq': 'cable_machine', 'm': ['triceps'],
        'en': [
            'Attach a rope to a high pulley, take an end in each hand and turn to face away from the stack.',
            'Step forward into a split stance and raise the hands overhead so the elbows point forward and the rope runs behind your head. This is the starting position.',
            'Extend the elbows to press the rope forward and up until the arms are straight, breathing out and keeping the upper arms beside your ears.',
            'Bend the elbows slowly to let the hands travel back behind your head as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Разгибания рук из-за головы на верхнем блоке',
        'rs': [
            'Закрепите канатную рукоять на верхнем блоке, возьмите по концу в каждую руку и развернитесь спиной к стойке.',
            'Сделайте шаг вперёд в разножку и поднимите кисти над головой так, чтобы локти смотрели вперёд, а канат уходил за голову. Это исходное положение.',
            'На выдохе разогните локти, выжимая канат вперёд и вверх до полного выпрямления рук; плечи остаются у висков.',
            'На вдохе медленно согните локти, отводя кисти за голову, и выполните рекомендованное количество повторений.',
        ],
    },
    'cable_standing_one_arm_triceps_extension': {
        't': 'Cable Standing One-Arm Triceps Extension',
        'eq': 'cable_machine', 'm': ['triceps'],
        'ru': 'Разгибание одной руки на верхнем блоке обратным хватом',
        'rs': [
            'Возьмитесь правой рукой за одиночную рукоять верхнего блока обратным хватом (ладонь вверх). Встаньте прямо перед стопкой отягощений.',
            'Потяните рукоять вниз так, чтобы плечо и локоть были прижаты к боку. Плечо и предплечье образуют острый угол (менее 90 градусов). Свободную руку можно держать на поясе, а одну ногу вывести вперёд, другую назад — так проще держать равновесие. Это исходное положение.',
            'Напрягая трицепс, опустите рукоять вниз вдоль тела до полного выпрямления руки. На этом движении делайте выдох. Подсказка: двигаться должно только предплечье, плечо всё время остаётся неподвижным.',
            'Сожмите трицепс и задержитесь в этом положении на секунду.',
            'Медленно верните рукоять в исходное положение.',
            'Выполните рекомендованное количество повторений, затем сделайте то же самое другой рукой.',
        ],
    },
    'cable_triceps_pushdown': {
        't': 'Cable Triceps Pushdown',
        'eq': 'cable_machine', 'm': ['triceps'],
        'ru': 'Разгибания рук на верхнем блоке',
        'rs': [
            'Закрепите прямую или изогнутую рукоять на верхнем блоке и возьмитесь за неё прямым хватом (ладони вниз) на ширине плеч.',
            'Встаньте прямо, слегка наклонив корпус вперёд; прижмите плечи к телу так, чтобы они были перпендикулярны полу, а предплечья с рукоятью направлены вверх к блоку. Это исходное положение.',
            'Усилием трицепсов опустите рукоять, пока она не коснётся передней поверхности бёдер, а руки не выпрямятся перпендикулярно полу. Плечи всё время остаются неподвижными у корпуса, двигаются только предплечья. На этом движении делайте выдох.',
            'Задержитесь на секунду в сокращении и медленно поднимите рукоять в исходное положение. На этом движении делайте вдох.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'close_grip_push_ups': {
        't': 'Close-Grip Push-Up',
        'eq': None, 'm': ['triceps', 'chest', 'shoulders'], 'p': ['triceps'],
        'en': [
            'Take a push-up position with the hands under your chest, closer than shoulder width, and the index fingers almost touching.',
            'Brace the core and the glutes so the body forms a straight line from the heels to the head. This is the starting position.',
            'Bend the elbows and lower your chest toward your hands as you breathe in, keeping the elbows brushing your ribs rather than flaring out.',
            'Press back up to straight arms as you breathe out, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Отжимания узким хватом',
        'rs': [
            'Примите упор лёжа, поставив ладони под грудью уже плеч так, чтобы указательные пальцы почти касались друг друга.',
            'Напрягите живот и ягодицы, чтобы тело вытянулось в прямую линию от пяток до головы. Это исходное положение.',
            'На вдохе согните локти и опустите грудь к ладоням, ведя локти вдоль рёбер, а не разводя их в стороны.',
            'На выдохе выжмите себя вверх до полного выпрямления рук и выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_kickback': {
        't': 'Dumbbell Kickback',
        'eq': 'dumbbell', 'm': ['triceps'],
        'ru': 'Разгибания рук с гантелями в наклоне',
        'rs': [
            'Возьмите по гантели в каждую руку ладонями к корпусу. Сохраняя прямую спину и слегка согнув колени, наклонитесь вперёд в тазобедренных суставах почти до параллели корпуса с полом. Голову держите поднятой. Плечи прижаты к корпусу и параллельны полу, предплечья с гантелями направлены вниз, между предплечьем и плечом — прямой угол. Это исходное положение.',
            'Удерживая плечи неподвижными, на выдохе усилием трицепсов разогните руки до полного выпрямления. Следите за тем, чтобы двигались только предплечья.',
            'После короткой паузы в верхней точке на вдохе медленно опустите гантели в исходное положение.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_lying_alternate_extension': {
        't': 'Dumbbell Lying Alternating Triceps Extension',
        'eq': 'dumbbell', 'm': ['triceps'],
        'en': [
            'Lie on a flat bench holding a dumbbell in each hand directly above your shoulders, arms straight and palms facing each other.',
            'Tuck the elbows in so the upper arms stay vertical for the whole set. This is the starting position.',
            'Keeping one arm locked out, bend the other elbow and lower that dumbbell toward your ear as you breathe in.',
            'Extend it back to straight as you breathe out, then repeat with the other arm.',
            'Keep alternating until you have completed the prescribed amount of repetitions with each arm.',
        ],
        'ru': 'Поочерёдные разгибания рук с гантелями лёжа',
        'rs': [
            'Лягте на горизонтальную скамью, удерживая по гантели в каждой руке прямо над плечами: руки выпрямлены, ладони обращены друг к другу.',
            'Прижмите локти внутрь так, чтобы плечи оставались вертикальными весь подход. Это исходное положение.',
            'Оставив одну руку выпрямленной, на вдохе согните другой локоть и опустите гантель к уху.',
            'На выдохе разогните руку обратно, затем повторите движение другой рукой.',
            'Чередуйте руки, пока не выполните рекомендованное количество повторений каждой.',
        ],
    },
    'dumbbell_one_arm_triceps_extension': {
        't': 'Dumbbell One-Arm Triceps Extension',
        'eq': 'dumbbell', 'm': ['triceps'],
        'ru': 'Разгибание одной руки с гантелью из-за головы',
        'rs': [
            'Возьмите гантель и либо сядьте на скамью со спинкой, положив гантель на бедро, либо встаньте прямо.',
            'Поднимите гантель к плечу, а затем выпрямите руку над головой так, чтобы вся рука была перпендикулярна полу и находилась рядом с головой. Гантель — точно над вами. Свободную руку можно опустить на пояс, поддержать ею рабочее плечо или взяться за неподвижную опору.',
            'Разверните кисть так, чтобы ладонь смотрела вперёд, а мизинец — в потолок. Это исходное положение.',
            'Медленно опустите гантель за голову, удерживая плечо неподвижным. На этом движении делайте вдох и остановитесь, когда трицепс полностью растянется.',
            'На выдохе вернитесь в исходное положение, напрягая трицепс. Подсказка: принципиально, чтобы двигалось только предплечье — плечо всё время остаётся неподвижным у головы.',
            'Выполните рекомендованное количество повторений и смените руку.',
        ],
    },
    'dumbbell_pronate_grip_triceps_extension': {
        't': 'Dumbbell Pronated-Grip Triceps Extension',
        'eq': 'dumbbell', 'm': ['triceps'],
        'ru': 'Разгибания рук с гантелями прямым хватом лёжа',
        'rs': [
            'Лягте на горизонтальную скамью, удерживая две гантели прямо над плечами. Руки полностью выпрямлены и образуют прямой угол с корпусом и полом.',
            'Ладони обращены вперёд, локти прижаты внутрь. Это исходное положение.',
            'На вдохе медленно опустите гантели к ушам. Плечи держите неподвижными, а локти — прижатыми.',
            'На выдохе усилием трицепсов верните вес в исходное положение.',
        ],
    },
    'dumbbell_seated_kickback': {
        't': 'Dumbbell Seated Kickback',
        'eq': 'dumbbell', 'm': ['triceps'],
        'en': [
            'Sit on the end of a bench with a dumbbell in each hand and hinge forward from the hips until your chest is close to your thighs.',
            'Draw the upper arms back so they run alongside your ribs and parallel to the floor, elbows bent to a right angle. This is the starting position.',
            'Extend both elbows until the arms are straight behind you as you breathe out, and squeeze the triceps for a second.',
            'Bend the elbows slowly back to the right angle as you breathe in, keeping the upper arms still, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Разгибания рук с гантелями сидя в наклоне',
        'rs': [
            'Сядьте на край скамьи с гантелями в руках и наклонитесь вперёд от тазобедренных суставов, пока грудь не окажется близко к бёдрам.',
            'Отведите плечи назад так, чтобы они шли вдоль рёбер параллельно полу, а локти были согнуты под прямым углом. Это исходное положение.',
            'На выдохе разогните оба локтя до полного выпрямления рук назад и на секунду напрягите трицепсы.',
            'На вдохе медленно согните локти обратно до прямого угла, не двигая плечами, и выполните рекомендованное количество повторений.',
        ],
    },
    'ez_barbell_lying_triceps_extension': {
        't': 'EZ-Bar Lying Triceps Extension',
        'eq': 'ez_curl_bar', 'm': ['triceps'],
        'en': [
            'Lie on a flat bench holding an EZ curl bar on the inner grips with an overhand grip, arms straight above your shoulders.',
            'Tuck the elbows in so the upper arms stay vertical. This is the starting position.',
            'Bend the elbows to lower the bar toward your forehead as you breathe in, keeping the upper arms still.',
            'Press the bar back up to straight arms with the triceps as you breathe out, and hold the top for a second.',
            'Repeat for the prescribed amount of repetitions, and have a spotter take the bar if the elbows start to drift outward.',
        ],
        'ru': 'Французский жим лёжа с изогнутым грифом',
        'rs': [
            'Лягте на горизонтальную скамью, взявшись за внутренние участки изогнутого грифа прямым хватом; руки выпрямлены над плечами.',
            'Прижмите локти внутрь так, чтобы плечи оставались вертикальными. Это исходное положение.',
            'На вдохе согните локти и опустите гриф ко лбу, удерживая плечи неподвижными.',
            'На выдохе усилием трицепсов выжмите гриф вверх до прямых рук и задержитесь на секунду.',
            'Выполните рекомендованное количество повторений; если локти начинают разъезжаться, попросите напарника принять гриф.',
        ],
    },
    'lever_seated_dips': {
        't': 'Machine Seated Dip',
        'eq': 'tricep_extension_machine', 'm': ['triceps', 'chest'],
        'p': ['triceps'],
        'en': [
            'Set the seat height so the handles sit level with the sides of your chest, then sit down with your back against the pad.',
            'Take a handle in each hand with a neutral grip, elbows bent and tucked against your ribs. This is the starting position.',
            'Press the handles down until the arms are straight beside your hips as you breathe out, and hold for a second.',
            'Let the handles rise back slowly to chest height as you breathe in, keeping the shoulders down and the back on the pad, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Отжимания в тренажёре сидя',
        'rs': [
            'Отрегулируйте высоту сиденья так, чтобы рукояти оказались на уровне боков грудной клетки, и сядьте, прижав спину к спинке.',
            'Возьмитесь за рукояти нейтральным хватом; локти согнуты и прижаты к рёбрам. Это исходное положение.',
            'На выдохе выжмите рукояти вниз до полного выпрямления рук вдоль бёдер и задержитесь на секунду.',
            'На вдохе медленно позвольте рукоятям вернуться на уровень груди, не поднимая плечи и не отрывая спину от спинки, и выполните рекомендованное количество повторений.',
        ],
    },
    'lever_triceps_extension_neutral_grip': {
        't': 'Machine Triceps Extension - Neutral Grip',
        'eq': 'tricep_extension_machine', 'm': ['triceps'],
        'en': [
            'Set the seat so your elbows rest on the pad level with your shoulders, and sit with your chest against the support.',
            'Take the parallel handles so your palms face each other and bend the elbows to bring the hands toward your head. This is the starting position.',
            'Extend the elbows until the arms are straight as you breathe out; the neutral grip keeps the wrists in line with the forearms.',
            'Bend the elbows slowly back to the stretched position as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Разгибания рук в тренажёре нейтральным хватом',
        'rs': [
            'Отрегулируйте сиденье так, чтобы локти лежали на упоре на уровне плеч, и сядьте, прижав грудь к опоре.',
            'Возьмитесь за параллельные рукояти ладонями друг к другу и согните локти, приблизив кисти к голове. Это исходное положение.',
            'На выдохе разогните локти до полного выпрямления рук; нейтральный хват удерживает запястья на одной линии с предплечьями.',
            'На вдохе медленно согните локти обратно в растянутое положение и выполните рекомендованное количество повторений.',
        ],
    },
    'stretching_kneeling_triceps_extension': {
        't': 'Kneeling Triceps Stretch',
        'eq': None, 'm': ['triceps', 'shoulders'], 'p': ['triceps'],
        'stretch': True,
        'en': [
            'Kneel on a mat and sit back onto your heels with the spine tall and the shoulders relaxed.',
            'Raise one arm overhead and bend the elbow so that hand drops down between your shoulder blades. This is the starting position.',
            'Take the raised elbow with the other hand and draw it gently back and toward the midline until the triceps stretches.',
            'Hold for 20 to 30 seconds without forcing the shoulder, then release and change arms.',
        ],
        'ru': 'Растяжка трицепса стоя на коленях',
        'rs': [
            'Встаньте на колени на коврик и сядьте на пятки, вытянув позвоночник вверх и расслабив плечи.',
            'Поднимите одну руку над головой и согните локоть так, чтобы кисть опустилась между лопаток. Это исходное положение.',
            'Возьмитесь другой рукой за поднятый локоть и мягко потяните его назад и к средней линии, пока трицепс не растянется.',
            'Удерживайте 20–30 секунд, не продавливая плечевой сустав, затем отпустите и смените руку.',
        ],
    },
    'stretching_reverse_dip': {
        't': 'Reverse Dip Stretch',
        'eq': 'adjustable_bench', 'm': ['triceps', 'chest', 'shoulders'],
        'p': ['triceps'], 'stretch': True,
        'en': [
            'Sit on the edge of a bench and place your hands on the edge either side of your hips, fingers pointing forward.',
            'Walk the feet out and slide your hips off the bench so your weight rests on your hands and heels. This is the starting position.',
            'Lower your hips slowly toward the floor until you feel a stretch across the front of the shoulders and the triceps.',
            'Hold for 15 to 20 seconds, breathing steadily, then press back up and sit down to release.',
        ],
        'ru': 'Растяжка трицепса и плеч в обратном упоре',
        'rs': [
            'Сядьте на край скамьи и поставьте ладони на край по сторонам от таза, пальцы направлены вперёд.',
            'Отшагните стопами вперёд и сместите таз со скамьи так, чтобы вес пришёлся на ладони и пятки. Это исходное положение.',
            'Медленно опускайте таз к полу, пока не почувствуете растяжение по передней поверхности плеч и в трицепсах.',
            'Удерживайте 15–20 секунд, дыша ровно, затем выжмите себя вверх и сядьте обратно.',
        ],
    },
    'dumbbell_lying_triceps_extension': {
        't': 'Dumbbell Lying Triceps Extension',
        'eq': 'dumbbell', 'm': ['triceps'],
        'ru': 'Разгибания рук с гантелями лёжа',
        'rs': [
            'Лягте на горизонтальную скамью, удерживая две гантели прямо над собой. Руки полностью выпрямлены и образуют прямой угол с корпусом и полом, ладони обращены внутрь, локти прижаты. Это исходное положение.',
            'На вдохе, удерживая плечи неподвижными и не разводя локти, медленно опустите вес, пока гантели не окажутся возле ушей.',
            'Из этого положения, по-прежнему не разводя локти и не двигая плечами, на выдохе усилием трицепсов верните вес в исходное положение.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_seated_triceps_extension': {
        't': 'Dumbbell Seated Triceps Extension',
        'eq': 'dumbbell', 'm': ['triceps'],
        'en': [
            'Sit on a bench with back support holding one dumbbell in both hands, palms pressed against the underside of the top plate.',
            'Press the dumbbell straight overhead until the arms are locked out, elbows close to your ears. This is the starting position.',
            'Bend the elbows to lower the dumbbell behind your head as you breathe in, keeping the upper arms vertical and still.',
            'Press it back overhead with the triceps as you breathe out, and hold the top for a second.',
            'Repeat for the prescribed amount of repetitions, keeping the lower back against the pad throughout.',
        ],
        'ru': 'Французский жим с гантелью сидя',
        'rs': [
            'Сядьте на скамью со спинкой, удерживая одну гантель обеими руками: ладони упираются во внутреннюю сторону верхнего диска.',
            'Выжмите гантель прямо над головой до полного выпрямления рук, локти близко к вискам. Это исходное положение.',
            'На вдохе согните локти и опустите гантель за голову, удерживая плечи вертикально и неподвижно.',
            'На выдохе усилием трицепсов выжмите гантель обратно вверх и задержитесь в верхней точке на секунду.',
            'Выполните рекомендованное количество повторений, всё время прижимая поясницу к спинке.',
        ],
    },
}
