// Speed / memory on iPhone PWA and Android (30.10.2026): lists build lazily,
// pictures decode at the size shown, long chats load in steps, the loads
// feed is bounded. Guards so these do not come back.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/utils/image_decode.dart';
import 'package:freightlink/features/chat/domain/message_repository.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('pictures decode at the size shown (tile ≠ full page)', () {
    expect(decodeWidthFor(const BoxConstraints(maxWidth: 169, maxHeight: 169), 3), 507, reason: 'list tile on an iPhone');
    expect(decodeWidthFor(const BoxConstraints(maxWidth: 390, maxHeight: 300), 3), 1170, reason: 'full width, sharp');
    expect(decodeWidthFor(const BoxConstraints(maxWidth: 40, maxHeight: 40), 2), 240, reason: 'never below 240');
    expect(decodeWidthFor(const BoxConstraints(maxWidth: 1600, maxHeight: 900), 2), 1200, reason: 'never above 1200');
    expect(decodeWidthFor(const BoxConstraints(), 3), 800, reason: 'unbounded → the old fixed size');
    for (final f in ['lib/features/cargo/presentation/widgets/cargo_picture.dart', 'lib/features/market/presentation/market_card.dart']) {
      expect(src(f), contains('cacheWidth: decodeWidthFor(c, MediaQuery.devicePixelRatioOf(context)),'), reason: f);
    }
    expect(src('lib/features/chat/presentation/widgets/attachment_view.dart'), contains('cacheWidth: 660,'));
  });

  test('long chats load the newest messages in steps ("Köhnə mesajlar")', () {
    expect(kChatPageSize, 300);
    final repo = src('lib/features/chat/data/message_repository_impl.dart');
    expect(repo, contains(".order('created_at', ascending: false)\n        .limit(limit)"));
    final thread = src('lib/features/chat/presentation/conversation_thread_screen.dart');
    expect(thread, contains('conversationMessagesProvider((t.conversation.id, _pageLimit))'));
    expect(thread, contains("key: const ValueKey('chat-load-older'),"));
    expect(thread, contains('(cutoff == null || !m.createdAt.isBefore(cutoff))'), reason: 'no gap between topics');
  });

  test('lists build only what is on screen; the loads feed is bounded', () {
    expect(src('lib/features/chat/presentation/conversations_screen.dart'), contains('ListView.builder('));
    expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart'), contains('SliverList.builder('));
    final cargo = src('lib/features/cargo/data/cargo_repository_impl.dart');
    expect(RegExp(r'\.limit\(kCargoFeedMax\)').allMatches(cargo).length, 2);
    final jobs = src('lib/features/jobs/presentation/job_center_screen.dart');
    expect(jobs, contains('const kJobFeedStep = 20;'));
  });

  test('the static SQL check does not mistake functions for tables', () {
    final v = src('scripts/validate_sql.py');
    expect(v, contains(r'create\s+policy'), reason: 'only real create policy statements');
    final r = Process.runSync('python3', ['scripts/validate_sql.py']);
    expect(r.exitCode, 0);
    expect('${r.stdout}'.contains('WARNING: policies defined on tables where RLS was never enabled'), isFalse);
  });
}
