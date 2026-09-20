import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import { prisma } from "@/lib/prisma";
import { SaleForm } from "@/components/SaleForm";
import { formatDateTime, formatEuro, PAYMENT_LABELS } from "@/lib/format";

export const dynamic = "force-dynamic";

export default async function TpvPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; success?: string }>;
}) {
  const session = await getSession();
  if (!session) redirect("/login");
  const { error, success } = await searchParams;

  const [clients, services, products, recentInvoices] = await Promise.all([
    prisma.client.findMany({ where: { tenantId: session.tenantId, deletedAt: null }, orderBy: { firstName: "asc" } }),
    prisma.service.findMany({ where: { tenantId: session.tenantId, active: true }, orderBy: { name: "asc" } }),
    prisma.product.findMany({ where: { tenantId: session.tenantId, active: true, type: { in: ["RETAIL", "BOTH"] } }, orderBy: { name: "asc" } }),
    prisma.invoice.findMany({
      where: { tenantId: session.tenantId },
      orderBy: { issuedAt: "desc" },
      take: 15,
      include: { client: true, payments: true, series: true },
    }),
  ]);

  return (
    <>
      <div className="page-header">
        <div>
          <h1>TPV / Facturación</h1>
          <p>Cobra servicios y productos, y consulta las últimas ventas.</p>
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}
      {success && <div className="alert success">Factura A-{success} creada correctamente.</div>}

      <div className="layout-2col">
        <div className="panel">
          <h2>Nueva venta</h2>
          <SaleForm
            clients={clients}
            services={services.map((s) => ({ id: s.id, name: s.name, price: Number(s.basePrice) }))}
            products={products.map((p) => ({ id: p.id, name: p.name, price: Number(p.retailPrice ?? p.unitCost) }))}
          />
        </div>

        <div className="panel">
          <h2>Últimas facturas</h2>
          {recentInvoices.length === 0 ? (
            <p className="empty">Todavía no se ha emitido ninguna factura.</p>
          ) : (
            <div className="table-wrap">
              <table className="list">
                <thead><tr><th>Nº</th><th>Fecha</th><th>Cliente</th><th>Total</th><th>Pago</th></tr></thead>
                <tbody>
                  {recentInvoices.map((inv) => (
                    <tr key={inv.id}>
                      <td>{inv.series.seriesCode}-{inv.invoiceNumber}</td>
                      <td>{formatDateTime(inv.issuedAt)}</td>
                      <td>{inv.client ? `${inv.client.firstName} ${inv.client.lastName}` : "—"}</td>
                      <td>{formatEuro(Number(inv.totalAmount))}</td>
                      <td>{inv.payments[0] ? PAYMENT_LABELS[inv.payments[0].method] : "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
