"use client";

import { useMemo, useState } from "react";
import { createSaleAction } from "@/lib/actions/tpv";
import { formatEuro } from "@/lib/format";

type Item = { id: string; name: string; price: number };
type Line = { key: string; type: "SERVICE" | "PRODUCT"; refId: string; name: string; unitPrice: number; quantity: number };

export function SaleForm({
  clients,
  services,
  products,
}: {
  clients: { id: string; firstName: string; lastName: string }[];
  services: Item[];
  products: Item[];
}) {
  const [lines, setLines] = useState<Line[]>([]);
  const [pickType, setPickType] = useState<"SERVICE" | "PRODUCT">("SERVICE");
  const [pickId, setPickId] = useState("");
  const [pickQty, setPickQty] = useState(1);

  const catalog = pickType === "SERVICE" ? services : products;

  const total = useMemo(() => lines.reduce((sum, l) => sum + l.unitPrice * l.quantity, 0), [lines]);

  function addLine() {
    const item = catalog.find((i) => i.id === pickId);
    if (!item || pickQty < 1) return;
    setLines((prev) => [
      ...prev,
      { key: `${pickType}-${item.id}-${Date.now()}`, type: pickType, refId: item.id, name: item.name, unitPrice: item.price, quantity: pickQty },
    ]);
    setPickId("");
    setPickQty(1);
  }

  function removeLine(key: string) {
    setLines((prev) => prev.filter((l) => l.key !== key));
  }

  return (
    <form action={createSaleAction}>
      <input type="hidden" name="linesJson" value={JSON.stringify(lines.map(({ type, refId, quantity }) => ({ type, refId, quantity })))} />

      <div className="field">
        <label htmlFor="clientId">Cliente (opcional)</label>
        <select id="clientId" name="clientId" defaultValue="">
          <option value="">Venta sin cliente asociado</option>
          {clients.map((c) => (
            <option key={c.id} value={c.id}>{c.firstName} {c.lastName}</option>
          ))}
        </select>
      </div>

      <div className="line-item">
        <div className="field" style={{ marginBottom: 0 }}>
          <label>Añadir</label>
          <select
            value={pickType}
            onChange={(e) => {
              setPickType(e.target.value as "SERVICE" | "PRODUCT");
              setPickId("");
            }}
          >
            <option value="SERVICE">Servicio</option>
            <option value="PRODUCT">Producto</option>
          </select>
        </div>
        <div className="field" style={{ marginBottom: 0, gridColumn: "span 1" }}>
          <label>Cant.</label>
          <input type="number" min={1} value={pickQty} onChange={(e) => setPickQty(Number(e.target.value))} />
        </div>
        <div className="field" style={{ marginBottom: 0 }}>
          <label>Artículo</label>
          <select value={pickId} onChange={(e) => setPickId(e.target.value)}>
            <option value="">Selecciona…</option>
            {catalog.map((i) => (
              <option key={i.id} value={i.id}>{i.name} — {formatEuro(i.price)}</option>
            ))}
          </select>
        </div>
        <button type="button" className="btn small secondary" onClick={addLine}>+ Añadir</button>
      </div>

      <div className="line-items" style={{ marginTop: 12 }}>
        {lines.length === 0 ? (
          <p className="empty">Añade servicios o productos a la venta.</p>
        ) : (
          lines.map((l) => (
            <div className="ticket" key={l.key}>
              <div className="line">
                <span>{l.quantity}× {l.name}</span>
                <span style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  {formatEuro(l.unitPrice * l.quantity)}
                  <button type="button" className="btn small secondary" onClick={() => removeLine(l.key)}>✕</button>
                </span>
              </div>
            </div>
          ))
        )}
      </div>

      <div className="total-row">
        <span>Total (IVA incl.)</span>
        <span className="amount">{formatEuro(total)}</span>
      </div>

      <div className="field" style={{ marginTop: 12 }}>
        <label htmlFor="paymentMethod">Forma de pago</label>
        <select id="paymentMethod" name="paymentMethod" defaultValue="CARD">
          <option value="CASH">Efectivo</option>
          <option value="CARD">Tarjeta</option>
          <option value="BIZUM">Bizum</option>
        </select>
      </div>

      <button type="submit" className="btn" disabled={lines.length === 0}>Cobrar</button>
    </form>
  );
}
