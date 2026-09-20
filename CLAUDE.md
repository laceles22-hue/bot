# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Project overview

**Salon Manager** — a web-based management system (ERP/POS) for hair salons and beauty parlors,
in the style of "Manager Pro" apps for the sector. Covers appointments/scheduling, client CRM
with technical history, point-of-sale/invoicing, inventory, staff commissions, and reporting.

The project has a real (seeded) PostgreSQL database and one working screen: the home dashboard
(`src/app/page.tsx`) reads live data from Postgres via Prisma and renders it in a modern
dashboard UI (sidebar nav, stat tiles, per-module preview cards). Authentication and the
per-module CRUD screens (Agenda, CRM, TPV, Stock, Comisiones, Informes as full pages) are not
built yet — today's UI only *previews* those modules on the dashboard.

## Stack

- **Framework**: Next.js 16 (App Router), TypeScript, React 19.
- **Styling**: Tailwind CSS.
- **Database**: PostgreSQL via Prisma ORM (`prisma/schema.prisma`).
- **Deployment target**: any Node.js host with a PostgreSQL database (e.g. Railway, Fly.io,
  Vercel + managed Postgres).

## Codebase structure

- `src/app/` — Next.js App Router pages and layouts. `page.tsx` is a dynamically-rendered
  (`export const dynamic = "force-dynamic"`) server component that queries Postgres via
  `src/lib/dashboard.ts` and renders today's stats plus a preview card per module.
- `src/lib/prisma.ts` — the shared `PrismaClient` singleton (avoids exhausting DB connections
  from hot-reloaded dev instances).
- `src/lib/dashboard.ts` — all the dashboard's data-fetching/aggregation queries, single-tenant
  (`prisma.tenant.findFirst()`) until per-tenant auth exists.
- `src/components/Icons.tsx` — the inline SVG icon sprite used by the sidebar and module cards.
- `prisma/seed.ts` — example data (`npm run db:seed`): one tenant ("Urban Beauty"), 3 stylists,
  services/products, clients, today's appointments, one real invoice, and a few historical
  invoices (Apr–Aug) purely so the revenue trend chart has something to plot.
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
npx prisma migrate dev       # create/apply a migration
npm run db:seed              # load example data (safe to re-run after `prisma migrate reset`)
npm run dev                  # start the dev server (http://localhost:3000)
npm run build                # production build
npm run typecheck            # tsc --noEmit
npm run lint                 # next lint
```

This dev container has a local PostgreSQL 16 server (`service postgresql start`) with a
`salon_manager` database/role already created and referenced from `.env` (gitignored, not
committed). A real deployment needs its own hosted Postgres — swap `DATABASE_URL` and re-run
`prisma migrate deploy`.

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

- Authentication & authorization (per-tenant users, role-based access per `UserRole`) — needed
  before the single-tenant `findFirst()` shortcut in `dashboard.ts` can go away.
- API routes / server actions implementing the business logic for each module (appointment
  overlap validation, invoice numbering + hash chain, stock deduction on sale/internal use,
  commission calculation).
- Full CRUD pages for each of the six modules — the dashboard only previews them today.
- Swapping the local dev Postgres for a real hosted instance for production use.

## Keeping this file up to date

Update this file whenever structure, workflows, or conventions change materially — especially
once authentication, API routes, and real UI screens are added, since right now this describes a
schema-and-scaffold-only stage.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
