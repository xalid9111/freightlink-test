// Gold VIP frame on the picture of VIP ads (owner, 24.10.2026): Loads and
// TIR Bazarı (phone + computer), one VIP mark only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/vip_frame.dart';

void main() {
  for (final size in const [Size(120, 120), Size(169, 169), Size(260, 168), Size(400, 300)]) {
    testWidgets('draws over the picture at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: const VipPictureFrame(child: ColoredBox(color: Color(0xFF334455), key: ValueKey('pic'))),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('pic')), findsOneWidget);
      expect(find.byKey(const ValueKey('vip-frame')), findsOneWidget);
      expect(tester.getSize(find.byType(VipPictureFrame)), size);
    });
  }

  test('used on every VIP picture; the older double marks are gone', () {
    String src(String p) => File(p).readAsStringSync();
    final tile = src('lib/features/cargo/presentation/widgets/cargo_card.dart');
    expect(tile, contains('VipPictureFrame('));
    final card = src('lib/features/market/presentation/market_card.dart');
    expect('VipPictureFrame('.allMatches(card).length, 2); // phone feed + grid card
    expect(card.contains('Icons.workspace_premium, key: ValueKey(\'feed-vip\')'), isFalse);
    expect(card.contains('if (vip) const Positioned(left: 8, top: 8, child: VipBadge())'), isFalse);
    final desk = src('lib/features/market/presentation/market_home_desktop.dart');
    expect(desk, contains('VipFramePainter(radius: 16)'));
    // Colours only from AppColors.
    expect(src('lib/core/widgets/vip_frame.dart').contains('Color(0x'), isFalse);
  });
}
