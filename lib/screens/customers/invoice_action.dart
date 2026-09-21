import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/business.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../services/invoice_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/confirm_dialog.dart';

/// The bundled authorised-signatory image embedded in the signature block.
const _signatureAsset = 'assets/images/signature.png';

/// Cached signature bytes so we only decode the asset once per session.
Uint8List? _signatureBytesCache;

/// Loads the bundled signature image, tolerating a missing/unreadable asset by
/// returning null (the PDF then falls back to a drawn flourish).
Future<Uint8List?> _loadSignatureBytes() async {
  if (_signatureBytesCache != null) return _signatureBytesCache;
  try {
    final data = await rootBundle.load(_signatureAsset);
    return _signatureBytesCache = data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Resolves the business whose details should appear as the invoice seller,
/// given the [contract] being invoiced and a [lookup] from business id to
/// [Business] (typically `DataController.businessById`). Precedence:
///
///   1. the business the [contract] was sold under
///      ([ServiceContract.businessId]), when resolvable;
///   2. an explicitly supplied [fallback] (e.g. the surface's default business);
///   3. the first of the customer's tagged businesses that resolves.
///
/// Returns null when none resolve. Pure (no widget/Firebase deps) so the
/// multi-business selection rule is unit-testable.
Business? resolveContractSeller(
  Customer customer,
  Business? Function(String id) lookup, {
  ServiceContract? contract,
  Business? fallback,
}) {
  final contractBusinessId = contract?.businessId ?? '';
  if (contractBusinessId.isNotEmpty) {
    final chosen = lookup(contractBusinessId);
    if (chosen != null) return chosen;
  }
  if (fallback != null) return fallback;
  for (final id in customer.businessIds) {
    final b = lookup(id);
    if (b != null) return b;
  }
  return null;
}

/// Glue between a customer surface (list row / detail header) and the pure
/// [Invoice] domain object + [InvoiceService] PDF generator. Resolves the
/// seller business, display currency and signatory from context, builds the
/// invoice and triggers the browser download, surfacing success / failure via
/// snackbars. Kept out of the widgets themselves so both call sites share one
/// code path and the business logic stays in [Invoice.forCustomer].
///
/// [businessId] scopes which of the customer's per-business contracts is billed:
///   * a specific id invoices that business's contract;
///   * null ("All Businesses") invoices the customer's sole contract when there
///     is exactly one, and otherwise asks the caller to pick a business (a
///     customer with contracts under several businesses can't be invoiced
///     ambiguously).
///
/// The seller shown on the invoice is the business the scoped *contract* was
/// sold under ([ServiceContract.businessId]) — not the customer's first tagged
/// business — so a customer spanning several businesses invoices correctly. An
/// explicitly supplied [business] only acts as a fallback when the contract
/// carries no (or an unresolvable) business id.
Future<void> generateCustomerInvoice(
  BuildContext context,
  Customer customer, {
  String? businessId,
  Business? business,
  CurrencyCode? currency,
}) async {
  final appState = context.read<AppState>();
  final data = context.read<DataController>();
  final user = appState.currentUser;

  // Scope to the contract in view. With a specific business selected we bill
  // that business's contract; under "All Businesses" we can only bill a lone
  // contract unambiguously.
  final ServiceContract? contract;
  if (businessId != null) {
    contract = customer.activeContractFor(businessId);
  } else if (customer.contractsByBusiness.length == 1) {
    contract = customer.contractsByBusiness.values.single.active;
  } else if (customer.contractsByBusiness.isEmpty) {
    contract = null;
  } else {
    if (context.mounted) {
      showErrorSnack(
          context,
          'This customer has contracts under multiple businesses. Select a '
          'business from the filter to invoice its contract.');
    }
    return;
  }

  // Resolve the seller business: the contract's chosen business first, then any
  // explicitly supplied fallback, then the first tagged business in scope.
  final seller = resolveContractSeller(
    customer,
    data.businessById,
    contract: contract,
    fallback: business ?? (businessId != null ? data.businessById(businessId) : null),
  );

  final invoice = Invoice.forCustomer(
    customer: customer,
    contract: contract,
    business: seller,
    currency: currency ?? seller?.currency ?? CurrencyCode.inr,
    issuerName: (user?.name.trim().isNotEmpty ?? false)
        ? user!.name.trim()
        : (seller?.name ?? 'Salesforce Business Manager'),
    issuerTitle: user?.role.label ?? '',
    now: DateTime.now(),
  );

  if (invoice.isEmpty) {
    if (context.mounted) {
      showErrorSnack(
          context,
          'No active service contract to invoice. Mark the deal won and '
          'capture a contract first.');
    }
    return;
  }

  try {
    final signatureBytes = await _loadSignatureBytes();
    await const InvoiceService()
        .generateAndDownload(invoice, signatureBytes: signatureBytes);
    if (context.mounted) {
      showSuccessSnack(context, 'Invoice ${invoice.number} downloaded');
    }
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}
