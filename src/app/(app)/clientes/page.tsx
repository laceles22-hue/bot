import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import { prisma } from "@/lib/prisma";
import { createClientAction } from "@/lib/actions/clients";

export const dynamic = "force-dynamic";

export default async function ClientesPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const session = await getSession();
  if (!session) redirect("/login");
  const { error } = await searchParams;

  const clients = await prisma.client.findMany({
    where: { tenantId: session.tenantId, deletedAt: null },
    include: { allergies: true, _count: { select: { appointments: true } } },
    orderBy: { createdAt: "desc" },
  });

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Clientes</h1>
          <p>Ficha técnica, alergias y visitas de cada cliente.</p>
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="layout-2col">
        <div className="panel">
          <h2>Nuevo cliente</h2>
          <form action={createClientAction}>
            <div className="field-row">
              <div className="field">
                <label htmlFor="firstName">Nombre</label>
                <input id="firstName" name="firstName" required />
              </div>
              <div className="field">
                <label htmlFor="lastName">Apellidos</label>
                <input id="lastName" name="lastName" required />
              </div>
            </div>
            <div className="field">
              <label htmlFor="phone">Teléfono</label>
              <input id="phone" name="phone" type="tel" />
            </div>
            <div className="field">
              <label htmlFor="email">Email</label>
              <input id="email" name="email" type="email" />
            </div>
            <button type="submit" className="btn">Crear cliente</button>
          </form>
        </div>

        <div className="panel">
          <h2>Todos los clientes ({clients.length})</h2>
          {clients.length === 0 ? (
            <p className="empty">Todavía no hay clientes registrados.</p>
          ) : (
            <div className="table-wrap">
              <table className="list">
                <thead>
                  <tr><th>Nombre</th><th>Teléfono</th><th>Visitas</th><th>Alergias</th><th></th></tr>
                </thead>
                <tbody>
                  {clients.map((c) => (
                    <tr key={c.id}>
                      <td>{c.firstName} {c.lastName}</td>
                      <td>{c.phone ?? "—"}</td>
                      <td>{c._count.appointments}</td>
                      <td>{c.allergies.length > 0 ? `⚠ ${c.allergies.map((a) => a.substance).join(", ")}` : "—"}</td>
                      <td><a className="btn small secondary" href={`/clientes/${c.id}`}>Ver ficha</a></td>
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
