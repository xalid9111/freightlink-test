import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/phone_country_field.dart';

/// TEST / PROOF OF CONCEPT — WhatsApp phone verification (admin panel only).
///
/// Checks whether Meta's webhook gives FreightLink the sender's real phone
/// number. It is isolated from registration, login and profiles: nothing
/// here changes the user's account, and a "verified" result is NOT saved to
/// the profile. See docs/WHATSAPP_VERIFY_POC.md.
///
/// Flow: number → wa-verify-start Edge Function (returns a wa.me link with a
/// one-time code) → the admin sends the prefilled message from WhatsApp →
/// wa-webhook matches it → this page polls the result row (RLS: own rows
/// only, no code / hash visible).
class AdminWaVerifyPocPage extends StatefulWidget {
  const AdminWaVerifyPocPage({super.key});

  @override
  State<AdminWaVerifyPocPage> createState() => _AdminWaVerifyPocPageState();
}

class _AdminWaVerifyPocPageState extends State<AdminWaVerifyPocPage> {
  final SupabaseClient _client = SupabaseConfig.client;
  final _form = GlobalKey<FormState>();
  String _phone = '';
  bool _busy = false;
  String? _error;
  String? _challengeId;
  String? _waLink;
  DateTime? _expiresAt;
  Map<String, dynamic>? _row;
  Timer? _poll;

  static const _cols = 'id,phone_e164,status,last_result,sender_kind,has_bsuid,attempts,created_at,expires_at,consumed_at';

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    _poll?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _row = null;
      _challengeId = null;
      _waLink = null;
    });
    try {
      final res = await _client.functions.invoke('wa-verify-start', body: {'phone': _phone});
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      final id = data['challenge_id'] as String?;
      final link = data['wa_link'] as String?;
      if (id == null || link == null) throw const FormatException('bad_response');
      if (!mounted) return;
      setState(() {
        _challengeId = id;
        _waLink = link;
        _expiresAt = DateTime.tryParse('${data['expires_at']}')?.toLocal();
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
      unawaited(_refresh());
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? '${details['error']}' : '${e.status}';
      if (mounted) setState(() => _error = _errorText(code));
    } catch (_) {
      if (mounted) setState(() => _error = 'Funksiyaya qoşulmaq olmadı. wa-verify-start yerləşdirilib? (docs/WHATSAPP_VERIFY_POC.md)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorText(String code) => switch (code) {
        'admin_only' => 'Bu test yalnız adminlər üçündür.',
        'rate_limited' => '10 dəqiqədə ən çox 5 test. Bir az gözləyin.',
        'invalid_phone' => 'Nömrə beynəlxalq formatda deyil (+ölkə kodu ilə).',
        'not_signed_in' => 'Giriş etməmisiniz.',
        'not_configured' => 'Funksiya qurulmayıb: WA_BUSINESS_NUMBER secret-i yoxdur.',
        _ => 'Test başlamadı ($code).',
      };

  Future<void> _refresh() async {
    final id = _challengeId;
    if (id == null) return;
    try {
      final row = await _client.from('wa_verify_challenges').select(_cols).eq('id', id).maybeSingle();
      if (!mounted || id != _challengeId) return;
      setState(() => _row = row);
      final status = row?['status'];
      final expired = _expiresAt != null && DateTime.now().isAfter(_expiresAt!.add(const Duration(seconds: 30)));
      if (status != 'pending' || expired) _poll?.cancel();
    } catch (_) {
      // Keep polling; a temporary network error is not a result.
    }
  }

  Future<void> _openWhatsApp() async {
    final link = _waLink;
    if (link == null) return;
    final ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    if (!ok && mounted) setState(() => _error = 'WhatsApp açılmadı. Linki kopyalayıb telefonda açın.');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('WhatsApp ilə nömrə təsdiqi', style: AppFonts.display(size: 26, color: AppColors.text)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.urgentBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.urgentFg),
          ),
          child: const Text(
            'TEST / PROOF OF CONCEPT. Qeydiyyata, girişə və profilə toxunmur. '
            'Nəticə profilə yazılmır. Məqsəd: Meta webhook-u göndərənin real nömrəsini verirmi?',
            style: TextStyle(color: AppColors.urgentFg, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: PhoneCountryField(label: 'Yoxlanacaq nömrə', onChanged: (v) => _phone = v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.verified_user_outlined),
          label: const Text('Verify with WhatsApp'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        if (_waLink != null) ...[
          const SizedBox(height: 16),
          const Text(
            '1) "WhatsApp-ı aç" düyməsini basın.\n'
            '2) Bu nömrənin WhatsApp-ından hazır mesajı DƏYİŞMƏDƏN göndərin.\n'
            '3) Nəticə aşağıda avtomatik görünəcək (10 dəqiqə etibarlıdır).',
            style: TextStyle(color: AppColors.textSoft, height: 1.4),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openWhatsApp,
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp-ı aç'),
          ),
          const SizedBox(height: 16),
          _ResultCard(row: _row),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic>? row;
  const _ResultCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final r = row;
    final status = r?['status'] as String?;
    final last = r?['last_result'] as String?;
    final kind = r?['sender_kind'] as String?;
    final (IconData icon, Color color, String title) = switch (status) {
      'verified' => (Icons.check_circle, AppColors.online, 'Təsdiqləndi: webhook-dakı nömrə daxil edilən nömrə ilə eynidir'),
      'expired' => (Icons.timer_off_outlined, AppColors.textSoft, 'Vaxt bitdi'),
      'locked' => (Icons.lock_outline, AppColors.danger, 'Çox səhv cəhd — kod bağlandı'),
      'superseded' => (Icons.refresh, AppColors.textSoft, 'Yeni test başladıldı'),
      _ => switch (last) {
          'no_phone_in_webhook' => (Icons.help_outline, AppColors.urgentFg, 'Mesaj gəldi, AMMA webhook nömrə vermədi (yalnız BSUID). Təsdiq edilmədi.'),
          'phone_mismatch' => (Icons.error_outline, AppColors.danger, 'Mesaj başqa nömrədən gəldi. Təsdiq edilmədi.'),
          'sender_conflict' => (Icons.error_outline, AppColors.danger, 'Webhook-da göndərən məlumatı ziddiyyətlidir. Təsdiq edilmədi.'),
          _ => (Icons.hourglass_top, AppColors.textSoft, 'Mesaj gözlənilir…'),
        },
    };
    final kindText = switch (kind) {
      'phone' => 'telefon nömrəsi var',
      'bsuid_only' => 'yalnız BSUID (nömrə yoxdur)',
      'conflict' => 'ziddiyyətli',
      'none' => 'heç bir identifikator yoxdur',
      _ => '—',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 10),
            Text('Nömrə: ${r?['phone_e164'] ?? '—'}', style: const TextStyle(color: AppColors.textSoft)),
            Text('Webhook-da göndərən: $kindText', style: const TextStyle(color: AppColors.textSoft)),
            Text('BSUID var: ${r?['has_bsuid'] == null ? '—' : (r!['has_bsuid'] == true ? 'bəli' : 'xeyr')}',
                style: const TextStyle(color: AppColors.textSoft)),
            Text('Cəhdlər: ${r?['attempts'] ?? 0}', style: const TextStyle(color: AppColors.textSoft)),
          ],
        ),
      ),
    );
  }
}
