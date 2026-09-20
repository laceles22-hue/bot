const modules = [
  { name: "Agenda y Citas", description: "Calendario por empleado, control de solapamientos y estados de cita." },
  { name: "Clientes (CRM)", description: "Historial técnico, fórmulas, alergias y visitas de cada cliente." },
  { name: "TPV / Facturación", description: "Cobro rápido, tickets, múltiples formas de pago y arqueos de caja." },
  { name: "Stock e Inventario", description: "Productos de venta y consumo interno, alertas de stock bajo." },
  { name: "Comisiones y Empleados", description: "Rendimiento y comisiones por servicio o producto vendido." },
  { name: "Métricas y Reportes", description: "Ticket medio, servicios más demandados y facturación." },
];

export default function HomePage() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-16">
      <h1 className="text-3xl font-bold tracking-tight">Salon Manager</h1>
      <p className="mt-2 text-slate-600">
        Gestión integral para peluquerías. Proyecto en construcción — base de datos y arquitectura definidas.
      </p>

      <div className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-2">
        {modules.map((mod) => (
          <div key={mod.name} className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="font-semibold text-slate-900">{mod.name}</h2>
            <p className="mt-1 text-sm text-slate-600">{mod.description}</p>
          </div>
        ))}
      </div>
    </main>
  );
}
