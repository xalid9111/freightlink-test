// Faster pages (owner, 09.11.2026, "Turbo.az kimi"): no repeated requests
// while scrolling — the load-type pictures are read once per session, and
// the profiles asked for at the same moment go in one request.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/data/cargo_media_repository.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_media_providers.dart';

String src(String p) => File(p).readAsStringSync();

class _Media implements CargoMediaRepository {
  int allCalls = 0;
  @override
  Future<List<CargoTemplate>> allTemplates() async {
    allCalls++;
    return const [
      CargoTemplate(id: '1', category: 'tent', imageUrl: 'a'),
      CargoTemplate(id: '2', category: 'ref', imageUrl: 'b'),
      CargoTemplate(id: '3', category: 'tent', imageUrl: 'c'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('load-type pictures: one read for every type, kept when no card shows them, same order per type', () async {
    final media = _Media();
    final c = ProviderContainer(overrides: [cargoMediaRepositoryProvider.overrideWithValue(media)]);
    addTearDown(c.dispose);
    await c.read(allCargoTemplatesProvider.future);
    // A card of each type comes and goes (scrolling): no new request.
    for (var i = 0; i < 3; i++) {
      final sub = c.listen(cargoTemplatesProvider('tent'), (_, __) {});
      expect([for (final t in sub.read().value!) t.imageUrl], ['a', 'c'], reason: 'at once, no loading step');
      sub.close();
      final sub2 = c.listen(cargoTemplatesProvider('ref'), (_, __) {});
      expect([for (final t in sub2.read().value!) t.imageUrl], ['b']);
      sub2.close();
      await Future<void>.delayed(Duration.zero);
    }
    expect(media.allCalls, 1);
    // An admin's change reads them again.
    c.invalidate(allCargoTemplatesProvider);
    await c.read(allCargoTemplatesProvider.future);
    expect(media.allCalls, 2);
  });

  test('wired: admin change refreshes; profiles batched with the old one-by-one read as fallback', () {
    expect(src('lib/features/cargo/presentation/admin_cargo_pictures_page.dart'), contains('ref.invalidate(allCargoTemplatesProvider);'));
    final p = src('lib/features/cargo/presentation/providers/cargo_media_providers.dart');
    expect(p, contains('final allCargoTemplatesProvider = FutureProvider<List<CargoTemplate>>('), reason: 'kept for the session');
    expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart'), contains('ref.listen(allCargoTemplatesProvider, (_, __) {});'));
    final r = src('lib/repositories/profile_repository.dart');
    expect(r, contains("await _client.from('user_profiles').select(_publicCols).inFilter('id', part);"));
    expect(r, contains('_fetchOne(id).then(jobs[id]!.complete, onError: jobs[id]!.completeError);'));
    expect(r, contains('if (userId == _client.auth.currentUser?.id) {'), reason: 'the own profile is read as before');
  });
}
