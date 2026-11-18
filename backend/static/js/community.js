/**
 * Módulo de Central de Compras en Comunidad de Origo (Persistente en Rust + SQLite)
 */
window.OrigoCommunity = (() => {
  function render(data) {
    if (!data || !data.products || data.products.length === 0) return;
    const prod = data.products[0];
    const totalQty = prod.total_quantity;
    const pct = Math.min(100, Math.round((totalQty / 100) * 100));
    const currentUser = window.OrigoAuth ? window.OrigoAuth.getUser() : null;

    document.getElementById('volumeBar').style.width = `${pct}%`;
    document.getElementById('volumeLabel').innerText = `${totalQty} / 100 ${prod.unit} reunidos`;
    document.getElementById('storesBadge').innerText = `${data.participating_stores_count} tiendas`;
    document.getElementById('discountBadge').innerText = `${prod.discount_percentage}% Dcto`;
    document.getElementById('commPriceSaving').innerText = `$${Number(prod.savings_cop).toLocaleString('es-CO')} COP`;
    document.getElementById('commFreightSaving').innerText = `$${Number(data.freight_savings_cop).toLocaleString('es-CO')} COP`;
    document.getElementById('commFreightEach').innerText = `$${Number(data.freight_per_store_cop).toLocaleString('es-CO')} COP`;
    document.getElementById('commTotalSaving').innerText = `$${Number(data.total_net_savings_cop).toLocaleString('es-CO')}`;

    document.getElementById('neighborsList').innerHTML = prod.contributions.map(c => {
      const isMe = currentUser && c.business_id === currentUser.id;
      return `
        <div class="neighbor-row">
          <strong>🏪 ${c.business_name} ${isMe ? '(Tú)' : ''}</strong>
          <span style="font-weight: 800; color: var(--primary);">${c.quantity} ${prod.unit}</span>
        </div>
      `;
    }).join('');
  }

  async function refresh() {
    const data = await window.OrigoAPI.getCollectiveSummary();
    render(data);
  }

  async function joinOrder() {
    const data = await window.OrigoAPI.joinCollectiveOrder(10);
    render(data);
    window.OrigoApp.showToast('🎉 ¡Sumaste +10 bultos reales al pedido de tu zona! Guardado en el servidor.');
  }

  return { refresh, joinOrder };
})();
