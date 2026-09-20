import { prisma } from "@/lib/prisma";

function startOfDay(d: Date) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}
function endOfDay(d: Date) {
  const x = new Date(d);
  x.setHours(23, 59, 59, 999);
  return x;
}

const MONTH_LABELS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

export async function getDashboardData(tenantId: string) {
  const tenant = await prisma.tenant.findUnique({ where: { id: tenantId } });
  if (!tenant) return null;

  const now = new Date();
  const todayStart = startOfDay(now);
  const todayEnd = endOfDay(now);
  const yesterdayStart = startOfDay(new Date(now.getTime() - 86400000));
  const yesterdayEnd = endOfDay(new Date(now.getTime() - 86400000));
  const periodMonth = now.toISOString().slice(0, 7);

  const [
    appointmentsToday,
    appointmentsYesterdayCount,
    invoicesToday,
    stylistCount,
    clientWithAllergy,
    latestInvoice,
    lowStockProducts,
    commissionByEmployee,
    allInvoices,
  ] = await Promise.all([
    prisma.appointment.findMany({
      where: { tenantId, startTime: { gte: todayStart, lte: todayEnd } },
      include: { client: true, employee: true, services: { include: { service: true } } },
      orderBy: { startTime: "asc" },
    }),
    prisma.appointment.count({
      where: { tenantId, startTime: { gte: yesterdayStart, lte: yesterdayEnd } },
    }),
    prisma.invoice.findMany({
      where: { tenantId, issuedAt: { gte: todayStart, lte: todayEnd }, status: "ISSUED" },
    }),
    prisma.user.count({ where: { tenantId, role: "STYLIST", active: true } }),
    prisma.client.findFirst({
      where: { tenantId, allergies: { some: {} } },
      include: { allergies: true, technicalNotes: { orderBy: { createdAt: "desc" }, take: 1 } },
    }),
    prisma.invoice.findFirst({
      where: { tenantId },
      orderBy: { issuedAt: "desc" },
      include: { lines: true, payments: true },
    }),
    prisma.product.findMany({
      where: { tenantId },
      orderBy: { stockQty: "asc" },
      take: 4,
    }),
    prisma.commissionRecord.groupBy({
      by: ["employeeId"],
      where: { tenantId, periodMonth },
      _sum: { amount: true },
    }),
    prisma.invoice.findMany({
      where: { tenantId },
      select: { issuedAt: true, totalAmount: true },
      orderBy: { issuedAt: "asc" },
    }),
  ]);

  const facturacionHoy = invoicesToday.reduce((sum, inv) => sum + Number(inv.totalAmount), 0);
  const ticketMedio = invoicesToday.length ? facturacionHoy / invoicesToday.length : 0;

  const bookedMinutes = appointmentsToday.reduce(
    (sum, a) => sum + (a.endTime.getTime() - a.startTime.getTime()) / 60000,
    0
  );
  const availableMinutes = Math.max(stylistCount, 1) * 8 * 60;
  const ocupacion = Math.min(100, Math.round((bookedMinutes / availableMinutes) * 100));

  const employeeIds = [...new Set(commissionByEmployee.map((c) => c.employeeId))];
  const employees = await prisma.user.findMany({ where: { id: { in: employeeIds } } });
  const commissionRanking = commissionByEmployee
    .map((c) => ({
      employee: employees.find((e) => e.id === c.employeeId),
      amount: Number(c._sum.amount ?? 0),
    }))
    .filter((c) => c.employee)
    .sort((a, b) => b.amount - a.amount);

  const byMonth = new Map<string, number>();
  for (const inv of allInvoices) {
    const key = `${inv.issuedAt.getFullYear()}-${inv.issuedAt.getMonth()}`;
    byMonth.set(key, (byMonth.get(key) ?? 0) + Number(inv.totalAmount));
  }
  const revenueTrend = [...byMonth.entries()]
    .sort(([a], [b]) => (a > b ? 1 : -1))
    .slice(-6)
    .map(([key, total]) => {
      const [, monthIdx] = key.split("-").map(Number);
      return { label: MONTH_LABELS[monthIdx], total };
    });
  const currentMonthTotal = revenueTrend.at(-1)?.total ?? 0;
  const previousMonthTotal = revenueTrend.at(-2)?.total ?? 0;
  const monthDeltaPct = previousMonthTotal
    ? ((currentMonthTotal - previousMonthTotal) / previousMonthTotal) * 100
    : 0;

  return {
    tenant,
    appointmentsToday,
    appointmentsDelta: appointmentsToday.length - appointmentsYesterdayCount,
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
  };
}
