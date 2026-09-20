# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Project overview

**Salon Manager** — a web-based management system (ERP/POS) for hair salons and beauty parlors,
in the style of "Manager Pro" apps for the sector. Covers appointments/scheduling, client CRM
with technical history, point-of-sale/invoicing, inventory, staff commissions, and reporting.

The project is in its **initial scaffold stage**: the data model (Prisma schema) is fully
designed and the Next.js app builds and runs, but business logic, authentication, and the API
layer are not implemented yet.

## Stack

- **Framework**: Next.js 16 (App Router), TypeScript, React 19.
- **Styling**: Tailwind CSS.
- **Database**: PostgreSQL via Prisma ORM (`prisma/schema.prisma`).
- **Deployment target**: any Node.js host with a PostgreSQL database (e.g. Railway, Fly.io,
  Vercel + managed Postgres).

## Codebase structure

- `src/app/` — Next.js App Router pages and layouts. `page.tsx` currently renders a placeholder
  dashboard listing the six functional modules.
- `prisma/schema.prisma` — the full relational data model, organized in commented sections:
  1. Tenants & users (multi-tenant: every business table hangs off a `Tenant`)
  2. CRM — clients, technical notes (dye formulas, allergies), append-only history
  3. Catalog — services and products (retail vs. internal-use vs. both)
  4. Agenda — appointments and appointment/service line items
  5. POS/Invoicing — invoice series (fiscal numbering), invoices, lines, payments
  6. Cash register sessions and movements (till reconciliation)
  7. Stock — stock movements, suppliers, purchase orders
  8. Commissions — rules and calculated records per employee
  9. Reporting is intentionally **not** modeled as tables — build SQL views over the above.
- `.env.example` — required environment variables (`DATABASE_URL`).

## Development workflow

```bash
npm install                 # install dependencies
cp .env.example .env         # then point DATABASE_URL at a real Postgres instance
npx prisma generate          # regenerate the Prisma client after any schema change
npx prisma migrate dev       # create/apply a migration (needs a live database)
npm run dev                  # start the dev server (http://localhost:3000)
npm run build                # production build
npm run typecheck            # tsc --noEmit
npm run lint                 # next lint
```

There is no live database configured in this environment — schema changes are validated with
`prisma generate`/`prisma format`, not `prisma migrate`, until a real Postgres instance is wired
up.

## Architecture notes / conventions

- **Multi-tenant by design**: every business model carries a `tenantId` foreign key to `Tenant`,
  even though the current scope is a single salon. This avoids a painful migration if the product
  becomes multi-salon SaaS later.
- **Money fields** use Prisma `Decimal` (`@db.Decimal(10, 2)`), never `Float`, to avoid rounding
  errors in invoicing/accounting.
- **Invoices are never deleted or mutated** — cancellation is a `status` change
  (`ISSUED`/`CANCELLED`), and `hashPrev`/`hashSelf` fields exist to support a tamper-evident
  hash chain between consecutive invoices (needed for fiscal anti-fraud compliance, e.g.
  Verifactu-style requirements in Spain). Implement the hash chain logic before going to
  production with real invoicing.
- **Soft deletes**: `Client` and `User` use `deletedAt` instead of physical deletion, to support
  GDPR "right to be forgotten" requests without breaking referential integrity of past invoices.
- **Technical history is append-only**: `ClientTechnicalNote` records (dye formulas, allergies,
  treatments) are never overwritten — a new note is added so the salon can see what was used in
  a client's previous visit.
- **Price snapshotting**: `AppointmentService.priceAtBooking` and `InvoiceLine.unitPrice` freeze
  the price at the time of the transaction, so later catalog price changes don't retroactively
  alter past appointments or invoices.
- **Stock truth lives in `StockMovement`**, not just the denormalized `Product.stockQty` — the
  latter is a fast-read cache; the former is the auditable ledger (purchases, sales, internal
  use, adjustments, losses).
- Naming: TypeScript/Prisma models use camelCase field names mapped to snake_case columns via
  `@map`/`@@map`, so raw SQL and generated migrations read as idiomatic Postgres.

## Branching / CI

- No CI pipeline configured yet.
- Default branch: `main` (this work happened on a feature branch; confirm before merging).

## Next steps (not yet built)

- Authentication & authorization (per-tenant users, role-based access per `UserRole`).
- API routes / server actions implementing the business logic for each module (appointment
  overlap validation, invoice numbering + hash chain, stock deduction on sale/internal use,
  commission calculation).
- Real UI for each of the six modules (currently only a placeholder landing page exists).
- A live PostgreSQL instance + first `prisma migrate dev` to create actual tables.

## Keeping this file up to date

Update this file whenever structure, workflows, or conventions change materially — especially
once authentication, API routes, and real UI screens are added, since right now this describes a
schema-and-scaffold-only stage.
