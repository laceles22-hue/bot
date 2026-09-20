import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import { prisma } from "@/lib/prisma";
import { createEmployeeAction } from "@/lib/actions/employees";
import { formatEuro } from "@/lib/format";

export const dynamic = "force-dynamic";

const ROLE_LABELS: Record<string, string> = { OWNER: "Propietario", ADMIN: "Administrador", STYLIST: "Estilista", RECEPTIONIST: "Recepción" };

export default async function EmpleadosPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const session = await getSession();
  if (!session) redirect("/login");
  const { error } = await searchParams;

  const periodMonth = new Date().toISOString().slice(0, 7);

  const [employees, commissionByEmployee] = await Promise.all([
    prisma.user.findMany({ where: { tenantId: session.tenantId, active: true }, orderBy: { fullName: "asc" } }),
    prisma.commissionRecord.groupBy({ by: ["employeeId"], where: { tenantId: session.tenantId, periodMonth }, _sum: { amount: true } }),
  ]);
  const commissionByEmployeeId = new Map(commissionByEmployee.map((c) => [c.employeeId, Number(c._sum.amount ?? 0)]));

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Empleados y Comisiones</h1>
          <p>Rendimiento y comisión calculada este mes por empleado.</p>
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="layout-2col">
        <div className="panel">
          <h2>Nuevo empleado</h2>
          <form action={createEmployeeAction}>
            <div className="field">
              <label htmlFor="fullName">Nombre completo</label>
              <input id="fullName" name="fullName" required />
            </div>
            <div className="field">
              <label htmlFor="email">Email</label>
              <input id="email" name="email" type="email" required />
            </div>
            <div className="field">
              <label htmlFor="password">Contraseña</label>
              <input id="password" name="password" type="password" required minLength={6} />
            </div>
            <div className="field">
              <label htmlFor="role">Rol</label>
              <select id="role" name="role" defaultValue="STYLIST">
                <option value="STYLIST">Estilista</option>
                <option value="RECEPTIONIST">Recepción</option>
                <option value="ADMIN">Administrador</option>
                <option value="OWNER">Propietario</option>
              </select>
            </div>
            <button type="submit" className="btn">Crear empleado</button>
          </form>
        </div>

        <div className="panel">
          <h2>Equipo ({employees.length})</h2>
          <div className="table-wrap">
            <table className="list">
              <thead><tr><th>Nombre</th><th>Email</th><th>Rol</th><th>Comisión este mes</th></tr></thead>
              <tbody>
                {employees.map((e) => (
                  <tr key={e.id}>
                    <td>{e.fullName}</td>
                    <td>{e.email}</td>
                    <td>{ROLE_LABELS[e.role]}</td>
                    <td>{formatEuro(commissionByEmployeeId.get(e.id) ?? 0)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </>
  );
}
