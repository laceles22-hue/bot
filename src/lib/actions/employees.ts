"use server";

import bcrypt from "bcryptjs";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/session";

export async function createEmployeeAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const fullName = String(formData.get("fullName") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const role = String(formData.get("role") ?? "STYLIST") as "OWNER" | "ADMIN" | "STYLIST" | "RECEPTIONIST";

  if (!fullName || !email || password.length < 6) {
    redirect("/empleados?error=" + encodeURIComponent("Nombre, email y una contraseña de al menos 6 caracteres son obligatorios."));
  }

  const existing = await prisma.user.findFirst({ where: { tenantId: session!.tenantId, email } });
  if (existing) redirect("/empleados?error=" + encodeURIComponent("Ya existe un empleado con ese email."));

  const passwordHash = await bcrypt.hash(password, 10);
  await prisma.user.create({
    data: { tenantId: session!.tenantId, fullName, email, passwordHash, role },
  });

  revalidatePath("/empleados");
  redirect("/empleados");
}
