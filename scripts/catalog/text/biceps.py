# -*- coding: utf-8 -*-
"""Biceps. 21 rows: 11 merge into the existing catalog, 10 authored here.

Three upstream matches are replaced. `barbell_prone_incline_curl` matched a
text that opens "Grab a dumbbell on each hand"; `dumbbell_seated_preacher_curl`
matched a plain seated dumbbell curl with no preacher pad in it; and
`cable_standing_inner_curl` matched a shoulder-width curl, which is exactly the
grip the "inner" qualifier is not.
"""
ENTRIES = {
    'barbell_prone_incline_curl': {
        't': 'Barbell Prone Incline Curl',
        'eq': 'barbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Set an incline bench and lie face down on it with your chest against the pad and your shoulders near the top edge.',
            'Take a barbell with an underhand grip at shoulder width and let your arms hang straight down, perpendicular to the floor. This is the starting position.',
            'Keeping the upper arms still, curl the bar up toward your shoulders as you breathe out, and squeeze the biceps for a second at the top.',
            'Lower the bar slowly until the arms are fully extended again as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Сгибания рук со штангой лёжа на наклонной скамье',
        'rs': [
            'Выставьте наклонную скамью и лягте на неё грудью вниз так, чтобы плечи находились у её верхнего края.',
            'Возьмите штангу обратным хватом на ширине плеч и позвольте рукам свободно свисать перпендикулярно полу. Это исходное положение.',
            'Не двигая плечами, на выдохе согните руки, поднимая штангу к плечам, и задержитесь в сокращении на секунду.',
            'На вдохе медленно опустите штангу до полного выпрямления рук и выполните рекомендованное количество повторений.',
        ],
    },
    'cable_one_arm_curl': {
        't': 'Cable One-Arm Curl',
        'eq': 'cable_machine', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'ru': 'Сгибание одной руки на нижнем блоке',
        'rs': [
            'Возьмитесь за одиночную рукоять у нижнего блока. Отойдите достаточно далеко, чтобы вес удерживался рукой.',
            'Плечо неподвижно и перпендикулярно полу, локоть прижат, ладонь смотрит вперёд. Свободной рукой возьмитесь за пояс — так проще держать равновесие.',
            'На выдохе медленно сгибайте руку, не двигая плечом, пока предплечье не коснётся бицепса. Подсказка: двигаться должно только предплечье.',
            'Задержитесь в сокращении, напрягая бицепс, затем на вдохе опустите рукоять в исходное положение.',
            'Выполните рекомендованное количество повторений.',
            'Повторите то же самое другой рукой.',
        ],
    },
    'cable_standing_inner_curl': {
        't': 'Standing Cable Inner Biceps Curl',
        'eq': 'cable_machine', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Attach a straight bar to a low pulley and stand upright holding it with an underhand grip, hands set wider than your shoulders.',
            'Keep the elbows tucked against your sides and the wrists straight, with the bar resting against your thighs. This is the starting position.',
            'Curl the bar up to shoulder height as you breathe out, moving only the forearms, and squeeze for a second — the wide grip biases the inner head of the biceps.',
            'Lower the bar slowly back to full extension as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Сгибания рук на нижнем блоке широким хватом',
        'rs': [
            'Закрепите прямую рукоять на нижнем блоке и встаньте прямо, взявшись за неё обратным хватом шире плеч.',
            'Локти прижаты к бокам, запястья прямые, рукоять касается бёдер. Это исходное положение.',
            'На выдохе согните руки, подняв рукоять до уровня плеч; двигаются только предплечья. Задержитесь на секунду — широкий хват сильнее нагружает внутреннюю (короткую) головку бицепса.',
            'На вдохе медленно опустите рукоять до полного выпрямления рук и выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_concentration_curl': {
        't': 'Dumbbell Concentration Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'ru': 'Концентрированное сгибание руки с гантелью',
        'rs': [
            'Сядьте на горизонтальную скамью, поставив одну гантель перед собой между ног. Ноги разведены, колени согнуты, стопы на полу.',
            'Возьмите гантель правой рукой. Упритесь задней частью правого плеча во внутреннюю поверхность правого бедра. Разверните ладонь вперёд, от бедра. Подсказка: рука выпрямлена, гантель не касается пола. Это исходное положение.',
            'Удерживая плечо неподвижным, на выдохе согните руку, напрягая бицепс. Двигается только предплечье. Поднимайте гантель, пока бицепс полностью не сократится и гантель не окажется на уровне плеча. Подсказка: в верхней точке мизинец должен быть выше большого пальца — это обеспечивает хорошее сокращение. Задержитесь на секунду.',
            'На вдохе медленно верните гантель в исходное положение. Внимание: не допускайте раскачивания.',
            'Выполните рекомендованное количество повторений, затем повторите то же самое левой рукой.',
        ],
    },
    'dumbbell_cross_body_hammer_curl': {
        't': 'Dumbbell Cross-Body Hammer Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'ru': 'Сгибание руки с гантелью поперёк корпуса',
        'rs': [
            'Встаньте прямо, держа по гантели в каждой руке. Руки опущены вдоль тела, ладони обращены внутрь.',
            'Сохраняя нейтральное положение ладоней и не разворачивая руку, на выдохе поднимите гантель правой руки к левому плечу. Коснитесь плеча верхним концом гантели и задержитесь в сокращении на секунду.',
            'На вдохе медленно опустите гантель по той же траектории, затем выполните то же движение левой рукой.',
            'Продолжайте чередовать руки, пока не выполните рекомендованное количество повторений на каждую.',
        ],
    },
    'dumbbell_preacher_curl_over_exercise_ball': {
        't': 'Dumbbell Preacher Curl Over an Exercise Ball',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Kneel behind a stability ball and drape the backs of your upper arms over the top of it, holding a dumbbell in each hand with the palms facing up.',
            'Let the arms straighten so the dumbbells hang below the ball and your armpits rest against its top. This is the starting position.',
            'Curl the dumbbells up toward your shoulders as you breathe out, keeping the upper arms pinned to the ball, and squeeze for a second at the top.',
            'Lower the dumbbells slowly until the elbows are almost straight as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Сгибания рук с гантелями через гимнастический мяч',
        'rs': [
            'Встаньте на колени за гимнастическим мячом и положите на него заднюю поверхность плеч, удерживая по гантели в каждой руке ладонями вверх.',
            'Выпрямите руки так, чтобы гантели свисали ниже мяча, а подмышки лежали на его верхушке. Это исходное положение.',
            'На выдохе согните руки, поднимая гантели к плечам; плечи остаются прижатыми к мячу. Задержитесь в верхней точке на секунду.',
            'На вдохе медленно опустите гантели почти до полного выпрямления локтей и выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_seated_preacher_curl': {
        't': 'Dumbbell Seated Preacher Curl',
        'eq': 'preacher_curl_bench', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Sit at a preacher bench with a dumbbell in one hand and lay the back of that upper arm flat on the pad, armpit against the top edge.',
            'Extend the arm until the elbow is almost straight, palm facing up. This is the starting position.',
            'Curl the dumbbell up toward your shoulder as you breathe out without letting the upper arm lift off the pad, and squeeze for a second at the top.',
            'Lower the dumbbell slowly back to the stretched position as you breathe in, repeat for the prescribed amount of repetitions, then change arms.',
        ],
        'ru': 'Сгибание руки с гантелью на парте Скотта',
        'rs': [
            'Сядьте за парту Скотта, возьмите гантель в одну руку и положите заднюю поверхность плеча на наклонный упор, подмышка — у его верхнего края.',
            'Выпрямите руку почти до конца, ладонь смотрит вверх. Это исходное положение.',
            'На выдохе согните руку, поднимая гантель к плечу и не отрывая плечо от упора; задержитесь в верхней точке на секунду.',
            'На вдохе медленно опустите гантель в растянутое положение, выполните рекомендованное количество повторений и смените руку.',
        ],
    },
    'ez_barbell_biceps_curl': {
        't': 'EZ-Bar Biceps Curl',
        'eq': 'ez_curl_bar', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Stand upright holding an EZ curl bar on the angled inner grips with your palms facing up and your elbows tucked against your sides.',
            'Let the bar hang at arm\'s length in front of your thighs, shoulders back and chest up. This is the starting position.',
            'Curl the bar up to shoulder height as you breathe out, keeping the upper arms still so only the forearms move, and squeeze the biceps for a second.',
            'Lower the bar slowly back to full extension as you breathe in, and repeat for the prescribed amount of repetitions.',
        ],
        'ru': 'Сгибания рук с изогнутым грифом',
        'rs': [
            'Встаньте прямо, взявшись за изогнутый гриф за внутренние наклонные участки ладонями вверх; локти прижаты к бокам.',
            'Гриф висит на прямых руках перед бёдрами, плечи расправлены, грудь развёрнута. Это исходное положение.',
            'На выдохе поднимите гриф до уровня плеч, удерживая плечи неподвижными, чтобы двигались только предплечья, и задержитесь в сокращении на секунду.',
            'На вдохе медленно опустите гриф до полного выпрямления рук и выполните рекомендованное количество повторений.',
        ],
    },
    'lying_supine_dumbbell_curl': {
        't': 'Lying Supine Dumbbell Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'ru': 'Сгибания рук с гантелями лёжа на спине',
        'rs': [
            'Лягте на горизонтальную скамью лицом вверх, удерживая по гантели в каждой руке на бёдрах.',
            'Опустите гантели по сторонам скамьи, руки выпрямлены, ладони обращены к бёдрам (нейтральный хват).',
            'Прижимая руки к корпусу и не разводя локти, медленно опустите почти прямые руки как можно ниже к полу. Достигнув предела, зафиксируйте плечи в этом положении — это исходное положение.',
            'На выдохе медленно поднимайте гантели, одновременно разворачивая кисти ладонями вверх. Продолжайте до полного сокращения бицепсов и на секунду сильно напрягите их в верхней точке. Подсказка: двигаются только предплечья, плечи остаются неподвижными, а локти — прижатыми.',
            'Очень медленно вернитесь в исходное положение.',
        ],
    },
    'stretching_butterfly_yoga_pose': {
        't': 'Butterfly Yoga Pose',
        'eq': None, 'm': ['adductors'], 'stretch': True,
        'en': [
            'Sit tall on the floor, bend both knees and bring the soles of your feet together in front of you, drawing the heels toward your groin.',
            'Hold your feet with both hands and lengthen your spine so you are sitting on top of your sitting bones. This is the starting position.',
            'Let both knees fall toward the floor and breathe steadily, allowing the inner thighs to release rather than pressing the knees down.',
            'Hold for 20 to 30 seconds, then bring the knees back together and release.',
        ],
        'ru': 'Поза бабочки',
        'rs': [
            'Сядьте на пол с прямой спиной, согните колени и соедините стопы подошвами друг к другу, подтянув пятки ближе к паху.',
            'Возьмитесь руками за стопы и вытяните позвоночник вверх, опираясь на седалищные кости. Это исходное положение.',
            'Позвольте коленям опуститься к полу и дышите ровно, расслабляя внутреннюю поверхность бёдер, а не продавливая их вниз.',
            'Удерживайте положение 20–30 секунд, затем сведите колени и выйдите из позы.',
        ],
    },
    'barbell_drag_curl': {
        't': 'Barbell Drag Curl',
        'eq': 'barbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Stand upright holding a barbell with an underhand grip at shoulder width, the bar resting against your thighs.',
            'Set the chest up and the elbows at your sides. This is the starting position.',
            'Curl the bar up while dragging it along your body, letting the elbows travel back behind you so the bar stays in contact with the torso.',
            'Stop when the bar reaches the lower chest, hold for a second, then lower it back down the same path as you breathe in.',
            'Repeat for the prescribed amount of repetitions; the drag keeps the front shoulders out of the lift, so use less weight than a standard curl.',
        ],
        'ru': 'Протяжка штанги вдоль корпуса на бицепс',
        'rs': [
            'Встаньте прямо, удерживая штангу обратным хватом на ширине плеч; гриф касается бёдер.',
            'Грудь развёрнута, локти прижаты к бокам. Это исходное положение.',
            'Поднимайте гриф, ведя его вплотную вдоль тела и отводя локти назад, чтобы гриф не отрывался от корпуса.',
            'Остановитесь, когда гриф дойдёт до низа груди, задержитесь на секунду и на вдохе опустите его по той же траектории.',
            'Выполните рекомендованное количество повторений: такая траектория выключает передние дельты, поэтому вес берите меньше, чем в обычных сгибаниях.',
        ],
    },
    'dumbbell_alternate_seated_biceps_curl': {
        't': 'Dumbbell Seated Alternating Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Sit on the end of a bench with the feet flat on the floor and a dumbbell hanging at arm\'s length in each hand, palms facing your thighs.',
            'Sit tall with the elbows close to your sides. This is the starting position.',
            'Curl one dumbbell up, rotating the palm to face your shoulder as it rises, and squeeze the biceps for a second at the top as you breathe out.',
            'Lower it slowly back to your thigh as you breathe in, rotating the palm back in, then repeat with the other arm.',
            'Keep alternating until you have completed the prescribed amount of repetitions with each arm; sitting stops the hips from helping the weight up.',
        ],
        'ru': 'Попеременные сгибания рук с гантелями сидя',
        'rs': [
            'Сядьте на край скамьи, поставив стопы на пол; гантели висят на прямых руках, ладони обращены к бёдрам.',
            'Сядьте ровно, локти прижаты к бокам. Это исходное положение.',
            'На выдохе поднимите одну гантель, разворачивая ладонь к плечу по ходу движения, и задержитесь в сокращении на секунду.',
            'На вдохе медленно опустите её к бедру, возвращая ладонь внутрь, затем повторите другой рукой.',
            'Чередуйте руки, пока не выполните рекомендованное количество повторений каждой: положение сидя не даёт помогать себе тазом.',
        ],
    },
    'dumbbell_biceps_curl': {
        't': 'Dumbbell Biceps Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'ru': 'Сгибания рук с гантелями стоя',
        'rs': [
            'Встаньте прямо, удерживая по гантели в каждой руке на прямых руках. Локти прижаты к корпусу, ладони развёрнуты вперёд. Это исходное положение.',
            'Не двигая плечами, на выдохе согните руки, напрягая бицепсы. Поднимайте гантели, пока бицепсы полностью не сократятся, а гантели не окажутся на уровне плеч. Задержитесь в верхней точке, сильно напрягая бицепсы.',
            'На вдохе медленно опустите гантели в исходное положение.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
    'dumbbell_incline_biceps_curl': {
        't': 'Dumbbell Incline Biceps Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Set a bench to about 45 degrees and sit back against it with a dumbbell in each hand, arms hanging straight down behind the line of your body.',
            'Turn the palms to face forward and let the shoulders settle back into the pad. This is the starting position.',
            'Curl both dumbbells up toward your shoulders as you breathe out, keeping the upper arms hanging still so only the forearms move.',
            'Lower them slowly all the way back to a full stretch as you breathe in.',
            'Repeat for the prescribed amount of repetitions; the incline holds the arms behind you, which stretches the long head of the biceps.',
        ],
        'ru': 'Сгибания рук с гантелями на наклонной скамье',
        'rs': [
            'Установите скамью под углом около 45 градусов и сядьте на неё с гантелями в руках; руки свободно свисают за линией корпуса.',
            'Разверните ладони вперёд и прижмите плечи к спинке. Это исходное положение.',
            'На выдохе согните обе руки, поднимая гантели к плечам; плечи остаются висеть неподвижно, двигаются только предплечья.',
            'На вдохе медленно опустите гантели до полного растяжения.',
            'Выполните рекомендованное количество повторений: наклон удерживает руки за корпусом и растягивает длинную головку бицепса.',
        ],
    },
    'dumbbell_incline_hammer_curl': {
        't': 'Dumbbell Incline Hammer Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'en': [
            'Set a bench to about 45 degrees and sit back against it with a dumbbell in each hand, arms hanging straight down.',
            'Turn the palms to face each other and keep them that way for the whole set. This is the starting position.',
            'Curl both dumbbells up toward your shoulders as you breathe out without rotating the wrists, so the thumbs stay on top.',
            'Lower them slowly back to a full stretch as you breathe in.',
            'Repeat for the prescribed amount of repetitions; the neutral grip shifts work onto the brachialis and the forearms.',
        ],
        'ru': 'Молотковые сгибания с гантелями на наклонной скамье',
        'rs': [
            'Установите скамью под углом около 45 градусов и сядьте на неё с гантелями в руках; руки свободно свисают вниз.',
            'Разверните ладони друг к другу и сохраняйте это положение весь подход. Это исходное положение.',
            'На выдохе согните обе руки, поднимая гантели к плечам и не разворачивая кисти: большие пальцы всё время сверху.',
            'На вдохе медленно опустите гантели до полного растяжения.',
            'Выполните рекомендованное количество повторений: нейтральный хват переносит нагрузку на плечевую мышцу и предплечья.',
        ],
    },
    'dumbbell_prone_incline_curl': {
        't': 'Dumbbell Prone Incline Curl',
        'eq': 'dumbbell', 'm': ['biceps', 'forearms'], 'p': ['biceps'],
        'ru': 'Сгибания рук с гантелями лёжа грудью на наклонной скамье',
        'rs': [
            'Возьмите по гантели в каждую руку и лягте грудью вниз на наклонную скамью так, чтобы плечи находились у её верхнего края. Колени можно поставить на сиденье или развести ноги по сторонам скамьи.',
            'Позвольте рукам свободно свисать перед собой перпендикулярно полу.',
            'Прижмите локти к бокам и разверните ладони вперёд. Это исходное положение.',
            'Поднимите гантели, сгибая руки до полного сокращения бицепсов. На этом движении делайте выдох и следите, чтобы двигались только предплечья: плечи всё время остаются неподвижными.',
            'Опускайте гантели, пока руки полностью не выпрямятся.',
            'Выполните рекомендованное количество повторений.',
        ],
    },
}
