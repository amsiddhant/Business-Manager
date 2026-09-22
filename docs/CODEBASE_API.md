# Codebase API Reference — Salesforce Business Manager

> **Read this file FIRST instead of re-reading `lib/**` after a context compaction.**
> It captures every constructor signature, getter, enum, and helper needed to
> author screens. All facts verified against source on 2026-09-22.

---

## 0. THE ONE LAYOUT RULE (do not violate)

Screens rendered inside `ShellRoute`/`AppShell` return a **plain widget** — normally:

```dart
Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [PageHeader(...), ...])
```

- **NO** `Scaffold`, **NO** outer `SingleChildScrollView`, **NO** `SafeArea`.
- `AppShell` already provides: scroll, `EdgeInsets.all(AppSpacing.lg)` padding, and `ConstrainedBox(maxWidth: 1400)`.
- **Auth screens** (`login_screen.dart`, `forgot_password_screen.dart`) DO use their own `Scaffold` — they render outside the shell.

The **12 list/section shell screens** have `const` no-arg constructors (Dashboard, Businesses, Products, Campaigns, Orders, Expenses, Dealers, **Customers**, Reports, Users, Settings, plus the `PlaceholderScreen`). The **7 detail screens** each take one required id: `BusinessDetailScreen({required String businessId})`, `ProductDetailScreen({required String productId})`, `CampaignDetailScreen({required String campaignId})`, `OrderDetailScreen({required String orderId})`, `ExpenseDetailScreen({required String expenseId})`, `DealerDetailScreen({required String dealerId})`, `CustomerDetailScreen({required String customerId})`. Detail screens follow the SAME layout rule (plain `Column`, no Scaffold).

---

## 1. Screens to build (paths + routes)

| Screen file | Class | Route const | Notes |
|---|---|---|---|
| `lib/screens/dashboard/dashboard_screen.dart` | `DashboardScreen` | `Routes.dashboard` | scorecards + charts + tables |
| `lib/screens/businesses/businesses_screen.dart` | `BusinessesScreen` | `Routes.businesses` | row tap → `context.go(Routes.businessDetailPath(id))` |
| `lib/screens/businesses/business_detail_screen.dart` | `BusinessDetailScreen({required String businessId})` | `Routes.businessDetail` | |
| `lib/screens/products/products_screen.dart` | `ProductsScreen` | `Routes.products` | row tap → `context.go(Routes.productDetailPath(id))` |
| `lib/screens/products/product_detail_screen.dart` | `ProductDetailScreen({required String productId})` | `Routes.productDetail` | |
| `lib/screens/campaigns/campaigns_screen.dart` | `CampaignsScreen` | `Routes.campaigns` | row tap → `Routes.campaignDetailPath(id)` |
| `lib/screens/campaigns/campaign_detail_screen.dart` | `CampaignDetailScreen({required String campaignId})` | `Routes.campaignDetail` | |
| `lib/screens/orders/orders_screen.dart` | `OrdersScreen` | `Routes.orders` | refund action; row tap → `Routes.orderDetailPath(id)` |
| `lib/screens/orders/order_detail_screen.dart` | `OrderDetailScreen({required String orderId})` | `Routes.orderDetail` | |
| `lib/screens/expenses/expenses_screen.dart` | `ExpensesScreen` | `Routes.expenses` | dealer-mirrored rows are read-only; row tap → `Routes.expenseDetailPath(id)` |
| `lib/screens/expenses/expense_detail_screen.dart` | `ExpenseDetailScreen({required String expenseId})` | `Routes.expenseDetail` | |
| `lib/screens/dealers/dealers_screen.dart` | `DealersScreen` | `Routes.dealers` | row tap → `Routes.dealerDetailPath(id)` |
| `lib/screens/dealers/dealer_detail_screen.dart` | `DealerDetailScreen({required String dealerId})` | `Routes.dealerDetail` | |
| `lib/screens/customers/customers_screen.dart` | `CustomersScreen` | `Routes.customers` | CRM; row tap → `Routes.customerDetailPath(id)` |
| `lib/screens/customers/customer_detail_screen.dart` | `CustomerDetailScreen({required String customerId})` | `Routes.customerDetail` | contacts, per-business contracts, comments, invoice |
| `lib/screens/reports/reports_screen.dart` | `ReportsScreen` | `Routes.reports` | CSV export |
| `lib/screens/users/users_screen.dart` | `UsersScreen` | `Routes.users` | owner-only |
| `lib/screens/settings/settings_screen.dart` | `SettingsScreen` | `Routes.settings` | Firebase wizard |

`app_router.dart` (18 GoRoutes under the ShellRoute, plus login + forgotPassword outside it = 20 total) already imports all of these — just create the files. Each detail route reads its id from `state.pathParameters['id']!`. `PermissionGuard` wraps every route by permission (or `ownerOnly` for Users). Nav-visible screens are driven by `kNavDestinations` (Customers uses `Icons.people_outline`, gated on `Permission.viewCustomer`); detail routes are not in the sidebar.

**Customer-flow helpers** (not screens, live under `lib/screens/customers/` or dialogs):
- `CustomerFormDialog` — create/edit a customer (name, business tags, deal status, per-business contract fields). FormDialog child: persists via `repo.saveCustomer` in `_submit`, returns bool.
- `ServiceContractFormDialog` — edit/renew the `ServiceContract` for one tagged business. FormDialog child.
- `ContactFormDialog` / `ContactViewDialog` — add/edit a contact vs. read-only view (every field with a `CopyButton`, live search on the list).
- `generateCustomerInvoice(...)` / `Invoice.forCustomer(...)` — builds the printable invoice model.
- `ChangePasswordDialog` — `lib/screens/auth/change_password_dialog.dart`.

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
- `String appName`, `setAppName(String)` — persists via ConfigStore.
- `String dateFormat`, `setDateFormat(String)` — persists AND calls `AppDate.configureDisplayFormat(pattern)` so `AppDate.format` uses it app-wide.
- Actions: `signIn(loginOrEmail, pw)`, `signInWithGoogle()`, `signOut()`, `sendPasswordReset(loginOrEmail)`, `changePassword(cur, new)`, `refreshCurrentUser()`
- Firebase: `testFirebaseConfig(FirebaseConfig)`, `activateFirebase(FirebaseConfig)`, `deactivateFirebase()`
- `resetDemoData()` — throws `AppException` unless LocalBackend.
- **Default backend is Firebase** (`ConfigStore.isFirebaseMode` returns true unless 'local' is explicitly stored). `FirebaseConfig.defaultConfig` holds the bundled public config (project `mybusiness-manager-bm`). Google is the primary sign-in; demo mode keeps the username/password form.
- **First-Owner bootstrap & access-request flow** (`_onAuthChanged`, when a signed-in account has no `users/{uid}` profile):
  1. calls `repository.bootstrapFirstOwnerIfNeeded(account)` → provisions the caller as OWNER + writes `meta/system` **iff** the project is unclaimed (returns the new OWNER `AppUser`).
  2. if still null (project already claimed) → `repository.recordAccessRequest(account)` then `signOut()` with "awaiting approval".
  3. a **disabled** account is signed out with "disabled".
  Enforced in `firestore.rules` too.

### DataController (ChangeNotifier) — cached working set
Fields (already scoped to what user can access): `List<Business> businesses`, `products`, `campaigns`, `orders`, `expenses`, `dealers`, `customers`.
Flags: `bool loading`, `bool loaded`, `String? error`, `List<String> warnings`, `bool hasWarnings`.
Lifecycle: `load()`, `refresh()` (== load), `clear()`, `rebind(Repository)`.
**After any mutation call `await data.refresh()`.**

**Per-collection load isolation** (see §11.4): only `businesses` is *essential* — if it fails, `error` is set and the app shows an error state. Every other collection loads through a `guard` that, on failure, degrades to `[]` and appends a human-readable line to `warnings` instead of blanking the whole app. So one denied query (e.g. a rules mismatch on customers) can't take down the dashboard.

Scoped views:
- `List<Business> selectableBusinesses` — excludes archived
- `Business? businessById(id)`, `Product? productById(id)`, `Campaign? campaignById(id)`, `Order? orderById(id)`, `Expense? expenseById(id)`, `Dealer? dealerById(id)`, `Customer? customerById(id)`
- `List<Product> productsFor(String? businessId)` (null = all)
- `campaignsFor(bizId?)`, `ordersFor(bizId?)`, `expensesFor(bizId?)`, `dealersFor(bizId?)`
- `List<Customer> customersFor(String? businessId)` — matches `customer.businessIds.contains(id)` (null = all)
- `campaignsForProduct(productId)`, `ordersForProduct(productId)`
- `List<Order> ordersForCustomer(String customerId)` — orders whose `customerReference` matches
- `Dealer? dealerForExpense(String expenseId)` — decodes an `EXP-DLR-<id>` mirror expense back to its dealer
- `Iterable<DateTime> activityDates({String? businessId})` — every dated activity across the scope (for period pickers)

### FilterController (ChangeNotifier) — global scope + period
- `String? selectedBusinessId` (null = All), `bool isAllBusinesses`
- `DateRange range` — **feed this to ProfitCalculationService**
- `String periodLabel`, `PeriodType periodType`, `FinancialYear financialYear`, `FinancialQuarter quarter`, `int calendarYear`, `int month`, `int monthYear`
- Setters: `selectBusiness(id?)`, `setFinancialYear(fy)`, `setPeriodType(t)`, `setQuarter(q)`, `setCalendarYear(y)`, `setMonth(m,y)`, `setCustomRange(DateRange)`
- Defaults to current FY.

**Currency for display:** if `filter.isAllBusinesses` → `CurrencyCode.inr`; else `data.businessById(filter.selectedBusinessId)?.currency ?? CurrencyCode.inr`.

---

## 3. Repository (all CRUD; IDs auto-generated on create; guards enforce perms)

`Repository({required Backend backend, AppUser? currentUser})`; `currentUser` getter. `rebind({required Backend backend, AppUser? currentUser})` swaps the backend (used on Firebase activate/deactivate); `setCurrentUser(AppUser?)` updates the identity used by guards.

- **Businesses:** `fetchBusinesses()`, `saveBusiness(Business, {required bool isNew})`, `archiveBusiness(String id)` (soft-delete)
- **Products:** `fetchProducts({String? businessId})`, `fetchProduct(id)`, `saveProduct(Product, {required bool isNew})`, `deleteProduct(id)`
- **Campaigns:** `fetchCampaigns({businessId})`, `saveCampaign(Campaign, {isNew})`, `deleteCampaign(id)`
- **Orders:** `fetchOrders({businessId})`, `saveOrder(Order, {isNew})`, `deleteOrder(id)`
- **Expenses:** `fetchExpenses({businessId})`, `saveExpense(Expense, {isNew})`, `deleteExpense(id)` — **throws AppException if `expense.isFromDealer`**
- **Dealers:** `fetchDealers({businessId})`, `saveDealer(Dealer, {isNew})` (mirrors `EXP-DLR-<id>` expense), `deleteDealer(id)` (removes mirror)
- **Customers:** `fetchCustomers({String? businessId})` — for a non-owner, fans out one `fetchWhereArrayContains(customers, 'businessIds', biz)` per assigned business and dedupes by id (see §11.3 — the customers read rule is `array-contains`-shaped, NOT a filter); `saveCustomer(Customer, {required bool isNew})` — for a non-owner, re-reads the stored doc and **merges back** business tags & per-business contracts the caller can't see, so a limited-scope edit never drops another business's data; `deleteCustomer(id)`.
- **Users:** `fetchUsers()`, `fetchUserByUid(uid)`, `resolveUserByLogin(loginOrEmail)`, `touchLastLogin(uid)` — **no permission guard** (needed pre-login / for self); `createUser({required String loginId, name, email, UserRole role, List<String> assignedBusinessIds, String password})` (guard `manageUsers`; throws if role==owner; friendly `email-already-in-use` message pointing to the access-request flow), `saveUserProfile(AppUser)` / `setUserStatus(uid, AccountStatus)` (guard `manageUsers`), `deleteUser(uid)` (guard `manageUsers`; refuses to delete an owner or yourself; also clears any matching access request), `bootstrapFirstOwnerIfNeeded(AuthAccount) → AppUser?` (unguarded — provisions first OWNER iff project unclaimed).
- **Access requests:** `recordAccessRequest(AuthAccount)` (unguarded — self-service on failed login), `fetchAccessRequests()` / `approveAccessRequest(AccessRequest, {loginId, name, role, assignedBusinessIds, granted, revoked})` / `denyAccessRequest(uid)` (all guard `manageUsers`).
- **Audit:** `fetchAuditLogs({int limit=100})` — requires `Permission.manageSettings`

Internals: `_nextScopedId(prefix, collection, {int width, bool arrayScoped})` generates the next sequential id. **do NOT set `.id` when creating** — repo generates it. For updates, pass the model with its existing id.

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
`parseDate(dynamic) → DateTime?` is a top-level helper in `lib/models/audit_fields.dart:61` used by every `fromMap`.

**Cross-cutting additions (Sept 2026):** every core entity — Business, Product, Campaign, Order, Expense, Dealer — now carries `List<EntityComment> comments = const []` and exposes a `DateTime? lastActivityAt` getter (latest of the entity's own dates + its newest comment). Their `copyWith` now also accepts an optional `String? id` (previously id was fixed); `businessId` is still NOT copyable on the business-scoped models. All add `comments` to copyWith.

### Business
`Business({required id, required name, description='', type='', website='', CurrencyCode currency=inr, country='India', EntityStatus status=active, CompanySize size=small, BusinessLifecycle lifecycle=active, String foundedBy='', ownedBy='', DateTime? startDate, DateTime? endDate, String facebookUrl='', instagramUrl='', xUrl='', pinterestUrl='', linkedinUrl='', redditUrl='', otherSocialUrl='', List<EntityComment> comments=const[], audit})`
Getters: `isActive` (EntityStatus), `isClosed` (`lifecycle.isClosed`), `TimeRemaining? tenure(DateTime asOf)` (startDate→endDate/asOf), `List<(String,String)> socialLinks` (label,url pairs, non-empty only), `lastActivityAt`. copyWith **includes `id`** plus every field above.
Top-level `const List<String> kBusinessTypes` (16 entries) for the type dropdown.

### Product
`Product({required id, required businessId, required name, description='', Money buyingPrice=zero, Money sellingPrice=zero, url='', sku='', category='', EntityStatus status=active, audit})`
Getter `isActive`. copyWith (no id/businessId): name, description, buyingPrice, sellingPrice, url, sku, category, status, audit.

### Campaign
`Campaign({required id, required businessId, required productId, required name, CampaignPlatform platform=other, type='', DateTime? startDate, DateTime? endDate, Money budget=zero, Money amountInvested=zero, int impressions=0, clicks=0, conversions=0, CampaignStatus status=draft, url='', notes='', audit})`
Getters: `DateTime? spendDate` (startDate ?? createdAt), `double ctr`, `double conversionRate`. copyWith (no id/businessId): productId, name, platform, type, startDate, endDate, budget, amountInvested, impressions, clicks, conversions, status, url, notes, audit.

### Order
`Order({required id, required businessId, required productId, required productName, DateTime? orderDate, int quantity=1, Money sellingCost=zero, discount=zero, shippingRevenue=zero, otherRevenue=zero, buyingCost=zero, marketingAllocation=zero, OrderStatus status=pending, customerReference='', notes='', Money refundAmount=zero, DateTime? refundDate, List<EntityComment> comments=const[], audit})`
Getters: `Money productRevenue` (=sellingCost*qty), `totalRevenue`, `productCost` (=buyingCost*qty), `grossProfit`, `bool isRecognised`, `bool isRefunded`, `Money effectiveRefund` (clamped to totalRevenue), `double refundRatio` (0..1), `recognisedRevenue` (net of refund), `recognisedProductCost`, `recognisedGrossProfit`, `lastActivityAt`. copyWith **includes `id`** (NOT businessId): productId, productName, orderDate, quantity, sellingCost, discount, shippingRevenue, otherRevenue, buyingCost, marketingAllocation, status, customerReference, notes, refundAmount, refundDate, comments, audit.

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

### EntityComment — `lib/models/entity_comment.dart`
`EntityComment({required id, authorId='', authorName='', text='', DateTime? createdAt})` + `toMap/fromMap`. Static `EntityComment.listFrom(dynamic) → List<EntityComment>` (tolerant decode, skips non-maps). **No copyWith.** Embedded on every core entity's `comments`.

### Contact — `lib/models/contact.dart`
`Contact({required id, name='', email='', designation='', number='', description='', DateTime? createdAt})` + `toMap/fromMap`, static `Contact.listFrom(dynamic)`, `copyWith` (keeps id, preserves createdAt). Embedded on `Customer.contacts`. In the UI the contact **tile** shows only avatar+name+designation; the **view dialog** shows every field, each with a `CopyButton`.

### Customer — `lib/models/customer.dart` (CRM; the richest new model)
`Customer({required id, required List<String> businessIds, required name, businessType='', CompanySize size=small, contactNo='', email='', city='', state='', country='India', socialMedia='', DealStatus dealStatus=pending, description='', Map<String,BusinessContract> contractsByBusiness=const{}, List<Contact> contacts=const[], List<CustomerComment> comments=const[], audit})`
A customer is tagged to one or more businesses (`businessIds`) and holds **one contract per business** in `contractsByBusiness` (keyed by businessId).
Getters: `bool hasServiceContract`, `hasContractFor(bizId)`, `ServiceContract? activeContractFor(bizId)`, `List<ServiceContract> historyFor(bizId)`, `ServiceContract? contractInScope(String? bizId)` (the active contract for a specific business; **null when bizId is null/All** — scope to a business to see a contract), `Iterable<ServiceContract> allActiveContracts`, `bool hasContractHistory`, `int contractTermCount`, `String location` (city/state/country joined), `DateTime? lastActivityAt`.
Methods: `withRenewedContract(ServiceContract renewal)` (moves the current active into history, sets renewal active for its businessId), `withContract(ServiceContract)` (set/replace active for its businessId). `copyWith` keeps id, includes every field incl. contractsByBusiness/contacts/comments.
**Legacy tolerance in `fromMap`:** a scalar `businessId` is lifted into `businessIds`; a legacy top-level `serviceContract` + `contractHistory` is migrated under that contract's `businessId` (or the first tag).

### ServiceContract / ServiceAddOn / BusinessContract — (same file)
- `ServiceAddOn({required name, Money price=zero})` + toMap/fromMap/copyWith.
- `ServiceContract({String businessId='', DateTime? purchaseDate, DateTime? expiryDate, Money price=zero, bool priceOneTime=false, SubscriptionPlan plan=basic, BillingCycle billingCycle=yearly, List<ServiceAddOn> addOns=const[], String comment=''})`. Getters: `Money addOnsTotal`, `recurringPrice`, `total`, `oneTimeTotal`, `bool hasOneTimeCharge`, `Money annualTotal`, `bool isExpiredAsOf(DateTime now)`, `TimeRemaining? timeRemainingAsOf(DateTime now)`.
- `BusinessContract({required ServiceContract active, List<ServiceContract> history=const[]})` + `int termCount`, `renewedWith(ServiceContract renewal)`.

### CustomerComment — (same file)
`CustomerComment({required id, authorId='', authorName='', text='', DateTime? createdAt})` + toMap/fromMap. **No copyWith.** (Distinct from `EntityComment`; predates it, kept for the customer document.)

### Invoice — `lib/models/invoice.dart` (pure value objects, no persistence)
- `InvoiceParty({required name, subtitle='', List<String> lines=const[]})`.
- `InvoiceLine({required description, detail='', int quantity=1, required Money unitPrice, bool oneTime=false})` + `Money amount`.
- `Invoice({...issuer/customer/business/currency/number/date + List<InvoiceLine> lines...})`. Getters: `Money total`, `recurringTotal`, `oneTimeTotal`, `bool hasMixedCharges`, `bool isEmpty`, `String fingerprint`.
- Factory `Invoice.forCustomer({required Customer customer, required ServiceContract? contract, required Business? business, required CurrencyCode currency, required issuerName, issuerTitle='', required DateTime now})`.

### AccessRequest — `lib/models/access_request.dart`
`AccessRequest({required uid, required email, displayName='', DateTime? requestedAt})` + toMap/fromMap. Written on a failed login to a claimed project; surfaced to owners in User management.

### AuditLog — `lib/models/audit_log.dart`
`AuditLog({required id, userId='', userName='', required AuditAction action, entityType='', entityId='', String? businessId, DateTime? timestamp, summary=''})` + toMap/fromMap.

---

## 6. Enums (`lib/core/enums.dart`) — all have `.wire`, `.label`, `.fromWire()`

- **UserRole**: `user, admin, owner` — `.isOwner/.isAdmin/.isUser`, `.atLeast(other)`. (owner highest)
- **EntityStatus**: `active, inactive, archived`
- **AccountStatus**: `active, disabled`
- **CurrencyCode**: `inr(₹), usd($), eur(€), gbp(£)` — `.symbol` and `.label` (the enum's `.wire`/`.symbol`/`.label` are a 3-arg record).
- **CampaignPlatform**: `meta, google, tiktok, youtube, linkedin, other`
- **CampaignStatus**: `draft, active, paused, completed, cancelled`
- **OrderStatus**: `pending, confirmed, processing, shipped, delivered, cancelled, returned` — `.contributesToRevenue` is **`this != cancelled`** (a *returned* order still recognises revenue; the return is modelled via `Order.refundAmount`, not by dropping it from revenue).
- **RecurrenceFrequency**: `oneTime, monthly, quarterly, halfYearly, yearly` — `.occurrencesPerYear` (0/12/4/2/1), `.isRecurring`
- **ExpenseCategory**: `domain, crm, hosting, dealer, software, subscription, paymentGateway, shipping, office, employee, advertising, other`
- **AuditAction**: `create, update, delete, archive, login, logout`
- **BusinessLifecycle**: `active, closed` — `.isClosed`.
- **CompanySize**: `micro, small, medium, large, enterprise` — labels carry headcount bands.
- **DealStatus**: `pending, inProgress, successful, cancelled` (CRM deal stage).
- **SubscriptionPlan**: `basic, pro, legend` (contract tier).
- **BillingCycle**: `monthly('mo', 12), yearly('yr', 1)` — `.unit` (short suffix), `.perYear`.

### Permission (`lib/core/permissions.dart`)
`viewDashboard, viewBusiness, createBusiness, editBusiness, deleteBusiness, viewProduct, createProduct, editProduct, deleteProduct, viewCampaign, createCampaign, editCampaign, deleteCampaign, viewOrder, createOrder, editOrder, deleteOrder, viewExpense, createExpense, editExpense, deleteExpense, viewDealer, createDealer, editDealer, deleteDealer, viewCustomer, createCustomer, editCustomer, deleteCustomer, viewReports, exportData, manageUsers, configureFirebase, manageSettings` (customer perms sit between `deleteDealer` and `viewReports`).

`Permissions.forRole(role)`, `Permissions.resolve(role, {granted, revoked})`.
- USER: view + create on product/campaign/order; **createExpense** (view/create, no edit/delete on expense); view business/dealer/dashboard; **customer view/create/edit (NO delete)**; **viewReports**. No other deletes/edits/admin.
- ADMIN: full CRUD on product/campaign/order/expense/dealer within assigned businesses + **full customer CRUD incl. deleteCustomer** + **createExpense** + viewReports + exportData. No manageUsers/configureFirebase/manageSettings/business CRUD.
- OWNER: everything.

**Gate UI with `user.can(Permission.x)`. Repo enforces the same — service layer is source of truth.**

### date_utils (`lib/core/utils/date_utils.dart`)
- `DateRange(start, end)` — `.contains(date)`, `.days`, `.overlapDays(other)`, `toString()` → "dd-MMM-yyyy → dd-MMM-yyyy"
- `FinancialYear(startYear)` — `.forDate(date)` factory, `.endYear`, `.range`, `.previous`, `.next`, `.label` ("FY 2026-27")
- `enum PeriodType { financialYear, calendarYear, quarter, month, custom }` — `.label`
- `enum FinancialQuarter { q1, q2, q3, q4 }` — `.label` ("Q1 (Apr–Jun)"), `.startMonth`
- `AppDate.format(DateTime?)` ("dd-MMM-yyyy", "—" if null), `.short(d)`, `.monthYear(d)`, `.iso(d)`, `.tryParseIso(s)`, `.dayOnly(d)`. Display pattern is configurable: `AppDate.defaultPattern = 'dd-MMM-yyyy'`, current `AppDate.displayPattern`, `AppDate.configureDisplayFormat(pattern)` (wired to `AppState.setDateFormat`).
- `enum TimeBucket { month, quarter, year }`, `bucketForRange(range) → TimeBucket`
- `PeriodOptions.financialYears(Iterable<DateTime> dates, {DateTime? now})` / `PeriodOptions.calendarYears(dates, {now})` — build the selectable period lists from the data's activity dates (feed `data.activityDates(...)`).
- `TimeRemaining` — `TimeRemaining.between(DateTime from, DateTime to)` factory; fields `years, months, days, totalDays, bool isPast`; getters `isToday`, `shortLabel`, `label`. Used by contract expiry, business tenure, etc.

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
`Routes.{login, forgotPassword, dashboard, businesses, businessDetail, products, productDetail, campaigns, campaignDetail, orders, orderDetail, expenses, expenseDetail, dealers, dealerDetail, customers, customerDetail, reports, users, settings}`. Path helpers for every detail route: `Routes.businessDetailPath(id)`, `productDetailPath(id)`, `campaignDetailPath(id)`, `orderDetailPath(id)`, `expenseDetailPath(id)`, `dealerDetailPath(id)`, `customerDetailPath(id)`.
`kNavDestinations` (List<NavDestination>) already drives the sidebar (Users is `ownerOnly`; Customers gated on `viewCustomer`). Navigate with `context.go(Routes.x)` (import `go_router`).

### id_generator (`lib/core/utils/id_generator.dart`)
Sequential prefixes: `PROD, ORD, CMP, EXP, DLR, BIZ, USR, CUST` (customers → `CUST-00001`). Repo calls this; don't set ids yourself on create.

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
- `StatusBadge({required String label, BadgeTone tone=neutral})` + factories `.entity(EntityStatus)`, `.account(AccountStatus)`, `.order(OrderStatus)`, `.campaign(CampaignStatus)`, `.role(UserRole)`, `.deal(DealStatus)`. `enum BadgeTone { neutral, success, warning, error, info, primary }`
- `CurrencyText(Money money, {CurrencyCode currency=inr, TextStyle? style, bool colorNegative=true, bool precise=false})`
- `SearchField({required ValueChanged<String> onChanged, String hintText='Search…', double? width, Duration debounce})` (debounced)

### Data table — `lib/widgets/common/data_table_card.dart`
- `AppColumn<T>({required String label, required Widget Function(T) cell, bool numeric=false, Comparable Function(T)? sortValue, double? width})`
- `AppDataTable<T>({required List<T> rows, required List<AppColumn<T>> columns, String searchText='', String Function(T)? searchableText, int rowsPerPage=10, String emptyTitle, String? emptyMessage, Widget? emptyAction, void Function(T)? onRowTap, int? initialSortColumn, bool initialSortAscending=true})`
- **Self-wraps in AppCard**, built-in search/sort/pagination/horizontal-scroll. Give a `searchableText` to enable the external `searchText` filter.

### Forms — `lib/widgets/forms/`
- `FormDialog({required String title, required Widget child, required Future<bool> Function() onSubmit, String submitLabel='Save', double width=560})` — spinner + no double-submit; **owns the single `Navigator.pop`** — pops(true) when onSubmit returns true. On mobile it renders full-bleed (`Dialog` with `insetPadding: EdgeInsets.all(md)`); desktop caps at `width` × 90% height. Show via `showDialog<bool>(context: ..., builder: (_) => ...)`. **See §11.1 — a child `_submit` must never also call `Navigator.pop`.**
- `FormRow(List<Widget> children)` — side-by-side desktop / stacked mobile.
- `FormGap()` — SizedBox(height: lg).
- `LabeledField({required label, required child, isRequired=false, helper})`
- `AppTextField({required String label, TextEditingController? controller, String? initialValue, String? Function(String?)? validator, TextInputType? keyboardType, bool isRequired=false, String? hintText, String? helper, int maxLines=1, bool obscureText=false, ValueChanged<String>? onChanged, List<TextInputFormatter>? inputFormatters, String? prefixText, bool enabled=true})`
- `AppMoneyField({required String label, required TextEditingController controller, bool isRequired=false, String symbol='₹', validator, helper, ValueChanged<String>? onChanged})` — number-only input (allows `[0-9.]`); parse with `Money.parse(controller.text)`; prefill with `money.major.toString()` or `MoneyFormatter` (prefer plain `.major`).
- `AppDropdown<T>({required String label, required T? value, required List<T> items, required String Function(T) itemLabel, required ValueChanged<T?> onChanged, bool isRequired=false, helper})`
- `AppSearchableDropdown<T>({required String label, required T? value, required List<T> items, required String Function(T) itemLabel, required ValueChanged<T?> onChanged, bool isRequired=false, helper, hintText, bool enabled=true})` — dropdown with a live search filter, for long lists (products, businesses, customers).
- `AppDateField({required String label, required DateTime? value, required ValueChanged<DateTime?> onChanged, bool isRequired=false, helper, DateTime? firstDate, DateTime? lastDate})`

### Dialogs — `lib/widgets/common/confirm_dialog.dart`
- `Future<bool> showConfirmDialog(context, {title, message, confirmLabel='Delete', cancelLabel='Cancel', bool destructive=true})`
- `void showSuccessSnack(context, String)`
- `void showErrorSnack(context, Object error)` (maps via ErrorMapper)

### Detail & CRM widgets — `lib/widgets/common/`
Used to compose the 7 detail screens and the CRM.
- `detail_widgets.dart`: `bool looksLikeUrl(String)`, `void openExternalUrl(String url)` (no-op if not a resolvable URL); `DetailField(String label, String value, {IconData? icon, bool isLink=false})` (value object); `DetailGrid({required List<DetailField> fields})`, `DetailFieldTile({required DetailField field})`, `DetailTwoColumn({required Widget left, Widget? right})`; `CopyButton({required String label, required String value})` (copies to clipboard + snack), `LinkButton({required String value})`.
- `initials_avatar.dart`: `InitialsAvatar({required String name, double size=40, double? fontSize})` + static `InitialsAvatar.initialsOf(name)`, `InitialsAvatar.colorOf(name)` (deterministic color from name).
- `comment_thread.dart`: `LastActivityCard({required DateTime? activityAt})`; `EntityCommentThread({required List<EntityComment> comments, required bool canComment, required Future<void> Function(EntityComment) onPost})` — `onPost` receives the freshly-built comment and must save + refresh; `DetailActivityColumn({required DateTime? activityAt, required List<EntityComment> comments, required bool canComment, required Future<void> Function(EntityComment) onPost})` (last-activity card + comment thread stacked).
- `csv_actions.dart`: `void exportProductsCsv(ctx, List<Product>)`, `Future<void> importProductsCsv(ctx)`, `void exportCustomersCsv(ctx, List<Customer>)`, `Future<void> importCustomersCsv(ctx)` — gated on `exportData` / the relevant `createX` permission (self-check + `showErrorSnack` on denial).

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

`Backend` interface (`lib/data/backend.dart`) adds `Future<AuthAccount> signInWithGoogle()` (FirebaseBackend: `GoogleAuthProvider` + `signInWithPopup`; LocalBackend: signs in demo Owner), `Future<AuthAccount> createAccount(email, password)`, and `Future<List<Map<String,dynamic>>> fetchWhereArrayContains(collection, field, value)` (the array-contains query behind scoped customer reads). `AuthAccount` gains `String displayName`. `Collections` now includes `customers`, `auditLogs`, `accessRequests`, `meta`.

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

---

## 11. Gotchas & contracts (learned the hard way — do not relearn)

### 11.1 FormDialog owns the single pop
`FormDialog` calls `Navigator.pop(true)` itself when its `onSubmit` returns `true`. A child dialog's `_submit` must **persist-and-return-bool, NEVER call `Navigator.pop`** — doing both pops twice, tears down the page route beneath, and leaves a blank white screen (the save still runs, so it looks like data vanished). The caller keys off the returned bool: `if (saved == true) { await data.refresh(); showSuccessSnack(...); }`. A dialog that must return a **payload** (not a bool) via `showDialog<T>` (e.g. the orders Refund dialog returning a result object) pops itself with the payload and then **`return false`** so FormDialog doesn't pop again.

### 11.2 Always refresh after a mutation
After any `repo.saveX/deleteX/archiveX`, `await context.read<DataController>().refresh()` before showing success. The cached working set does not auto-invalidate.

### 11.3 Firestore rules are NOT filters
Every non-owner list query must be **provably authorizable by its own where-clauses**, because Firestore evaluates the read rule against the *query*, not the returned rows. Customers are scoped by `array-contains` on `businessIds`: `Repository.fetchCustomers` fans out one `fetchWhereArrayContains(customers, 'businessIds', biz)` per assigned business and dedupes by id — it never issues an unfiltered `list()`. **Do NOT add conditional / data-shape branches to the customers read rule**, and do not "optimize" the fan-out into a single unscoped query — either reintroduces the Sept 2026 Admin/User lockout. On write, `saveCustomer` merges back business tags & contracts the caller can't see so a limited-scope edit never drops another business's data.

### 11.4 DataController per-collection load isolation
`DataController.load()` treats only `businesses` as essential. Every other collection loads through a `guard` that degrades to `[]` + a `warnings` entry on failure. So a single denied/misconfigured query surfaces a warning banner, not a blank app. Preserve this — don't hoist another collection into the essential path, and don't let a `guard` rethrow.

### 11.5 Listing users is owner-only; identity lookups are not
`fetchUsers` / `createUser` / `saveUserProfile` / `setUserStatus` / `deleteUser` / access-request methods require `manageUsers`. But `fetchUserByUid` / `resolveUserByLogin` / `touchLastLogin` are **unguarded** on purpose — they run before a role is known (login, self-profile). Keep that split.

### 11.6 Never surface raw Firebase errors
Catch and route through `ErrorMapper.friendly(e)` / `showErrorSnack(ctx, e)`. Prefer soft delete/archive for anything financial.
