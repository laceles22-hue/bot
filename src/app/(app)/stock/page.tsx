import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import { prisma } from "@/lib/prisma";
import { createProductAction, registerStockMovementAction } from "@/lib/actions/stock";

export const dynamic = "force-dynamic";

const TYPE_LABELS: Record<string, string> = { RETAIL: "Venta al público", INTERNAL_USE: "Consumo interno", BOTH: "Ambos" };

export default async function StockPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const session = await getSession();
  if (!session) redirect("/login");
  const { error } = await searchParams;

  const products = await prisma.product.findMany({
    where: { tenantId: session.tenantId, active: true },
    orderBy: { stockQty: "asc" },
  });

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Stock e Inventario</h1>
          <p>Productos de venta y consumo interno, con alertas de stock bajo.</p>
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="layout-2col">
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="panel">
            <h2>Nuevo producto</h2>
            <form action={createProductAction}>
              <div className="field-row">
                <div className="field">
                  <label htmlFor="name">Nombre</label>
                  <input id="name" name="name" required />
                </div>
                <div className="field">
                  <label htmlFor="sku">SKU</label>
                  <input id="sku" name="sku" required />
                </div>
              </div>
              <div className="field">
                <label htmlFor="type">Uso</label>
                <select id="type" name="type" defaultValue="BOTH">
                  <option value="RETAIL">Venta al público</option>
                  <option value="INTERNAL_USE">Consumo interno</option>
                  <option value="BOTH">Ambos</option>
                </select>
              </div>
              <div className="field-row">
                <div className="field">
                  <label htmlFor="unitCost">Coste unitario (€)</label>
                  <input id="unitCost" name="unitCost" type="number" step="0.01" min="0" required />
                </div>
                <div className="field">
                  <label htmlFor="retailPrice">Precio venta (€)</label>
                  <input id="retailPrice" name="retailPrice" type="number" step="0.01" min="0" />
                </div>
              </div>
              <div className="field-row">
                <div className="field">
                  <label htmlFor="stockQty">Stock inicial</label>
                  <input id="stockQty" name="stockQty" type="number" step="0.01" defaultValue={0} />
                </div>
                <div className="field">
                  <label htmlFor="minStockAlert">Alerta mínima</label>
                  <input id="minStockAlert" name="minStockAlert" type="number" step="0.01" />
                </div>
              </div>
              <button type="submit" className="btn">Crear producto</button>
            </form>
          </div>

          <div className="panel">
            <h2>Registrar movimiento</h2>
            <form action={registerStockMovementAction}>
              <div className="field">
                <label htmlFor="productId">Producto</label>
                <select id="productId" name="productId" required defaultValue="">
                  <option value="" disabled>Selecciona un producto</option>
                  {products.map((p) => (
                    <option key={p.id} value={p.id}>{p.name}</option>
                  ))}
                </select>
              </div>
              <div className="field-row">
                <div className="field">
                  <label htmlFor="type2">Tipo</label>
                  <select id="type2" name="type" defaultValue="PURCHASE">
                    <option value="PURCHASE">Compra (entrada)</option>
                    <option value="LOSS">Merma (salida)</option>
                    <option value="ADJUSTMENT">Ajuste manual</option>
                  </select>
                </div>
                <div className="field">
                  <label htmlFor="quantity">Cantidad</label>
                  <input id="quantity" name="quantity" type="number" step="0.01" required />
                </div>
              </div>
              <button type="submit" className="btn small secondary">Registrar movimiento</button>
            </form>
          </div>
        </div>

        <div className="panel">
          <h2>Inventario ({products.length})</h2>
          {products.length === 0 ? (
            <p className="empty">Todavía no hay productos dados de alta.</p>
          ) : (
            <div className="table-wrap">
              <table className="list">
                <thead><tr><th>Producto</th><th>Uso</th><th>Stock</th><th>Mínimo</th><th></th></tr></thead>
                <tbody>
                  {products.map((p) => {
                    const low = p.minStockAlert != null && Number(p.stockQty) < Number(p.minStockAlert);
                    return (
                      <tr key={p.id}>
                        <td>{p.name}</td>
                        <td>{TYPE_LABELS[p.type]}</td>
                        <td>{Number(p.stockQty)}</td>
                        <td>{p.minStockAlert != null ? Number(p.minStockAlert) : "—"}</td>
                        <td>{low && <span className="status-pill cancelled">Stock bajo</span>}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
