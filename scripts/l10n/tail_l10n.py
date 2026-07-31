# -*- coding: utf-8 -*-
"""The last thirteen: relative times, fault reasons, a donor badge.

Found only after `extract_strings.py` learned to look at switch arms and bare
returns. All of them live in a small label method next to the widget that shows
them, which is why the original migration -- which looked at `Text(...)` and a
list of named parameters -- walked straight past every one.

Each method gains the localizations object as a parameter rather than reading
it from a context, because none of them has a context: they are private helpers
on a widget, called from build.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path('D:/test 2/Fitness App/mobile')
ARB_EN = ROOT / 'lib' / 'l10n' / 'app_en.arb'
ARB_RU = ROOT / 'lib' / 'l10n' / 'app_ru.arb'

NEW = {
    'commonToday': ('Today', 'Сегодня', None),
    'commonYesterday': ('Yesterday', 'Вчера', None),
    'commonDaysAgo': ('{count} days ago', '{count} дн. назад', 'int'),
    'commonMinutesAgo': ('{count}m ago', '{count} мин назад', 'int'),
    'commonHoursAgo': ('{count}h ago', '{count} ч назад', 'int'),
    'commonDaysAgoShort': ('{count}d ago', '{count} дн. назад', 'int'),
    'equipmentFaultUnsafe': ('Unsafe', 'Опасно', None),
    'equipmentFaultDegraded': ('Degraded', 'Работает плохо', None),
    'equipmentFaultQrMissing': ('QR missing', 'Нет QR-кода', None),
    'equipmentFaultOther': ('Other', 'Другое', None),
    'donorwallLifetime': ('LIFETIME', 'НАВСЕГДА', None),
}

EDITS = {
    'lib/features/progress/progress_page.dart': [
        ("  String _formatDate(DateTime when) {",
         "  String _formatDate(AppLocalizations l10n, DateTime when) {"),
        ("    if (diff == 0) return 'Today';\n"
         "    if (diff == 1) return 'Yesterday';\n"
         "    if (diff < 7) return '$diff days ago';",
         "    if (diff == 0) return l10n.commonToday;\n"
         "    if (diff == 1) return l10n.commonYesterday;\n"
         "    if (diff < 7) return l10n.commonDaysAgo(diff);"),
        ("_formatDate(", "_formatDate(l10n, "),
    ],
    'lib/features/equipment/widgets/equipment_report_sheet.dart': [
        ("  String _label(EquipmentFault f) {",
         "  String _label(AppLocalizations l10n, EquipmentFault f) {"),
        ("        return 'Unsafe';", "        return l10n.equipmentFaultUnsafe;"),
        ("        return 'Degraded';", "        return l10n.equipmentFaultDegraded;"),
        ("        return 'QR missing';", "        return l10n.equipmentFaultQrMissing;"),
        ("        return 'Other';", "        return l10n.equipmentFaultOther;"),
        ("_label(", "_label(l10n, "),
    ],
    'lib/features/community/team_feed_page.dart': [
        ("  String _ago(DateTime t) {", "  String _ago(AppLocalizations l10n, DateTime t) {"),
        ("    if (d.inMinutes < 60) return '${d.inMinutes}m ago';\n"
         "    if (d.inHours < 24) return '${d.inHours}h ago';\n"
         "    return '${d.inDays}d ago';",
         "    if (d.inMinutes < 60) return l10n.commonMinutesAgo(d.inMinutes);\n"
         "    if (d.inHours < 24) return l10n.commonHoursAgo(d.inHours);\n"
         "    return l10n.commonDaysAgoShort(d.inDays);"),
        ("_ago(", "_ago(l10n, "),
    ],
    'lib/features/donor_wall/donor_wall_page.dart': [
        ("  String _label() {", "  String _label(AppLocalizations l10n) {"),
        ("    if (entry.isLifetime) return 'LIFETIME';",
         "    if (entry.isLifetime) return l10n.donorwallLifetime;"),
        ("_label()", "_label(l10n)"),
    ],
}


def main() -> None:
    en = json.loads(ARB_EN.read_text('utf-8'))
    ru = json.loads(ARB_RU.read_text('utf-8'))
    for key, (e, r, arg) in NEW.items():
        en[key], ru[key] = e, r
        if arg:
            en[f'@{key}'] = {'placeholders': {'count': {'type': arg}}}
    ARB_EN.write_text(json.dumps(en, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    ARB_RU.write_text(json.dumps(ru, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    print(f'arb keys added: {len(NEW)}')

    for rel, edits in EDITS.items():
        p = ROOT / rel
        src = p.read_text('utf-8')
        for old, new in edits:
            if old.endswith('(') and not old.startswith(' '):
                # A call site: rewrite every occurrence that is not the
                # declaration we just changed.
                src = re.sub(rf"(?<!String ){re.escape(old)}(?!AppLocalizations)",
                             new, src)
            else:
                if old not in src:
                    raise SystemExit(f'{rel}: did not match\n{old[:80]}')
                src = src.replace(old, new)
        # The localizations import, and the local in every build().
        if "import 'package:flutter_gen/gen_l10n/app_localizations.dart';" not in src:
            src = src.replace("import 'package:flutter/material.dart';",
                              "import 'package:flutter/material.dart';\n"
                              "import 'package:flutter_gen/gen_l10n/app_localizations.dart';", 1)
        src = re.sub(r'(Widget build\(BuildContext context(?:, WidgetRef ref)?\) \{\n)',
                     r'\1    final l10n = AppLocalizations.of(context);\n', src)
        p.write_text(src, 'utf-8')
        print(f'  {rel}')


if __name__ == '__main__':
    main()
