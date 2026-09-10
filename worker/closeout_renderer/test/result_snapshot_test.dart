import 'dart:async';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:test/test.dart';

class _Repository extends CloseoutRepository {
  _Repository()
    : super(
        SupabaseClient('http://fixture.invalid', 'fixture-key'),
        reuseResultSnapshots: true,
      );
  int reads = 0;
  String revision = '1';
  Completer<void>? gate;
  bool fail = false;
  bool alwaysChanges = false;
  @override
  Future<String> loadResultRevision(String showId) async => revision;
  @override
  Future<ReportResultSnapshot> readResultSnapshot(
    String showId, {
    List<String>? sectionIds,
  }) async {
    reads++;
    await gate?.future;
    if (fail) throw StateError('read failed');
    if (alwaysChanges) revision += 'x';
    return ReportResultSnapshot(
      showId: showId,
      sections: [],
      rowsBySection: {},
    );
  }
}

void main() {
  late _Repository repo;
  setUp(() => repo = _Repository());
  tearDown(() => repo.supabase.dispose());
  test(
    'concurrent exhibitors share one complete load of the same revision',
    () async {
      repo.gate = Completer<void>();
      final a = repo.loadResultSnapshot('show', sectionIds: ['b', 'a']);
      final b = repo.loadResultSnapshot('show', sectionIds: ['a', 'b']);
      await Future<void>.delayed(Duration.zero);
      repo.gate!.complete();
      final values = await Future.wait([a, b]);
      expect(identical(values[0], values[1]), isTrue);
      expect(repo.reads, 1);
    },
  );
  test('edits invalidate the snapshot on the very next report', () async {
    await repo.loadResultSnapshot('show');
    repo.revision = '2';
    await repo.loadResultSnapshot('show');
    expect(repo.reads, 2);
  });
  test('Open, Youth, and other shows never share scoped rows', () async {
    await repo.loadResultSnapshot('show', sectionIds: ['open']);
    await repo.loadResultSnapshot('show', sectionIds: ['youth']);
    await repo.loadResultSnapshot('other', sectionIds: ['open']);
    expect(repo.reads, 3);
  });
  test('a read spanning edits is discarded and retried', () async {
    repo.gate = Completer<void>();
    final pending = repo.loadResultSnapshot('show');
    await Future<void>.delayed(Duration.zero);
    repo.revision = '2';
    repo.gate!.complete();
    await pending;
    expect(repo.reads, 2);
  });
  test(
    'repeated edits fail visibly instead of using a mixed snapshot',
    () async {
      repo.alwaysChanges = true;
      await expectLater(repo.loadResultSnapshot('show'), throwsStateError);
      expect(repo.reads, 3);
    },
  );
  test(
    'a failed read is evicted instead of poisoning future reports',
    () async {
      repo.fail = true;
      await expectLater(repo.loadResultSnapshot('show'), throwsStateError);
      repo.fail = false;
      await repo.loadResultSnapshot('show');
      expect(repo.reads, 2);
    },
  );
  test('cache retains no more than four scopes', () async {
    for (var n = 0; n < 5; n++) {
      await repo.loadResultSnapshot('show$n');
    }
    await repo.loadResultSnapshot('show0');
    expect(repo.reads, 6);
  });
}
