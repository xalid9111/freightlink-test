import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../domain/vip_rows.dart';

/// How many normal rows come before a VIP row (admin setting, 0059).
/// Until 0059 is run (or offline): the default, 3.
final cargoVipEveryProvider = FutureProvider<int>((ref) async {
  try {
    final row = await SupabaseConfig.client
        .from('cargo_feed_settings')
        .select('vip_every_rows')
        .eq('id', 1)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    final n = (row?['vip_every_rows'] as num?)?.toInt();
    return kVipEveryChoices.contains(n) ? n! : kDefaultVipEvery;
  } catch (_) {
    return kDefaultVipEvery;
  }
});
