// "Reklam ver" — which ad kinds a user can create (pure logic, unit-tested
// in test/ad_kind_logic_test.dart).

/// Load ad (shown in the loads feed, leads to a profile / link / route) or
/// service ad (leads to the user's own service page, service templates).
enum AdKind { cargo, service }

/// A user with a service profile gets service ads first, and can still
/// switch to a load ad; everybody else gets load ads only (as before).
List<AdKind> adKindsFor({required bool hasService}) =>
    hasService ? const [AdKind.service, AdKind.cargo] : const [AdKind.cargo];

/// Editor route for a template picked in the "Reklam ver" window.
String adCreateRoute(AdKind kind, String templateId, {String? serviceId}) =>
    kind == AdKind.service && serviceId != null
        ? '/ad-create?service=$serviceId&tpl=$templateId'
        : '/ad-create?tpl=$templateId';
