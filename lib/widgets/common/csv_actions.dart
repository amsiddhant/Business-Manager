import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/csv_import.dart';
import '../../core/utils/entity_csv.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import 'confirm_dialog.dart';

/// Glue between the Products / Customers list surfaces and the pure CSV layer
/// ([CsvExport], [CsvImport], [ProductCsv], [CustomerCsv]). Kept out of the
/// widgets themselves — like [generateCustomerInvoice] — so both screens share
/// one code path and no import/export logic lives inside build methods.
///
/// Export emits exactly the rows the caller passes (the already access- and
/// filter-scoped visible list). Import gates on the create permission, resolves
/// every referenced business against the caller's accessible set (the
/// repository re-checks on save regardless), saves sequentially, and reports a
/// per-row success / failure summary.

// ---- Products ---------------------------------------------------------------

/// Downloads [products] (the currently-visible, scoped list) as a CSV. Gated on
/// [Permission.exportData] (the same gate the Reports screen uses); callers
/// should also disable the trigger when the user lacks it.
void exportProductsCsv(BuildContext context, List<Product> products) {
  if (!(context.read<AppState>().currentUser?.can(Permission.exportData) ??
      false)) {
    showErrorSnack(context, "You don't have permission to export data.");
    return;
  }
  if (products.isEmpty) return;
  final data = context.read<DataController>();
  String bizName(String id) => data.businessById(id)?.name ?? id;
  CsvExport.download(
    filename: 'products',
    header: ProductCsv.header,
    rows: [
      for (final p in products)
        ProductCsv.row(p, businessName: bizName(p.businessId)),
    ],
  );
  showSuccessSnack(context, _exportedMessage(products.length, 'product'));
}

/// Picks a CSV file and bulk-creates products from it. Gated on
/// [Permission.createProduct]; every row is scoped to a business the caller can
/// access (via the current filter as the fallback for rows that name none).
Future<void> importProductsCsv(BuildContext context) async {
  final appState = context.read<AppState>();
  final data = context.read<DataController>();
  final filter = context.read<FilterController>();
  final user = appState.currentUser;

  if (!(user?.can(Permission.createProduct) ?? false)) {
    showErrorSnack(context, "You don't have permission to import products.");
    return;
  }
  final businesses = data.selectableBusinesses;
  if (businesses.isEmpty) {
    showErrorSnack(context, 'Create a business before importing products.');
    return;
  }

  final doc = await CsvImport.pickAndDecode();
  if (!context.mounted) return;
  if (doc == null) {
    showErrorSnack(context, 'That file has no rows to import.');
    return;
  }

  final resolver = BusinessResolver(businesses);
  // Only trust the current filter as the fallback target when it names a
  // business actually in scope (never null/All, never an archived/hidden id).
  final selectedId = filter.selectedBusinessId;
  final fallback =
      (selectedId != null && resolver.contains(selectedId)) ? selectedId : null;
  final report = ImportReport();
  final repo = appState.repository;

  // Parse every row first (pure, no I/O); collect the ones that build cleanly.
  final parsed = <ParsedRow<Product>>[];
  for (var i = 0; i < doc.rows.length; i++) {
    final fileRow = i + 2; // header is row 1
    try {
      parsed.add(ParsedRow(
        fileRow,
        ProductCsv.parseRow(doc, doc.rows[i], resolver,
            fallbackBusinessId: fallback),
      ));
    } on FormatException catch (e) {
      report.addError(fileRow, e.message);
    } catch (e) {
      report.addError(fileRow, ErrorMapper.friendly(e));
    }
  }

  // Save sequentially: each save mints its id by scanning the collection, so
  // parallel saves would collide on the same id and overwrite one another.
  for (final row in parsed) {
    try {
      await repo.saveProduct(row.model, isNew: true);
      report.created++;
    } catch (e) {
      report.addError(row.fileRow, ErrorMapper.friendly(e));
    }
  }

  if (report.created > 0) await data.refresh();
  if (!context.mounted) return;
  await _reportImport(context, entity: 'product', report: report);
}

// ---- Customers --------------------------------------------------------------

/// Downloads [customers] (the currently-visible, scoped list) as a CSV. Gated
/// on [Permission.exportData], mirroring [exportProductsCsv] and Reports.
void exportCustomersCsv(BuildContext context, List<Customer> customers) {
  if (!(context.read<AppState>().currentUser?.can(Permission.exportData) ??
      false)) {
    showErrorSnack(context, "You don't have permission to export data.");
    return;
  }
  if (customers.isEmpty) return;
  final data = context.read<DataController>();
  String bizName(String id) => data.businessById(id)?.name ?? id;
  CsvExport.download(
    filename: 'customers',
    header: CustomerCsv.header,
    rows: [
      for (final c in customers) CustomerCsv.row(c, businessName: bizName),
    ],
  );
  showSuccessSnack(context, _exportedMessage(customers.length, 'customer'));
}

/// Picks a CSV file and bulk-creates customers from it. Gated on
/// [Permission.createCustomer]; every referenced business must be accessible.
Future<void> importCustomersCsv(BuildContext context) async {
  final appState = context.read<AppState>();
  final data = context.read<DataController>();
  final filter = context.read<FilterController>();
  final user = appState.currentUser;

  if (!(user?.can(Permission.createCustomer) ?? false)) {
    showErrorSnack(context, "You don't have permission to import customers.");
    return;
  }
  final businesses = data.selectableBusinesses;
  if (businesses.isEmpty) {
    showErrorSnack(context, 'Create a business before importing customers.');
    return;
  }

  final doc = await CsvImport.pickAndDecode();
  if (!context.mounted) return;
  if (doc == null) {
    showErrorSnack(context, 'That file has no rows to import.');
    return;
  }

  final resolver = BusinessResolver(businesses);
  // Only trust the current filter as the fallback target when it names a
  // business actually in scope (never null/All, never an archived/hidden id).
  final selectedId = filter.selectedBusinessId;
  final fallback =
      (selectedId != null && resolver.contains(selectedId)) ? selectedId : null;
  final report = ImportReport();
  final repo = appState.repository;

  final parsed = <ParsedRow<Customer>>[];
  for (var i = 0; i < doc.rows.length; i++) {
    final fileRow = i + 2;
    try {
      parsed.add(ParsedRow(
        fileRow,
        CustomerCsv.parseRow(doc, doc.rows[i], resolver,
            fallbackBusinessId: fallback),
      ));
    } on FormatException catch (e) {
      report.addError(fileRow, e.message);
    } catch (e) {
      report.addError(fileRow, ErrorMapper.friendly(e));
    }
  }

  for (final row in parsed) {
    try {
      await repo.saveCustomer(row.model, isNew: true);
      report.created++;
    } catch (e) {
      report.addError(row.fileRow, ErrorMapper.friendly(e));
    }
  }

  if (report.created > 0) await data.refresh();
  if (!context.mounted) return;
  await _reportImport(context, entity: 'customer', report: report);
}

// ---- Shared feedback --------------------------------------------------------

String _exportedMessage(int count, String entity) =>
    '$count ${count == 1 ? entity : '${entity}s'} exported';

/// Surfaces the outcome of a bulk import: a plain success snack when every row
/// imported, otherwise a dialog listing the per-row failures alongside the
/// created / failed counts.
Future<void> _reportImport(
  BuildContext context, {
  required String entity,
  required ImportReport report,
}) async {
  if (!report.hasErrors) {
    showSuccessSnack(
        context,
        report.created == 0
            ? 'No new ${entity}s were imported.'
            : _exportedMessage(report.created, entity)
                .replaceFirst('exported', 'imported'));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _ImportResultDialog(entity: entity, report: report),
  );
}

/// A summary dialog shown after an import that had at least one failed row.
class _ImportResultDialog extends StatelessWidget {
  const _ImportResultDialog({required this.entity, required this.report});

  final String entity;
  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final title =
        report.created == 0 ? 'Import failed' : 'Import finished with errors';
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text('${report.created} imported',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: AppSpacing.lg),
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text('${report.failed} skipped',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'These rows could not be imported:',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 260),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: AppColors.border),
                ),
                child: Scrollbar(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: report.errors.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, i) => Text(
                      report.errors[i],
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
