"use client";

import { usePathname } from "next/navigation";
import { Icon, IconSprite } from "@/components/Icons";
import { logoutAction } from "@/lib/actions/auth";

const NAV_ITEMS = [
  { href: "/", icon: "home", label: "Panel" },
  { href: "/agenda", icon: "calendar", label: "Agenda" },
  { href: "/clientes", icon: "users", label: "Clientes" },
  { href: "/tpv", icon: "receipt", label: "TPV" },
  { href: "/stock", icon: "box", label: "Stock" },
  { href: "/empleados", icon: "bars", label: "Empleados" },
  { href: "/informes", icon: "trend", label: "Informes" },
];

export function Sidebar({ tenantName, userName }: { tenantName: string; userName: string }) {
  const pathname = usePathname();

  return (
    <aside className="rail">
      <IconSprite />
      <div className="brand">
        <span className="brand-mark">
          <svg className="icon" viewBox="0 0 24 24" stroke="currentColor">
            <path d="M6 6l12 12M18 6 6 18" />
            <circle cx="7" cy="6" r="1.6" fill="currentColor" stroke="none" />
            <circle cx="7" cy="18" r="1.6" fill="currentColor" stroke="none" />
          </svg>
        </span>
        <span className="brand-name">Salon Manager</span>
      </div>
      <nav className="rail-nav">
        {NAV_ITEMS.map((item) => (
          <a key={item.href} href={item.href} className={pathname === item.href ? "current" : undefined}>
            <Icon name={item.icon} />
            <span className="label">{item.label}</span>
          </a>
        ))}
      </nav>
      <div className="rail-foot">
        <div className="rail-user">{userName}</div>
        {tenantName}
        <form action={logoutAction}>
          <button type="submit" className="rail-logout">Cerrar sesión</button>
        </form>
      </div>
    </aside>
  );
}
