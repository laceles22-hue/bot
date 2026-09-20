"use server";

import bcrypt from "bcryptjs";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { createSession, destroySession } from "@/lib/session";

export async function loginAction(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");

  const user = await prisma.user.findFirst({ where: { email, active: true } });
  const valid = user ? await bcrypt.compare(password, user.passwordHash) : false;

  if (!user || !valid) {
    redirect("/login?error=1");
  }

  await createSession({
    userId: user.id,
    tenantId: user.tenantId,
    fullName: user.fullName,
    role: user.role,
  });
  redirect("/");
}

export async function logoutAction() {
  await destroySession();
  redirect("/login");
}
