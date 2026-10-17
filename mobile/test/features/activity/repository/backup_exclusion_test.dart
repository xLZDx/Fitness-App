// S02-02 I08 (GPS-PRIV-083): both Android backup configuration files exclude
// the journal, sources and quarantine directories. Proves the CONFIGURATION
// FILES only; no device backup was performed.
import 'dart:io';

import 'package:fitness_app/features/activity/repository/journal_layout.dart';
import 'package:fitness_app/features/activity/repository/journal_generation_writer.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res/xml';

String _read(String name) => File('$_res/$name').readAsStringSync();

String _section(String tag, List<String> excludes) =>
    '<$tag>\n${excludes.map((e) => '  $e').join('\n')}\n</$tag>';

void main() {
  const fullBackup = ['full-backup-content'];
  const dataExtraction = ['cloud-backup', 'device-transfer'];

  test('the constants name exactly journal, sources, quarantine and '
      'activity_journal under domain file', () {
    expect(kActivityBackupExcludedDirs,
        ['journal', 'sources', 'quarantine', 'activity_journal']);
    expect(androidBackupExclusions(), [
      'file|journal',
      'file|sources',
      'file|quarantine',
      'file|activity_journal',
    ]);
  });

  test('the constants are the directories the repository really writes', () {
    const p = JournalPaths('/root');
    expect(p.journalDir, '/root/journal');
    expect(p.sourcesDir, '/root/sources');
    expect(p.quarantineDir, '/root/quarantine');
    expect(kActivityBackupExcludedDirs,
        containsAll(['journal', 'sources', 'quarantine']));
  });

  test('backup_rules.xml (API <= 30) excludes the journal constants', () {
    expect(backupXmlExcludesJournal(_read('backup_rules.xml'), fullBackup), isTrue);
  });

  test('data_extraction_rules.xml excludes them in cloud-backup AND '
      'device-transfer', () {
    expect(backupXmlExcludesJournal(_read('data_extraction_rules.xml'), dataExtraction),
        isTrue);
    for (final one in dataExtraction) {
      expect(backupXmlExcludesJournal(_read('data_extraction_rules.xml'), [one]),
          isTrue,
          reason: one);
    }
  });

  test('every constant appears as a real <exclude> element in each real '
      'section (text check independent of the checker)', () {
    final dx = _read('data_extraction_rules.xml');
    final bk = _read('backup_rules.xml');
    for (final line in androidBackupExcludeElements()) {
      expect(RegExp(RegExp.escape(line)).allMatches(bk).length, 1, reason: line);
      expect(RegExp(RegExp.escape(line)).allMatches(dx).length, 2, reason: line);
    }
  });

  group('the checker itself fails on bad fixtures', () {
    final all = androidBackupExcludeElements();

    test('one directory missing from backup_rules.xml', () {
      final bad = _section('full-backup-content', all.sublist(0, 2));
      expect(backupXmlExcludesJournal(bad, fullBackup), isFalse);
    });

    test('one directory missing from device-transfer only', () {
      final bad = '<data-extraction-rules>'
          '${_section('cloud-backup', all)}'
          '${_section('device-transfer', all.sublist(1))}'
          '</data-extraction-rules>';
      expect(backupXmlExcludesJournal(bad, dataExtraction), isFalse);
      expect(backupXmlExcludesJournal(bad, ['cloud-backup']), isTrue);
    });

    test('a commented-out exclusion does not count', () {
      final bad = _section('full-backup-content',
          [all[0], all[1], '<!-- ${all[2]} -->']);
      expect(backupXmlExcludesJournal(bad, fullBackup), isFalse);
    });

    test('a wrong domain or a typo does not count', () {
      expect(
          backupXmlExcludesJournal(
              _section('full-backup-content', [
                '<exclude domain="root" path="journal" />',
                all[1],
                all[2],
              ]),
              fullBackup),
          isFalse);
      expect(
          backupXmlExcludesJournal(
              _section('full-backup-content',
                  [all[0], all[1], '<exclude domain="file" path="quarantin" />']),
              fullBackup),
          isFalse);
    });

    test('a missing section is a failure', () {
      expect(backupXmlExcludesJournal('<other/>', fullBackup), isFalse);
    });

    test('the complete set passes (control)', () {
      expect(backupXmlExcludesJournal(_section('full-backup-content', all), fullBackup),
          isTrue);
    });
  });
}
