import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import { getReportsData } from "@/lib/reports";
import { formatEuro } from "@/lib/format";

export const dynamic = "force-dynamic";

export default async function InformesPage() {
  const session = await getSession();
  if (!session) redirect("/login");

  const { revenueTrend, totalRevenue, ticketMedio, invoiceCount, topServices } = await getReportsData(session.tenantId);
  const maxRevenue = Math.max(1, ...revenueTrend.map((m) => m.total));
  const maxServiceRevenue = Math.max(1, ...topServices.map((s) => s.revenue));

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Métricas y Reportes</h1>
          <p>Facturación, ticket medio y servicios más demandados.</p>
        </div>
      </div>

      <div className="stat-row" style={{ marginBottom: 20 }}>
        <div className="stat">
          <div className="label">Facturación total</div>
          <div className="value">{formatEuro(totalRevenue)}</div>
        </div>
        <div className="stat">
          <div className="label">Ticket medio</div>
          <div className="value">{formatEuro(ticketMedio)}</div>
        </div>
        <div className="stat">
          <div className="label">Facturas emitidas</div>
          <div className="value">{invoiceCount}</div>
        </div>
      </div>

      <div className="layout-2col">
        <div className="panel">
          <h2>Facturación por mes</h2>
          {revenueTrend.length === 0 ? (
            <p className="empty">Todavía no hay facturación registrada.</p>
          ) : (
            <div className="bigchart">
              {revenueTrend.map((m) => (
                <div className="col" key={m.label}>
                  <span className="bar-value">{formatEuro(m.total)}</span>
                  <div className="bar" style={{ height: `${Math.max(2, (m.total / maxRevenue) * 130)}px` }} />
                  <span className="bar-label">{m.label}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="panel">
          <h2>Servicios más demandados</h2>
          {topServices.length === 0 ? (
            <p className="empty">Todavía no hay servicios facturados.</p>
          ) : (
            topServices.map((s) => (
              <div className="rank-row" key={s.service!.id}>
                <span className="rank-name" style={{ flexBasis: 120 }}>{s.service!.name}</span>
                <span className="rank-bar-bg">
                  <span className="rank-bar" style={{ width: `${(s.revenue / maxServiceRevenue) * 100}%`, background: "var(--seq-450)" }} />
                </span>
                <span className="rank-val">{formatEuro(s.revenue)}</span>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  );
}
