import { getSession } from "@/lib/session";
import { prisma } from "@/lib/prisma";
import { Sidebar } from "@/components/Sidebar";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await getSession();
  const tenant = session ? await prisma.tenant.findUnique({ where: { id: session.tenantId } }) : null;

  return (
    <div className="shell">
      <Sidebar tenantName={tenant?.name ?? ""} userName={session?.fullName ?? ""} />
      <main className="content">
        <div className="main-inner">{children}</div>
      </main>
    </div>
  );
}
