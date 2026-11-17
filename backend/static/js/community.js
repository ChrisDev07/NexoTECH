/**
 * Módulo de Central de Compras en Comunidad de Origo
 */
window.OrigoCommunity = (() => {
  let joinedExtraBultos = 0;

  async function refresh() {
    const data = await window.OrigoAPI.getCollectiveSummary();
    const prod = data.products[0];
    const totalQty = prod.total_quantity + joinedExtraBultos;
    const extraSavings = joinedExtraBultos * 30000;
    const pct = Math.min(100, Math.round((totalQty / 100) * 100));

    document.getElementById('volumeBar').style.width = `${pct}%`;
    document.getElementById('volumeLabel').innerText = `${totalQty} / 100 bultos reunidos`;
    document.getElementById('storesBadge').innerText = `${data.participating_stores_count} tiendas`;
    document.getElementById('discountBadge').innerText = `${prod.discount_percentage}% Dcto`;
    document.getElementById('commPriceSaving').innerText = `$${(prod.savings_cop + extraSavings).toLocaleString('es-CO')} COP`;
    document.getElementById('commFreightSaving').innerText = `$${data.freight_savings_cop.toLocaleString('es-CO')} COP`;
    document.getElementById('commFreightEach').innerText = `$${data.freight_per_store_cop.toLocaleString('es-CO')} COP`;
    document.getElementById('commTotalSaving').innerText = `$${(data.total_net_savings_cop + extraSavings).toLocaleString('es-CO')}`;

    document.getElementById('neighborsList').innerHTML = prod.contributions.map((c, idx) => {
      const qty = idx === 0 ? c.quantity + joinedExtraBultos : c.quantity;
      return `
        <div class="neighbor-row">
          <strong>🏪 ${c.business_name} ${idx === 0 ? '(Tú)' : ''}</strong>
          <span style="font-weight: 800; color: var(--primary);">${qty} bultos</span>
        </div>
      `;
    }).join('');
  }

  function joinOrder() {
    joinedExtraBultos += 10;
    refresh();
    window.OrigoApp.showToast('🎉 ¡Sumaste +10 bultos al pedido de la Comuna 2! Ahorro actualizado.');
  }

  return { refresh, joinOrder };
})();
