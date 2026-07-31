# -*- coding: utf-8 -*-
"""Localise the onboarding flow: 97 English strings across ten files.

Every one of them is a label, a chip or a placeholder on the first screen a new
user sees, in an app whose interface language is Russian. The Russian below is
authored, not generated -- "Sedentary" is not "Сидячий", it is "Малоподвижный",
and "Prefer not to say" is a phrase, not four words.

The three shapes this rewrites, all of which the l10n extractor's patterns miss:

    const FieldLabel('Age')          positional argument to a custom widget
    hint: 'e.g. asthma, diabetes'    a named parameter it does not list
    Gender.female => 'Female'        a switch arm inside a label function

`const` has to go from the FieldLabel sites: a localized string is a method
call, and a const constructor cannot hold one.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path('D:/test 2/Fitness App/mobile')
ONB = ROOT / 'lib' / 'features' / 'onboarding'
ARB_EN = ROOT / 'lib' / 'l10n' / 'app_en.arb'
ARB_RU = ROOT / 'lib' / 'l10n' / 'app_ru.arb'

# english -> (arb key, russian)
T = {
    # --- step titles, shown in the app bar as "Step 3 of 7 - Goals"
    'Personal':        ('onbStepPersonal', 'О себе'),
    'Health':          ('onbStepHealth', 'Здоровье'),
    'Goals':           ('onbStepGoals', 'Цели'),
    'Fitness level':   ('onbStepLevel', 'Уровень подготовки'),
    'Lifestyle':       ('onbStepLifestyle', 'Образ жизни'),
    'Equipment':       ('onbStepEquipment', 'Оборудование'),
    'Motivation':      ('onbStepMotivation', 'Мотивация'),

    # --- personal
    'Age':                          ('onbAge', 'Возраст'),
    'Gender':                       ('onbGender', 'Пол'),
    'Female':                       ('onbGenderFemale', 'Женский'),
    'Male':                         ('onbGenderMale', 'Мужской'),
    'Non-binary':                   ('onbGenderNonBinary', 'Небинарный'),
    'Prefer not to say':            ('onbGenderPreferNotToSay', 'Предпочитаю не отвечать'),
    'Height (cm)':                  ('onbHeightCm', 'Рост, см'),
    'Current weight (kg)':          ('onbWeightCurrent', 'Текущий вес, кг'),
    'Target weight (kg, optional)': ('onbWeightTarget', 'Желаемый вес, кг (необязательно)'),
    'Activity level':               ('onbActivityLevel', 'Уровень активности'),
    'Sedentary':                    ('onbActivitySedentary', 'Малоподвижный'),
    'Lightly active':               ('onbActivityLight', 'Слегка активный'),
    'Moderately active':            ('onbActivityModerate', 'Умеренно активный'),
    'Active':                       ('onbActivityActive', 'Активный'),
    'Very active':                  ('onbActivityVery', 'Очень активный'),
    'Occupation':                   ('onbOccupation', 'Род занятий'),

    # --- health
    'Pre-existing conditions':    ('onbConditions', 'Хронические заболевания'),
    'e.g. asthma, diabetes':      ('onbConditionsHint', 'например: астма, диабет'),
    'Allergies':                  ('onbAllergies', 'Аллергии'),
    'e.g. peanuts, penicillin':   ('onbAllergiesHint', 'например: арахис, пенициллин'),
    'Current medications':        ('onbMedications', 'Принимаемые лекарства'),
    'e.g. ibuprofen, insulin':    ('onbMedicationsHint', 'например: ибупрофен, инсулин'),
    'Past or current injuries':   ('onbInjuries', 'Травмы: прошлые и текущие'),
    'knee: meniscus, lower back: strain':
        ('onbInjuriesHint', 'колено: мениск, поясница: растяжение'),
    'Physical limitations':       ('onbLimitations', 'Физические ограничения'),
    'e.g. cannot lift overhead':  ('onbLimitationsHint', 'например: не поднимаю руки над головой'),
    'Recent surgeries':           ('onbSurgeries', 'Недавние операции'),
    'e.g. ACL repair (2025)':     ('onbSurgeriesHint', 'например: пластика крестообразной связки, 2025'),
    'Blood pressure':             ('onbBloodPressure', 'Артериальное давление'),
    'Low':                        ('onbBloodPressureLow', 'Пониженное'),
    'Normal':                     ('onbBloodPressureNormal', 'Нормальное'),
    'High':                       ('onbBloodPressureHigh', 'Повышенное'),
    'Other health concerns':      ('onbOtherHealth', 'Что ещё важно знать о здоровье'),
    'Anything else we should know':
        ('onbOtherHealthHint', 'всё, что нам стоит знать'),

    # --- goals
    'Weight loss':                  ('onbGoalWeightLoss', 'Снижение веса'),
    'Muscle gain':                  ('onbGoalMuscleGain', 'Набор мышечной массы'),
    'Endurance':                    ('onbGoalEndurance', 'Выносливость'),
    'Strength':                     ('onbGoalStrength', 'Сила'),
    'Flexibility':                  ('onbGoalFlexibility', 'Гибкость'),
    'General fitness':              ('onbGoalGeneral', 'Общая форма'),
    'Specific sport (optional)':    ('onbSport', 'Конкретный вид спорта (необязательно)'),
    'e.g. tennis, climbing, marathon':
        ('onbSportHint', 'например: теннис, скалолазание, марафон'),

    # --- level
    'Sessions per week':          ('onbSessionsPerWeek', 'Тренировок в неделю'),
    'Exercises you currently do': ('onbCurrentExercises', 'Чем занимаетесь сейчас'),
    'running, yoga, weights':     ('onbCurrentExercisesHint', 'бег, йога, штанга'),
    'Self-rated level':           ('onbSelfRatedLevel', 'Как оцениваете свой уровень'),
    'Beginner':                   ('onbLevelBeginner', 'Начинающий'),
    'Intermediate':               ('onbLevelIntermediate', 'Средний'),
    'Advanced':                   ('onbLevelAdvanced', 'Продвинутый'),
    'Comfortable with push-ups, squats, planks?':
        ('onbBasicAbility', 'Уверенно делаете отжимания, приседания, планку?'),
    'Yes':                        ('onbBasicAbilityYes', 'Да'),
    'Some':                       ('onbBasicAbilityPartial', 'Отчасти'),
    'Not yet':                    ('onbBasicAbilityNo', 'Пока нет'),

    # --- lifestyle
    'Dietary preferences': ('onbDiet', 'Особенности питания'),
    'Vegetarian':          ('onbDietVegetarian', 'Вегетарианское'),
    'Vegan':               ('onbDietVegan', 'Веганское'),
    'Gluten-free':         ('onbDietGlutenFree', 'Без глютена'),
    'Dairy-free':          ('onbDietDairyFree', 'Без молочного'),
    'Halal':               ('onbDietHalal', 'Халяль'),
    'Kosher':              ('onbDietKosher', 'Кошерное'),
    'No restrictions':     ('onbDietNone', 'Без ограничений'),
    'Smoking':             ('onbSmoking', 'Курение'),
    'Never':               ('onbSmokingNever', 'Не курю'),
    'Former':              ('onbSmokingFormer', 'Бросил'),
    'Occasional':          ('onbSmokingOccasional', 'Изредка'),
    'Regular':             ('onbSmokingRegular', 'Регулярно'),
    'Alcohol':             ('onbAlcohol', 'Алкоголь'),
    'None':                ('onbAlcoholNone', 'Не употребляю'),
    'Light':               ('onbAlcoholLight', 'Редко'),
    'Moderate':            ('onbAlcoholModerate', 'Умеренно'),
    'Heavy':               ('onbAlcoholHeavy', 'Часто'),
    'Sleep (hours per night)': ('onbSleepHours', 'Сон, часов за ночь'),
    'Stress level (1–10)':     ('onbStressLevel', 'Уровень стресса, 1–10'),

    # --- equipment
    'Do you have access to a gym?': ('onbGymAccess', 'Есть доступ в зал?'),
    'Equipment at home':            ('onbHomeEquipment', 'Оборудование дома'),
    'e.g. dumbbells, kettlebell, mat':
        ('onbHomeEquipmentHint', 'например: гантели, гиря, коврик'),

    # --- motivation
    'What motivates you most?':  ('onbMotivationPrompt', 'Что мотивирует вас больше всего?'),
    'A few words about why you train':
        ('onbMotivationHint', 'пара слов о том, зачем вы тренируетесь'),
    'Preferred environment':     ('onbEnvironment', 'Как предпочитаете заниматься'),
    'High-intensity':            ('onbEnvIntense', 'Интенсивно'),
    'Relaxed':                   ('onbEnvRelaxed', 'Спокойно'),
    'Group classes':             ('onbEnvGroup', 'В группе'),
    '1-on-1':                    ('onbEnvOneOnOne', 'С тренером один на один'),
    'Outdoor':                   ('onbEnvOutdoor', 'На улице'),
    'Preferred session length':  ('onbSessionLength', 'Длительность тренировки'),
    'Under 15 min':              ('onbSession15', 'До 15 минут'),
    '15–30 min':                 ('onbSession1530', '15–30 минут'),
    '30–45 min':                 ('onbSession3045', '30–45 минут'),
    '45–60 min':                 ('onbSession4560', '45–60 минут'),
    'Over an hour':              ('onbSession60', 'Больше часа'),
}


def add_to_arb() -> None:
    en = json.loads(ARB_EN.read_text('utf-8'))
    ru = json.loads(ARB_RU.read_text('utf-8'))
    for english, (key, russian) in T.items():
        en[key] = english
        ru[key] = russian
    ARB_EN.write_text(json.dumps(en, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    ARB_RU.write_text(json.dumps(ru, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    print(f'arb keys added: {len(T)}')


def rewrite() -> None:
    # Longest first, so 'Active' cannot eat the tail of 'Very active'.
    order = sorted(T, key=len, reverse=True)
    touched = 0
    for path in sorted(ONB.rglob('*.dart')):
        src = original = path.read_text('utf-8')
        for english in order:
            key = T[english][0]
            e = re.escape(english)
            src = re.sub(rf"const FieldLabel\(\s*'{e}'\s*\)",
                         f'FieldLabel(l10n.{key})', src)
            src = re.sub(rf"FieldLabel\(\s*'{e}'\s*\)",
                         f'FieldLabel(l10n.{key})', src)
            src = re.sub(rf"hint:\s*'{e}'", f'hint: l10n.{key}', src)
            src = re.sub(rf"(=>\s*)'{e}'(\s*,)", rf'\1l10n.{key}\2', src)
            src = re.sub(rf"^(\s*)'{e}',$", rf'\1l10n.{key},', src, flags=re.M)
        if src != original:
            path.write_text(src, 'utf-8')
            touched += 1
            print(f'  {path.name}')
    print(f'files rewritten: {touched}')


if __name__ == '__main__':
    add_to_arb()
    rewrite()
