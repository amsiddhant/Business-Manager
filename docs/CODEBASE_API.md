# Codebase API Reference — Salesforce Business Manager

> **Read this file FIRST instead of re-reading `lib/**` after a context compaction.**
> It captures every constructor signature, getter, enum, and helper needed to
> author screens. All facts verified against source on 2026-09-22.

---

## 0. THE ONE LAYOUT RULE (do not violate)

Screens rendered inside the shell (`StatefulShellRoute.indexedStack` → `AppShell`) **own their scrolling** through `AppPage` (`lib/widgets/layout/app_page.dart`):

```dart
AppPage(children: [PageHeader(...), SectionCard(...), ...])
// or, for slivers (pinned headers, long lists):
AppPage.slivers(slivers: [...])
```

- **NO** `Scaffold`, **NO** `SingleChildScrollView`, **NO** `SafeArea`.
- `AppShell` does **not** scroll (since 1.1.0). `AppPage` provides the `CustomScrollView`, `AppSpacing.lg` padding, centring at `maxWidth` (default 1400), and builds each child lazily — off-screen sections aren't built until scrolled to, and once built they are kept alive (table sort/page/search survive scrolling).
- Pass sections as separate `children`, not one big `Column`, or nothing is lazy.
- Every routed screen is an `AppPage` (list/section pages) or a `DetailPage` (record pages; it returns an `AppPage`). The router adds no scroll or padding wrapper (`LegacyScroll` was removed in 1.4.0), so a screen that returns a plain `Column` won't scroll.
- **Auth screens** (`login_screen.dart`, `forgot_password_screen.dart`) DO use their own `Scaffold` — they render outside the shell.

The **12 list/section shell screens** have `const` no-arg constructors (Dashboard, Businesses, Products, Campaigns, Orders, Expenses, Dealers, **Customers**, Reports, Users, Settings, plus the `PlaceholderScreen`). The **7 detail screens** each take one required id: `BusinessDetailScreen({required String businessId})`, `ProductDetailScreen({required String productId})`, `CampaignDetailScreen({required String campaignId})`, `OrderDetailScreen({required String orderId})`, `ExpenseDetailScreen({required String expenseId})`, `DealerDetailScreen({required String dealerId})`, `CustomerDetailScreen({required String customerId})`. Detail screens return a `DetailPage` (no Scaffold).

---

## 1. Screens to build (paths + routes)

| Screen file | Class | Route const | Notes |
|---|---|---|---|
| `lib/screens/dashboard/dashboard_screen.dart` | `DashboardScreen` | `Routes.dashboard` | hero + attention strip + 10 KPIs + 12 charts (business comparison only for All Businesses with 2+) + 3 tables, all from `DashboardViewModel` (see §11.9) |
| `lib/screens/alerts/alerts_screen.dart` | `AlertsScreen` | `Routes.alerts` | alerts center: Active / Snoozed / Dismissed, severity + type filters (since 1.3.0) |
| `lib/screens/goals/goals_screen.dart` | `GoalsScreen` | `Routes.goals` | goal cards with progress rings, period switch, `goal_editor.dart` (months × metrics matrix) (since 1.5.0) |
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
| `lib/screens/reports/reports_screen.dart` | `ReportsScreen({String? initialTab})` | `Routes.reports` | CSV export; `?tab=` one of `ReportsScreen.tabKeys` (`sales, expenses, marketing, products, business`) — link with `Routes.reportsTab(tab)` |
| `lib/screens/users/users_screen.dart` | `UsersScreen` | `Routes.users` | owner-only |
| `lib/screens/settings/settings_screen.dart` | `SettingsScreen` | `Routes.settings` | hub: Personal (everyone) / Organisation (`manageSettings`) / System (Owner: Firebase wizard, audit log, Danger zone); sections in `settings/sections/`, `?section=` deep links (since 1.5.0) |

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

### ThemeController / UserPrefs (ChangeNotifier, since 1.2.0)
- `ThemeController(prefs, userPrefs)`: `mode` (ThemeMode), `density`, `motion` (MotionLevel), `light` / `dark` (memoised ThemeData), `canChooseMode`, `org` (`OrgTheme{brand, defaultMode, allowUserOverride, density, motion, corners, chartPalette}` — the last two since 1.5.0), `applyOrgTheme(OrgTheme)`. The org theme is cached in prefs (`sbm_org_theme_v1`), so the first frame (and the `web/index.html` splash) already uses it.
- `UserPrefs(prefs)` — per-user device preferences under `sbm.u.<uid>.*` (call `bindUser(uid)`; null = signed out): `themeMode`, `reduceMotion`, `density`, `sidebarCollapsed`, `favourites` (`PinnedPage{path, label}`, `toggleFavourite`), `recentCommands` (newest first, `maxRecent = 8`), `scope` (the remembered business + period, `FilterController.toJson()`), plus `readJson` / `writeJson` for new features. Device-wide: `lastLoginId`, and the last theme picked (styles the sign-in screen). Never written to Firestore.
- `FilterController.toJson()` / `restore(json)` — tolerant round-trip of the scope; unreadable values fall back to the defaults.

### SettingsController (ChangeNotifier, since 1.5.0) — `lib/state/settings_controller.dart`
- The organisation's `settings/app` document (`AppSettings`, `lib/models/app_settings.dart`), provided in `main.dart` right after `ThemeController`. **1 read after sign-in** (+1 for `settings/logo` only when `branding.logoHash` changed); the last copy is cached in prefs (`sbm_org_settings_v1`, logo `sbm_org_logo_v1`) so the brand, FY start and sign-in branding are right on the first frame.
- `settings`, `hasRemote` (false = nothing saved yet → defaults merged with the old per-browser app name / date format; **never seeded**), `logo` (data URL), `loading`, `loaded`, `error`, `rulesMissing` (the rules refused the read), `canEdit(user)` (= `manageSettings`), `editorSeed`, `load()`, `save(draft, {logoChanged, logoDataUrl})` (**1 write** + the logo; throws).
- Applying: FY start month (`FinancialYear.configureStartMonth`), date format + app name (kept in step with `AppState`), number grouping (`MoneyFormatter.configureGrouping`), and the org theme (`orgThemeOf(s)` → `ThemeController.applyOrgTheme`, including corners and chart palette).
- Feature toggles: `s.features.isOn(AppFeature.x)` — `commandPalette`, `insights`, `forecasts`, `anomalies`, `suggestions`, `drafts`, `bulkActions`, `savedViews`, `csvImport`, `csvExport`, `invoices`, `whatsNew`. Check them where the feature is shown (e.g. `AppDataGrid` reads `bulkActions` / `savedViews` / `csvExport`); a switched-off feature hides UI only.
- Widgets read settings with `context.orgSettings((s) => …)` (a `select`, rebuilds only on change) and `context.readOrgSettings()` in callbacks (`lib/state/org_settings.dart`). Both fall back to `const AppSettings()` when no `SettingsController` is provided, so widget tests don't need one.
- `AppSettings` reading is tolerant: missing / unknown / out-of-range values fall back to defaults and are clamped (`AlertSettings`: urgent ≤ window, `spendZHigh` ≥ `spendZ`). `sameAs(other)` ignores `updatedAt`/`updatedBy`. **Modules only hide UI — totals always include every record.** Dashboard, Users, Settings and What's new are always on.

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
Fields (already scoped to what user can access): `List<Business> businesses`, `products`, `campaigns`, `orders`, `expenses`, `dealers`, `customers`, `goals` (since 1.5.0; org-wide `ALL` goals are Owner-only; `goalsUnavailable` = the goals read was refused — rules not deployed — and degrades silently to `[]`).
Flags: `bool loading`, `bool loaded`, `String? error`, `List<String> warnings`, `bool hasWarnings`.
Lifecycle: `load()` (concurrent calls share one in-flight load), `sync()` (== load; the header's "Sync now"), `refresh()` (kept for `ErrorView` retry; == sync), `softSyncIfStale({maxAge = 30 min})` (run when the tab returns to the foreground), `clear()`, `bind(Repository)` / `rebind(Repository)`.
Sync state: `int version` (bumps on every change — use it as a memo stamp), `DateTime? lastSyncedAt` (last server read), `bool showingCachedData` (painted from the offline cache, server read pending), `ValueNotifier<bool> syncing`.

**Do NOT refresh after a mutation.** The controller subscribes to `Repository.changes` and applies each `Upserted`/`Removed` in place (copy-on-write lists, same sort as `load()`, records the user can no longer see are dropped). Notifications are coalesced into one per microtask, so a CSV import notifies once. A change that lands during a `load()` is re-applied after it.

`*ById` lookups are O(1) maps; `*For(businessId)` results are memoised by `version` — safe inside row builders.

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
- `List<Goal> goalsFor(String? businessId)` — that business's goals; null = the organisation-wide (`Goal.allBusinesses`) ones only

### AlertController (ChangeNotifier, since 1.3.0) — `lib/state/alert_controller.dart`
- `AlertController(userPrefs, [settingsController])` (provided in `main.dart`). `alertsFor(data, {demoMode, now})` → every `AppAlert`, most urgent first, memoised on `data.version` + the effective settings — **0 reads**. In widgets use `alertsOf(context)` (`lib/widgets/alerts/alerts_panel.dart`).
- Since 1.5.0: thresholds and switched-off types come from `settings.alerts` (`AlertSettings`); the `anomalies` feature off also turns off unusual spend. `hiddenTypes` / `setHiddenTypes(Set<String>)` hide types for this user only (`UserPrefs.hiddenAlertTypes`); `effectiveSettings` = org + personal. New type `goalAtRisk` (current-period goals projected under `goalAtRiskPercent`, default 90%: at risk = medium, behind = high).
- `stateOf(alert)` → `AlertState {active, snoozed, dismissed}`, `active(alerts)`, `badgeCount(alerts)` (info alerts aside), `snoozedUntil(alert)`, `dismiss(keys)`, `snooze(key, duration)`, `restore(key)`. Kept per user in `UserPrefs` (`alerts`), never in Firestore; dismissals are forgotten after 180 days.
- UI: `AlertsBell` (top bar badge: error-coloured when a high alert is active), `AlertsPanel.open(context)` (side panel on desktop, sheet on phones), `AlertTile`.

### FilterController (ChangeNotifier) — global scope + period
- `String? selectedBusinessId` (null = All), `bool isAllBusinesses`
- `DateRange range` — **feed this to ProfitCalculationService**
- `String periodLabel`, `PeriodType periodType`, `FinancialYear financialYear`, `FinancialQuarter quarter`, `int calendarYear`, `int month`, `int monthYear`
- Setters: `selectBusiness(id?)`, `setFinancialYear(fy)`, `setPeriodType(t)`, `setQuarter(q)`, `setCalendarYear(y)`, `setMonth(m,y)`, `setCustomRange(DateRange)`
- Comparison (since 1.3.0): `ComparisonBasis comparison` + `setComparison(basis)`; `comparisonWindow({now})` → `ComparisonWindow` (both sides stop at today while the period runs).
- Defaults to current FY.

**Currency for display:** if `filter.isAllBusinesses` → `CurrencyCode.inr`; else `data.businessById(filter.selectedBusinessId)?.currency ?? CurrencyCode.inr`.

---

## 3. Repository (all CRUD; IDs auto-generated on create; guards enforce perms)

`Repository({required Backend backend, AppUser? currentUser})`; `currentUser` getter. `rebind({required Backend backend, AppUser? currentUser})` swaps the backend (used on Firebase activate/deactivate); `setCurrentUser(AppUser?)` updates the identity used by guards.

**Change stream:** `Stream<RepoChange> changes` (`lib/data/repo_change.dart`: sealed `RepoChange` → `Upserted(collection, id, entity)` / `Removed(collection, id)`). Emitted only after a write succeeds, including the dealer mirror `EXP-DLR-<id>` expense. Every `saveX` **returns the saved entity** (with its minted id). Every delete/archive takes an optional `known:` entity — pass the in-memory one and the repo skips the pre-read.

- **Businesses:** `fetchBusinesses()`, `saveBusiness(Business, {required bool isNew})`, `archiveBusiness(String id)` (soft-delete)
- **Products:** `fetchProducts({String? businessId})`, `fetchProduct(id)`, `saveProduct(Product, {required bool isNew})`, `deleteProduct(id)`
- **Campaigns:** `fetchCampaigns({businessId})`, `saveCampaign(Campaign, {isNew})`, `deleteCampaign(id)`
- **Orders:** `fetchOrders({businessId})`, `saveOrder(Order, {isNew})`, `deleteOrder(id)`
- **Expenses:** `fetchExpenses({businessId})`, `saveExpense(Expense, {isNew})`, `deleteExpense(id)` — **throws AppException if `expense.isFromDealer`**
- **Dealers:** `fetchDealers({businessId})`, `saveDealer(Dealer, {isNew})` (mirrors `EXP-DLR-<id>` expense), `deleteDealer(id)` (removes mirror)
- **Customers:** `fetchCustomers({String? businessId})` — for a non-owner, fans out one `fetchWhereArrayContains(customers, 'businessIds', biz)` per assigned business and dedupes by id (see §11.3 — the customers read rule is `array-contains`-shaped, NOT a filter); `saveCustomer(Customer, {required bool isNew})` — for a non-owner, re-reads the stored doc and **merges back** business tags & per-business contracts the caller can't see, so a limited-scope edit never drops another business's data; `deleteCustomer(id)`.
- **Sign-in:** `emailForLogin(loginOrEmail) → String?` — input with `@` is used as typed; a login ID is looked up with **one `get`** of `loginIndex/{key}` (pre-auth; `list` is denied), falling back to `resolveUserByLogin` on backends without `PublicLookupCapable` (demo). Errors → null. `static loginIndexKey(loginId) → String?` (lower-cased; null for ids that can't be a doc key). `rebuildLoginIndex() → int` (Owner; one batch over all users — the Users screen's "Rebuild sign-in index" button).
- **Users:** `fetchUsers()`, `fetchUsersCached()` (per-session cache, cleared on any user write or sign-in change), `fetchUserByUid(uid)`, `resolveUserByLogin(loginOrEmail)`, `touchLastLogin(AppUser)` (self, `lastLoginAt`-only field update, fire-and-forget, skipped if already today) — **no permission guard** (needed pre-login / for self); `createUser({required String loginId, name, email, UserRole role, List<String> assignedBusinessIds, String password})` (guard `manageUsers`; throws if role==owner; friendly `email-already-in-use` message pointing to the access-request flow), `saveUserProfile(AppUser, {AppUser? previous})` (pass `previous` so a renamed login ID moves its `loginIndex` entry in the same batch) / `setUserStatus(uid, AccountStatus)` (guard `manageUsers`), `deleteUser(uid)` (guard `manageUsers`; refuses to delete an owner or yourself; also clears any matching access request), `bootstrapFirstOwnerIfNeeded(AuthAccount) → AppUser?` (unguarded — provisions first OWNER iff project unclaimed).
- **Access requests:** `recordAccessRequest(AuthAccount)` (unguarded — self-service on failed login), `fetchAccessRequests()` / `approveAccessRequest(AccessRequest, {loginId, name, role, assignedBusinessIds, granted, revoked})` / `denyAccessRequest(uid)` (all guard `manageUsers`).
- **Audit:** `fetchAuditLogs({int limit=100})` — **Owner only** (since 1.5.0; admins now hold `manageSettings`)
- **Organisation settings (since 1.5.0):** `fetchAppSettings() → AppSettings?` (null = no doc → defaults), `fetchLogo() → String?`, `saveAppSettings(settings, {logoChanged, logoDataUrl})` (guard `manageSettings`; one batch: `settings/app` + `settings/logo` set/delete + audit; stamps `updatedAt`/`updatedBy`; logo ≤ `Repository.maxLogoChars` = 210000).
- **Goals (since 1.5.0):** `fetchGoals()` (Owner: all; others: one query per assigned business), `saveGoals(List<Goal>)` / `saveGoal`, `deleteGoals(List<Goal>)` / `deleteGoal` — guard `manageGoals` + business access; `ALL` goals are Owner-only. Batched in chunks of `maxOps - 1` with one audit log each. Ids are deterministic (`{business}_{periodKey}_{metric}`), so saving again replaces.

**Ids:** **do NOT set `.id` when creating** — repo generates it. For updates, pass the model with its existing id. `_nextScopedId` reserves from the global `counters/{prefix}` doc in a transaction (1 read + 1 write) when the backend is `CounterCapable`, floored at `max(idHint, highest minted this session)` so a lagging counter heals itself. The counter is created lazily by the **Owner** from one scan; until it exists (or while its rules aren't deployed) everyone falls back to the old scan. Mints run one at a time per repository, so two creates in flight never share an id.
- `idHint` — set by `DataController` to `highestIdNumber(prefix)`.
- `reserveIdsFor(collection, count)` before a bulk create (CSV import) reserves a block in one transaction; `releaseReservedIds()` afterwards.
- `healIdCounters(Map<String,int> highestByPrefix)` — Owner only, best-effort `ensureAtLeast`.

**Atomic writes:** on a `BatchCapable` backend, a save writes the entity + any mirror + its audit log in **one batch**. If the batch is refused (`permission-denied`, e.g. the audit rule isn't deployed), it is retried without the optional audit write and a line is added to `List<String> diagnostics` (newest last, capped at 50). Without batches, writes run in sequence and an audit failure is swallowed.

### Backend capabilities — `lib/data/backend_capabilities.dart`
`Backend` has **no new abstract methods** (test fakes keep compiling). Optional features are interfaces, checked with a pattern — `if (_backend case final CounterCapable c) { ... }` (`is` won't promote to an unrelated interface):
- `BatchCapable` — `maxOps` (450), `commit(List<WriteOp>)`; `WriteOp` is sealed: `SetOp(collection, id, data)`, `DeleteOp(collection, id)`.
- `CounterCapable` — `reserveNumbers(prefix, count, {floor, create}) → int?` (first number, or null if the counter doesn't exist and `create` is false), `ensureAtLeast(prefix, value)`.
- `FieldUpdateCapable` — partial field update (used by `touchLastLogin`).
- `QueryCapable`, `CacheCapable` (cache-first reads), `PublicLookupCapable` (`fetchPublicDoc` before sign-in), `UsageMeter` (reads/writes this session).
`LocalBackend` implements Batch/Counter/FieldUpdate/Query; its store is persisted with a 250 ms debounce (`flush()` forces it). Fakes for tests: `test/support/memory_backend.dart` (`MemoryBackend`, `BatchMemoryBackend`, `LookupMemoryBackend`).

---

## 4. ProfitCalculationService — `const ProfitCalculationService()`

All money math lives here. Feed it `filter.range` and lists scoped via `data.*For(filter.selectedBusinessId)`.

### Result types
- **`ProfitSummary`** `{revenue, productCost, marketingCost, operatingExpenses, orderCount, unitsSold}` (all `Money`/int) + getters `grossProfit`, `contributionProfit`, `netProfit`, `grossMargin` (double %), `netMargin` (double %), `totalExpenses`. `static const empty`.
- **`ProductProfit`** `{Product product, int orderCount, int unitsSold, Money revenue, productCost, marketingCost}` + `grossProfit`, `netProfit`, `margin` (double %).
- **`CampaignPerformance`** `{Campaign campaign, Money spend, Money attributedRevenue}` + `double? roi` (null if spend zero), `double? roas` (null if spend zero).
- **`TimeSeriesPoint`** `{String label, Money revenue, productCost, marketingCost, operatingExpenses, int orders}` + `netProfit`.
- **`CategorySlice(String label, Money amount)`**.
- Since 1.3.0: **`KpiMetric`** (revenue … units; `label`, `higherIsBetter`, `isMoney/isPercent/isCount`, `valueOf(summary)`, `valueOfPoint(point)`); **`ProfitComparison{current, previous}`** with `hasPrevious` and `[metric]` → **`MetricDelta{current, previous?}`** + `change` (% for amounts/counts, points for margins; null with no basis) and `favourable` (null when flat); **`WaterfallStep{label, amount, start, end, kind}`**; **`BusinessSummary{business, summary}`**; **`PeriodProjection{revenue, netProfit, revenuePerDay, netProfitPerDay, elapsedDays, totalDays}`**; **`ForecastPoint{label, revenue?, netProfit?, projectedRevenue?, projectedNetProfit?}`**.

### Methods
- `summarise({required List<Order> orders, List<Campaign> campaigns, List<Expense> expenses, DateRange range}) → ProfitSummary`
- `productProfitability({required products, orders, campaigns, range}) → List<ProductProfit>`
- `campaignPerformance({required campaigns, orders, range}) → List<CampaignPerformance>`
- `timeSeries({required orders, campaigns, expenses, range, TimeBucket? bucket}) → List<TimeSeriesPoint>`
- `expenseBreakdown({required orders, campaigns, expenses, range}) → List<CategorySlice>` (already sorted desc, positives only)
- `marketingByPlatform(List<Campaign>, DateRange) → Map<CampaignPlatform, Money>`
- Since 1.3.0: `compare(current, previous) → ProfitComparison`, `profitWaterfall(summary) → List<WaterfallStep>`, `summariseByBusiness({businesses, orders, campaigns, expenses, range})`, `orderStatusBreakdown(orders, range) → Map<OrderStatus, int>` (every status), `trailingMonths({orders, campaigns, expenses, asOf, months=12})` (sparklines), `projectRunRate({toDate, range, asOf, minDays=7}) → PeriodProjection?`, `projectSeries(series, projection, asOf) → List<ForecastPoint>`, `monthlySpendByCategory({campaigns, expenses, asOf, months=7})`.
- Since 1.4.0: `summariseOrders(Iterable<Order>) → OrderListSummary{count, recognisedCount, units, revenue, grossProfit, refunds, refundedCount, cancelledCount}` + `averageOrderValue`, `grossMargin` (double %, null with no revenue) — the Orders list/detail KPI strips. Per-module list figures live in **`lib/services/summaries/<module>_summaries.dart`** as `extension <Module>Summaries on ProfitCalculationService` (same rule: pure, `Money` ops, no widget maths).
- Since 1.5.0 (goals): `goalProgress({goal, orders, campaigns, expenses, asOf, atRiskPercent = 90, projectedOverride}) → GoalProgress{actual, expectedToDate, projected, requiredPerDay, elapsedDays, totalDays, status, percent, pace, projectedPercent, remaining}` (`GoalStatus`: notStarted / achieved / onTrack / atRisk / behind / missed; the first 2 days count as on track), `metricOf(summary, GoalMetric)`, `metricByRange({metric, orders, campaigns, expenses, ranges})`, `seasonalSplit(target, weights)` (largest remainder: always sums exactly; no usable weights = even).
- Rule-based, pure, **0 reads**: `AlertService().build(...)` (`lib/services/alert_service.dart`: contracts expiring/overdue, campaigns ending, low margin, unusual spend via `robustZ`, data warnings, demo mode; keys are stable, `stableHash` is FNV-1a) and `InsightService().build(...)` (`lib/services/insight_service.dart`: revenue ±10%, margin ±3 pts, concentration > 40%, ROAS, spend spikes, contracts).
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
`viewDashboard, viewBusiness, createBusiness, editBusiness, deleteBusiness, viewProduct, createProduct, editProduct, deleteProduct, viewCampaign, createCampaign, editCampaign, deleteCampaign, viewOrder, createOrder, editOrder, deleteOrder, viewExpense, createExpense, editExpense, deleteExpense, viewDealer, createDealer, editDealer, deleteDealer, viewCustomer, createCustomer, editCustomer, deleteCustomer, viewReports, exportData, manageUsers, configureFirebase, manageSettings, manageGoals` (customer perms sit between `deleteDealer` and `viewReports`).

`Permissions.forRole(role)`, `Permissions.resolve(role, {granted, revoked})`.
- USER: view + create on product/campaign/order; **createExpense** (view/create, no edit/delete on expense); view business/dealer/dashboard; **customer view/create/edit (NO delete)**; **viewReports**. No other deletes/edits/admin.
- ADMIN: full CRUD on product/campaign/order/expense/dealer within assigned businesses + **full customer CRUD incl. deleteCustomer** + **createExpense** + viewReports + exportData + **manageSettings + manageGoals** (since 1.5.0; the Owner can revoke either per admin). No manageUsers/configureFirebase/business CRUD. Owner-only regardless: Firebase setup, users, audit log, sign-in index, ID counters, Danger zone.
- OWNER: everything.

**Gate UI with `user.can(Permission.x)`. Repo enforces the same — service layer is source of truth.**

### date_utils (`lib/core/utils/date_utils.dart`)
- `DateRange(start, end)` — `.contains(date)`, `.days`, `.overlapDays(other)`, `toString()` → "dd-MMM-yyyy → dd-MMM-yyyy"
- `FinancialYear(startYear)` — `.forDate(date)` factory, `.endYear`, `.range`, `.previous`, `.next`, `.label` ("FY 2026-27"; "FY 2026" when it starts in January)
- Since 1.5.0 the FY start month is configurable: `FinancialYear.startMonth` (default `defaultStartMonth = 4`), `startMonths = [1, 4, 7, 10]`, `configureStartMonth(m)` (anything else → April; returns whether it changed; set by `SettingsController`). `FinancialQuarter` counts from it. Tests that change it must reset to 4 in `tearDown`.
- `enum PeriodType { financialYear, calendarYear, quarter, month, custom }` — `.label`
- `enum FinancialQuarter { q1, q2, q3, q4 }` — `.label` ("Q1 (Apr–Jun)"), `.startMonth`
- `AppDate.format(DateTime?)` ("dd-MMM-yyyy", "—" if null), `.short(d)`, `.monthYear(d)`, `.iso(d)`, `.tryParseIso(s)`, `.dayOnly(d)`. Display pattern is configurable: `AppDate.defaultPattern = 'dd-MMM-yyyy'`, current `AppDate.displayPattern`, `AppDate.configureDisplayFormat(pattern)` (wired to `AppState.setDateFormat`).
- `enum TimeBucket { month, quarter, year }`, `bucketForRange(range) → TimeBucket`
- `PeriodOptions.financialYears(Iterable<DateTime> dates, {DateTime? now})` / `PeriodOptions.calendarYears(dates, {now})` — build the selectable period lists from the data's activity dates (feed `data.activityDates(...)`).
- `enum ComparisonBasis { previousPeriod, lastYear }` — `.label`, `.shortLabel` ("vs previous period"). `ComparisonWindow.of(range, periodType, basis, {now})` → `{current, previous, isToDate}`. `shiftMonths(date, months, {keepMonthEnd})` clamps to the month's length.
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
`Routes.{login, forgotPassword, dashboard, alerts, businesses, businessDetail, products, productDetail, campaigns, campaignDetail, orders, orderDetail, expenses, expenseDetail, dealers, dealerDetail, customers, customerDetail, reports, users, settings, whatsNew}`. Path helpers for every detail route: `Routes.businessDetailPath(id)`, `productDetailPath(id)`, `campaignDetailPath(id)`, `orderDetailPath(id)`, `expenseDetailPath(id)`, `dealerDetailPath(id)`, `customerDetailPath(id)`; `Routes.reportsTab(tab)` → `/reports?tab=…`.
`kNavDestinations` (List<NavDestination>) already drives the sidebar (Users is `ownerOnly`; Customers gated on `viewCustomer`). Navigate with `context.go(Routes.x)` (import `go_router`).
**Route guard:** every shell route is wrapped in `PermissionGuard` (`app_router.dart`), which shows an access-denied message when `Routes.canOpen(user, location)` is false — so a pasted URL can't open a screen the sidebar hides. `Routes.sectionOf(location)` → the top-level section (`/orders/ORD-000001` → `/orders`); `Routes.accessFor(location)` → the `NavDestination` whose rule applies (detail pages inherit their list's rule; `null` for Settings and What's new, which every signed-in user can open — Settings gates its own sections). The sidebar highlights by `sectionOf`, so detail pages keep their section selected. A new route needs a `kNavDestinations` entry (or is open to all signed-in users).
**Shell & navigation (`lib/core/routing/nav_registry.dart`, since 1.2.0):** one `StatefulShellBranch` per section, in `kShellBranches` order (`test/nav_registry_test.dart` checks the router matches); each section keeps its own navigator, so lists keep their place. A new section needs: a `kNavDestinations` entry, a `kShellBranches` entry + branch in `app_router.dart` (same position), and a `kNavGroups` group. `NavRegistry`: `visible(user)`, `groupsFor(user)` (sidebar groups, empty ones dropped), `mobilePrimary(user)` (≤ 4 bottom-bar items), `branchIndexOf(location)`, `scopeFor(location)` → `ScopeUse` (which scope selectors the top bar shows: dashboard/reports both, list pages business, product/business detail period), `isSectionRoot`, `titleFor`. Navigate between sections with `ShellNav.go(context, route)` (returns to where the section was left); `context.go` still works for deep links.

### id_generator (`lib/core/utils/id_generator.dart`)
Sequential prefixes: `PROD, ORD, CMP, EXP, DLR, BIZ, USR, CUST` (customers → `CUST-00001`). Repo calls this; don't set ids yourself on create.

---

## 7. Reusable widgets

### Layout
- `PageHeader({required String title, String? subtitle, List<Widget> actions = const [], int? count, IconData? icon})` — `lib/widgets/common/page_header.dart`. `count` shows a pill next to the title (list pages), `icon` a gradient tile.
- `KpiStrip({required List<KpiItem> items, double minTileWidth=168, int maxColumns=6})` + `KpiItem({required String label, required String value, IconData? icon, Color? tone, String? caption, String? tooltip, VoidCallback? onTap})` — `lib/widgets/layout/kpi_strip.dart`. The headline figures under a list/detail header; tiles share the width evenly (≥ 2 per row) and wrap. Values are pre-formatted strings (figures come from the service).
- `DetailPage({required String title, required VoidCallback onBack, required List<Widget> children, String backLabel='Back', String? subtitle, IconData? icon, String? avatarName, Widget? status, List<DetailMeta> meta, Widget? primaryAction, List<Widget> actions, List<DetailAction> menu, List<KpiItem> kpis, Widget? banner, Widget? activity, String activityLabel='Activity'})` + `DetailPage.loading({title, onBack, backLabel})` / `DetailPage.notFound({title, onBack, backLabel, message})` — `lib/widgets/layout/detail_page.dart`. The layout of every record page: back row, header card (avatar or icon tile, title + status, subtitle, `DetailMeta(icon, text, {tooltip, onTap})` chips, actions + primary + a "More" `MenuAnchor` of `DetailAction({label, icon, onSelected, destructive})` with destructive items below a divider), `KpiStrip`, then `children` beside `activity` (380/320 px) on desktop or as Overview/Activity tabs on phones. Returns an `AppPage`; don't wrap it. Reference: `order_detail_screen.dart`.
- `AppShell` — already wired; screens don't touch it. Desktop (≥ 1024): `AppSidebar` (grouped, collapsible 248 ↔ 72 px, Pinned pages, footer with theme toggle + version) + `AppTopBar`. Tablet (640–1023): the collapsed `AppSidebar` as an icon rail, its menu button opens the full sidebar in a drawer. Phone (< 640): `AppTopBar(mobile: true)` + `AppBottomNav` (≤ 4 sections + More sheet) + a "new" FAB on list pages (`createActionForLocation`).
- `AppTopBar` — breadcrumbs (with a pin button), the scope selectors the page uses (`ScopeSelectors`, or the compact `ScopePill` that opens `showScopeSheet` when space is short), the palette trigger, quick-create menu, `SyncStatus`, `NotificationsButton`, `ProfileMenu` (Settings, What's new, Shortcuts, Theme, Sign out).
- `CommandPalette.show(context, {initialQuery})` — `lib/widgets/command_palette/`. Commands come from `CommandRegistry` (Navigate, Create — permission-gated, Records, Actions); records from `SearchIndex.of(data).search(query)` (`lib/services/search_index.dart`; scored exact > prefix > word > substring over the same fields the old search page used — `test/search_index_parity_test.dart`). Recent commands are remembered per user.
- `AppShortcuts` (`lib/core/shortcuts.dart`, in the shell): Ctrl/⌘ K and `/` open the palette, `N` new, `G` then `D/O/C/…` go to a section, `?` shows `showShortcutsHelp`. Single-key shortcuts are ignored while typing.
- `AppPage({children, maxWidth = 1400})` / `AppPage.slivers({slivers})` — the page scroll (see §0).
- `SyncStatus` (`lib/widgets/layout/sync_status.dart`) — header "Synced X ago · Sync now"; `syncedAgoLabel(DateTime?, DateTime now)` is the pure label.
- `WhatsNewPrompt` — in the shell; shows a one-time "Updated to version X" snackbar after an upgrade (`AppState.hasUnseenRelease` / `markReleaseSeen()`).

### Version & release notes
- `lib/core/app_info.dart` — `kAppVersion`, `kAppBuild`; **must equal** `pubspec.yaml` `version:` (`test/app_info_test.dart` enforces it). Shown in the sidebar footer.
- `lib/core/release_notes.dart` — `kReleaseNotes` (newest first, `ReleaseNote{version, date, title, highlights}`); the first entry must be `kAppVersion`. Rendered by `WhatsNewScreen` at `/whats-new`.
- Releasing: bump pubspec **and** `app_info.dart`, add a `kReleaseNotes` entry at the top.

### Cards / states — `lib/widgets/common/`
- `AppCard({required Widget child, EdgeInsetsGeometry padding=EdgeInsets.all(xl), VoidCallback? onTap, bool raised=false})` — outlined; tappable cards lift slightly on hover (not under reduced motion).
- `SectionCard({required String title, required Widget child, String? subtitle, Widget? trailing, padding})`
- `LoadingView({String? label})`, `SkeletonBox({width, height=16, radius})` (pulses; still under reduced motion), `SkeletonCard({lines=3, height})` — prefer skeletons to spinners for page content.
- `EmptyView({required String title, String? message, IconData icon=inbox_outlined, Widget? action})`
- `ErrorView({required String message, VoidCallback? onRetry})`
- `Scorecard({required String label, required String value, required IconData icon, Color accent=primary, String? caption, Color? captionTone, String? tooltip, VoidCallback? onTap})` — self-wraps in AppCard(padding lg); one Semantics label for the whole tile.
- `StatusBadge({required String label, BadgeTone tone=neutral})` + factories `.entity(EntityStatus)`, `.account(AccountStatus)`, `.order(OrderStatus)`, `.campaign(CampaignStatus)`, `.role(UserRole)`, `.deal(DealStatus)`. `enum BadgeTone { neutral, success, warning, error, info, primary }`
- `CurrencyText(Money money, {CurrencyCode currency=inr, TextStyle? style, bool colorNegative=true, bool precise=false})`
- `SearchField({required ValueChanged<String> onChanged, String hintText='Search…', double? width, Duration debounce})` (debounced)

### Data grid — `lib/widgets/data/` (since 1.4.0)
- `GridColumn<T>({required String id, required String label, required Widget Function(T) cell, bool numeric=false, Comparable Function(T)? sortValue, double? width, double? minWidth, int flex=1, String Function(T)? exportValue, GridFilter<T>? filter, bool visibleByDefault=true, bool pinned=false, CardRole? cardRole, String Function(List<T> rows)? footer, String? tooltip})`. **Ids are persisted** (saved views, column order) — never rename one. `footer` gets the filtered rows (all pages).
  - Filters: `GridFilter.choice(String Function(T), {List<String>? options})`, `GridFilter.dateRange(DateTime? Function(T))`, `GridFilter.numberRange(num? Function(T))`.
  - `CardRole { title, subtitle, badge, metric, meta, actions, hidden }` — how the column shows when the grid becomes cards below `cardBreakpoint` (640): one `title`, a `subtitle`, a status `badge`, `metric` figures, `meta` lines, `actions`.
  - Actions column: an `IconButton` is 48 px and cells have `AppSpacing.md` padding each side → `minWidth: 2 * AppSpacing.md + 48 * buttons`.
- `AppDataGrid<T>({required rows, required columns, Object Function(T)? rowKey, String? gridId, GridController? controller, String Function(T)? searchText, String externalSearch='', String searchHint, bool showToolbar=true, bool showSearch=true, String? title, String? subtitle, List<Widget> toolbarActions, List<GridQuickFilter<T>> quickFilters, void Function(T)? onRowTap, List<GridRowAction<T>> Function(T)? rowActions, List<GridBulkAction<T>> bulkActions, bool? selectable, String? exportName, VoidCallback? onExportAll, String exportAllLabel, String emptyTitle, String? emptyMessage, IconData emptyIcon, Widget? emptyAction, List<GridSort> initialSort, int? pageSize, bool framed=true, double cardBreakpoint})` — the box variant (detail sub-tables, reports, dashboard). `SliverAppDataGrid<T>(...)` — same parameters, for `AppPage.slivers` list pages (pinned header, virtualised rows).
  - `pageSize: null` (the usual) = the organisation's `defaults.pageSize` (25 unless changed). Density, zebra stripes and the fixed header follow `settings.tables` unless the user picked a density.
  - `gridId` turns on per-user persistence (`GridViewStore` in `UserPrefs`: sort, filters, columns, page size, density, saved views). With no saved columns, a grid starts from `settings.tables.defaultColumns[gridId]` (then `visibleByDefault`). Settings editors get **Save as default for everyone** in the column chooser (1 settings write); everyone gets **Reset to organisation default**. `rowKey` keeps selection stable across edits. `selectable` defaults on when there are `bulkActions`. `framed: false` only when the grid sits inside another card.
  - Toolbar: search (every word must match), filter chips, columns (show/hide, drag to reorder), density, page size (10/25/50/100/All), saved views, export (the current view: filtered rows, shown columns, `exportValue`s).
  - `GridQuickFilter<T>({id, label, test, icon})` — one-tap chips above the grid (statuses/types).
  - `GridRowAction<T>({label, icon, onSelected(BuildContext, T), destructive})`; `GridBulkAction<T>({label, icon, onRun(BuildContext, List<T>), bool Function(T)? allowed, destructive, children})` — `allowed` hides the action unless every selected row passes (permission/read-only rows); `children` makes a submenu (e.g. Change status → each status).
  - `runGridBulk<T>(context, {rows, task, verb, noun, describe})` — runs `task` per row with progress, confirms above `kBulkConfirmAbove` (write quota), reports failures, returns `BulkOutcome{done, failed}`. Confirm destructive bulk actions yourself first (`showConfirmDialog`).
- Reference: `lib/screens/orders/orders_screen.dart` (KPI strip, status quick filters, column filters, footers, bulk Change status/Delete, Duplicate, cards).

### Forms — `lib/widgets/forms/`
- `showAppForm<T>({required context, required WidgetBuilder builder, bool barrierDismissible=true, bool useRootNavigator=true})` — `app_form.dart`. **The way to open an entity form** (since 1.4.0): a right-hand side panel over a scrim on tablet/desktop (`formPanelWidth`), a full-screen route on phones. It has its own `ScaffoldMessenger`, so snacks shown from the form appear in it. Keep `showDialog` for small dialogs (confirm, refund, change password).
- `FormDialog({required String title, required Widget child, required Future<bool> Function() onSubmit, String submitLabel='Save', double width=560, String? subtitle, IconData? icon, String? draftKey})` — renders as panel / full screen / dialog depending on how it was opened (`AppFormScope.modeOf`). Spinner + no double-submit; **owns the single `Navigator.pop`** — pops(true) when onSubmit returns true. **See §11.1 — a child `_submit` must never also call `Navigator.pop`.** Ctrl/⌘ + Enter and Ctrl/⌘ + S submit (hint shown on desktop).
  - **Dirty guard:** typing or changing a field marks the form dirty ("Unsaved" dot); Esc, the scrim, Close, Cancel and back then ask "Discard changes?" (Discard / Keep draft / Keep editing). Closing goes through `Navigator.maybePop`, which respects the guard.
  - **Error summary:** a failed save lists "Label: message" for every invalid field (labels from the enclosing `LabeledField`); tapping one scrolls to it.
  - **Drafts:** with a `draftKey` (new records only, e.g. `isNew ? 'order.new' : null`) the text of every `AppTextField`/`AppMoneyField` is autosaved per user (800 ms debounce, 14 days, `FormDraftStore` in `UserPrefs`, never Firestore) and offered back next time ("Restore" / "Discard"). Saving clears it. Password and disabled fields are never stored.
- `FormSection({required String title, required List<Widget> children, IconData? icon, String? description, bool first=false})` — `form_section.dart`. A titled group of fields; with ≥ 2 sections the form shows chips that jump to each. Mark the first `first: true` (no rule above it).
- `FormRow(List<Widget> children)` — side-by-side desktop / stacked mobile.
- `FormGap()` — SizedBox(height: lg).
- `LabeledField({required label, required child, isRequired=false, helper})`
- `AppTextField({required String label, TextEditingController? controller, String? initialValue, String? Function(String?)? validator, TextInputType? keyboardType, bool isRequired=false, String? hintText, String? helper, int maxLines=1, bool obscureText=false, ValueChanged<String>? onChanged, List<TextInputFormatter>? inputFormatters, String? prefixText, bool enabled=true, Widget? prefixIcon, Widget? suffixIcon, TextInputAction? textInputAction, ValueChanged<String>? onFieldSubmitted, Iterable<String>? autofillHints, FocusNode? focusNode, bool autofocus=false})`
- `AppMoneyField({required String label, required TextEditingController controller, bool isRequired=false, String symbol='₹', validator, helper, ValueChanged<String>? onChanged})` — **pass the business's `currency.symbol`**. Allows `[0-9.,]`; digits are grouped on blur (`groupMoneyDigits(raw, {required bool indian})`: Indian 1,25,000 for ₹, else 125,000) and ungrouped on focus. `Money.parse` ignores the commas; prefill with `money.major.toString()`.
- `AppDropdown<T>({required String label, required T? value, required List<T> items, required String Function(T) itemLabel, required ValueChanged<T?> onChanged, bool isRequired=false, helper})`
- `AppSearchableDropdown<T>({required String label, required T? value, required List<T> items, required String Function(T) itemLabel, required ValueChanged<T?> onChanged, bool isRequired=false, helper, hintText, bool enabled=true})` — dropdown with a live search filter, for long lists (products, businesses, customers).
- `AppDateField({required String label, required DateTime? value, required ValueChanged<DateTime?> onChanged, bool isRequired=false, helper, DateTime? firstDate, DateTime? lastDate})` — calendar icon, a "Today" quick pick (when today is in range) and a Clear button (optional fields only).
- `SuggestionChips<T>({required List<Suggestion<T>> suggestions, required String Function(T) labelOf, required ValueChanged<T> onSelected, T? current})` — `suggestion_chips.dart`. Up to 3 one-tap chips under a field ("Suggested"); the tooltip is the reason. **Never fills a field without a tap**; hides itself when empty or when every suggestion equals `current`. Rebuild it with a `ListenableBuilder` on the controllers it reads.
- `SuggestionProvider` / `DartSuggestionProvider({DateTime? now})` — `lib/services/smart/suggestion_service.dart`. Ranks values from records already loaded (0 reads), by word overlap, frequency and recency: `expenseCategory({name, vendor, history, businessId})`, `campaignPlatform({name, history, businessId})`, `campaignType({typed, history, businessId})`, `orderPrice({productId, history})` (last price + median of the last 25 recognised orders). Each returns `List<Suggestion<T>>` (`value`, `reason`), best first. Only offer suggestions on **new** records. Used by the order, expense and campaign forms; P5 can put an on-device model behind the same interface.

### Dialogs — `lib/widgets/common/confirm_dialog.dart`
- `Future<bool> showConfirmDialog(context, {title, message, confirmLabel='Delete', cancelLabel='Cancel', bool destructive=true})` — Cancel has focus for destructive actions.
- `void showSuccessSnack(context, String)`
- `void showErrorSnack(context, Object error)` (maps via ErrorMapper)

### Detail & CRM widgets — `lib/widgets/common/`
Used to compose the 7 detail screens and the CRM.
- `detail_widgets.dart`: `bool looksLikeUrl(String)`, `void openExternalUrl(String url)` (no-op if not a resolvable URL); `DetailField(String label, String value, {IconData? icon, bool isLink=false})` (value object); `DetailGrid({required List<DetailField> fields})`, `DetailFieldTile({required DetailField field})`, `DetailTwoColumn({required Widget left, Widget? right})`; `CopyButton({required String label, required String value})` (copies to clipboard + snack), `LinkButton({required String value})`.
- `initials_avatar.dart`: `InitialsAvatar({required String name, double size=40, double? fontSize})` + static `InitialsAvatar.initialsOf(name)`, `InitialsAvatar.colorOf(name)` (deterministic color from name).
- `comment_thread.dart`: `LastActivityCard({required DateTime? activityAt})`; `EntityCommentThread({required List<EntityComment> comments, required bool canComment, required Future<void> Function(EntityComment) onPost})` — `onPost` receives the freshly-built comment and must save it (no refresh, §11.2); `DetailActivityColumn({required DateTime? activityAt, required List<EntityComment> comments, required bool canComment, required Future<void> Function(EntityComment) onPost})` (last-activity card + comment thread stacked).
- `team_access_card.dart`: `TeamAccessCard({required List<Business> businesses, String subtitle})` — who can see these businesses, as a tree per business (customer detail); `TeamAccessCard.business(Business, {String subtitle})` — one business, flat (business detail). Owners are listed for every business; admins/users by `assignedBusinessIds`. The roster needs the Owner-only `users` list (`fetchUsersCached()`), so other roles see the business tree without names (multi-business) or a short note (single business).
- `csv_actions.dart`: `void exportProductsCsv(ctx, List<Product>)`, `Future<void> importProductsCsv(ctx)`, `void exportCustomersCsv(ctx, List<Customer>)`, `Future<void> importCustomersCsv(ctx)` — gated on `exportData` / the relevant `createX` permission (self-check + `showErrorSnack` on denial).

### Charts — `lib/widgets/charts/`
- `ChartCard({required String title, required Widget child, String? subtitle, Widget? trailing, double height=280, bool isEmpty=false, String emptyMessage, IconData? icon, ChartTableData? table, Widget? footer})` — self-wraps in AppCard, sized box height, empty state built-in; with `table` it gets a "View as table" toggle.
- `chart_kit.dart`: `ChartKit` (axes, grid, tooltips, `niceMax`, gradients), `ChartReveal(id, builder: (context, k))` (one draw-in per id per session; `ChartReveal.reset()` in tests), `ChartLegend` (tap to hide a series), `ChartTableData(headers, rows)`.
- Since 1.3.0: `ProfitWaterfallChart(steps, currency)`, `TrendForecastChart(points, currency)` (dashed run-rate projection + Today line), `PlatformMixChart(mix, currency)`, `RoasChart(rows, currency, {limit, onTap})` (+ `RoasChart.pick`), `OrderStatusChart(breakdown)`, `BusinessComparisonChart(rows, currency)`, `ShareBars` (labelled horizontal bars).
- `ChartLegendDot({required Color color, required String label})`
- `RevenueExpenseChart({required List<TimeSeriesPoint> points, required CurrencyCode currency})` — grouped bars + built-in legend.
- `ExpenseDonutChart({required List<CategorySlice> slices, required CurrencyCode currency, String? centerLabel, String revealId})`
- `CategoryBarChart({required List<String> labels, required List<Money> values, required CurrencyCode currency, Color color=primary, String revealId})`
- `TrendLineChart({required List<String> labels, required List<double> values, Color color=primary, CurrencyCode? currency, String revealId, String seriesLabel})` — money axis if currency set, else integer.

---

## 8. Theme tokens — `lib/core/theme/`

Light **and** dark, branded at runtime (since 1.2.0). **Never use `AppColors` or `Color(0x…)` in widgets** — read colours from the theme (`test/theme_tokens_guard_test.dart` fails otherwise; the login brand panel and the PDF invoice are the only exceptions).

- `context.tokens` (`AppTokens`, a `ThemeExtension`): `primary`, `primaryDark`, `primaryLight`, `primarySurface`, `background`, `card`, `surfaceAlt`, `border`, `borderStrong`, `textPrimary`, `textSecondary`, `textTertiary`, `textOnPrimary`, `success`/`warning`/`error`/`info` + `…Surface`, `focusRing`, `skeletonBase`/`skeletonHighlight`, `chartSeries` (10), `cardShadow`, `raisedShadow`, `isDark`; `AppTokens.contrastRatio(a, b)`, `onColor(bg)`. Falls back to the default palette in a bare `MaterialApp` (tests).
- `AppPalette.light({brand})` keeps the brand colour exactly (defaults = the old `AppColors`); `AppPalette.dark({brand})` tone-shifts the brand and status colours to ≥ 4.5:1 on dark surfaces (`test/theme_controller_test.dart` checks AA for several brands).
- `context.motion` (`AppMotion`): `fast` 120, `base` 200, `slow` 320, `chart` 650 ms, `stagger`; `allowsMovement`, `enabled`; `AppMotion.standard` curve. Level = the stricter of the org setting, the user's Reduce motion, and the OS setting. Reduced → fades only; off → zero. No looping animations (skeletons excepted, and they stop when motion is reduced).
- `context.density` (`AppDensity.compact/comfortable/spacious`: control and row heights).
- `AppTheme.build({brand, brightness, density, motion, corners, chartPalette})` — Material 3, Inter, every component themed. `ThemeController` builds and memoises it; widgets never call it.
- `AppShape.of(context)` (since 1.5.0, a `ThemeExtension`): `radiusSm` / `radius` / `radiusLg` = `AppSpacing.radius*` × the organisation's `CornerStyle` scale (`sharp` 0.5, `standard` 1, `rounded` 1.5). Use it for new rounded surfaces; component themes and `AppCard` already do. Hard-coded `AppSpacing.radius` elsewhere stays at the standard size.
- `chartSeries` follows `ChartPaletteStyle` (`brand` — derived from the brand colour, `vivid`, `calm`, `mono`), in light and dark.

`AppSpacing`: `xs=4, sm=8, md=12, lg=16, xl=24, xxl=32`; `radius=12, radiusSm=8, radiusLg=16`; `mobileMax=640, tabletMax=1024`.

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

1. Lists: `AppPage.slivers([PageHeader(icon, count, actions), KpiStrip, SliverAppDataGrid])`. Records: `DetailPage(...)`. Otherwise `AppPage(children: [PageHeader(...), ...])`, one child per section. No Scaffold/scroll; no router wrapper. Copy `lib/screens/orders/` and `test/orders_screen_test.dart`.
2. `context.watch<DataController>()` for `loading`/`error`/`loaded` → show `LoadingView`/`ErrorView(onRetry: data.refresh)` early (inside an `AppPage`).
3. Scope lists via `data.*For(filter.selectedBusinessId)`.
4. Metrics via `const ProfitCalculationService()` over `filter.range`. Never compute money in the widget.
5. Currency = selected business currency (INR for All Businesses).
6. Create/Edit → `showAppForm<bool>` + `FormDialog(icon, draftKey for new records)` with `FormSection`s, in a StatefulWidget with `GlobalKey<FormState>`; on submit call `repo.saveX(...)`, `showSuccessSnack`, return true — **no refresh** (the change stream updates the lists). Catch → `showErrorSnack`, return false.
7. Delete/archive → `showConfirmDialog` then `repo.deleteX(id, known: entity)`/`archiveBusiness(id, known: biz)`, snack.
8. Gate every action button with `user.can(Permission.x)` (and `user.isOwner` where owner-only). New-business select needs a business chosen (can't create product without one).
9. Grid layout: use `LayoutBuilder`/`Wrap` or `Responsive` for scorecard/chart grids (e.g. `Wrap` with fixed-width cards, or `Row` of `Expanded` on desktop).

---

## 11. Gotchas & contracts (learned the hard way — do not relearn)

### 11.1 FormDialog owns the single pop
`FormDialog` calls `Navigator.pop(true)` itself when its `onSubmit` returns `true`. A child dialog's `_submit` must **persist-and-return-bool, NEVER call `Navigator.pop`** — doing both pops twice, tears down the page route beneath, and leaves a blank white screen (the save still runs, so it looks like data vanished). The caller keys off the returned bool: `if (saved == true) showSuccessSnack(...);`. A dialog that must return a **payload** (not a bool) via `showDialog<T>` (e.g. the orders Refund dialog returning a result object) pops itself with the payload and then **`return false`** so FormDialog doesn't pop again.

### 11.2 Never refresh after a mutation (changed in 1.1.0)
`DataController` applies `Repository.changes` in place, so a save is visible immediately and costs no reads. The old `await data.refresh()` after every save re-read all 7 collections (≈189k reads/day at 1.5k docs × 100 edits — far past the Spark 50k/day quota). Only `ErrorView` retry, the header's "Sync now" and the stale-tab soft sync read from the server. If you add a repository write, emit a `RepoChange` for it (after the write succeeds) and teach `DataController._apply` its collection.

### 11.3 Firestore rules are NOT filters
Every non-owner list query must be **provably authorizable by its own where-clauses**, because Firestore evaluates the read rule against the *query*, not the returned rows. Customers are scoped by `array-contains` on `businessIds`: `Repository.fetchCustomers` fans out one `fetchWhereArrayContains(customers, 'businessIds', biz)` per assigned business and dedupes by id — it never issues an unfiltered `list()`. **Do NOT add conditional / data-shape branches to the customers read rule**, and do not "optimize" the fan-out into a single unscoped query — either reintroduces the Sept 2026 Admin/User lockout. On write, `saveCustomer` merges back business tags & contracts the caller can't see so a limited-scope edit never drops another business's data.

### 11.4 DataController per-collection load isolation
`DataController.load()` treats only `businesses` as essential. Every other collection loads through a `guard` that degrades to `[]` + a `warnings` entry on failure. So a single denied/misconfigured query surfaces a warning banner, not a blank app. Preserve this — don't hoist another collection into the essential path, and don't let a `guard` rethrow.

### 11.5 Listing users is owner-only; identity lookups are not
`fetchUsers` / `createUser` / `saveUserProfile` / `setUserStatus` / `deleteUser` / access-request methods require `manageUsers`. But `fetchUserByUid` / `resolveUserByLogin` / `emailForLogin` / `touchLastLogin` are **unguarded** on purpose — they run before a role is known (login, self-profile). Keep that split. In Firebase mode a login ID is resolved via `loginIndex/{key}` (single-doc `get`, allowed before sign-in) — **never** by listing `users`, which the rules refuse before auth. `touchLastLogin` may only touch `lastLoginAt` (the rule checks `affectedKeys().hasOnly(['lastLoginAt'])`).

### 11.6 Never surface raw Firebase errors
Catch and route through `ErrorMapper.friendly(e)` / `showErrorSnack(ctx, e)`. Prefer soft delete/archive for anything financial.

### 11.7 Counters and the sign-in index are rules-backed
`counters/{prefix}`: prefix allow-list (`PROD, ORD, CMP, EXP, DLR, BIZ, USR, CUST`), `{value: int}` only, created by the Owner, and every update must **increase** the value (by ≤ 1000 for non-owners). No list, no delete. `loginIndex/{key}`: `get` for anyone, `list` denied, written by the Owner as `{email}` only. Trade-off (accepted): knowing a login ID reveals its email; email sign-in always works. Both degrade gracefully if the rules aren't deployed yet (scan fallback; `resolveUserByLogin`), so deploy **rules first, then hosting**, then run Users → "Rebuild sign-in index" once.

### 11.8 Hosting cache headers
`firebase.json` serves the un-hashed app files (`index.html`, `flutter_bootstrap.js`, `flutter.js`, `flutter_service_worker.js`, `main.dart.js` + parts, `manifest.json`, `version.json`, `assets/**`, `canvaskit/**`) with `no-cache` so users never get stuck on an old build. Only versioned folders (`/tfjs/**`, `/smart/**`) are `immutable`. No COOP/COEP headers — they break the Google sign-in popup. `test/firebase_json_test.dart` enforces all of this.

### 11.9 Dashboard 2.0 (since 1.3.0)
Every dashboard figure comes from `DashboardViewModel.of(data, filter)` (`lib/view_models/dashboard_view_model.dart`), memoised on the controller + `data.version` + the filter — never call the service from dashboard widgets. Sections are listed in `DashboardSectionId` / `kDefaultDashboardSections` (`widgets/dashboard_registry.dart`; P4 makes them admin-configurable) and laid out with `DashboardSection` + `DashTile(span, {tablet, mobile})` on a 12-column grid. KPI tiles take `KpiData`; `HeroKpiTile` sits on the brand band, `KpiTile` everywhere else. Dashboard tables search with `dashboardRows` **before** taking the top 10. Reports is a deferred library: **never import `reports_screen.dart` from the dashboard** — link with `Routes.reportsTab(tab)`. Motion is one-time per session (`Entrance`, `AnimatedNumber`, `ChartReveal` each have a static `reset()` — call them in widget tests' `setUp`); nothing loops.

### 11.10 Organisation settings and goals (since 1.5.0)
New collections `settings/{app|logo}` and `goals/{id}` need the 1.5.0 rules. Until they're deployed, settings fall back to the cached copy / defaults (`SettingsController.rulesMissing`) and goals to `[]` (`DataController.goalsUnavailable`); the Owner sees a "deploy the latest Firestore rules" hint. Deploy order: `firebase deploy --only firestore:rules`, **then** hosting. Goals keep the FY start month they were set under (`GoalPeriod.fyStartMonth`), so moving the FY start doesn't move existing goals' dates.

- **Modules and routing:** `buildRouter(appState, {settings})` sends a switched-off section (`!modules.allows(location)`, detail routes included) and the bare root / auth routes after sign-in to `landing()` — the organisation's `navigation.landingRoute` when it's on and the user may open it, else the dashboard. Nav, the command palette and quick-create hide switched-off sections too.
- **Branding:** `OrgLogo({required size, maxWidth, fit})` (`lib/widgets/common/org_logo.dart`) shows the organisation logo (nothing if none; `OrgLogo.dataUrlOf(context)` to decide a fallback). Used by the sidebar (with `branding.shortName` when collapsed) and the sign-in screen (when `showLogoOnLogin`, plus the tagline).
- **Money grouping:** `MoneyFormatter.configureGrouping(NumberGrouping)` — `byCurrency` (default: lakh/crore for ₹, thousands otherwise), `indian`, `international`. Global, like the FY start; tests that change it reset it.
- **Diagnostics** (Settings → System, Owner): version, data source, last sync, whether settings are saved, reads/writes this session (`UsageMeter`), records loaded and problems (`DataController.error`/`warnings`, settings/goals rules hints, `Repository.diagnostics`). Reads nothing; **Copy** puts a plain-text report on the clipboard.

### 11.11 Tests: wait for the profile after sign-in
`AppState.signIn` returns before the user's profile is attached to `appState.repository.currentUser`. A `DataController.load()` started in that gap belongs to "no account" and is discarded when the profile lands (the app reloads on the account change, so it only bites tests), leaving empty lists. Widget tests that need demo data must wait: `while (appState.repository.currentUser == null) await Future<void>.delayed(const Duration(milliseconds: 5));` before `data.load()` (see `test/orders_screen_test.dart`).
