import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import { prisma } from "@/lib/prisma";
import { createAppointmentAction, updateAppointmentStatusAction } from "@/lib/actions/agenda";
import { formatTime, STATUS_LABELS } from "@/lib/format";

export const dynamic = "force-dynamic";

function toDateInputValue(d: Date) {
  return d.toISOString().slice(0, 10);
}
function addDays(d: Date, n: number) {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

export default async function AgendaPage({
  searchParams,
}: {
  searchParams: Promise<{ date?: string; error?: string }>;
}) {
  const session = await getSession();
  if (!session) redirect("/login");

  const { date: dateParam, error } = await searchParams;
  const date = dateParam ? new Date(`${dateParam}T00:00:00`) : new Date();
  const dateStr = toDateInputValue(date);
  const dayStart = new Date(`${dateStr}T00:00:00`);
  const dayEnd = new Date(`${dateStr}T23:59:59`);

  const [appointments, clients, employees, services] = await Promise.all([
    prisma.appointment.findMany({
      where: { tenantId: session.tenantId, startTime: { gte: dayStart, lte: dayEnd } },
      include: { client: true, employee: true, services: { include: { service: true } } },
      orderBy: { startTime: "asc" },
    }),
    prisma.client.findMany({ where: { tenantId: session.tenantId, deletedAt: null }, orderBy: { firstName: "asc" } }),
    prisma.user.findMany({ where: { tenantId: session.tenantId, role: "STYLIST", active: true }, orderBy: { fullName: "asc" } }),
    prisma.service.findMany({ where: { tenantId: session.tenantId, active: true }, orderBy: { name: "asc" } }),
  ]);

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Agenda</h1>
          <p>Citas del {date.toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" })}</p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <a className="btn secondary small" href={`/agenda?date=${toDateInputValue(addDays(date, -1))}`}>‹ Anterior</a>
          <a className="btn secondary small" href={`/agenda?date=${toDateInputValue(new Date())}`}>Hoy</a>
          <a className="btn secondary small" href={`/agenda?date=${toDateInputValue(addDays(date, 1))}`}>Siguiente ›</a>
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="layout-2col">
        <div className="panel">
          <h2>Nueva cita</h2>
          <form action={createAppointmentAction}>
            <input type="hidden" name="date" value={dateStr} />
            <div className="field">
              <label htmlFor="clientId">Cliente</label>
              <select id="clientId" name="clientId" required defaultValue="">
                <option value="" disabled>Selecciona un cliente</option>
                {clients.map((c) => (
                  <option key={c.id} value={c.id}>{c.firstName} {c.lastName}</option>
                ))}
              </select>
            </div>
            <div className="field">
              <label htmlFor="employeeId">Empleado</label>
              <select id="employeeId" name="employeeId" required defaultValue="">
                <option value="" disabled>Selecciona un empleado</option>
                {employees.map((e) => (
                  <option key={e.id} value={e.id}>{e.fullName}</option>
                ))}
              </select>
            </div>
            <div className="field">
              <label htmlFor="serviceId">Servicio</label>
              <select id="serviceId" name="serviceId" required defaultValue="">
                <option value="" disabled>Selecciona un servicio</option>
                {services.map((s) => (
                  <option key={s.id} value={s.id}>{s.name} ({s.durationMinutes} min)</option>
                ))}
              </select>
            </div>
            <div className="field">
              <label htmlFor="time">Hora</label>
              <input id="time" name="time" type="time" required defaultValue="10:00" />
            </div>
            <button type="submit" className="btn">Crear cita</button>
          </form>
        </div>

        <div className="panel">
          <h2>Citas del día ({appointments.length})</h2>
          {appointments.length === 0 ? (
            <p className="empty">No hay citas para este día.</p>
          ) : (
            <div className="table-wrap">
              <table className="list">
                <thead>
                  <tr>
                    <th>Hora</th>
                    <th>Cliente</th>
                    <th>Empleado</th>
                    <th>Servicio</th>
                    <th>Estado</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {appointments.map((a) => (
                    <tr key={a.id}>
                      <td>{formatTime(a.startTime)}–{formatTime(a.endTime)}</td>
                      <td>{a.client.firstName} {a.client.lastName}</td>
                      <td>{a.employee.fullName}</td>
                      <td>{a.services.map((s) => s.service.name).join(", ")}</td>
                      <td><span className={`status-pill ${a.status.toLowerCase()}`}>{STATUS_LABELS[a.status]}</span></td>
                      <td>
                        <form action={updateAppointmentStatusAction} style={{ display: "flex", gap: 4 }}>
                          <input type="hidden" name="appointmentId" value={a.id} />
                          <input type="hidden" name="date" value={dateStr} />
                          {a.status !== "DONE" && (
                            <button type="submit" name="status" value="DONE" className="btn small secondary">Realizada</button>
                          )}
                          {a.status !== "CANCELLED" && (
                            <button type="submit" name="status" value="CANCELLED" className="btn small secondary">Cancelar</button>
                          )}
                        </form>
                      </td>
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
