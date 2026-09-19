# Salesforce Business Manager

A production-ready **Flutter Web** business management and profitability
tracking platform. Create and manage multiple businesses, track products,
marketing campaigns, orders, expenses and dealers, and get a live, financially
accurate picture of gross profit, contribution profit and net profit — with
role-based access, Indian financial-year reporting and Firebase persistence.

The app ships **connected to a live Firebase project by default** and signs in
with **Google**. A **built-in demo mode** is also available (offline, seeded
data) for exploring the product without any account — switch between the two
from **Settings → Firebase**.

---

## Highlights

- **Premium SaaS dashboard** — Material 3, light theme, Inter typography,
  responsive from desktop to mobile.
- **Live financials** — every number is computed from real data by a single
  `ProfitCalculationService`; nothing is hardcoded.
- **Indian financial year** — reporting defaults to the current FY (1 Apr –
  31 Mar); supports FY / calendar year / quarter / month / custom range.
- **Google Sign-In** — one-tap authentication via Firebase Auth; the first
  person to sign in claims the workspace as Owner (see below).
- **Role-based access** — Owner / Admin / User, enforced both in the service
  layer and in Firestore security rules.
- **Recurring-expense proration** — yearly/monthly/quarterly costs are prorated
  to the selected reporting period rather than naively summed.
- **Financially precise** — money is stored in integer minor units (paise), so
  there is no floating-point drift; INR uses Indian digit grouping (₹1,25,000).
- **Full CRUD** across businesses, products, campaigns, orders, expenses,
  dealers and users, with soft-delete/archive for financial records.
- **Reports + CSV export** respecting the current business, period and the
  signed-in user's permissions.

---

## Requirements

- **Flutter SDK** 3.x (Dart 3) with web support enabled
- **Chrome** (or any Chromium browser) for `flutter run -d chrome`
- A **Firebase** account + the **Firebase CLI** (only if you want to move off
  demo mode to a live backend)

Verify your toolchain:

```bash
flutter --version
flutter config --enable-web
flutter devices        # should list "Chrome"
```

---

## Installation

```bash
flutter pub get
```

## Run

```bash
flutter run -d chrome
```

The app boots **connected to Firebase** and presents **Continue with Google**.
The bundled project (`mybusiness-manager-bm`) is configured out of the box — the
public client config lives in
[`lib/models/firebase_config.dart`](lib/models/firebase_config.dart)
(`FirebaseConfig.defaultConfig`). To point at a different project, use
**Settings → Firebase → Reconfigure** (Owner only).

### First sign-in claims the workspace

A brand-new Firestore has no user profiles. To avoid manual seeding, **the first
person to sign in with Google is automatically provisioned as the Owner** and
the project is marked "claimed" (a `meta/system` sentinel document). Everyone
who signs in afterward gets no access until the Owner invites them from the
**Users** screen and assigns businesses — this is enforced by the Firestore
rules, not just the UI.

### Demo mode (offline, zero setup)

Prefer to explore without Google? From **Settings → Firebase → Switch to demo**,
or on first launch the app can be pointed at the local demo backend. Demo mode
adds a username/password form and one-tap logins:

| Role  | Login ID | Password   |
|-------|----------|------------|
| Owner | `owner`  | `demo1234` |
| Admin | `admin`  | `demo1234` |
| User  | `staff`  | `demo1234` |

> Demo data lives in this browser only. Reset it anytime from
> **Settings → Demo Data → Reset Demo Data** (Owner, demo mode only).
> "Continue with Google" in demo mode signs in as the demo Owner.

---

## Firebase Setup (using your own project)

The app is already wired to a Firebase project. To connect **your own** instead,
you need three things enabled on the Firebase side, then either edit
`FirebaseConfig.defaultConfig` or use the in-app wizard at
**Settings → Firebase → Reconfigure**.

> **Security note.** Only *public* client configuration values (`apiKey`,
> `authDomain`, `projectId`, `storageBucket`, `messagingSenderId`, `appId`,
> `measurementId`, and an optional Realtime Database URL) are stored. These are
> **not** secret credentials and are safe to embed in a web build. Never enter
> service-account keys, Admin SDK private keys, API secrets or passwords — the
> app neither asks for nor stores them.

### 1. Create a Firebase project
Open the [Firebase Console](https://console.firebase.google.com/), click
**Add project**, name it, and finish setup.

### 2. Enable Google Authentication
Build → **Authentication** → **Get started** → enable the **Google** sign-in
provider → Save. Under **Authentication → Settings → Authorized domains**, add
the domain you serve the web app from (`localhost` is authorized by default for
local development).

### 3. Create the Firestore database
Build → **Firestore Database** → **Create database** → choose a region →
start in production mode. Then deploy the security rules (see below).

### 4. Register a Web App
Project settings → **Your apps** → add a **Web app** (`</>`), register it, and
copy the `firebaseConfig` object values.

### 5. Point the app at your project
Either replace the values in `FirebaseConfig.defaultConfig`, **or** run the app,
go to **Settings → Firebase → Reconfigure**, paste the config values →
**Test Connection** → **Save & Activate**. The app switches to your project and
prompts you to sign in with Google against it.

### Deploy Firestore security rules

The repository includes [`firestore.rules`](firestore.rules), which enforce the
Owner/Admin/User model, per-business isolation, and the one-time first-Owner
bootstrap on the backend.

```bash
firebase login
firebase init firestore      # if not already initialised; point it at firestore.rules
firebase deploy --only firestore:rules
```

### The first Owner

There is **no manual seeding step**. Deploy the rules, then simply sign in with
Google — the first sign-in provisions your Owner profile and claims the project.
From **Users**, that Owner then invites Admin and User accounts and assigns them
to businesses.

---

## Build & Deploy

Build the optimized web bundle:

```bash
flutter build web
```

The output is written to `build/web/`. Deploy it to Firebase Hosting:

```bash
firebase init hosting        # set public directory to "build/web"
firebase deploy --only hosting
```

(Any static host — Netlify, Vercel, S3/CloudFront, GitHub Pages — also works;
just serve the contents of `build/web/`.)

---

## Testing

```bash
flutter analyze   # static analysis — expected clean
flutter test      # unit + widget tests
```

The suite covers the financially critical logic:

- **`test/money_test.dart`** — integer-minor-unit arithmetic (no float drift),
  parsing, and INR/compact formatting.
- **`test/date_utils_test.dart`** — Indian FY boundaries and labels, date-range
  containment/overlap, chart bucketing, configurable date format.
- **`test/profit_calculation_service_test.dart`** — revenue, product cost, gross
  / contribution / net profit, gross & net margin (zero-revenue safe), ROI,
  ROAS, recurring-expense proration and per-product/campaign roll-ups.
- **`test/permissions_test.dart`** — role defaults, per-user grant/revoke
  overrides, `can()` gating with account status, and business isolation.
- **`test/widget_test.dart`** — reusable UI component smoke tests.

---

## Architecture

Clean separation of concerns — business logic never lives in widgets:

```
lib/
├── main.dart                 # entry, provider wiring, auth→data bridge
├── core/
│   ├── enums.dart            # wire/label domain enums
│   ├── permissions.dart      # Permission catalogue + role resolver
│   ├── theme/                # colors, spacing, Material 3 theme
│   ├── routing/              # go_router config + auth redirect
│   ├── utils/                # Money, DateRange/FinancialYear, formatters
│   └── validators.dart
├── models/                   # immutable domain models (Money-typed)
├── services/
│   └── profit_calculation_service.dart   # THE financial engine
├── data/
│   ├── backend.dart          # Backend abstraction + Collections
│   ├── local_backend.dart    # in-browser demo backend + seed
│   ├── firebase_backend.dart # Firestore/Auth backend
│   ├── repository.dart       # CRUD + permission guards + ID generation
│   └── config_store.dart     # app prefs + Firebase config persistence
├── state/                    # AppState, DataController, FilterController
├── widgets/                  # reusable UI (cards, tables, forms, charts…)
└── screens/                  # dashboard, businesses, products, campaigns,
                              # orders, expenses, dealers, reports, users,
                              # settings, auth
```

### Data model (Firestore)

Flat top-level collections; every business-scoped document carries a
`businessId`:

```
users/{uid}
businesses/{businessId}
products/{productId}        # + businessId
campaigns/{campaignId}      # + businessId, productId
orders/{orderId}            # + businessId, productId
expenses/{expenseId}        # + businessId (dealer-sourced rows are read-only)
dealers/{dealerId}          # + businessId (mirrored into expenses)
auditLogs/{logId}           # append-only
meta/system                 # first-Owner bootstrap sentinel (created once)
```

### Financial formulas (single source of truth)

```
Product Revenue     = Selling Cost × Quantity
Total Revenue       = Product Revenue + Shipping + Other − Discount
Product Cost        = Buying Price × Quantity        (price at time of order)
Gross Profit        = Revenue − Product Cost
Contribution Profit = Gross Profit − Marketing Cost
Net Profit          = Revenue − Product Cost − Marketing − Operating Expenses
Gross/Net Margin    = Profit / Revenue × 100         (0 when revenue is 0)
ROI %               = (Attributed Revenue − Spend) / Spend × 100   (N/A if 0)
ROAS                = Attributed Revenue / Spend                    (N/A if 0)
```

Cancelled/returned orders are excluded from recognised revenue. Recurring
expenses are annualised then prorated by the fraction of the year covered by the
selected period (and clipped to the expense's own active window).

---

## Roles at a glance

| Capability                           | Owner | Admin | User |
|--------------------------------------|:-----:|:-----:|:----:|
| View dashboard / reports             |  ✅   |  ✅   |  ✅  |
| Create products / campaigns / orders |  ✅   |  ✅   |  ✅  |
| Edit / delete records                |  ✅   |  ✅   |  ⚙️  |
| Manage expenses / dealers            |  ✅   |  ✅   |  ❌  |
| Manage users                         |  ✅   |  ❌   |  ❌  |
| Configure Firebase / settings        |  ✅   |  ❌   |  ❌  |
| Access all businesses                |  ✅   | assigned | assigned |

⚙️ = configurable per-user via permission overrides (Users → Edit user).

Admins and Users only ever see data for the businesses assigned to them —
enforced in the repository **and** in Firestore rules.

---

## Security

- Firebase Authentication via **Google Sign-In** (demo mode also offers a
  login-id/password form resolved to an email).
- Firestore security rules enforce role and per-business authorization; the UI
  is never the sole gate. The first-Owner bootstrap is a single, rule-gated
  self-provision that closes permanently once `meta/system` exists.
- Only public Firebase client config is stored; no secrets or service-account
  keys in client code or Firestore.
- Soft delete / archive for financial records; delete confirmations throughout.
- Audit fields (`createdAt/By`, `updatedAt/By`) on records plus an append-only
  `auditLogs` trail.
