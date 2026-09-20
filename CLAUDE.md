# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Project overview

**Salon Manager** — a web-based management system (ERP/POS) for hair salons and beauty parlors,
in the style of "Manager Pro" apps for the sector. Covers appointments/scheduling, client CRM
with technical history, point-of-sale/invoicing, inventory, staff commissions, and reporting.

The app is **functionally complete for a first working version**: authentication, a live
PostgreSQL database, and all six modules (Agenda, Clientes, TPV, Stock, Empleados/Comisiones,
Informes) are implemented with real create/read flows backed by Prisma. What's still missing is
listed under "Next steps" below (mainly: automatic commission calculation on sale, richer
editing on existing records, and fiscal-grade invoicing).

## Stack

- **Framework**: Next.js 16 (App Router, Turbopack), TypeScript, React 19.
- **Auth**: custom email/password login — `bcryptjs` for hashing, a `jose`-signed JWT in an
  httpOnly cookie for the session, enforced by `src/proxy.ts` (Next 16 renamed `middleware.ts` to
  `proxy.ts`; the file must export a `proxy` function).
- **Styling**: hand-written CSS design system in `src/app/globals.css` (dark/light aware via CSS
  custom properties), not Tailwind utility classes — Tailwind is installed but only its
  base/reset layers are used.
- **Database**: PostgreSQL via Prisma ORM (`prisma/schema.prisma`).
- **Mutations**: Next.js Server Actions (`"use server"` files under `src/lib/actions/`), called
  directly from `<form action={...}>` — no separate REST/API route layer.
- **Deployment target**: any Node.js host with a PostgreSQL database (e.g. Railway, Fly.io,
  Vercel + managed Postgres).

## Codebase structure

- `src/app/login/page.tsx` — public login page (outside the authenticated route group).
- `src/app/(app)/` — the authenticated route group (shares a sidebar layout via
  `(app)/layout.tsx`); the group segment doesn't affect URLs, so `(app)/page.tsx` serves `/`.
  - `page.tsx` — dashboard: today's stats + one preview card per module.
  - `agenda/page.tsx` — day view of appointments (prev/today/next), new-appointment form with
    overlap checking, status updates (Realizada/Cancelada).
  - `clientes/page.tsx` + `clientes/[id]/page.tsx` — client list/create, and a detail page for
    allergies, technical notes, and appointment history.
  - `tpv/page.tsx` + `src/components/SaleForm.tsx` — point-of-sale: build a multi-line sale
    (services + products) client-side, submit as JSON to a server action that creates the
    invoice, lines, payment, and stock movements atomically.
  - `stock/page.tsx` — product catalog + manual stock movement entry (purchase/loss/adjustment).
  - `empleados/page.tsx` — team list with this month's commission total, new-employee form.
  - `informes/page.tsx` — revenue-by-month bar chart, top services by revenue.
- `src/proxy.ts` — redirects unauthenticated requests to `/login` and vice versa.
- `src/lib/session.ts` — JWT session cookie create/read/verify (`getSession()` in server
  components, `verifySessionToken()` in the edge-runtime proxy).
- `src/lib/actions/*.ts` — one file per module's server actions (auth, agenda, clients, tpv,
  stock, employees). All of them re-check `getSession()` server-side; nothing trusts the client.
- `src/lib/prisma.ts` — the shared `PrismaClient` singleton.
- `src/lib/dashboard.ts` / `src/lib/reports.ts` — read-only aggregation queries for the dashboard
  and the Informes page.
- `src/lib/format.ts` — shared `formatEuro`/date formatters and status/payment label maps.
- `src/components/Sidebar.tsx`, `src/components/Icons.tsx` — the nav shell and the inline SVG
  icon sprite it (and other pages) use.
- `prisma/seed.ts` — example data (`npm run db:seed`, password `salon1234` for every seeded
  user): tenant "Urban Beauty", 4 users (3 stylists + 1 owner), services/products, 5 clients,
  today's appointments, one real invoice, and a few historical invoices (Apr–Aug) so the revenue
  chart has something to plot.
- `prisma/schema.prisma` — the full relational data model, organized in commented sections
  (tenants/users, CRM, catalog, agenda, invoicing, cash sessions, stock, commissions).

## Development workflow

```bash
npm install                 # install dependencies
cp .env.example .env         # then set DATABASE_URL, and add SESSION_SECRET (openssl rand -hex 32)
npx prisma migrate dev       # create/apply a migration
npm run db:seed              # load example data (safe to re-run after `prisma migrate reset`)
npm run dev                  # start the dev server (http://localhost:3000) — redirects to /login
npm run build                # production build
npm run typecheck            # tsc --noEmit
npm run lint                 # next lint
```

This dev container has a local PostgreSQL 16 server (`service postgresql start`) with a
`salon_manager` database/role already created and referenced from `.env` (gitignored, not
committed — `SESSION_SECRET` lives there too). A real deployment needs its own hosted Postgres
and its own `SESSION_SECRET`.

## Architecture notes / conventions

- **Multi-tenant by design**: every business model carries a `tenantId` foreign key to `Tenant`.
  The logged-in user's `tenantId` comes from their session (`getSession()`), not from a
  single-tenant shortcut — every query in `src/lib/actions/*` and page loaders filters by it.
- **Server Actions over API routes**: every mutation is a `"use server"` function passed directly
  to a form's `action` prop. Keeps the module count down; if a mutation ever needs to be called
  from outside a form (e.g. a future mobile client), it'll need a real API route instead.
- **Money fields** use Prisma `Decimal` (`@db.Decimal(10, 2)`), never `Float`, to avoid rounding
  errors in invoicing/accounting.
- **Invoices are never deleted or mutated** — cancellation would be a `status` change
  (`ISSUED`/`CANCELLED`, not yet wired to a UI action), and `hashPrev`/`hashSelf` fields exist to
  support a tamper-evident hash chain between consecutive invoices (needed for fiscal anti-fraud
  compliance, e.g. Verifactu-style requirements in Spain) — **not implemented yet**; don't treat
  current invoice numbering as fiscally compliant.
- **Soft deletes**: `Client` and `User` use `deletedAt` instead of physical deletion (no UI action
  sets it yet), to support GDPR "right to be forgotten" requests without breaking referential
  integrity of past invoices.
- **Technical history is append-only**: `ClientTechnicalNote` records are never overwritten — a
  new note is added so the salon can see what was used in a client's previous visit.
- **Price snapshotting**: `AppointmentService.priceAtBooking` and `InvoiceLine.unitPrice` freeze
  the price at the time of the transaction, so later catalog price changes don't retroactively
  alter past appointments or invoices.
- **Stock truth lives in `StockMovement`**, not just the denormalized `Product.stockQty` — a TPV
  sale and a manual stock movement both write a ledger row *and* adjust `stockQty` in the same
  `$transaction`, so the two never drift.
- **Invoice numbering** increments `InvoiceSeries.currentNumber` inside the same `$transaction`
  that creates the invoice, to avoid duplicate numbers under concurrent sales.
- Naming: TypeScript/Prisma models use camelCase field names mapped to snake_case columns via
  `@map`/`@@map`, so raw SQL and generated migrations read as idiomatic Postgres.

## Branching / CI

- No CI pipeline configured yet.
- Default branch: `main` (this work happened on a feature branch; confirm before merging).

## Next steps (not yet built)

- **Automatic commission calculation** on each TPV sale — `CommissionRule`/`CommissionRecord`
  exist in the schema and the Empleados page reads them, but nothing currently *writes* a
  `CommissionRecord` when a sale happens (today's commission figures come only from seed data).
- Editing/cancelling existing clients, products, and invoices (current CRUD is create + list;
  no update/delete UI yet, aside from appointment status).
- Cash register (arqueo) UI — `CashSession`/`CashMovement` models exist, unused by any page.
- The invoice hash-chain and real fiscal numbering rules before this is used for real billing.
- Role-based UI restrictions (every logged-in user currently sees every page, regardless of
  `UserRole`).
- Swapping the local dev Postgres for a real hosted instance for production use.

## Keeping this file up to date

Update this file whenever structure, workflows, or conventions change materially.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
