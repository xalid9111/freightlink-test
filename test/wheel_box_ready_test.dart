import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/widgets/wheel_feed.dart';

void main() {
  test('wheelBoxReady: false while an ancestor (page slide) is not laid out', () {
    final card = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(10, 10)));
    final slide = RenderFractionalTranslation(translation: const Offset(0, 0.02), child: card);
    slide.attach(PipelineOwner());
    card.layout(BoxConstraints.loose(const Size(100, 100)));

    expect(card.hasSize, isTrue);
    expect(slide.hasSize, isFalse);
    // This is the AutoFix "RenderBox was not laid out" crash.
    expect(() => card.localToGlobal(Offset.zero, ancestor: slide), throwsA(anything));
    expect(wheelBoxReady(card), isFalse);

    slide.layout(BoxConstraints.loose(const Size(100, 100)));
    expect(wheelBoxReady(card), isTrue);
    expect(card.localToGlobal(Offset.zero, ancestor: slide), isA<Offset>());
  });

  test('wheelBoxReady: null, detached or not laid out boxes are not ready', () {
    expect(wheelBoxReady(null), isFalse);
    final box = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(10, 10)));
    expect(wheelBoxReady(box), isFalse);
    box.attach(PipelineOwner());
    expect(wheelBoxReady(box), isFalse);
    box.layout(BoxConstraints.loose(const Size(100, 100)));
    expect(wheelBoxReady(box), isTrue);
  });
}
