"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/session";

export async function createClientAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const firstName = String(formData.get("firstName") ?? "").trim();
  const lastName = String(formData.get("lastName") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const email = String(formData.get("email") ?? "").trim() || null;

  if (!firstName || !lastName) redirect("/clientes?error=" + encodeURIComponent("Nombre y apellidos son obligatorios."));

  const client = await prisma.client.create({
    data: { tenantId: session!.tenantId, firstName, lastName, phone, email },
  });

  revalidatePath("/clientes");
  redirect(`/clientes/${client.id}`);
}

export async function addTechnicalNoteAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const clientId = String(formData.get("clientId") ?? "");
  const type = String(formData.get("type") ?? "OTRO");
  const producto = String(formData.get("producto") ?? "").trim();

  const client = await prisma.client.findFirst({ where: { id: clientId, tenantId: session!.tenantId } });
  if (!client) redirect("/clientes");

  await prisma.clientTechnicalNote.create({
    data: {
      clientId,
      authorUserId: session!.userId,
      type: type as "FORMULA_TINTE" | "DECOLORACION" | "QUERATINA" | "ALERGIA" | "OTRO",
      content: { producto },
    },
  });

  revalidatePath(`/clientes/${clientId}`);
  redirect(`/clientes/${clientId}`);
}

export async function addAllergyAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const clientId = String(formData.get("clientId") ?? "");
  const substance = String(formData.get("substance") ?? "").trim();
  const severity = String(formData.get("severity") ?? "").trim() || null;

  const client = await prisma.client.findFirst({ where: { id: clientId, tenantId: session!.tenantId } });
  if (!client || !substance) redirect(`/clientes/${clientId}`);

  await prisma.clientAllergy.create({ data: { clientId, substance, severity } });

  revalidatePath(`/clientes/${clientId}`);
  redirect(`/clientes/${clientId}`);
}
