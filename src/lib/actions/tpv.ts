"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/session";

const IVA_RATE = 21;

type SaleLine = { type: "SERVICE" | "PRODUCT"; refId: string; quantity: number };

export async function createSaleAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");
  const tenantId = session!.tenantId;

  const clientId = String(formData.get("clientId") ?? "") || null;
  const paymentMethod = String(formData.get("paymentMethod") ?? "CASH") as "CASH" | "CARD" | "BIZUM";
  let lines: SaleLine[] = [];
  try {
    lines = JSON.parse(String(formData.get("linesJson") ?? "[]"));
  } catch {
    lines = [];
  }
  if (lines.length === 0) {
    redirect("/tpv?error=" + encodeURIComponent("Añade al menos una línea a la venta."));
  }

  const services = await prisma.service.findMany({ where: { tenantId, id: { in: lines.filter((l) => l.type === "SERVICE").map((l) => l.refId) } } });
  const products = await prisma.product.findMany({ where: { tenantId, id: { in: lines.filter((l) => l.type === "PRODUCT").map((l) => l.refId) } } });

  for (const line of lines) {
    if (line.type === "PRODUCT") {
      const product = products.find((p) => p.id === line.refId);
      if (product && Number(product.stockQty) < line.quantity) {
        redirect("/tpv?error=" + encodeURIComponent(`No hay stock suficiente de "${product.name}".`));
      }
    }
  }

  const resolvedLines = lines.map((line) => {
    if (line.type === "SERVICE") {
      const s = services.find((x) => x.id === line.refId)!;
      return { type: "SERVICE" as const, refId: s.id, description: s.name, unitPrice: Number(s.basePrice), quantity: line.quantity };
    }
    const p = products.find((x) => x.id === line.refId)!;
    return { type: "PRODUCT" as const, refId: p.id, description: p.name, unitPrice: Number(p.retailPrice ?? p.unitCost), quantity: line.quantity };
  });

  const totalAmount = resolvedLines.reduce((sum, l) => sum + l.unitPrice * l.quantity, 0);
  const taxAmount = Math.round(((totalAmount * IVA_RATE) / (100 + IVA_RATE)) * 100) / 100;

  const year = new Date().getFullYear();

  const invoice = await prisma.$transaction(async (tx) => {
    let series = await tx.invoiceSeries.findFirst({ where: { tenantId, seriesCode: "A", year } });
    if (!series) {
      series = await tx.invoiceSeries.create({ data: { tenantId, seriesCode: "A", year, currentNumber: 0 } });
    }
    const nextNumber = series.currentNumber + 1;
    await tx.invoiceSeries.update({ where: { id: series.id }, data: { currentNumber: nextNumber } });

    const inv = await tx.invoice.create({
      data: {
        tenantId,
        seriesId: series.id,
        invoiceNumber: nextNumber,
        clientId,
        totalAmount,
        taxAmount,
      },
    });

    for (const line of resolvedLines) {
      const invoiceLine = await tx.invoiceLine.create({
        data: {
          invoiceId: inv.id,
          lineType: line.type,
          referenceId: line.refId,
          description: line.description,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          taxRate: IVA_RATE,
          lineTotal: line.unitPrice * line.quantity,
        },
      });
      if (line.type === "PRODUCT") {
        await tx.stockMovement.create({
          data: { tenantId, productId: line.refId, type: "SALE", quantity: -line.quantity, relatedInvoiceId: inv.id },
        });
        await tx.product.update({ where: { id: line.refId }, data: { stockQty: { decrement: line.quantity } } });
      }
      void invoiceLine;
    }

    await tx.payment.create({ data: { invoiceId: inv.id, method: paymentMethod, amount: totalAmount } });

    return inv;
  });

  revalidatePath("/tpv");
  revalidatePath("/stock");
  revalidatePath("/");
  redirect(`/tpv?success=${invoice.invoiceNumber}`);
}
