"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/session";

export async function createProductAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const name = String(formData.get("name") ?? "").trim();
  const sku = String(formData.get("sku") ?? "").trim();
  const type = String(formData.get("type") ?? "BOTH") as "RETAIL" | "INTERNAL_USE" | "BOTH";
  const unitCost = Number(formData.get("unitCost") ?? 0);
  const retailPrice = formData.get("retailPrice") ? Number(formData.get("retailPrice")) : null;
  const stockQty = Number(formData.get("stockQty") ?? 0);
  const minStockAlert = formData.get("minStockAlert") ? Number(formData.get("minStockAlert")) : null;

  if (!name || !sku) redirect("/stock?error=" + encodeURIComponent("Nombre y SKU son obligatorios."));

  await prisma.product.create({
    data: { tenantId: session!.tenantId, name, sku, type, unitCost, retailPrice, stockQty, minStockAlert },
  });

  revalidatePath("/stock");
  redirect("/stock");
}

export async function registerStockMovementAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const productId = String(formData.get("productId") ?? "");
  const type = String(formData.get("type") ?? "ADJUSTMENT") as "PURCHASE" | "ADJUSTMENT" | "LOSS";
  const quantity = Number(formData.get("quantity") ?? 0);

  const product = await prisma.product.findFirst({ where: { id: productId, tenantId: session!.tenantId } });
  if (!product || !quantity) redirect("/stock");

  const signedQty = type === "LOSS" ? -Math.abs(quantity) : quantity;

  await prisma.$transaction([
    prisma.stockMovement.create({
      data: { tenantId: session!.tenantId, productId, type, quantity: signedQty },
    }),
    prisma.product.update({ where: { id: productId }, data: { stockQty: { increment: signedQty } } }),
  ]);

  revalidatePath("/stock");
  redirect("/stock");
}
