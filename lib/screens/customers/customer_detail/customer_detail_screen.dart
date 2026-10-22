import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/enums.dart';
import '../../../core/permissions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../models/app_settings.dart';
import '../../../models/customer.dart';
import '../../../models/entity_comment.dart';
import '../../../services/profit_calculation_service.dart';
import '../../../services/summaries/customer_summaries.dart';
import '../../../state/app_state.dart';
import '../../../state/data_controller.dart';
import '../../../state/filter_controller.dart';
import '../../../state/org_settings.dart';
import '../../../widgets/common/comment_thread.dart';
import '../../../widgets/common/team_access_card.dart';
import '../../../widgets/layout/detail_page.dart';
import '../../../widgets/layout/kpi_strip.dart';
import '../customers_screen.dart';
import '../invoice_action.dart';
import 'contacts_card.dart';
import 'deal_status_changer.dart';
import 'orders_card.dart';
import 'profile_card.dart';
import 'service_contract_card.dart';
import 'subscription_band.dart';

// The contact dialogs live in contacts_card.dart; keep them reachable from the
// screen's library path as before.
export 'contacts_card.dart' show ContactFormDialog, ContactViewDialog;

/// A full-screen customer profile: a header with the deal-status changer, a
/// strip of headline figures, the profile / contract / contacts / orders /
/// team sections, and the comment thread beside them.
class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  static const _service = ProfitCalculationService();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final filter = context.watch<FilterController>();
    final user = appState.currentUser;
    void back() => context.go(Routes.customers);

    if (data.loading && !data.loaded) {
      return DetailPage.loading(
          title: 'Customer', onBack: back, backLabel: 'Customers');
    }

    final customer = data.customerById(customerId);
    if (customer == null) {
      return DetailPage.notFound(
        title: 'Customer',
        onBack: back,
        backLabel: 'Customers',
        message: 'This customer may have been removed or is not accessible.',
      );
    }

    final t = context.tokens;
    final now = DateTime.now();

    // Businesses this customer is tagged to that are visible in the current
    // scope (a non-owner may not be able to resolve every tag to a name).
    final businesses = [
      for (final id in customer.businessIds)
        if (data.businessById(id) != null) data.businessById(id)!,
    ];
    final canEdit = user?.can(Permission.editCustomer) ?? false;
    final canCreate = user?.can(Permission.createCustomer) ?? false;
    final canDelete = user?.can(Permission.deleteCustomer) ?? false;
    final repo = appState.repository;

    // Orders placed by this customer. `ordersForCustomer` matches on the order's
    // customerReference over the already access-scoped order set, so a non-owner
    // only ever sees orders for businesses they can access.
    final orders = data.ordersForCustomer(customer.id);
    // A customer can span several businesses; use the first visible business's
    // currency as a fallback (per-contract displays use their own business's).
    final currency =
        businesses.isNotEmpty ? businesses.first.currency : CurrencyCode.inr;

    // The globally-selected business scopes which contracts show: a specific
    // business shows only its contract; "All Businesses" (null) shows every
    // visible business's contract. Non-owners only ever see businesses they are
    // assigned to (businesses is already filtered to what they can resolve), so
    // this never leaks a contract for an inaccessible business.
    final scopedId = filter.selectedBusinessId;
    final contractBusinesses = [
      for (final b in businesses)
        if ((scopedId == null || b.id == scopedId) &&
            customer.hasContractFor(b.id))
          b,
    ];
    // The headline subscription band is only unambiguous when exactly one
    // contract is in scope.
    final highlightBusiness =
        contractBusinesses.length == 1 ? contractBusinesses.first : null;
    final highlightContract = highlightBusiness == null
        ? null
        : customer.activeContractFor(highlightBusiness.id);

    // Revenue and profit only add up when every order bills in one currency.
    final orderCurrencies = {
      for (final o in orders)
        data.businessById(o.businessId)?.currency ?? CurrencyCode.inr,
    };
    final ordersCurrency = orderCurrencies.length <= 1
        ? (orderCurrencies.firstOrNull ?? currency)
        : null;
    final orderSummary = _service.summariseOrders(orders);
    final nextExpiry = _service.customerNextExpiry(customer, scopedId);
    final recurring =
        _service.customerAnnualRecurring(customer, scopedId, now: now);
    final recurringCurrency = highlightBusiness?.currency ?? currency;
    final expiredNext = nextExpiry != null &&
        nextExpiry.isBefore(DateTime(now.year, now.month, now.day));
    final margin = orderSummary.grossMargin;

    final subtitle = StringBuffer(customer.id);
    if (businesses.length == 1) {
      subtitle.write(' · ${businesses.first.name}');
    } else if (businesses.length > 1) {
      subtitle.write(' · ${businesses.length} businesses');
    }

    return DetailPage(
      title: customer.name,
      subtitle: subtitle.toString(),
      avatarName: customer.name,
      backLabel: 'Customers',
      onBack: back,
      status: DealStatusChanger(
        customer: customer,
        businesses: businesses,
        scopedBusinessId: scopedId,
        enabled: canEdit,
      ),
      meta: [
        if (customer.businessType.isNotEmpty)
          DetailMeta(Icons.category_outlined, customer.businessType,
              tooltip: 'Business type'),
        DetailMeta(Icons.groups_outlined, customer.size.label,
            tooltip: 'Company size'),
        if (customer.location.isNotEmpty)
          DetailMeta(Icons.location_on_outlined, customer.location),
        for (final b in businesses)
          DetailMeta(Icons.storefront_outlined, b.name,
              tooltip: 'Open business',
              onTap: () => context.go(Routes.businessDetailPath(b.id))),
      ],
      primaryAction: canEdit
          ? FilledButton.icon(
              onPressed: () => CustomersScreen.openForm(context, customer, null),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            )
          : null,
      actions: [
        if (contractBusinesses.isNotEmpty &&
            context.orgSettings((s) => s.features.isOn(AppFeature.invoices)))
          OutlinedButton.icon(
            onPressed: () => generateCustomerInvoice(
              context,
              customer,
              businessId: scopedId,
              business: highlightBusiness ??
                  (businesses.isNotEmpty ? businesses.first : null),
              currency: highlightBusiness?.currency ?? currency,
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Invoice'),
          ),
      ],
      menu: [
        if (canCreate)
          DetailAction(
            label: 'Duplicate',
            icon: Icons.copy_all_outlined,
            onSelected: () => CustomerActions.duplicate(context, customer),
          ),
        if (canDelete)
          DetailAction(
            label: 'Delete customer',
            icon: Icons.delete_outline,
            destructive: true,
            onSelected: () async {
              if (await CustomerActions.delete(context, customer) &&
                  context.mounted) {
                back();
              }
            },
          ),
      ],
      kpis: [
        KpiItem(
          label: 'Orders',
          value: '${orders.length}',
          icon: Icons.receipt_long_outlined,
          caption: orders.isEmpty ? 'None placed yet' : 'Placed by this customer',
        ),
        if (ordersCurrency != null) ...[
          KpiItem(
            label: 'Revenue',
            value: MoneyFormatter.compact(orderSummary.revenue, ordersCurrency),
            icon: Icons.trending_up,
            caption: 'Net of refunds',
          ),
          KpiItem(
            label: 'Gross profit',
            value:
                MoneyFormatter.compact(orderSummary.grossProfit, ordersCurrency),
            icon: Icons.savings_outlined,
            tone: orderSummary.grossProfit.isNegative ? t.error : t.success,
            caption:
                margin == null ? null : '${margin.toStringAsFixed(1)}% margin',
          ),
        ],
        if (recurring.isPositive &&
            (scopedId != null || contractBusinesses.length <= 1))
          KpiItem(
            label: 'Annual recurring',
            value: MoneyFormatter.compact(recurring, recurringCurrency),
            icon: Icons.autorenew,
            caption: 'Active contracts',
            tooltip: 'What the active contracts bill in a year '
                '(monthly ones times twelve). Excludes one-time charges.',
          ),
        if (nextExpiry != null)
          KpiItem(
            label: 'Next renewal',
            value: AppDate.format(nextExpiry),
            icon: Icons.event_repeat_outlined,
            tone: expiredNext ? t.error : null,
            caption: expiredNext ? 'Overdue' : null,
          ),
        KpiItem(
          label: 'Contacts',
          value: '${customer.contacts.length}',
          icon: Icons.groups_outlined,
        ),
      ],
      banner: highlightContract == null
          ? null
          : SubscriptionBand(
              contract: highlightContract,
              currency: highlightBusiness?.currency ?? currency,
            ),
      activity: DetailActivityColumn(
        activityAt: customer.lastActivityAt,
        comments: [
          for (final c in customer.comments)
            EntityComment(
              id: c.id,
              authorId: c.authorId,
              authorName: c.authorName,
              text: c.text,
              createdAt: c.createdAt,
            ),
        ],
        canComment: canEdit,
        onPost: (comment) async {
          await repo.saveCustomer(
            customer.copyWith(comments: [
              ...customer.comments,
              CustomerComment(
                id: comment.id,
                authorId: comment.authorId,
                authorName: comment.authorName,
                text: comment.text,
                createdAt: comment.createdAt,
              ),
            ]),
            isNew: false,
          );
        },
      ),
      children: [
        ProfileCard(customer: customer),
        for (final b in contractBusinesses)
          ServiceContractCard(
            customer: customer,
            business: b,
            active: customer.activeContractFor(b.id)!,
            history: customer.historyFor(b.id),
            showBusinessName: contractBusinesses.length > 1 || scopedId == null,
            canEdit: canEdit,
          ),
        ContactsCard(customer: customer, canEdit: canEdit),
        OrdersCard(orders: orders, businesses: businesses),
        TeamAccessCard(businesses: businesses),
      ],
    );
  }
}
