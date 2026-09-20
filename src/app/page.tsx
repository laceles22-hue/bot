import { getDashboardData } from "@/lib/dashboard";
import { Icon, IconSprite } from "@/components/Icons";

// The dashboard depends on "today"/"this month", so it must be computed per request, not baked in at build time.
export const dynamic = "force-dynamic";

const NAV_ITEMS = [
  { icon: "calendar", label: "Agenda", current: true },
  { icon: "users", label: "Clientes" },
  { icon: "receipt", label: "TPV" },
  { icon: "box", label: "Stock" },
  { icon: "bars", label: "Empleados" },
  { icon: "trend", label: "Informes" },
];

const SERIES_COLORS = ["var(--series-1)", "var(--series-2)", "var(--series-3)"];
const SALON_DAY_START_MIN = 9 * 60;
const SALON_DAY_END_MIN = 20 * 60;

function formatEuro(n: number) {
  return n.toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €";
}

function minutesSinceMidnight(d: Date) {
  return d.getHours() * 60 + d.getMinutes();
}

export default async function HomePage() {
  const data = await getDashboardData();

  if (!data) {
    return (
      <div className="shell">
        <main className="content">
          <div className="main-inner">
            <p className="empty">
              Aún no hay ningún salón configurado en la base de datos. Ejecuta{" "}
              <code>npm run db:seed</code> para cargar datos de ejemplo.
            </p>
          </div>
        </main>
      </div>
    );
  }

  const {
    tenant,
    appointmentsToday,
    appointmentsDelta,
    facturacionHoy,
    ticketMedio,
    ocupacion,
    clientWithAllergy,
    latestInvoice,
    lowStockProducts,
    commissionRanking,
    revenueTrend,
    currentMonthTotal,
    monthDeltaPct,
  } = data;

  const employeeColorById = new Map<string, string>();
  for (const a of appointmentsToday) {
    if (!employeeColorById.has(a.employeeId)) {
      employeeColorById.set(a.employeeId, SERIES_COLORS[employeeColorById.size % SERIES_COLORS.length]);
    }
  }
  const dayLabel = new Date()
    .toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long", year: "numeric" });

  const maxCommission = Math.max(1, ...commissionRanking.map((c) => c.amount));
  const maxRevenue = Math.max(1, ...revenueTrend.map((m) => m.total));
  const sparkPoints = revenueTrend
    .map((m, i) => {
      const x = revenueTrend.length > 1 ? (i / (revenueTrend.length - 1)) * 120 : 0;
      const y = 40 - (m.total / maxRevenue) * 36;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
  const lastPoint = sparkPoints.split(" ").at(-1)?.split(",").map(Number);

  return (
    <div className="shell">
      <IconSprite />
      <aside className="rail">
        <div className="brand">
          <span className="brand-mark">
            <svg className="icon" viewBox="0 0 24 24" stroke="currentColor">
              <path d="M6 6l12 12M18 6 6 18" />
              <circle cx="7" cy="6" r="1.6" fill="currentColor" stroke="none" />
              <circle cx="7" cy="18" r="1.6" fill="currentColor" stroke="none" />
            </svg>
          </span>
          <span className="brand-name">Salon Manager</span>
        </div>
        <nav className="rail-nav">
          {NAV_ITEMS.map((item) => (
            <a key={item.label} className={item.current ? "current" : undefined}>
              <Icon name={item.icon} />
              <span className="label">{item.label}</span>
            </a>
          ))}
        </nav>
        <div className="rail-foot">
          Conectado a PostgreSQL
          <div className="stack-badges">
            <span>Next.js</span>
            <span>Postgres</span>
            <span>Prisma</span>
          </div>
        </div>
      </aside>

      <main className="content">
        <div className="main-inner">
          <div className="hero">
            <div className="hero-top">
              <div>
                <h1>Hola, {tenant.name}</h1>
                <p className="sub">{dayLabel.charAt(0).toUpperCase() + dayLabel.slice(1)} · resumen del día</p>
              </div>
              <span className="badge">Datos en vivo</span>
            </div>
            <div className="stat-row">
              <div className="stat">
                <div className="label">Citas hoy</div>
                <div className="value">{appointmentsToday.length}</div>
                <div className={`delta ${appointmentsDelta > 0 ? "good" : appointmentsDelta < 0 ? "critical" : "neutral"}`}>
                  {appointmentsDelta === 0 ? "= que ayer" : `${appointmentsDelta > 0 ? "▲" : "▼"} ${Math.abs(appointmentsDelta)} vs. ayer`}
                </div>
              </div>
              <div className="stat">
                <div className="label">Facturación hoy</div>
                <div className="value">{formatEuro(facturacionHoy)}</div>
                <div className="delta neutral">emitida hoy</div>
              </div>
              <div className="stat">
                <div className="label">Ticket medio</div>
                <div className="value">{formatEuro(ticketMedio)}</div>
                <div className="delta neutral">hoy</div>
              </div>
              <div className="stat">
                <div className="label">Ocupación</div>
                <div className="value">{ocupacion}%</div>
                <div className="delta neutral">de la jornada</div>
              </div>
            </div>
          </div>

          <h2 className="section-title">Módulos</h2>
          <div className="modules">

            <div className="card">
              <div className="card-head">
                <span className="ic"><Icon name="calendar" /></span>
                <div className="htext"><h3>Agenda y Citas</h3><span>09:00–20:00</span></div>
              </div>
              <p className="desc">Calendario por empleado con control de solapamientos y estado de cada cita.</p>
              <div className="mock">
                {appointmentsToday.length === 0 ? (
                  <p className="empty">No hay citas registradas para hoy.</p>
                ) : (
                  <div className="timeline">
                    <div className="axis"><span>9:00</span><span>11:00</span><span>13:00</span><span>15:00</span><span>17:00</span><span>20:00</span></div>
                    <div className="track" style={{ height: `${Math.max(74, employeeColorById.size * 26)}px` }}>
                      {appointmentsToday.map((a, i) => {
                        const start = Math.max(SALON_DAY_START_MIN, minutesSinceMidnight(a.startTime));
                        const end = Math.min(SALON_DAY_END_MIN, minutesSinceMidnight(a.endTime));
                        const total = SALON_DAY_END_MIN - SALON_DAY_START_MIN;
                        const left = ((start - SALON_DAY_START_MIN) / total) * 100;
                        const width = Math.max(4, ((end - start) / total) * 100);
                        const row = [...employeeColorById.keys()].indexOf(a.employeeId);
                        return (
                          <div
                            key={a.id}
                            className="appt"
                            title={`${a.client.firstName} ${a.client.lastName} · ${a.services[0]?.service.name ?? ""}`}
                            style={{
                              left: `${left}%`,
                              width: `${width}%`,
                              top: `${row * 26}px`,
                              background: employeeColorById.get(a.employeeId),
                            }}
                          >
                            {a.client.firstName} {a.client.lastName.charAt(0)}.
                          </div>
                        );
                      })}
                    </div>
                    <div className="legend-row">
                      {[...employeeColorById.entries()].map(([employeeId, color]) => {
                        const appt = appointmentsToday.find((a) => a.employeeId === employeeId);
                        return (
                          <span key={employeeId}>
                            <i className="dot" style={{ background: color }} />
                            {appt?.employee.fullName.split(" ")[0]}
                          </span>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>
            </div>

            <div className="card">
              <div className="card-head">
                <span className="ic"><Icon name="users" /></span>
                <div className="htext"><h3>Clientes (CRM)</h3><span>ficha técnica</span></div>
              </div>
              <p className="desc">Historial de fórmulas, alergias y visitas, siempre a mano al recibir al cliente.</p>
              <div className="mock">
                {!clientWithAllergy ? (
                  <p className="empty">Todavía no hay clientes con notas técnicas.</p>
                ) : (
                  <div className="client-row">
                    <div className="avatar">
                      {clientWithAllergy.firstName[0]}
                      {clientWithAllergy.lastName[0]}
                    </div>
                    <div>
                      <div className="client-name">
                        {clientWithAllergy.firstName} {clientWithAllergy.lastName}
                      </div>
                      <div className="client-meta">Ficha técnica registrada</div>
                      <div className="tags">
                        {clientWithAllergy.technicalNotes[0] && (
                          <span className="tag">
                            {(clientWithAllergy.technicalNotes[0].content as { producto?: string }).producto ?? "Nota técnica"}
                          </span>
                        )}
                        {clientWithAllergy.allergies.map((al) => (
                          <span className="tag warn" key={al.id}>⚠ Alergia: {al.substance}</span>
                        ))}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>

            <div className="card">
              <div className="card-head">
                <span className="ic"><Icon name="receipt" /></span>
                <div className="htext"><h3>TPV / Facturación</h3><span>última venta</span></div>
              </div>
              <p className="desc">Cobro rápido con múltiples formas de pago y series de facturación controladas.</p>
              <div className="mock ticket">
                {!latestInvoice || latestInvoice.lines.length === 0 ? (
                  <p className="empty">Todavía no se ha emitido ninguna factura.</p>
                ) : (
                  <>
                    {latestInvoice.lines.map((line) => (
                      <div className="line" key={line.id}>
                        <span>{line.description}</span>
                        <span>{formatEuro(Number(line.lineTotal))}</span>
                      </div>
                    ))}
                    <div className="total">
                      <span>Total (IVA incl.)</span>
                      <span>{formatEuro(Number(latestInvoice.totalAmount))}</span>
                    </div>
                    {latestInvoice.payments[0] && (
                      <span className="pay-badge">
                        Pago: {latestInvoice.payments[0].method === "CARD" ? "Tarjeta" : latestInvoice.payments[0].method === "CASH" ? "Efectivo" : "Bizum"}
                      </span>
                    )}
                  </>
                )}
              </div>
            </div>

            <div className="card">
              <div className="card-head">
                <span className="ic"><Icon name="box" /></span>
                <div className="htext"><h3>Stock e Inventario</h3><span>{lowStockProducts.length} productos</span></div>
              </div>
              <p className="desc">Nivel de existencias para venta y consumo interno, con alertas de stock bajo.</p>
              <div className="mock">
                {lowStockProducts.length === 0 ? (
                  <p className="empty">No hay productos dados de alta.</p>
                ) : (
                  <>
                    {lowStockProducts.map((p) => {
                      const reference = Math.max(Number(p.minStockAlert ?? 20) * 5, 1);
                      const pct = Math.min(100, Math.round((Number(p.stockQty) / reference) * 100));
                      const low = p.minStockAlert != null && Number(p.stockQty) < Number(p.minStockAlert);
                      return (
                        <div className="stock-row" key={p.id}>
                          <span className="stock-name">{p.name}</span>
                          <span className="bar-bg"><span className={`bar-fill${low ? " low" : ""}`} style={{ width: `${pct}%` }} /></span>
                          <span className="stock-pct">{pct}%</span>
                        </div>
                      );
                    })}
                    {lowStockProducts.some((p) => p.minStockAlert != null && Number(p.stockQty) < Number(p.minStockAlert)) && (
                      <div className="low-flag">⚠ Hay productos por debajo del mínimo</div>
                    )}
                  </>
                )}
              </div>
            </div>

            <div className="card">
              <div className="card-head">
                <span className="ic"><Icon name="bars" /></span>
                <div className="htext"><h3>Comisiones y Empleados</h3><span>este mes</span></div>
              </div>
              <p className="desc">Rendimiento y comisión calculada por servicio y producto vendido.</p>
              <div className="mock">
                {commissionRanking.length === 0 ? (
                  <p className="empty">Aún no hay comisiones calculadas este mes.</p>
                ) : (
                  commissionRanking.map((c, i) => (
                    <div className="rank-row" key={c.employee!.id}>
                      <span className="rank-name">{c.employee!.fullName.split(" ")[0]}</span>
                      <span className="rank-bar-bg">
                        <span
                          className="rank-bar"
                          style={{ width: `${(c.amount / maxCommission) * 100}%`, background: SERIES_COLORS[i % SERIES_COLORS.length] }}
                        />
                      </span>
                      <span className="rank-val">{formatEuro(c.amount)}</span>
                    </div>
                  ))
                )}
              </div>
            </div>

            <div className="card">
              <div className="card-head">
                <span className="ic"><Icon name="trend" /></span>
                <div className="htext"><h3>Métricas y Reportes</h3><span>últimos {revenueTrend.length} meses</span></div>
              </div>
              <p className="desc">Facturación, ticket medio y horas de mayor afluencia de un vistazo.</p>
              <div className="mock">
                {revenueTrend.length === 0 ? (
                  <p className="empty">Todavía no hay facturación registrada.</p>
                ) : (
                  <div className="spark-wrap">
                    <div>
                      <div className="spark-num">{formatEuro(currentMonthTotal)}</div>
                      <div className={`delta ${monthDeltaPct >= 0 ? "good" : "critical"}`} style={{ fontSize: "0.72rem" }}>
                        {monthDeltaPct >= 0 ? "▲" : "▼"} {Math.abs(monthDeltaPct).toFixed(1)}% vs. mes anterior
                      </div>
                    </div>
                    <svg width="140" height="46" viewBox="0 0 128 46" style={{ flex: "none", overflow: "visible" }}>
                      <polyline points={sparkPoints} fill="none" stroke="var(--seq-450)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
                      <polygon points={`0,46 ${sparkPoints} ${lastPoint?.[0] ?? 0},46`} fill="var(--seq-450)" opacity="0.14" />
                      {lastPoint && <circle cx={lastPoint[0]} cy={lastPoint[1]} r="3.5" fill="var(--seq-450)" />}
                    </svg>
                  </div>
                )}
              </div>
            </div>

          </div>

          <footer className="page-foot">
            Salon Manager — datos leídos en directo desde PostgreSQL vía Prisma. Aún sin autenticación ni edición desde la interfaz.
          </footer>
        </div>
      </main>
    </div>
  );
}
