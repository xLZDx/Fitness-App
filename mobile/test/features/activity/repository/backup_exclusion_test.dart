// S02-02 I08 (GPS-PRIV-083): both Android backup configuration files exclude
// the journal, sources and quarantine directories. Proves the CONFIGURATION
// FILES only; no device backup was performed.
import 'dart:io';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/features/activity/repository/journal_layout.dart';
import 'package:fitness_app/features/activity/repository/journal_generation_writer.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../../support/s02_fixtures.dart';

class _SupportPath extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _SupportPath(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// `domain="file"` excluded paths of the first `<tag>` section.
Set<String> _fileExcludes(String xml, String tag) {
  final clean = xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(clean);
  if (m == null) return {};
  return {
    for (final e in RegExp(r'<exclude\b([^>]*?)/?>').allMatches(m.group(1)!))
      if (RegExp(r'domain="file"').hasMatch(e.group(1)!))
        RegExp(r'path="([^"]*)"').firstMatch(e.group(1)!)!.group(1)!,
  };
}

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

  test('DT-0-6 every top-level entry the production factory writes has a '
      'domain=file exclude in all three XML sections', () async {
    final tmp = Directory.systemTemp.createTempSync('s03_dt006_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final saved = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SupportPath(tmp.path);
    addTearDown(() => PathProviderPlatform.instance = saved);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    final journal =
        await fileActivityJournalFactory()(activityJournalScopeId('u1'));
    await journal.start();
    await journal.put(miniSession());
    expect(await journal.list(), hasLength(1), reason: 'positive control');
    await journal.close();

    final written = [
      for (final e in tmp.listSync())
        e.path.replaceAll('\\', '/').split('/').last
    ];
    expect(written, isNotEmpty);
    final rules = _read('backup_rules.xml');
    final dx = _read('data_extraction_rules.xml');
    final sections = <String, Set<String>>{
      'full-backup-content': _fileExcludes(rules, 'full-backup-content'),
      'cloud-backup': _fileExcludes(dx, 'cloud-backup'),
      'device-transfer': _fileExcludes(dx, 'device-transfer'),
    };
    for (final name in written) {
      for (final s in sections.entries) {
        expect(s.value, contains(name),
            reason: 'top-level entry "$name" has no domain=file exclude in '
                '${s.key}');
      }
    }
  });

  test('DT-0-7 the factory and the exclusion list share one root constant; '
      'the legacy names stay', () {
    expect(kScopedJournalRootDirName, 'activity_journal');
    expect(kActivityBackupExcludedDirs, contains(kScopedJournalRootDirName));
    expect(kActivityBackupExcludedDirs,
        containsAll([kJournalDirName, kSourcesDirName, kQuarantineDirName]));
    expect(kActivityBackupExcludedDirs, hasLength(4));
    final src = File(
            'lib/features/activity/repository/uid_scoped_activity_journal.dart')
        .readAsStringSync();
    expect(src, contains(r'$kScopedJournalRootDirName'),
        reason: 'the factory must build its root from the shared constant');
    expect(src.contains("'activity_journal'"), isFalse,
        reason: 'a second literal would let the two names drift apart');
  });

  test('DT-0-8 whenever the local-journal default is on, the activity_journal '
      'exclude exists in all three sections', () {
    final dx = _read('data_extraction_rules.xml');
    final rules = _read('backup_rules.xml');
    expect(ActivityFlags.compileTime.localJournal, isTrue,
        reason: 'precondition of this guard: the S03-0 default flip');
    expect(_fileExcludes(rules, 'full-backup-content'),
        contains('activity_journal'));
    expect(_fileExcludes(dx, 'cloud-backup'), contains('activity_journal'));
    expect(_fileExcludes(dx, 'device-transfer'), contains('activity_journal'));
  });

  test('the DT-0-8 section parser can fail (planted fixture)', () {
    expect(
        _fileExcludes('<cloud-backup><exclude domain="file" path="journal" />'
            '</cloud-backup>', 'cloud-backup'),
        isNot(contains('activity_journal')));
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
