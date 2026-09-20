import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

function todayAt(hour: number, minute: number) {
  const d = new Date();
  d.setHours(hour, minute, 0, 0);
  return d;
}

async function main() {
  const tenant = await prisma.tenant.create({
    data: {
      name: "Urban Beauty",
      taxId: "B12345678",
    },
  });

  const [marta, laura, david] = await Promise.all([
    prisma.user.create({
      data: {
        tenantId: tenant.id,
        email: "marta@urbanbeauty.test",
        passwordHash: "seed-placeholder",
        fullName: "Marta Gómez",
        role: "STYLIST",
      },
    }),
    prisma.user.create({
      data: {
        tenantId: tenant.id,
        email: "laura@urbanbeauty.test",
        passwordHash: "seed-placeholder",
        fullName: "Laura Fernández",
        role: "STYLIST",
      },
    }),
    prisma.user.create({
      data: {
        tenantId: tenant.id,
        email: "david@urbanbeauty.test",
        passwordHash: "seed-placeholder",
        fullName: "David Ortega",
        role: "STYLIST",
      },
    }),
  ]);

  const colorCategory = await prisma.serviceCategory.create({
    data: { tenantId: tenant.id, name: "Color" },
  });
  const corteCategory = await prisma.serviceCategory.create({
    data: { tenantId: tenant.id, name: "Corte" },
  });
  const tratamientoCategory = await prisma.serviceCategory.create({
    data: { tenantId: tenant.id, name: "Tratamiento" },
  });

  const [corteSenora, mechas, coloracion, corteYPeinado, queratina] = await Promise.all([
    prisma.service.create({
      data: { tenantId: tenant.id, categoryId: corteCategory.id, name: "Corte señora", durationMinutes: 45, basePrice: 18 },
    }),
    prisma.service.create({
      data: { tenantId: tenant.id, categoryId: colorCategory.id, name: "Mechas", durationMinutes: 90, basePrice: 45 },
    }),
    prisma.service.create({
      data: { tenantId: tenant.id, categoryId: colorCategory.id, name: "Coloración", durationMinutes: 90, basePrice: 50 },
    }),
    prisma.service.create({
      data: { tenantId: tenant.id, categoryId: corteCategory.id, name: "Corte + peinado", durationMinutes: 45, basePrice: 25 },
    }),
    prisma.service.create({
      data: { tenantId: tenant.id, categoryId: tratamientoCategory.id, name: "Tratamiento queratina", durationMinutes: 60, basePrice: 60 },
    }),
  ]);

  const coloracionProductos = await prisma.productCategory.create({
    data: { tenantId: tenant.id, name: "Coloración" },
  });
  const higieneProductos = await prisma.productCategory.create({
    data: { tenantId: tenant.id, name: "Higiene" },
  });

  const tinte = await prisma.product.create({
    data: {
      tenantId: tenant.id,
      categoryId: coloracionProductos.id,
      sku: "TIN-7.1",
      name: "Tinte 7.1 rubio ceniza",
      type: "INTERNAL_USE",
      unitCost: 4.5,
      stockQty: 72,
      minStockAlert: 15,
    },
  });
  await prisma.product.create({
    data: {
      tenantId: tenant.id,
      categoryId: coloracionProductos.id,
      sku: "OXI-20",
      name: "Oxidante 20 vol",
      type: "INTERNAL_USE",
      unitCost: 2.8,
      stockQty: 54,
      minStockAlert: 15,
    },
  });
  const champu = await prisma.product.create({
    data: {
      tenantId: tenant.id,
      categoryId: higieneProductos.id,
      sku: "CHA-TEC",
      name: "Champú técnico",
      type: "BOTH",
      unitCost: 5.2,
      retailPrice: 12.5,
      stockQty: 3,
      minStockAlert: 10,
    },
  });
  await prisma.product.create({
    data: {
      tenantId: tenant.id,
      categoryId: higieneProductos.id,
      sku: "MAS-QUE",
      name: "Mascarilla queratina",
      type: "BOTH",
      unitCost: 6.1,
      retailPrice: 15,
      stockQty: 63,
      minStockAlert: 15,
    },
  });

  const clientDefs = [
    { first: "Ana", last: "Ruiz", allergy: "amoníaco", note: "Tinte 7.1 rubio ceniza" },
    { first: "Carla", last: "García" },
    { first: "Sonia", last: "Pérez" },
    { first: "Iván", last: "Torres" },
    { first: "Nuria", last: "Martín" },
  ];
  const [ana, carla, sonia, ivan, nuria] = await Promise.all(
    clientDefs.map((c) =>
      prisma.client.create({
        data: {
          tenantId: tenant.id,
          firstName: c.first,
          lastName: c.last,
          gdprConsent: true,
          gdprConsentAt: new Date(),
        },
      })
    )
  );

  await prisma.clientAllergy.create({
    data: { clientId: ana.id, substance: "amoníaco", severity: "alta" },
  });
  await prisma.clientTechnicalNote.create({
    data: {
      clientId: ana.id,
      authorUserId: marta.id,
      type: "FORMULA_TINTE",
      content: { producto: "Tinte 7.1 rubio ceniza", oxidante: "20 vol", tiempo: "35 min" },
    },
  });

  const series = await prisma.invoiceSeries.create({
    data: { tenantId: tenant.id, seriesCode: "A", year: 2026, currentNumber: 482 },
  });

  const appointmentDefs = [
    { client: carla, employee: marta, service: corteYPeinado, start: [9, 0], end: [9, 45], status: "DONE" as const },
    { client: sonia, employee: laura, service: coloracion, start: [9, 30], end: [10, 15], status: "DONE" as const },
    { client: ana, employee: david, service: mechas, start: [10, 0], end: [11, 30], status: "CONFIRMED" as const },
    { client: ivan, employee: marta, service: corteSenora, start: [11, 0], end: [11, 30], status: "CONFIRMED" as const },
    { client: nuria, employee: laura, service: queratina, start: [12, 0], end: [13, 0], status: "PENDING" as const },
  ];

  for (const a of appointmentDefs) {
    const appointment = await prisma.appointment.create({
      data: {
        tenantId: tenant.id,
        clientId: a.client.id,
        employeeId: a.employee.id,
        startTime: todayAt(a.start[0], a.start[1]),
        endTime: todayAt(a.end[0], a.end[1]),
        status: a.status,
      },
    });
    await prisma.appointmentService.create({
      data: { appointmentId: appointment.id, serviceId: a.service.id, priceAtBooking: a.service.basePrice },
    });
  }

  const invoice = await prisma.invoice.create({
    data: {
      tenantId: tenant.id,
      seriesId: series.id,
      invoiceNumber: 482,
      clientId: ana.id,
      totalAmount: 75.5,
      taxAmount: 6.86,
    },
  });
  const [lineCorte, lineMechas, lineChampu] = await Promise.all([
    prisma.invoiceLine.create({
      data: { invoiceId: invoice.id, lineType: "SERVICE", referenceId: corteSenora.id, description: "Corte señora", quantity: 1, unitPrice: 18, taxRate: 10, lineTotal: 18 },
    }),
    prisma.invoiceLine.create({
      data: { invoiceId: invoice.id, lineType: "SERVICE", referenceId: mechas.id, description: "Mechas", quantity: 1, unitPrice: 45, taxRate: 10, lineTotal: 45 },
    }),
    prisma.invoiceLine.create({
      data: { invoiceId: invoice.id, lineType: "PRODUCT", referenceId: champu.id, description: "Champú técnico", quantity: 1, unitPrice: 12.5, taxRate: 10, lineTotal: 12.5 },
    }),
  ]);
  await prisma.payment.create({
    data: { invoiceId: invoice.id, method: "CARD", amount: 75.5 },
  });
  await prisma.stockMovement.create({
    data: { tenantId: tenant.id, productId: champu.id, type: "SALE", quantity: -1, relatedInvoiceId: invoice.id },
  });

  const commissionRule = await prisma.commissionRule.create({
    data: { tenantId: tenant.id, percentage: 10 },
  });
  const periodMonth = new Date().toISOString().slice(0, 7);
  await Promise.all([
    prisma.commissionRecord.create({
      data: { tenantId: tenant.id, employeeId: marta.id, invoiceId: invoice.id, invoiceLineId: lineCorte.id, amount: 312, periodMonth },
    }),
    prisma.commissionRecord.create({
      data: { tenantId: tenant.id, employeeId: laura.id, invoiceId: invoice.id, invoiceLineId: lineMechas.id, amount: 268, periodMonth },
    }),
    prisma.commissionRecord.create({
      data: { tenantId: tenant.id, employeeId: david.id, invoiceId: invoice.id, invoiceLineId: lineChampu.id, amount: 194, periodMonth },
    }),
  ]);
  void commissionRule;

  await prisma.cashSession.create({
    data: { tenantId: tenant.id, userId: marta.id, openingAmount: 100 },
  });

  // Historical monthly totals purely to give the revenue trend chart something to plot.
  const monthlyTotals: [string, number][] = [
    ["2026-04-15", 9800],
    ["2026-05-15", 10200],
    ["2026-06-15", 9700],
    ["2026-07-15", 11500],
    ["2026-08-15", 12100],
  ];
  await Promise.all(
    monthlyTotals.map(([date, total], i) =>
      prisma.invoice.create({
        data: {
          tenantId: tenant.id,
          seriesId: series.id,
          invoiceNumber: 100 + i,
          issuedAt: new Date(date),
          totalAmount: total,
          taxAmount: Math.round(((total * 10) / 110) * 100) / 100,
        },
      })
    )
  );

  console.log(`Seed complete for tenant "${tenant.name}" (${tenant.id})`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
