import { redirect, notFound } from "next/navigation";
import { getSession } from "@/lib/session";
import { prisma } from "@/lib/prisma";
import { addTechnicalNoteAction, addAllergyAction } from "@/lib/actions/clients";
import { formatDateTime, STATUS_LABELS } from "@/lib/format";

export const dynamic = "force-dynamic";

const NOTE_TYPE_LABELS: Record<string, string> = {
  FORMULA_TINTE: "Fórmula de tinte",
  DECOLORACION: "Decoloración",
  QUERATINA: "Queratina",
  ALERGIA: "Alergia",
  OTRO: "Otro",
};

export default async function ClientDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const session = await getSession();
  if (!session) redirect("/login");
  const { id } = await params;

  const client = await prisma.client.findFirst({
    where: { id, tenantId: session.tenantId },
    include: {
      allergies: true,
      technicalNotes: { orderBy: { createdAt: "desc" }, include: { author: true } },
      appointments: {
        orderBy: { startTime: "desc" },
        take: 10,
        include: { services: { include: { service: true } }, employee: true },
      },
    },
  });
  if (!client) notFound();

  return (
    <>
      <div className="page-header">
        <div>
          <h1>{client.firstName} {client.lastName}</h1>
          <p>{client.phone ?? "Sin teléfono"} · {client.email ?? "Sin email"}</p>
        </div>
        <a className="btn secondary small" href="/clientes">← Volver a clientes</a>
      </div>

      <div className="layout-2col">
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="panel">
            <h2>Alergias</h2>
            {client.allergies.length === 0 ? (
              <p className="empty">Sin alergias registradas.</p>
            ) : (
              <div className="tags" style={{ marginBottom: 12 }}>
                {client.allergies.map((a) => (
                  <span key={a.id} className="tag warn">⚠ {a.substance}{a.severity ? ` (${a.severity})` : ""}</span>
                ))}
              </div>
            )}
            <form action={addAllergyAction}>
              <input type="hidden" name="clientId" value={client.id} />
              <div className="field">
                <label htmlFor="substance">Sustancia</label>
                <input id="substance" name="substance" required placeholder="Amoníaco, níquel…" />
              </div>
              <div className="field">
                <label htmlFor="severity">Gravedad</label>
                <select id="severity" name="severity" defaultValue="">
                  <option value="">Sin especificar</option>
                  <option value="leve">Leve</option>
                  <option value="media">Media</option>
                  <option value="alta">Alta</option>
                </select>
              </div>
              <button type="submit" className="btn small secondary">Añadir alergia</button>
            </form>
          </div>

          <div className="panel">
            <h2>Nueva nota técnica</h2>
            <form action={addTechnicalNoteAction}>
              <input type="hidden" name="clientId" value={client.id} />
              <div className="field">
                <label htmlFor="type">Tipo</label>
                <select id="type" name="type" defaultValue="FORMULA_TINTE">
                  {Object.entries(NOTE_TYPE_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>{label}</option>
                  ))}
                </select>
              </div>
              <div className="field">
                <label htmlFor="producto">Detalle</label>
                <input id="producto" name="producto" required placeholder="Tinte 7.1, oxidante 20 vol…" />
              </div>
              <button type="submit" className="btn small secondary">Guardar nota</button>
            </form>
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="panel">
            <h2>Historial técnico</h2>
            {client.technicalNotes.length === 0 ? (
              <p className="empty">Sin notas técnicas todavía.</p>
            ) : (
              <div className="table-wrap">
                <table className="list">
                  <thead><tr><th>Fecha</th><th>Tipo</th><th>Detalle</th><th>Autor</th></tr></thead>
                  <tbody>
                    {client.technicalNotes.map((n) => (
                      <tr key={n.id}>
                        <td>{formatDateTime(n.createdAt)}</td>
                        <td>{NOTE_TYPE_LABELS[n.type]}</td>
                        <td>{(n.content as { producto?: string }).producto ?? "—"}</td>
                        <td>{n.author.fullName}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          <div className="panel">
            <h2>Últimas citas</h2>
            {client.appointments.length === 0 ? (
              <p className="empty">Sin citas registradas.</p>
            ) : (
              <div className="table-wrap">
                <table className="list">
                  <thead><tr><th>Fecha</th><th>Servicio</th><th>Empleado</th><th>Estado</th></tr></thead>
                  <tbody>
                    {client.appointments.map((a) => (
                      <tr key={a.id}>
                        <td>{formatDateTime(a.startTime)}</td>
                        <td>{a.services.map((s) => s.service.name).join(", ")}</td>
                        <td>{a.employee.fullName}</td>
                        <td><span className={`status-pill ${a.status.toLowerCase()}`}>{STATUS_LABELS[a.status]}</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
