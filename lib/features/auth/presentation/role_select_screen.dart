import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/localization/locale_controller.dart';

/// "Mən yük yerləşdirirəm" / "Mən daşıyıcıyam" — registration-time
/// role choice (brief §5). This is step 1 of a two-step registration
/// flow: picking a role here just carries it as a query param into
/// /register, which does the actual AuthRepository.signUp(role: role)
/// call. Kept as its own screen/step (rather than a dropdown inside one
/// long form) because the brief frames it as the very first decision a
/// new user makes, before anything else about them is collected.
class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.t('role_select_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _RoleCard(
              icon: Icons.inventory_2_outlined,
              label: strings.t('role_cargo_owner_label'),
              sublabel: strings.t('role_cargo_owner_sub'),
              role: AppConstants.roleCargoOwner,
            ),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.local_shipping_outlined,
              label: strings.t('role_carrier_label'),
              sublabel: strings.t('role_carrier_sub'),
              role: AppConstants.roleCarrier,
            ),
            const SizedBox(height: 12),
            // "Usta / Servis": the account gets an ordinary role; the
            // service profile (individual mechanic or service centre) is a
            // separate record filled in right after signup.
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: Text(strings.t('svc_role_label')),
                subtitle: Text(strings.t('svc_role_sub')),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                children: [
                  ListTile(
                    leading: const Icon(Icons.handyman_outlined),
                    title: Text(strings.t('svc_kind_individual')),
                    subtitle: Text(strings.t('svc_kind_individual_sub')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => context.go('/register?role=${AppConstants.roleCargoOwner}&service=individual'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.car_repair),
                    title: Text(strings.t('svc_kind_center')),
                    subtitle: Text(strings.t('svc_kind_center_sub')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => context.go('/register?role=${AppConstants.roleCargoOwner}&service=center'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final String role;
  const _RoleCard({required this.icon, required this.label, required this.sublabel, required this.role});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(sublabel),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => context.go('/register?role=$role'),
      ),
    );
  }
}
