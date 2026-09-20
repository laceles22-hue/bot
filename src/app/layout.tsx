import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Salon Manager",
  description: "Gestión integral para peluquerías: agenda, clientes, TPV, stock y comisiones.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
