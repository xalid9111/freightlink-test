// "Fon şəklini dəyiş" for Park, Servis and Mağaza (owner, 05.11.2026, 0096):
// one sheet (templates of the section + own picture), the owner only, the
// round picture and the gallery apart; admin templates.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/admin/presentation/admin_cover_templates_page.dart';
import 'package:freightlink/features/covers/profile_covers.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));
const _base = 'https://x.supabase.co/storage/v1/object/public/profile-media/a';

const _tpl = [
  CoverTemplate(id: 't1', name: 'Gün batımı', imageUrl: '$_base/sunset.jpg', sections: [CoverSection.park]),
  CoverTemplate(id: 't2', name: 'Kafe', imageUrl: '$_base/cafe.jpg', sections: [CoverSection.park, CoverSection.shop]),
];

Widget _sheet({List<CoverTemplate> list = _tpl, String? current, CoverSection section = CoverSection.park}) => ProviderScope(
      overrides: [coverTemplatesProvider.overrideWith((ref, s) async => [for (final t in list) if (t.sections.contains(s)) t])],
      child: MaterialApp(home: Scaffold(body: CoverPickerSheet(s: _az, section: section, current: current))),
    );

void main() {
  test('templates are read; a link without its place / zoom is the same picture', () {
    final t = CoverTemplate.fromJson({
      'id': 'x',
      'name': 'A',
      'image_url': '$_base/a.jpg',
      'sections': ['park', 'shop', 'loads'],
      'is_active': false,
    });
    expect(t.sections, [CoverSection.park, CoverSection.shop]);
    expect(t.isActive, isFalse);
    expect(coverBase('$_base/a.jpg?ax=0.2&ay=0&z=1.4'), '$_base/a.jpg');
  });

  testWidgets('the sheet: templates of this section, own picture, easy to close', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_sheet(current: '$_base/cafe.jpg?ax=0.1&ay=0&z=1'));
    await tester.pumpAndSettle();
    expect(find.text('Fon şəklini seç'), findsOneWidget);
    expect(find.text('Şablonlardan seç'), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-template-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-template-t2')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget, reason: 'the current background is ticked');
    expect(find.byKey(const ValueKey('cover-upload')), findsOneWidget);
    expect(find.text('Öz şəklini yüklə'), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-sheet-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-adjust')), findsOneWidget, reason: '"Yerini düzəlt" for the current one');
  });

  testWidgets('a service sees only service templates; none yet = a clear note', (tester) async {
    await tester.pumpWidget(_sheet(section: CoverSection.service));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover-template-t1')), findsNothing);
    expect(find.byKey(const ValueKey('cover-templates-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-adjust')), findsNothing, reason: 'nothing to adjust yet');
  });

  testWidgets('header: the owner gets "Fon şəklini dəyiş" and the camera; a visitor neither', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget header({required bool owner}) => MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: PlaceCoverHeader(
                coverUrl: null,
                fallback: Container(color: Colors.grey),
                avatar: const Icon(Icons.local_parking),
                name: 'Upark',
                changeLabel: _az.t('cover_change'),
                subtitle: const Text('Bakı · 3.7 km'),
                onChangeCover: owner ? () {} : null,
                onAvatarEdit: owner ? () {} : null,
                badge: const Text('1/6', key: ValueKey('badge')),
              ),
            ),
          ),
        );
    await tester.pumpWidget(header(owner: true));
    expect(find.byKey(const ValueKey('cover-change')), findsOneWidget);
    expect(find.text('Fon şəklini dəyiş'), findsOneWidget);
    expect(find.byKey(const ValueKey('place-avatar-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('place-cover-default')), findsOneWidget, reason: 'no background yet: the default picture');
    // The round picture stands half over the background's lower edge.
    final cover = tester.getRect(find.byKey(const ValueKey('place-cover-default')));
    final avatar = tester.getRect(find.byKey(const ValueKey('place-avatar')));
    expect(avatar.top, lessThan(cover.bottom));
    expect(avatar.bottom, greaterThan(cover.bottom));
    expect(avatar.width, closeTo(avatar.height, 0.01), reason: 'always round');
    await tester.pumpWidget(header(owner: false));
    expect(find.byKey(const ValueKey('cover-change')), findsNothing);
    expect(find.byKey(const ValueKey('place-avatar-edit')), findsNothing);
    expect(find.byKey(const ValueKey('badge')), findsOneWidget);
  });

  testWidgets('admin: templates with sections, on / off, edit, delete, add', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        adminCoverTemplatesProvider.overrideWith((ref) async => [
              ..._tpl,
              const CoverTemplate(id: 't3', name: 'Köhnə', imageUrl: '$_base/old.jpg', sections: [CoverSection.service], isActive: false),
            ]),
      ],
      child: const MaterialApp(home: Scaffold(body: AdminCoverTemplatesPage())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-cover-t3')), findsOneWidget);
    expect(find.text('Passiv'), findsOneWidget);
    expect(find.text('Mağaza'), findsOneWidget);
    expect(find.byTooltip('Redaktə et'), findsNWidgets(3));
    expect(find.byTooltip('Sil'), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('admin-cover-add')));
    await tester.pumpAndSettle();
    for (final k in ['admin-cover-pick', 'admin-cover-name', 'admin-cover-sec-park', 'admin-cover-sec-service', 'admin-cover-sec-shop', 'admin-cover-save']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
  });

  test('wired: the owner only; booking, contact, route and the gallery stay; the server checks', () {
    final park = src('lib/features/tirpark/presentation/tir_park_detail_screen.dart');
    expect(park, contains("owner: me != null && park.managerId == me.id && park.managerStatus == 'approved'"));
    expect(park, contains('TirParkBookingSection(park: park, s: s)'));
    expect(park, contains('_PhoneCard(phone: park.phone!, s: s)'));
    expect(park, contains('_RouteCard(park: park, s: s)'));
    expect(park, contains('onAdd: () => _addPhoto(park, s)'), reason: 'the gallery stays the admins\'');
    expect(park, contains('repo.setParkLogo(park.id, url)'), reason: 'the round picture apart');
    final svc = src('lib/features/services/presentation/service_detail_screen.dart');
    expect(svc, contains('owner: isOwner,'));
    expect(svc, contains('repo.setServiceCover(p.id, url)'));
    expect(src('lib/features/ads/presentation/public_profile_screen.dart'), contains('changeShopCover('));
    expect(src('lib/features/auth/presentation/widgets/profile_cover.dart'), contains('changeShopCover('));
    expect(src('lib/features/admin/presentation/admin_shell.dart'), contains("case 'cover_templates':"));
    final sql = src('supabase/migrations/0096_profile_covers.sql');
    expect(sql, contains('perform public._require_admin();'));
    expect(sql, contains('public.is_tir_park_manager(p_park)'));
    expect(sql, contains('p_section = any (t.sections)'));
    expect(sql, contains('grant select (cover_url) on table public.service_providers to authenticated;'));
  });
}
