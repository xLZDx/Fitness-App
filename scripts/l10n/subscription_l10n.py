# -*- coding: utf-8 -*-
"""Localise the subscription page: plan copy, statuses, periods, prices.

The donation page is the one screen where an English word costs money. Someone
deciding whether to give $9.99 a month should not have to read "Pausing at
period end" in a language they did not choose.

Four shapes, none of which the extractor's patterns reach:

    price: 'Free forever'          named parameters it does not list
    features: const ['...', ...]   string literals inside a list literal
    case X: return 'Trial';        a switch arm in a label method
    r'$9.99 / month · tax-deductible'   a raw string, and money inside prose

PRICES ARE NOT TRANSLATED, the sentences around them are. The amount is the
same in both languages; "/ month · tax-deductible" is not. So the numbers stay
in the Dart and ride into the ARB as placeholders, which also keeps a single
source of truth for what the picker advertises -- the comment above
`_priceLabelFor` says the server enforces the real amounts, and a translator
must not be able to move a decimal point.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path('D:/Repo/Fitness_App/mobile')
PAGE = ROOT / 'lib' / 'features' / 'subscription' / 'subscription_page.dart'
ARB_EN = ROOT / 'lib' / 'l10n' / 'app_en.arb'
ARB_RU = ROOT / 'lib' / 'l10n' / 'app_ru.arb'

# english -> (key, russian). Plain strings only; the money templates are below.
T = {
    # plan cards
    'Free forever': ('subFreeForever', 'Бесплатно навсегда'),
    'Full app access — workouts, scanning, injury filtering, progress.':
        ('subMemberTagline',
         'Полный доступ: тренировки, распознавание, фильтр травм, прогресс.'),
    'Full body-weight + equipment library':
        ('subFeatureLibrary', 'Вся библиотека: свой вес и тренажёры'),
    'Injury-aware filtering (always on)':
        ('subFeatureInjuryFilter', 'Фильтр по травмам (всегда включён)'),
    'Workout logging + last-week chart':
        ('subFeatureLogging', 'Дневник тренировок и график за неделю'),
    'Equipment QR scanning':
        ('subFeatureQr', 'Распознавание тренажёров по QR-коду'),
    'Stay a Member': ('subStayMember', 'Остаться участником'),
    'Funds the mission and unlocks long-term progress + reminders.':
        ('subSupporterTagline',
         'Поддерживает проект и открывает долгий прогресс и напоминания.'),
    'Everything in Member': ('subFeatureAllMember', 'Всё, что у участника'),
    'Long-term progress charts':
        ('subFeatureLongProgress', 'Графики прогресса за долгий период'),
    'Schedule + reminders': ('subFeatureSchedule', 'Расписание и напоминания'),
    'For you': ('subFeatureForYou', 'Подборка под вас'),
    'Tax-deductible (501(c)(3) pending)':
        ('subFeatureTaxDeductible',
         'Вычитается из налога (статус 501(c)(3) на рассмотрении)'),
    'Become a Supporter': ('subBecomeSupporter', 'Стать сторонником'),
    'Powers celebrity-donated content + advanced analytics.':
        ('subSustainerTagline',
         'Оплачивает контент от приглашённых тренеров и расширенную аналитику.'),
    'Everything in Supporter': ('subFeatureAllSupporter', 'Всё, что у сторонника'),
    'Celebrity in-kind video donations':
        ('subFeatureCelebrity', 'Видео, переданные приглашёнными тренерами'),
    'AI form coach (when available)':
        ('subFeatureFormCoach', 'Тренер по технике (когда доступен)'),
    'Body comp + advanced analytics':
        ('subFeatureBodyComp', 'Состав тела и расширенная аналитика'),
    'Donor-wall recognition (opt-in)':
        ('subFeatureDonorWall', 'Упоминание на стене жертвователей (по желанию)'),
    'Become a Sustainer': ('subBecomeSustainer', 'Стать покровителем'),

    # status
    'Not yet supporting': ('subStatusNone', 'Пока не поддерживаете'),
    'Trial': ('subStatusTrial', 'Пробный период'),
    'Supporting': ('subStatusActive', 'Поддерживаете'),
    'Pausing at period end': ('subStatusCancelling', 'Приостановится в конце периода'),
    'Lapsed': ('subStatusExpired', 'Истекло'),
    'Ends today': ('subEndsToday', 'Заканчивается сегодня'),
    'Ends tomorrow': ('subEndsTomorrow', 'Заканчивается завтра'),

    # period toggle
    'Monthly': ('subPeriodMonthly', 'Помесячно'),
    'Annual · save ~50%': ('subPeriodAnnual', 'Год · выгоднее вдвое'),
    'Family · 2': ('subPeriodFamily2', 'Семейный · 2'),
    'Family · 4': ('subPeriodFamily4', 'Семейный · 4'),
    'Lifetime': ('subPeriodLifetime', 'Навсегда'),

    # buttons
    'Choose': ('subChoose', 'Выбрать'),
    'Current': ('subCurrent', 'Текущий'),
}

# Templates carrying a number. `{amount}` is passed from the Dart, so the
# figure itself is never translatable.
MONEY = {
    'subPriceMonthTaxDeductible': (
        '{amount} / month · tax-deductible',
        '{amount} / мес · вычитается из налога'),
    'subPriceYearEffective': (
        '{amount} / year · ~{effective}/mo effective',
        '{amount} / год · выходит ~{effective} в месяц'),
    'subPriceMonthSeats': (
        '{amount} / month · {seats} seats',
        '{amount} / мес · мест: {seats}'),
    'subPriceLifetime': (
        '{amount} lifetime · one-time donor',
        '{amount} навсегда · разовое пожертвование'),
    'subLapsedDaysAgo': (
        'Lapsed {days}d ago', 'Истекло {days} дн. назад'),
    'subEndsInDays': (
        'Ends in {days} days', 'Заканчивается через {days} дн.'),
}

ARG_TYPES = {
    'amount': 'String', 'effective': 'String', 'seats': 'int', 'days': 'int',
}


def add_to_arb() -> None:
    en = json.loads(ARB_EN.read_text('utf-8'))
    ru = json.loads(ARB_RU.read_text('utf-8'))
    for english, (key, russian) in T.items():
        en[key] = english
        ru[key] = russian
    for key, (e, r) in MONEY.items():
        en[key] = e
        ru[key] = r
        names = re.findall(r'\{(\w+)\}', e)
        en[f'@{key}'] = {
            'placeholders': {n: {'type': ARG_TYPES[n]} for n in names}
        }
    ARB_EN.write_text(json.dumps(en, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    ARB_RU.write_text(json.dumps(ru, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    print(f'arb keys added: {len(T) + len(MONEY)}')


# The money call sites, rewritten by hand rather than by pattern: each one
# needs its numbers pulled out into arguments, and there are only nine.
MONEY_SITES = [
    (r"return r'\$9\.99 / month · tax-deductible';",
     r"return l10n.subPriceMonthTaxDeductible(r'$9.99');"),
    (r"return r'\$59\.99 / year · ~\$5/mo effective';",
     r"return l10n.subPriceYearEffective(r'$59.99', r'$5');"),
    (r"return r'\$14\.99 / month · 2 seats';",
     r"return l10n.subPriceMonthSeats(r'$14.99', 2);"),
    (r"return r'\$19\.99 / month · 4 seats';",
     r"return l10n.subPriceMonthSeats(r'$19.99', 4);"),
    (r"return r'\$19\.99 / month · tax-deductible';",
     r"return l10n.subPriceMonthTaxDeductible(r'$19.99');"),
    (r"return r'\$119\.99 / year · ~\$9\.99/mo effective';",
     r"return l10n.subPriceYearEffective(r'$119.99', r'$9.99');"),
    (r"return r'\$499 lifetime · one-time donor';",
     r"return l10n.subPriceLifetime(r'$499');"),
    (r"if \(daysLeft < 0\) return 'Lapsed \$\{-daysLeft\}d ago';",
     "if (daysLeft < 0) return l10n.subLapsedDaysAgo(-daysLeft);"),
    (r"return 'Ends in \$daysLeft days';",
     "return l10n.subEndsInDays(daysLeft);"),
]


def rewrite() -> None:
    src = original = PAGE.read_text('utf-8')
    for english in sorted(T, key=len, reverse=True):
        key = T[english][0]
        e = re.escape(english)
        src = re.sub(rf"(price|title|tagline|label|text):\s*'{e}'",
                     rf"\1: l10n.{key}", src)
        src = re.sub(rf"return '{e}';", f'return l10n.{key};', src)
        src = re.sub(rf"^(\s*)'{e}',$", rf'\1l10n.{key},', src, flags=re.M)
        src = re.sub(rf"Text\('{e}'\)", f'Text(l10n.{key})', src)
    for pat, repl in MONEY_SITES:
        src, n = re.subn(pat, repl, src)
        if n != 1:
            raise SystemExit(f'money site matched {n} times: {pat}')
    # `features: const [...]` cannot hold a lookup once its entries are calls.
    src = src.replace('features: const [', 'features: [')
    PAGE.write_text(src, 'utf-8')
    print('rewritten' if src != original else 'NO CHANGE')


if __name__ == '__main__':
    add_to_arb()
    rewrite()
