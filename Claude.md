# Build a Production-Ready Flutter Web Application: "Salesforce Business Manager"

## 1. Project Overview

Build a modern, production-ready **Flutter Web application** called:

**Salesforce Business Manager**

The application is a business management and profitability tracking platform.

The primary purpose is to allow a user to:

* Create and manage multiple businesses
* Create and manage products within each business
* Track advertising/marketing campaigns for products
* Track product orders and sales
* Track product purchase/buying costs
* Track recurring and non-recurring business expenses
* Manage multiple dealers/vendors
* Calculate Gross Profit
* Calculate Net Profit
* Analyse expenses by category
* Analyse business performance over different time periods
* Manage users and permissions using Owner/Admin/User roles
* Store all application data in Firebase
* Configure Firebase from within the application by the Owner
* Perform complete CRUD operations throughout the application

The application must be designed as a **serious business management SaaS-style dashboard**, not as a basic CRUD demo.

---

# 2. Technology Stack

Use:

* Flutter
* Dart
* Flutter Web
* Firebase
* Firebase Authentication
* Firebase Firestore or Firebase Realtime Database
* Firebase Storage where required
* Responsive Flutter UI
* Material 3
* Google Fonts
* Charts/graphs using a suitable Flutter charting package
* Proper state management architecture

Prefer a clean architecture with clear separation between:

* UI
* Models
* Services
* Repositories
* Controllers/ViewModels
* Firebase integration
* Authentication
* Permissions
* Business logic

Do not put Firebase queries and business logic directly inside UI widgets.

---

# 3. Application Design

## Design Direction

Create a premium, modern SaaS dashboard.

The design must be:

* Light theme only
* No dark mode
* Clean
* Professional
* Minimal
* Modern
* Highly responsive
* Desktop-first but fully usable on tablets and mobile
* Suitable for business/finance management
* Easy to understand
* Visually polished

Use:

* White backgrounds
* Very light grey surfaces
* Purple/indigo primary accent
* Subtle shadows
* Rounded cards
* Clean typography
* Modern icons
* Consistent spacing
* Professional tables
* Attractive charts
* Clear status badges
* Tooltips
* Hover effects
* Smooth transitions
* Loading states
* Empty states
* Error states
* Confirmation dialogs

Do NOT use:

* Dark theme
* Excessive gradients
* Excessive animations
* Neon colours
* Cluttered layouts
* Tiny fonts
* Excessive rounded elements
* Generic template-looking UI

Use a modern typography system such as **Inter**.

---

# 4. Application Layout

## Desktop

Use a persistent left sidebar.

Sidebar:

* Dashboard
* Businesses
* Products
* Campaigns
* Orders
* Expenses
* Dealers
* Reports
* Users
* Settings

Bottom of sidebar:

* Current user
* Role
* Profile
* Logout

Top application bar:

* Business selector
* Global date/FY selector
* Search
* Notifications
* User profile

---

# 5. Responsive Behaviour

The application MUST be fully responsive.

### Desktop

Use:

* Sidebar
* Multi-column dashboard
* Full data tables
* Advanced filters

### Tablet

Use:

* Collapsible sidebar
* Responsive cards
* Responsive tables
* Horizontal scrolling only where absolutely necessary

### Mobile

Use:

* Navigation drawer
* Single-column dashboard
* Responsive cards
* Compact tables
* Bottom/action menus where appropriate
* Mobile-friendly forms

No page should overflow horizontally unnecessarily.

---

# 6. Authentication

Implement authentication with Firebase.

Users should be able to log in using:

* Username/ID
* Password

The application should internally map the user ID to the authentication account.

Authentication must be secure.

After login:

1. Authenticate user
2. Retrieve user profile
3. Retrieve assigned role
4. Retrieve assigned businesses
5. Apply permission rules
6. Redirect to Dashboard

Implement:

* Login
* Logout
* Forgot password
* Change password
* Session handling
* Authentication state listener
* Unauthorized access handling

---

# 7. User Roles

There are exactly three roles:

## OWNER

Owner has complete access.

Permissions:

* View all businesses
* Create business
* Edit business
* Delete business
* View all products
* Create/edit/delete products
* View/create/edit/delete campaigns
* View/create/edit/delete orders
* View/create/edit/delete expenses
* Manage dealers
* Manage users
* Create Admin users
* Create User users
* Assign businesses
* Configure Firebase
* Application settings
* View all reports
* Export data
* Full dashboard access

Owner is the highest-level role.

---

## ADMIN

Admin is assigned to one or more businesses.

Admin can:

* View assigned businesses
* Create/edit products
* Create/edit campaigns
* Create/edit orders
* Create/edit expenses
* Manage dealers
* View reports
* View dashboard
* Export permitted data

Admin cannot:

* Manage Owner
* Configure Firebase
* Modify global application configuration
* Access businesses that are not assigned
* Create/modify Owner accounts

---

## USER

User has restricted access.

User should only have:

* View access
* Add access to permitted modules

For example:

* View products
* Add products
* View campaigns
* Add campaigns
* View orders
* Add orders

Do not allow User to:

* Delete important records
* Modify application settings
* Manage users
* Configure Firebase
* Access unauthorized businesses

Permissions should be configurable per user/module where practical.

---

# 8. Business Management

Owner can create multiple businesses.

Business fields:

* Business ID
* Business Name
* Business Description
* Business Type
* Website
* Currency
* Country
* Status
* Created Date
* Updated Date

Business status:

* Active
* Inactive

Each business must have its own:

* Products
* Campaigns
* Orders
* Expenses
* Dealers
* Reports
* Profit calculations

Users must never see data belonging to businesses they are not authorized to access.

---

# 9. Product Management

Each business can contain multiple products.

Product fields:

* Product ID
* Product Name
* Product Description
* Buying Price
* Selling Price / Default Selling Cost
* Product URL
* SKU
* Category
* Status
* Created Date
* Updated Date

Product ID must be unique.

Example:

PROD-00001

Automatically generate IDs.

Product URL should be clickable.

Product page should show:

### Product Summary

* Product Name
* Product ID
* Buying Price
* Default Selling Price
* Total Orders
* Units Sold
* Revenue
* Product Cost
* Marketing Cost
* Gross Profit
* Net Profit

### Product Campaigns

Show all campaigns associated with the product.

### Product Orders

Show all orders associated with the product.

---

# 10. Campaign / Marketing Management

Each product can have multiple advertising campaigns.

Campaign fields:

* Campaign ID
* Campaign Name
* Product
* Platform
* Campaign Type
* Start Date
* End Date
* Budget
* Amount Invested
* Impressions
* Clicks
* Conversions
* Status
* Campaign URL
* Notes

Platforms can include:

* Meta Ads
* Google Ads
* TikTok Ads
* YouTube Ads
* LinkedIn Ads
* Other

Campaign status:

* Draft
* Active
* Paused
* Completed
* Cancelled

Marketing cost should contribute to business/product profitability calculations.

Dashboard metrics should include:

* Total Marketing Spend
* Campaign Count
* Active Campaigns
* Marketing Spend by Platform
* Marketing Spend by Product
* Marketing Spend over time

---

# 11. Order Management

Orders belong to a business and product.

Order fields:

* Order ID
* Product ID
* Product Name
* Order Date
* Quantity
* Selling Cost
* Discount
* Shipping Revenue
* Other Revenue
* Total Revenue
* Buying Cost
* Marketing Allocation
* Order Status
* Customer Reference
* Notes

Order statuses:

* Pending
* Confirmed
* Processing
* Shipped
* Delivered
* Cancelled
* Returned

Order ID must be unique.

Example:

ORD-000001

Automatically generate sequential IDs.

---

# 12. Revenue Calculation

For an order:

```text
Product Revenue =
Selling Cost × Quantity

Total Revenue =
Product Revenue
+ Shipping Revenue
+ Other Revenue
- Discount
```

Orders marked as cancelled should not contribute to recognized revenue unless explicitly configured.

Returns should be handled appropriately.

---

# 13. Product Cost Calculation

For each order:

```text
Product Cost =
Buying Price × Quantity
```

Use the product buying price applicable at the time of order where possible.

Do not blindly use the current product buying price for historical orders.

---

# 14. Gross Profit

Calculate:

```text
Gross Revenue
- Product Cost
= Gross Profit
```

Also calculate:

```text
Gross Margin % =
Gross Profit / Gross Revenue × 100
```

Handle zero revenue safely.

---

# 15. Marketing Cost

Marketing expenses related to campaigns should be tracked separately.

For reporting:

```text
Gross Profit
- Marketing Cost
= Contribution Profit
```

Display this clearly so the user can understand the impact of advertising.

---

# 16. Business Expenses

Businesses have their own operating costs.

Expense categories should include:

* Domain
* CRM
* Hosting
* Dealer
* Software
* Subscription
* Payment Gateway
* Shipping
* Office
* Employee
* Advertising
* Other

Each expense should have:

* Expense ID
* Business ID
* Category
* Expense Name
* Description
* Amount
* Currency
* Frequency
* Start Date
* End Date
* Vendor
* Status
* Notes
* Created Date
* Updated Date

---

# 17. Recurring Expenses

Support:

* Monthly
* Quarterly
* Half-Yearly
* Yearly
* One-Time

Example:

Domain:

₹1,200/year

Hosting:

₹3,000/year

CRM:

₹2,000/month

Dealer:

₹5,000/month

The application should calculate the relevant expense for the selected reporting period.

Do not simply add yearly costs to monthly reports.

Example:

If yearly domain cost is ₹12,000:

```text
Monthly equivalent = ₹1,000
```

For annual reporting:

```text
₹12,000
```

For quarterly reporting:

```text
₹3,000
```

The reporting engine should correctly prorate recurring costs based on the selected period.

---

# 18. Dealer Management

Each business can have multiple dealers.

Dealer fields:

* Dealer ID
* Dealer Name
* Dealer URL
* Dealer Description
* Cost
* Cost Frequency
* Start Date
* End Date
* Status
* Contact Name
* Contact Information
* Notes

Example:

Dealer:

ABC Supplier

Cost:

₹10,000/month

The dealer expense should automatically appear under Business Expenses.

---

# 19. Dashboard

The Dashboard is the most important screen.

It must be highly polished.

At the top:

### Filters

* Business
* Financial Year
* Year
* Quarter
* Month
* Custom Date Range
* Product
* Category
* Campaign Platform

Default filter:

**Current Financial Year**

For India, default financial year:

```text
1 April – 31 March
```

Example:

If current date is September 2026:

```text
FY 2026-27
```

---

# 20. Dashboard Scorecards

Display:

### Total Revenue

Total recognized sales revenue.

### Product Cost

Total product purchasing cost.

### Marketing Cost

Total campaign/advertising spend.

### Operating Expenses

Domain, CRM, hosting, dealer and other business expenses.

### Gross Profit

```text
Revenue - Product Cost
```

### Contribution Profit

```text
Gross Profit - Marketing Cost
```

### Net Profit

```text
Revenue
- Product Cost
- Marketing Cost
- Operating Expenses
```

### Net Margin

```text
Net Profit / Revenue × 100
```

### Total Orders

Number of valid orders.

### Units Sold

Total quantity sold.

---

# 21. Dashboard Charts

Create professional interactive charts.

## Revenue vs Expenses

Bar/line chart:

* Revenue
* Product Cost
* Marketing
* Operating Expenses
* Net Profit

Grouped by:

* Month
* Quarter
* Year

depending on selected date range.

---

## Expense Breakdown

Donut chart showing:

* Product Cost
* Marketing
* Domain
* CRM
* Hosting
* Dealer
* Other

---

## Revenue by Product

Bar chart:

```text
Product → Revenue
```

---

## Profit by Product

Bar chart:

```text
Product → Net Profit
```

---

## Marketing Spend

Chart:

```text
Month → Marketing Spend
```

---

## Orders Trend

Line chart:

```text
Date → Orders
```

---

# 22. Dashboard Tables

Include:

### Top Products

Columns:

* Product
* Orders
* Revenue
* Cost
* Marketing
* Gross Profit
* Net Profit
* Margin %

---

### Recent Orders

Columns:

* Order ID
* Product
* Date
* Revenue
* Cost
* Profit
* Status

---

### Campaign Performance

Columns:

* Campaign
* Product
* Platform
* Spend
* Clicks
* Conversions
* Revenue
* ROI

ROI:

```text
ROI =
(Revenue - Marketing Cost) / Marketing Cost × 100
```

Handle zero marketing cost safely.

---

# 23. Financial Year Support

The application must support Indian financial years.

Example:

```text
FY 2025-26
01-Apr-2025 → 31-Mar-2026

FY 2026-27
01-Apr-2026 → 31-Mar-2027
```

Dashboard should default to the current FY.

Allow users to select:

* Current FY
* Previous FY
* Next FY
* Calendar Year
* Quarter
* Month
* Custom Range

---

# 24. Reports

Create a dedicated Reports section.

Reports:

### Sales Report

* Revenue
* Orders
* Quantity
* Product
* Date

### Expense Report

* Expense category
* Amount
* Frequency
* Date

### Marketing Report

* Campaign
* Platform
* Spend
* Revenue
* ROI

### Product Profitability

* Product
* Revenue
* Product Cost
* Marketing
* Expenses
* Gross Profit
* Net Profit

### Business Profitability

* Revenue
* Total Expenses
* Gross Profit
* Net Profit
* Margin

Allow:

* CSV export
* Excel-compatible export
* PDF export where practical
* Print

---

# 25. Search and Filtering

All major tables must support:

* Search
* Sort
* Pagination
* Filters
* Date filtering
* Status filtering
* Business filtering
* Product filtering

Use debounced search where appropriate.

---

# 26. CRUD Operations

Implement complete CRUD.

### Business

Create / Read / Update / Delete

### Product

Create / Read / Update / Delete

### Campaign

Create / Read / Update / Delete

### Order

Create / Read / Update / Delete

### Expense

Create / Read / Update / Delete

### Dealer

Create / Read / Update / Delete

### User

Create / Read / Update / Disable

Do not permanently delete important financial records by default.

Prefer:

```text
Active
Inactive
Archived
```

where appropriate.

---

# 27. Delete Confirmation

Never immediately delete important records.

Show confirmation dialog:

```text
Are you sure?

This action cannot be easily undone.

Cancel
Delete
```

For financial records, consider soft deletion.

---

# 28. User Management

Owner-only screen.

Owner can:

* Create Admin
* Create User
* Edit users
* Disable users
* Reset password
* Assign businesses
* Configure permissions

User fields:

* User ID
* Name
* Email
* Role
* Assigned Businesses
* Status
* Created Date
* Last Login

Roles:

```text
OWNER
ADMIN
USER
```

Owner cannot create another Owner through the standard interface unless explicitly configured.

---

# 29. Permission System

Implement centralized permission checks.

Example:

```text
canViewDashboard
canCreateProduct
canEditProduct
canDeleteProduct
canCreateCampaign
canEditCampaign
canDeleteCampaign
canCreateOrder
canEditOrder
canDeleteOrder
canManageExpenses
canManageDealers
canManageUsers
canConfigureFirebase
```

Do not rely only on UI hiding.

Permissions must also be enforced in the data/service layer.

---

# 30. Firebase Configuration

The Owner should be able to configure Firebase from:

```text
Settings → Firebase Configuration
```

This screen should contain a detailed setup wizard.

IMPORTANT:

Firebase configuration must be treated securely.

Do not store private Firebase Admin credentials, service account private keys, API secrets, or passwords in Firestore.

Client-side Firebase configuration values are not secret credentials.

---

# 31. Firebase Setup Wizard

Create a step-by-step UI.

### Step 1 — Create Firebase Project

Explain:

1. Open Firebase Console
2. Create a Firebase project
3. Give it a project name
4. Continue through setup

Provide a button/link:

**Open Firebase Console**

---

### Step 2 — Enable Authentication

Explain:

1. Open Firebase Console
2. Go to Authentication
3. Enable Email/Password authentication
4. Save

---

### Step 3 — Create Database

Explain:

1. Open Firestore Database
2. Create database
3. Select region
4. Start with appropriate security configuration
5. Deploy security rules

---

### Step 4 — Register Web App

Explain:

1. Open Project Settings
2. Add Web App
3. Register the application
4. Copy Firebase configuration

Expected fields:

```text
apiKey
authDomain
projectId
storageBucket
messagingSenderId
appId
measurementId
```

---

### Step 5 — Configure Application

Provide a form for the Owner to enter:

* API Key
* Auth Domain
* Project ID
* Storage Bucket
* Messaging Sender ID
* App ID
* Measurement ID

Include:

* Test Connection
* Save Configuration
* Reset Configuration

Never expose sensitive credentials.

---

# 32. Firebase Configuration Storage

The application should support Firebase configuration persistence.

However, distinguish between:

### Public client configuration

Examples:

* apiKey
* authDomain
* projectId
* storageBucket
* messagingSenderId
* appId

and:

### Secret credentials

Never store:

* Service account private key
* Admin SDK private key
* Passwords
* Private API secrets

in Firestore.

---

# 33. Firestore Data Structure

Use a scalable structure.

Suggested structure:

```text
users/{userId}

businesses/{businessId}

businesses/{businessId}/products/{productId}

businesses/{businessId}/campaigns/{campaignId}

businesses/{businessId}/orders/{orderId}

businesses/{businessId}/expenses/{expenseId}

businesses/{businessId}/dealers/{dealerId}

businesses/{businessId}/reports/{reportId}
```

User-business assignments:

```text
users/{userId}/businessAccess/{businessId}
```

or a suitable normalized/denormalized structure.

Include:

* createdAt
* updatedAt
* createdBy
* updatedBy

where appropriate.

---

# 34. Firestore Security Rules

Create proper Firebase security rules.

Rules must enforce:

### Owner

Full access.

### Admin

Access only to assigned businesses.

### User

Access only to assigned businesses and allowed operations.

Never rely solely on Flutter UI permissions.

The backend security rules must enforce authorization.

---

# 35. Data Validation

Every form must have validation.

Examples:

Product:

```text
Product name required
Buying price >= 0
URL must be valid
```

Campaign:

```text
Campaign name required
Amount invested >= 0
Start date required
```

Order:

```text
Order ID required
Quantity > 0
Selling cost >= 0
```

Expense:

```text
Amount >= 0
Frequency required
Category required
```

---

# 36. Financial Precision

Use proper numeric handling.

Do not use floating-point arithmetic carelessly for financial calculations.

Use integer minor units where practical.

For INR:

```text
₹1 = 100 paise
```

Store monetary values consistently.

Display:

```text
₹1,25,000
```

Use Indian number formatting.

---

# 37. Currency

Business should have a currency.

Initially support:

* INR
* USD
* EUR
* GBP

Architecture should allow additional currencies later.

---

# 38. Notifications

Create notification support for:

* Failed Firebase connection
* Expiring subscription
* Campaign ending
* Important system messages
* User account events

Use an application notification center.

---

# 39. Loading / Error / Empty States

Every screen must support:

### Loading

Use polished skeleton loaders.

### Empty

Example:

```text
No products found

Create your first product to start tracking profitability.

+ Add Product
```

### Error

Show meaningful error messages.

Never display raw Firebase exceptions to users.

---

# 40. Audit Trail

For important records maintain:

* Created By
* Created At
* Updated By
* Updated At

For sensitive operations optionally maintain:

```text
auditLogs/{logId}
```

Track:

* User
* Action
* Entity
* Entity ID
* Timestamp
* Before
* After

---

# 41. Application Settings

Settings menu:

## General

* Application name
* Currency preferences
* Date format
* Number format

## Firebase

* Firebase setup wizard
* Connection status
* Configuration

## Users

* User management

## Permissions

* Role permissions

## Business

* Business defaults

## Data

* Export
* Backup information
* Import where supported

## Profile

* Name
* Email
* Password

---

# 42. Global Business Selector

If the logged-in user has access to multiple businesses:

Show:

```text
All Businesses
Business A
Business B
Business C
```

Owner can select:

```text
All Businesses
```

Dashboard should aggregate all authorized businesses.

Admin/User should only see businesses assigned to them.

---

# 43. Global Date Filter

Provide a global filter component:

```text
Financial Year
Quarter
Month
Custom Range
```

Default:

```text
Current Financial Year
```

The selected filter should affect:

* Dashboard scorecards
* Charts
* Tables
* Reports
* Profit calculations

---

# 44. Profit Calculation Engine

Create a centralized service:

```text
ProfitCalculationService
```

It should calculate:

```text
Revenue
Product Cost
Marketing Cost
Operating Expenses
Gross Profit
Contribution Profit
Net Profit
Gross Margin
Net Margin
ROI
ROAS
```

Do not duplicate financial calculation formulas throughout UI screens.

---

# 45. ROAS

For campaigns:

```text
ROAS =
Revenue Attributed to Campaign / Marketing Spend
```

Display:

```text
2.5x
```

If marketing spend is zero:

```text
N/A
```

---

# 46. Dashboard UX

Dashboard should immediately answer:

1. How much did I sell?
2. How much did I spend?
3. How much did products cost?
4. How much did I spend on marketing?
5. What is my gross profit?
6. What is my net profit?
7. Which products generate the most revenue?
8. Which products generate the most profit?
9. Which campaigns consume the most money?
10. Where are my expenses going?

---

# 47. Dashboard Visual Hierarchy

Top:

```text
Business Selector
FY Selector
Date Filter
```

Second row:

```text
Revenue
Gross Profit
Marketing
Net Profit
```

Third row:

```text
Revenue vs Expenses
Expense Breakdown
```

Fourth row:

```text
Revenue by Product
Profit by Product
```

Fifth row:

```text
Recent Orders
Campaign Performance
```

Make the dashboard visually balanced.

---

# 48. Global Search

Add global search.

Allow searching:

* Products
* Orders
* Campaigns
* Dealers
* Expenses
* Businesses

Search results should show entity type.

Example:

```text
PROD-00023
Wireless Earbuds

Product
Business: ABC Store
```

---

# 49. Export

Allow exporting filtered data.

Formats:

* CSV
* XLSX where supported
* PDF where practical

Export should respect:

* Current business
* Current filters
* Current date range
* User permissions

---

# 50. Performance

The application must be designed for scalability.

Use:

* Pagination
* Firestore queries
* Lazy loading
* Cached reference data
* Debounced searches
* Efficient chart aggregation
* Avoid unnecessary rebuilds
* Proper state management

Do not download entire collections unnecessarily.

---

# 51. Security

Implement:

* Firebase Authentication
* Firestore Security Rules
* Role-based access
* Business-level authorization
* Input validation
* Secure configuration handling
* Soft deletion for financial records
* Audit logs
* No secret credentials in client code
* No service-account keys in Firebase/Flutter

---

# 52. Code Architecture

Use a maintainable folder structure similar to:

```text
lib/
├── main.dart
├── app.dart
│
├── core/
│   ├── constants/
│   ├── theme/
│   ├── routing/
│   ├── utils/
│   ├── validators/
│   └── permissions/
│
├── models/
│   ├── user_model.dart
│   ├── business_model.dart
│   ├── product_model.dart
│   ├── campaign_model.dart
│   ├── order_model.dart
│   ├── expense_model.dart
│   ├── dealer_model.dart
│   └── audit_log_model.dart
│
├── services/
│   ├── auth_service.dart
│   ├── firebase_service.dart
│   ├── business_service.dart
│   ├── product_service.dart
│   ├── campaign_service.dart
│   ├── order_service.dart
│   ├── expense_service.dart
│   ├── dealer_service.dart
│   ├── user_service.dart
│   └── profit_calculation_service.dart
│
├── repositories/
│
├── controllers/
│
├── screens/
│   ├── auth/
│   ├── dashboard/
│   ├── businesses/
│   ├── products/
│   ├── campaigns/
│   ├── orders/
│   ├── expenses/
│   ├── dealers/
│   ├── reports/
│   ├── users/
│   └── settings/
│
├── widgets/
│   ├── common/
│   ├── dashboard/
│   ├── charts/
│   ├── tables/
│   ├── forms/
│   └── dialogs/
│
└── firebase/
    ├── firebase_config.dart
    └── firebase_initializer.dart
```

Adapt the structure if a better architecture is required, but maintain strict separation of concerns.

---

# 53. Reusable UI Components

Create reusable components for:

* App sidebar
* App header
* Page header
* Search field
* Filter bar
* Scorecard
* Data table
* Status badge
* Currency display
* Date selector
* Business selector
* Empty state
* Error state
* Loading state
* Confirmation dialog
* Form field
* Primary button
* Secondary button
* Chart card
* Pagination

Do not duplicate UI code unnecessarily.

---

# 54. Theme

Create a centralized theme.

Example visual direction:

Primary:

```text
#582DD3
```

Background:

```text
#F7F8FC
```

Cards:

```text
#FFFFFF
```

Text:

```text
#1F2937
```

Secondary text:

```text
#6B7280
```

Success:

```text
Green
```

Warning:

```text
Amber
```

Error:

```text
Red
```

Use the theme consistently throughout the application.

---

# 55. Important UX Requirements

Every create/edit form should:

* Use clear labels
* Show required fields
* Validate input
* Preserve entered data when validation fails
* Show success feedback
* Show error feedback
* Prevent duplicate submissions

After successful creation:

```text
Product created successfully
```

and refresh relevant data.

---

# 56. Data Relationships

Relationships must be preserved.

Example:

```text
Business
   |
   ├── Products
   |      |
   |      ├── Campaigns
   |      |
   |      └── Orders
   |
   ├── Expenses
   |
   └── Dealers
```

Deleting a business must not accidentally leave inaccessible orphan data.

Prefer archive/soft delete for businesses containing financial records.

---

# 57. Demo / Seed Data

For development, provide optional seed/demo data.

Create:

```text
Demo Business
Demo Products
Demo Campaigns
Demo Orders
Demo Expenses
Demo Dealers
```

This allows the dashboard to immediately demonstrate realistic data.

Do not seed production data automatically.

---

# 58. Testing

Include tests for:

### Unit Tests

* Profit calculation
* Gross margin
* Net margin
* ROI
* ROAS
* Financial year calculation
* Recurring expense calculation
* Permission checks

### Widget Tests

* Login
* Dashboard
* Forms
* Tables
* Filters

### Integration Tests

* Authentication
* CRUD
* Business isolation
* Role permissions

---

# 59. Error Handling

Create centralized error handling.

Convert Firebase errors into user-friendly messages.

Example:

Instead of:

```text
FirebaseException: [cloud_firestore/permission-denied]
```

show:

```text
You don't have permission to perform this action.
```

---

# 60. Accessibility

Support:

* Keyboard navigation
* Accessible labels
* Good contrast
* Tooltips
* Responsive font sizing
* Screen-reader-friendly controls where practical

---

# 61. Final Deliverables

Generate a complete working Flutter Web application.

Deliver:

1. Complete Flutter source code
2. Firebase integration
3. Firebase Authentication
4. Firestore database integration
5. Firestore security rules
6. Firebase configuration flow
7. Role-based authorization
8. Business management
9. Product management
10. Campaign management
11. Order management
12. Expense management
13. Dealer management
14. User management
15. Dashboard
16. Reports
17. Charts
18. Filters
19. Search
20. CRUD operations
21. Responsive UI
22. Validation
23. Error handling
24. Loading states
25. Empty states
26. Audit fields/logging
27. Export functionality
28. Test/seed data
29. Unit tests for financial calculations
30. Setup documentation

---

# 62. README

Create a detailed README containing:

## Requirements

* Flutter SDK
* Dart
* Firebase account
* Firebase CLI

## Installation

```text
flutter pub get
```

## Firebase Setup

Explain:

1. Create Firebase project
2. Enable Authentication
3. Create Firestore
4. Register Web App
5. Configure Firebase
6. Deploy Firestore rules
7. Run Flutter Web

## Run

```text
flutter run -d chrome
```

## Build

```text
flutter build web
```

## Deploy

Explain Firebase Hosting deployment.

---

# 63. Important Implementation Rules

Do not create a fake/static dashboard.

All dashboard numbers must be derived from actual Firebase data.

Do not hardcode:

* Revenue
* Expenses
* Profit
* Orders
* Campaign spend

All financial metrics must be dynamically calculated.

Do not put business logic inside widgets.

Do not bypass Firebase security rules.

Do not store sensitive Firebase credentials.

Do not use dummy CRUD implementations.

Every major module must perform actual Firebase CRUD operations.

---

# 64. Development Approach

Build the application in logical phases:

### Phase 1

* Project setup
* Theme
* Routing
* Authentication
* Firebase integration

### Phase 2

* User roles
* Permissions
* Business management

### Phase 3

* Products
* Campaigns
* Orders

### Phase 4

* Expenses
* Dealers

### Phase 5

* Financial calculation engine
* Dashboard
* Charts

### Phase 6

* Reports
* Export

### Phase 7

* Settings
* Firebase setup wizard
* User management

### Phase 8

* Security rules
* Validation
* Testing
* Performance
* Responsive polishing

---

# 65. Expected Result

The final application should feel like a polished commercial SaaS product.

The user should be able to log in and immediately see:

```text
Salesforce Business Manager

FY 2026-27

Revenue              ₹5,42,500
Product Cost         ₹2,10,000
Marketing            ₹85,000
Operating Expenses   ₹42,500
──────────────────────────────
Gross Profit         ₹3,32,500
Net Profit           ₹2,05,000
Net Margin           37.8%
```

with interactive charts, tables, filters and drill-down capabilities.

The application must be:

**Responsive + Secure + Scalable + Firebase-powered + Role-based + Financially accurate + Production-ready.**

Do not treat this as a simple CRUD project. Build it as a complete business management SaaS web application.
