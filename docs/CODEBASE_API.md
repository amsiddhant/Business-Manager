# Codebase API Reference — Salesforce Business Manager

> **Read this file FIRST instead of re-reading `lib/**` after a context compaction.**
> It captures every constructor signature, getter, enum, and helper needed to
> author screens. All facts verified against source on 2026-09-19.

---

## 0. THE ONE LAYOUT RULE (do not violate)

Screens rendered inside `ShellRoute`/`AppShell` return a **plain widget** — normally:

```dart
Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [PageHeader(...), ...])
```

- **NO** `Scaffold`, **NO** outer `SingleChildScrollView`, **NO** `SafeArea`.
- `AppShell` already provides: scroll, `EdgeInsets.all(AppSpacing.lg)` padding, and `ConstrainedBox(maxWidth: 1400)`.
- **Auth screens** (`login_screen.dart`, `forgot_password_screen.dart`) DO use their own `Scaffold` — they render outside the shell.

All 11 shell screens have `const` no-arg constructors **except** `ProductDetailScreen({required String productId})`.

---

## 1. Screens to build (paths + routes)

| Screen file | Class | Route const | Notes |
|---|---|---|---|
| `lib/screens/dashboard/dashboard_screen.dart` | `DashboardScreen` | `Routes.dashboard` | scorecards + charts + tables |
| `lib/screens/businesses/businesses_screen.dart` | `BusinessesScreen` | `Routes.businesses` | |
| `lib/screens/products/products_screen.dart` | `ProductsScreen` | `Routes.products` | row tap → `context.go(Routes.productDetailPath(id))` |
| `lib/screens/products/product_detail_screen.dart` | `ProductDetailScreen({required String productId})` | `Routes.productDetail` | |
| `lib/screens/campaigns/campaigns_screen.dart` | `CampaignsScreen` | `Routes.campaigns` | |
| `lib/screens/orders/orders_screen.dart` | `OrdersScreen` | `Routes.orders` | |
| `lib/screens/expenses/expenses_screen.dart` | `ExpensesScreen` | `Routes.expenses` | dealer-mirrored rows are read-only |
| `lib/screens/dealers/dealers_screen.dart` | `DealersScreen` | `Routes.dealers` | |
| `lib/screens/reports/reports_screen.dart` | `ReportsScreen` | `Routes.reports` | CSV export |
| `lib/screens/users/users_screen.dart` | `UsersScreen` | `Routes.users` | owner-only |
| `lib/screens/settings/settings_screen.dart` | `SettingsScreen` | `Routes.settings` | Firebase wizard |

`app_router.dart` already imports all of these — just create the files.

---

## 2. State access (Provider)

```dart
final appState = context.watch<AppState>();     // or context.read for actions
final data     = context.watch<DataController>();
final filter   = context.watch<FilterController>();
final repo      = context.read<AppState>().repository;   // for CRUD
final user      = context.read<AppState>().currentUser;  // AppUser?  (gate UI with user.can(...))
```

### AppState (ChangeNotifier)
- `Repository repository`
- `AppUser? currentUser`
- `AuthStatus status` — enum `{ initializing, signedOut, signedIn }`
- `String? authError`
- `ConfigStore configStore`
- `Backend backend`
- `bool isFirebaseMode`
- `String appName`
- Actions: `signIn(loginOrEmail, pw)`, `signInWithGoogle()`, `signOut()`, `sendPasswordReset(loginOrEmail)`, `changePassword(cur, new)`, `refreshCurrentUser()`
- Firebase: `testFirebaseConfig(FirebaseConfig)`, `activateFirebase(FirebaseConfig)`, `deactivateFirebase()`
- `resetDemoData()` — throws `AppException` unless LocalBackend.
- **Default backend is Firebase** (`ConfigStore.isFirebaseMode` returns true unless 'local' is explicitly stored). `FirebaseConfig.defaultConfig` holds the bundled public config (project `mybusiness-manager-bm`). Google is the primary sign-in; demo mode keeps the username/password form.
- **First-Owner bootstrap:** `_onAuthChanged` calls `repository.bootstrapFirstOwnerIfNeeded(account)` when a signed-in account has no `users/{uid}` profile. It provisions the caller as OWNER + writes `meta/system` **iff** the project is unclaimed; otherwise returns null and the user is signed out with "no profile" — enforced in `firestore.rules` too.

### DataController (ChangeNotifier) — cached working set
Fields (already scoped to what user can access): `List<Business> businesses`, `products`, `campaigns`, `orders`, `expenses`, `dealers`.
Flags: `bool loading`, `bool loaded`, `String? error`.
Lifecycle: `load()`, `refresh()` (== load), `clear()`, `rebind(Repository)`.
**After any mutation call `await data.refresh()`.**

Scoped views:
- `List<Business> selectableBusinesses` — excludes archived
- `Business? businessById(id)`, `Product? productById(id)`
- `List<Product> productsFor(String? businessId)` (null = all)
- `campaignsFor(bizId?)`, `ordersFor(bizId?)`, `expensesFor(bizId?)`, `dealersFor(bizId?)`
- `campaignsForProduct(productId)`, `ordersForProduct(productId)`

### FilterController (ChangeNotifier) — global scope + period
- `String? selectedBusinessId` (null = All), `bool isAllBusinesses`
- `DateRange range` — **feed this to ProfitCalculationService**
- `String periodLabel`, `PeriodType periodType`, `FinancialYear financialYear`, `FinancialQuarter quarter`, `int calendarYear`, `int month`, `int monthYear`
- Setters: `selectBusiness(id?)`, `setFinancialYear(fy)`, `setPeriodType(t)`, `setQuarter(q)`, `setCalendarYear(y)`, `setMonth(m,y)`, `setCustomRange(DateRange)`
- Defaults to current FY.

**Currency for display:** if `filter.isAllBusinesses` → `CurrencyCode.inr`; else `data.businessById(filter.selectedBusinessId)?.currency ?? CurrencyCode.inr`.

---

## 3. Repository (all CRUD; IDs auto-generated on create; guards enforce perms)

`Repository({required Backend backend, AppUser? currentUser})`; `currentUser` getter.

- **Businesses:** `fetchBusinesses()`, `saveBusiness(Business, {required bool isNew})`, `archiveBusiness(String id)` (soft-delete)
- **Products:** `fetchProducts({String? businessId})`, `fetchProduct(id)`, `saveProduct(Product, {required bool isNew})`, `deleteProduct(id)`
- **Campaigns:** `fetchCampaigns({businessId})`, `saveCampaign(Campaign, {isNew})`, `deleteCampaign(id)`
- **Orders:** `fetchOrders({businessId})`, `saveOrder(Order, {isNew})`, `deleteOrder(id)`
- **Expenses:** `fetchExpenses({businessId})`, `saveExpense(Expense, {isNew})`, `deleteExpense(id)` — **throws AppException if `expense.isFromDealer`**
- **Dealers:** `fetchDealers({businessId})`, `saveDealer(Dealer, {isNew})` (mirrors `EXP-DLR-<id>` expense), `deleteDealer(id)` (removes mirror)
- **Users:** `fetchUsers()`, `fetchUserByUid(uid)`, `resolveUserByLogin(loginOrEmail)`, `createUser({required String loginId, name, email, UserRole role, List<String> assignedBusinessIds, String password})` (throws if role==owner), `saveUserProfile(AppUser)`, `setUserStatus(uid, AccountStatus)`, `touchLastLogin(uid)`
- **Audit:** `fetchAuditLogs({int limit=100})` — requires `Permission.manageSettings`

Note: **do NOT set `.id` when creating** — repo generates it. For updates, pass the model with its existing id.

---

## 4. ProfitCalculationService — `const ProfitCalculationService()`

All money math lives here. Feed it `filter.range` and lists scoped via `data.*For(filter.selectedBusinessId)`.

### Result types
- **`ProfitSummary`** `{revenue, productCost, marketingCost, operatingExpenses, orderCount, unitsSold}` (all `Money`/int) + getters `grossProfit`, `contributionProfit`, `netProfit`, `grossMargin` (double %), `netMargin` (double %), `totalExpenses`. `static const empty`.
- **`ProductProfit`** `{Product product, int orderCount, int unitsSold, Money revenue, productCost, marketingCost}` + `grossProfit`, `netProfit`, `margin` (double %).
- **`CampaignPerformance`** `{Campaign campaign, Money spend, Money attributedRevenue}` + `double? roi` (null if spend zero), `double? roas` (null if spend zero).
- **`TimeSeriesPoint`** `{String label, Money revenue, productCost, marketingCost, operatingExpenses, int orders}` + `netProfit`.
- **`CategorySlice(String label, Money amount)`**.

### Methods
- `summarise({required List<Order> orders, List<Campaign> campaigns, List<Expense> expenses, DateRange range}) → ProfitSummary`
- `productProfitability({required products, orders, campaigns, range}) → List<ProductProfit>`
- `campaignPerformance({required campaigns, orders, range}) → List<CampaignPerformance>`
- `timeSeries({required orders, campaigns, expenses, range, TimeBucket? bucket}) → List<TimeSeriesPoint>`
- `expenseBreakdown({required orders, campaigns, expenses, range}) → List<CategorySlice>` (already sorted desc, positives only)
- `marketingByPlatform(List<Campaign>, DateRange) → Map<CampaignPlatform, Money>`
- Lower-level: `recognisedOrdersIn(orders, range)`, `revenueOf(orders)`, `productCostOf(orders)`, `unitsSoldOf(orders)`, `marketingSpendIn(campaigns, range)`, `operatingExpensesIn(expenses, range, {bool excludeAdvertising=true})`, `proratedExpense(Expense, range)`

---

## 5. Models (constructors + copyWith)

All models are immutable with `copyWith`, `toMap()`, `fromMap()`. `id` is `required`.
`AuditFields audit` defaults to `const AuditFields()` — **do not set on create** (repo stamps it).

### Business
`Business({required id, required name, description='', type='', website='', CurrencyCode currency=inr, country='India', EntityStatus status=active, audit})`
Getter `isActive`. copyWith: name, description, type, website, currency, country, status, audit.

### Product
`Product({required id, required businessId, required name, description='', Money buyingPrice=zero, Money sellingPrice=zero, url='', sku='', category='', EntityStatus status=active, audit})`
Getter `isActive`. copyWith (no id/businessId): name, description, buyingPrice, sellingPrice, url, sku, category, status, audit.

### Campaign
`Campaign({required id, required businessId, required productId, required name, CampaignPlatform platform=other, type='', DateTime? startDate, DateTime? endDate, Money budget=zero, Money amountInvested=zero, int impressions=0, clicks=0, conversions=0, CampaignStatus status=draft, url='', notes='', audit})`
Getters: `DateTime? spendDate` (startDate ?? createdAt), `double ctr`, `double conversionRate`. copyWith (no id/businessId): productId, name, platform, type, startDate, endDate, budget, amountInvested, impressions, clicks, conversions, status, url, notes, audit.

### Order
`Order({required id, required businessId, required productId, required productName, DateTime? orderDate, int quantity=1, Money sellingCost=zero, discount=zero, shippingRevenue=zero, otherRevenue=zero, buyingCost=zero, marketingAllocation=zero, OrderStatus status=pending, customerReference='', notes='', audit})`
Getters: `Money productRevenue` (=sellingCost*qty), `totalRevenue`, `productCost` (=buyingCost*qty), `grossProfit`, `bool isRecognised`, `recognisedRevenue`, `recognisedProductCost`. copyWith (no id/businessId): productId, productName, orderDate, quantity, sellingCost, discount, shippingRevenue, otherRevenue, buyingCost, marketingAllocation, status, customerReference, notes, audit.

### Expense
`Expense({required id, required businessId, required name, ExpenseCategory category=other, description='', Money amount=zero, RecurrenceFrequency frequency=oneTime, DateTime? startDate, DateTime? endDate, vendor='', EntityStatus status=active, notes='', String? sourceDealerId, audit})`
Getters: `isActive`, `bool isFromDealer` (sourceDealerId != null), `Money annualisedAmount`. copyWith (no id/businessId): name, category, description, amount, frequency, startDate, endDate, vendor, status, notes, sourceDealerId, audit.

### Dealer
`Dealer({required id, required businessId, required name, url='', description='', Money cost=zero, RecurrenceFrequency costFrequency=monthly, DateTime? startDate, DateTime? endDate, EntityStatus status=active, contactName='', contactInfo='', notes='', audit})`
Getter `isActive`. copyWith (no id/businessId): name, url, description, cost, costFrequency, startDate, endDate, status, contactName, contactInfo, notes, audit.

### AppUser
`AppUser({required uid, required loginId, required name, required email, required UserRole role, AccountStatus status=active, List<String> assignedBusinessIds=const[], Set<Permission> grantedPermissions=const{}, revokedPermissions=const{}, DateTime? lastLoginAt, audit})`
Getters: `isOwner`, `isActive`, `Set<Permission> permissions`, `bool can(Permission)`, `bool canAccessBusiness(businessId)`. copyWith (no uid): loginId, name, email, role, status, assignedBusinessIds, grantedPermissions, revokedPermissions, lastLoginAt, audit.

### FirebaseConfig
`FirebaseConfig({required apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId, measurementId=''})`
Getter `bool isComplete`. copyWith all fields. **Public client values only — never store secrets.**

---

## 6. Enums (`lib/core/enums.dart`) — all have `.wire`, `.label`, `.fromWire()`

- **UserRole**: `user, admin, owner` — `.isOwner/.isAdmin/.isUser`, `.atLeast(other)`. (owner highest)
- **EntityStatus**: `active, inactive, archived`
- **AccountStatus**: `active, disabled`
- **CurrencyCode**: `inr(₹), usd($), eur(€), gbp(£)` — also `.symbol`
- **CampaignPlatform**: `meta, google, tiktok, youtube, linkedin, other`
- **CampaignStatus**: `draft, active, paused, completed, cancelled`
- **OrderStatus**: `pending, confirmed, processing, shipped, delivered, cancelled, returned` — `.contributesToRevenue` (false for cancelled/returned)
- **RecurrenceFrequency**: `oneTime, monthly, quarterly, halfYearly, yearly` — `.occurrencesPerYear` (0/12/4/2/1), `.isRecurring`
- **ExpenseCategory**: `domain, crm, hosting, dealer, software, subscription, paymentGateway, shipping, office, employee, advertising, other`
- **AuditAction**: `create, update, delete, archive, login, logout`

### Permission (`lib/core/permissions.dart`)
`viewDashboard, viewBusiness, createBusiness, editBusiness, deleteBusiness, viewProduct, createProduct, editProduct, deleteProduct, viewCampaign, createCampaign, editCampaign, deleteCampaign, viewOrder, createOrder, editOrder, deleteOrder, viewExpense, createExpense, editExpense, deleteExpense, viewDealer, createDealer, editDealer, deleteDealer, viewReports, exportData, manageUsers, configureFirebase, manageSettings`

`Permissions.forRole(role)`, `Permissions.resolve(role, {granted, revoked})`.
- USER: view + create on product/campaign/order; view business/expense/dealer/reports/dashboard. No deletes/edits/admin.
- ADMIN: full CRUD on product/campaign/order/expense/dealer within assigned businesses + viewReports + exportData. No manageUsers/configureFirebase/manageSettings/business CRUD.
- OWNER: everything.

**Gate UI with `user.can(Permission.x)`. Repo enforces the same — service layer is source of truth.**

### date_utils (`lib/core/utils/date_utils.dart`)
- `DateRange(start, end)` — `.contains(date)`, `.days`, `.overlapDays(other)`, `toString()` → "dd-MMM-yyyy → dd-MMM-yyyy"
- `FinancialYear(startYear)` — `.forDate(date)` factory, `.endYear`, `.range`, `.previous`, `.next`, `.label` ("FY 2026-27")
- `enum PeriodType { financialYear, calendarYear, quarter, month, custom }` — `.label`
- `enum FinancialQuarter { q1, q2, q3, q4 }` — `.label` ("Q1 (Apr–Jun)"), `.startMonth`
- `AppDate.format(DateTime?)` ("dd-MMM-yyyy", "—" if null), `.short(d)`, `.monthYear(d)`, `.iso(d)`, `.tryParseIso(s)`, `.dayOnly(d)`
- `enum TimeBucket { month, quarter, year }`, `bucketForRange(range) → TimeBucket`

### money (`lib/core/utils/money.dart`)
- `Money(int minor)`, `Money.zero`, `Money.fromMajor(num)`, `Money.parse(String)`, `.major` (double), `.minor`
- Operators: `+ - * /` (`*`/`/` take num), `> < >= <=`, `== hashCode`
- `.isZero .isNegative .isPositive`
- `MoneyFormatter.format(money, currency)` (drops decimals if whole), `.formatPrecise(money, cur)` (always 2dp), `.compact(money, cur)` (₹1.2L/₹3.4Cr/$1.2K)
- `PercentFormatter.format(double, {decimals=1})` ("37.8%", "—" if NaN/inf), `.roas(double?)` ("2.5x" / "N/A")

### validators (`lib/core/validators.dart`)
`Validators.required(v, {field})`, `.email(v)`, `.password(v, {min=6})`, `.url(v, {requiredField})`, `.nonNegativeNumber(v, {field})`, `.optionalNonNegativeNumber(v, {field})`, `.positiveInteger(v, {field})`, `.compose([...])`

### app_exception (`lib/core/app_exception.dart`)
`AppException(message, {code})`, `PermissionDeniedException([msg])`, `NotFoundException([msg])`, `ErrorMapper.friendly(Object) → String`.

### routing (`lib/core/routing/app_routes.dart`)
`Routes.{login, forgotPassword, dashboard, businesses, products, productDetail, campaigns, orders, expenses, dealers, reports, users, settings}`; `Routes.productDetailPath(id)`.
`kNavDestinations` (List<NavDestination>) already drives the sidebar. Navigate with `context.go(Routes.x)` (import `go_router`).

---

## 7. Reusable widgets

### Layout
- `PageHeader({required String title, String? subtitle, List<Widget> actions = const []})` — `lib/widgets/common/page_header.dart`
- `AppShell` / `AppHeader` / `AppSidebar` — already wired; screens don't touch these.

### Cards / states — `lib/widgets/common/`
- `AppCard({required Widget child, EdgeInsetsGeometry padding=EdgeInsets.all(xl), VoidCallback? onTap})`
- `SectionCard({required String title, required Widget child, String? subtitle, Widget? trailing, padding})`
- `LoadingView({String? label})`, `SkeletonBox({width, height=16, radius})`
- `EmptyView({required String title, String? message, IconData icon=inbox_outlined, Widget? action})`
- `ErrorView({required String message, VoidCallback? onRetry})`
- `Scorecard({required String label, required String value, required IconData icon, Color accent=primary, String? caption, Color? captionTone, String? tooltip})` — self-wraps in AppCard(padding lg)
- `StatusBadge({required String label, BadgeTone tone=neutral})` + factories `.entity(EntityStatus)`, `.account(AccountStatus)`, `.order(OrderStatus)`, `.campaign(CampaignStatus)`, `.role(UserRole)`. `enum BadgeTone { neutral, success, warning, error, info, primary }`
- `CurrencyText(Money money, {CurrencyCode currency=inr, TextStyle? style, bool colorNegative=true, bool precise=false})`
- `SearchField({required ValueChanged<String> onChanged, String hintText='Search…', double? width, Duration debounce})` (debounced)

### Data table — `lib/widgets/common/data_table_card.dart`
- `AppColumn<T>({required String label, required Widget Function(T) cell, bool numeric=false, Comparable Function(T)? sortValue, double? width})`
- `AppDataTable<T>({required List<T> rows, required List<AppColumn<T>> columns, String searchText='', String Function(T)? searchableText, int rowsPerPage=10, String emptyTitle, String? emptyMessage, Widget? emptyAction, void Function(T)? onRowTap, int? initialSortColumn, bool initialSortAscending=true})`
- **Self-wraps in AppCard**, built-in search/sort/pagination/horizontal-scroll. Give a `searchableText` to enable the external `searchText` filter.

### Forms — `lib/widgets/forms/`
- `FormDialog({required String title, required Widget child, required Future<bool> Function() onSubmit, String submitLabel='Save', double width=560})` — spinner + no double-submit; pops(true) when onSubmit returns true. Show via `showDialog<bool>(context: ..., builder: (_) => ...)`.
- `FormRow(List<Widget> children)` — side-by-side desktop / stacked mobile.
- `FormGap()` — SizedBox(height: lg).
- `LabeledField({required label, required child, isRequired=false, helper})`
- `AppTextField({required String label, TextEditingController? controller, String? initialValue, String? Function(String?)? validator, TextInputType? keyboardType, bool isRequired=false, String? hintText, String? helper, int maxLines=1, bool obscureText=false, ValueChanged<String>? onChanged, List<TextInputFormatter>? inputFormatters, String? prefixText, bool enabled=true})`
- `AppMoneyField({required String label, required TextEditingController controller, bool isRequired=false, String symbol='₹', validator, helper})` — parse with `Money.parse(controller.text)`; prefill with `money.major.toString()` or `MoneyFormatter` (prefer plain `.major`).
- `AppDropdown<T>({required String label, required T? value, required List<T> items, required String Function(T) itemLabel, required ValueChanged<T?> onChanged, bool isRequired=false, helper})`
- `AppDateField({required String label, required DateTime? value, required ValueChanged<DateTime?> onChanged, bool isRequired=false, helper, DateTime? firstDate, DateTime? lastDate})`

### Dialogs — `lib/widgets/common/confirm_dialog.dart`
- `Future<bool> showConfirmDialog(context, {title, message, confirmLabel='Delete', cancelLabel='Cancel', bool destructive=true})`
- `void showSuccessSnack(context, String)`
- `void showErrorSnack(context, Object error)` (maps via ErrorMapper)

### Charts — `lib/widgets/charts/`
- `ChartCard({required String title, required Widget child, String? subtitle, Widget? trailing, double height=280, bool isEmpty=false, String emptyMessage})` — self-wraps in AppCard, sized box height, empty state built-in.
- `ChartLegendDot({required Color color, required String label})`
- `RevenueExpenseChart({required List<TimeSeriesPoint> points, required CurrencyCode currency})` — grouped bars + built-in legend.
- `ExpenseDonutChart({required List<CategorySlice> slices, required CurrencyCode currency})`
- `CategoryBarChart({required List<String> labels, required List<Money> values, required CurrencyCode currency, Color color=primary})`
- `TrendLineChart({required List<String> labels, required List<double> values, Color color=primary, CurrencyCode? currency})` — money axis if currency set, else integer.

---

## 8. Theme tokens — `lib/core/theme/`

`AppColors`: `primary(0xFF582DD3)`, `primaryDark`, `primaryLight`, `primarySurface`, `background`, `card`, `surfaceAlt`, `border`, `borderStrong`, `textPrimary`, `textSecondary`, `textTertiary`, `textOnPrimary`, `success`, `successSurface`, `warning`, `warningSurface`, `error`, `errorSurface`, `info`, `infoSurface`, `List<Color> chartSeries` (10).

`AppSpacing`: `xs=4, sm=8, md=12, lg=16, xl=24, xxl=32`; `radius=12, radiusSm=8, radiusLg=16`; `mobileMax=640, tabletMax=1024`.
`AppTheme.light`, `AppTheme.cardShadow`.

`Responsive.isMobile/isTablet/isDesktop(context)`, `.of(context) → ScreenType`, `.showInlineSidebar(context)`. `ResponsiveBuilder({required mobile, tablet, desktop})`.

Dart 3 null-aware element: `?trailing,` inside a children list is valid (used in chart_card.dart / app_card.dart) — safe to use.

---

## 9. Demo seed (`lib/data/demo_seed.dart`) — for reference/tests

`DemoSeed(DateTime now)`; static creds: `ownerLogin='owner'`, `adminLogin='admin'`, `userLogin='staff'`, `password='demo1234'`; emails `owner@demo.com`/`admin@demo.com`/`staff@demo.com`.
Businesses `BIZ-00001` (Aurora Gadgets), `BIZ-00002` (Bloom Organics). Products `PROD-00001..06`, campaigns `CMP-00001..06`, dealers `DLR-00001/02`, expenses `EXP-*`. Orders generated across the FY.

`ConfigStore`: `isFirebaseMode` (**true by default** — only explicit 'local' opts out), `setFirebaseMode(bool)`, `firebaseConfig` (getter — **returns `FirebaseConfig.defaultConfig` when nothing saved**), `saveFirebaseConfig(cfg)`, `clearFirebaseConfig()`, `appName`, `setAppName(s)`, `dateFormat`, `setDateFormat(s)`.

`FirebaseConfig`: fields `apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId, measurementId, databaseURL`; `isComplete`; `toMap/fromMap/copyWith`; static `FirebaseConfig.defaultConfig` (bundled public web config). `databaseURL` is stored/passed to `FirebaseOptions` but unused (data layer is Firestore).

`Backend` interface adds `Future<AuthAccount> signInWithGoogle()` (FirebaseBackend: `GoogleAuthProvider` + `signInWithPopup`; LocalBackend: signs in demo Owner). `AuthAccount` gains `String displayName`. `Collections.meta = 'meta'`.

---

## 10. Screen authoring checklist

1. Return `Column(crossAxisAlignment: stretch, children: [PageHeader(...), ...])`. No Scaffold/scroll.
2. `context.watch<DataController>()` for `loading`/`error`/`loaded` → show `LoadingView`/`ErrorView(onRetry: data.refresh)` early.
3. Scope lists via `data.*For(filter.selectedBusinessId)`.
4. Metrics via `const ProfitCalculationService()` over `filter.range`. Never compute money in the widget.
5. Currency = selected business currency (INR for All Businesses).
6. Create/Edit → `FormDialog` in a StatefulWidget with `GlobalKey<FormState>`; on submit call `repo.saveX(...)`, then `await data.refresh()`, `showSuccessSnack`, return true. Catch → `showErrorSnack`, return false.
7. Delete/archive → `showConfirmDialog` then `repo.deleteX`/`archiveBusiness`, refresh, snack.
8. Gate every action button with `user.can(Permission.x)` (and `user.isOwner` where owner-only). New-business select needs a business chosen (can't create product without one).
9. Grid layout: use `LayoutBuilder`/`Wrap` or `Responsive` for scorecard/chart grids (e.g. `Wrap` with fixed-width cards, or `Row` of `Expanded` on desktop).
