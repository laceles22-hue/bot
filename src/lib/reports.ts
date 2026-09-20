import { prisma } from "@/lib/prisma";

const MONTH_LABELS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

export async function getReportsData(tenantId: string) {
  const [invoices, serviceLines, services] = await Promise.all([
    prisma.invoice.findMany({
      where: { tenantId, status: "ISSUED" },
      select: { issuedAt: true, totalAmount: true },
      orderBy: { issuedAt: "asc" },
    }),
    prisma.invoiceLine.groupBy({
      by: ["referenceId"],
      where: { invoice: { tenantId, status: "ISSUED" }, lineType: "SERVICE" },
      _sum: { lineTotal: true, quantity: true },
    }),
    prisma.service.findMany({ where: { tenantId } }),
  ]);

  const byMonth = new Map<string, number>();
  for (const inv of invoices) {
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

  const totalRevenue = invoices.reduce((sum, i) => sum + Number(i.totalAmount), 0);
  const ticketMedio = invoices.length ? totalRevenue / invoices.length : 0;

  const topServices = serviceLines
    .map((l) => ({
      service: services.find((s) => s.id === l.referenceId),
      revenue: Number(l._sum.lineTotal ?? 0),
      count: Number(l._sum.quantity ?? 0),
    }))
    .filter((l) => l.service)
    .sort((a, b) => b.revenue - a.revenue)
    .slice(0, 5);

  return { revenueTrend, totalRevenue, ticketMedio, invoiceCount: invoices.length, topServices };
}
