"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/session";

export async function createAppointmentAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const clientId = String(formData.get("clientId") ?? "");
  const employeeId = String(formData.get("employeeId") ?? "");
  const serviceId = String(formData.get("serviceId") ?? "");
  const date = String(formData.get("date") ?? "");
  const time = String(formData.get("time") ?? "");

  if (!clientId || !employeeId || !serviceId || !date || !time) {
    redirect(`/agenda?date=${date}&error=${encodeURIComponent("Rellena todos los campos.")}`);
  }

  const service = await prisma.service.findUnique({ where: { id: serviceId } });
  if (!service) redirect(`/agenda?date=${date}&error=${encodeURIComponent("Servicio no válido.")}`);

  const startTime = new Date(`${date}T${time}:00`);
  const endTime = new Date(startTime.getTime() + service!.durationMinutes * 60000);

  const overlap = await prisma.appointment.findFirst({
    where: {
      employeeId,
      status: { notIn: ["CANCELLED"] },
      startTime: { lt: endTime },
      endTime: { gt: startTime },
    },
  });
  if (overlap) {
    redirect(`/agenda?date=${date}&error=${encodeURIComponent("Ese empleado ya tiene una cita en ese horario.")}`);
  }

  const appointment = await prisma.appointment.create({
    data: {
      tenantId: session!.tenantId,
      clientId,
      employeeId,
      startTime,
      endTime,
      status: "CONFIRMED",
    },
  });
  await prisma.appointmentService.create({
    data: { appointmentId: appointment.id, serviceId, priceAtBooking: service!.basePrice },
  });

  revalidatePath("/agenda");
  revalidatePath("/");
  redirect(`/agenda?date=${date}`);
}

export async function updateAppointmentStatusAction(formData: FormData) {
  const session = await getSession();
  if (!session) redirect("/login");

  const appointmentId = String(formData.get("appointmentId") ?? "");
  const status = String(formData.get("status") ?? "");
  const date = String(formData.get("date") ?? "");

  const appointment = await prisma.appointment.findFirst({ where: { id: appointmentId, tenantId: session!.tenantId } });
  if (!appointment) redirect(`/agenda?date=${date}`);

  await prisma.appointment.update({
    where: { id: appointmentId },
    data: { status: status as "PENDING" | "CONFIRMED" | "DONE" | "CANCELLED" | "NO_SHOW" },
  });

  revalidatePath("/agenda");
  revalidatePath("/");
  redirect(`/agenda?date=${date}`);
}
