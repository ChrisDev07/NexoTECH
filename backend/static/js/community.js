/**
 * Módulo de Tablón Comunitario de Compras Colectivas de Origo (Rust + SQLite)
 */
window.OrigoCommunity = (() => {
  let lastData = null;
  let expandedCardIndex = 0; // Primera tarjeta expandida por defecto
  const cardSteppers = {}; // { [product_id]: number }

  const PRODUCT_ICONS = {
    prod_arroz_casanare: '🌾',
    prod_aceite_vegetal: '🛢️',
    prod_panela_criolla: '🟫',
    prod_papa_pastusa: '🥔',
    prod_abono_triple15: '🌱',
    prod_cemento_gris: '🧱',
    prod_sal_marina: '🧂',
    prod_harina_pan: '🌽'
  };

  function getIcon(pid) {
    return PRODUCT_ICONS[pid] || '📦';
  }

  function render(data) {
    lastData = data;
    if (!data) return;

    const currentUser = window.OrigoAuth ? window.OrigoAuth.getUser() : null;
    const zoneName = currentUser ? currentUser.zone : 'Yopal';

    const heroTitle = document.getElementById('communityZoneHeroTitle');
    if (heroTitle) heroTitle.innerText = `🤝 Tablón Comunitario · ${zoneName}`;

    const zoneTitle = document.getElementById('communityZoneTitle');
    if (zoneTitle) zoneTitle.innerText = `💰 Impacto acumulado · ${zoneName}`;

    const storesTotal = document.getElementById('commStoresTotal');
    if (storesTotal) storesTotal.innerText = `${data.participating_stores_count || 0} tiendas unidas`;

    const freightSaving = document.getElementById('commFreightSaving');
    if (freightSaving) freightSaving.innerText = `$${Number(data.freight_savings_cop || 0).toLocaleString('es-CO')} COP`;

    const totalSaving = document.getElementById('commTotalSaving');
    if (totalSaving) totalSaving.innerText = `$${Number(data.total_net_savings_cop || 0).toLocaleString('es-CO')} COP`;

    const board = document.getElementById('collectiveBoardList');
    if (!board) return;

    const products = data.products || [];
    if (products.length === 0) {
      board.innerHTML = `
        <div style="text-align: center; padding: 32px 16px; color: var(--text-muted); background: var(--card); border-radius: 16px; border: 1.5px dashed var(--border);">
          No hay pedidos activos en este momento. ¡Sé el primero en proponer una compra!
        </div>
      `;
      return;
    }

    board.innerHTML = products.map((prod, idx) => {
      const isExpanded = idx === expandedCardIndex;
      const icon = getIcon(prod.product_id);
      const target = Number(prod.target_quantity) || 50;
      const current = Number(prod.total_quantity) || 0;
      const pct = Math.min(100, Math.round((current / target) * 100));

      if (cardSteppers[prod.product_id] === undefined) {
        cardSteppers[prod.product_id] = 10;
      }
      const myStepQty = cardSteppers[prod.product_id];

      const myContribution = currentUser
        ? (prod.contributions || []).find(c => c.business_id === currentUser.id)
        : null;

      const contributionsHtml = (prod.contributions || []).map(c => {
        const isMe = currentUser && c.business_id === currentUser.id;
        return `
          <div class="neighbor-row" style="background: ${isMe ? '#ecfdf5' : '#ffffff'}; border-color: ${isMe ? '#a7f3d0' : '#e7e5e4'};">
            <div>
              <strong style="color: ${isMe ? '#047857' : 'inherit'};">🏪 ${c.business_name} ${isMe ? '(Tú)' : ''}</strong>
              <div style="font-size: 0.78rem; color: var(--text-muted);">${c.zone || zoneName}</div>
            </div>
            <span style="font-weight: 800; color: #047857; font-size: 0.95rem;">${c.quantity} ${prod.unit}</span>
          </div>
        `;
      }).join('');

      return `
        <div class="board-card ${isExpanded ? 'expanded' : ''}" id="board-card-${idx}">
          <div class="board-card-header" onclick="OrigoCommunity.toggleCard(${idx})">
            <div class="board-card-top">
              <div class="board-prod-title">
                <span style="font-size: 1.4rem;">${icon}</span>
                <span>${prod.product_name}</span>
              </div>
              <span class="certainty-badge" style="background: var(--primary-soft); color: var(--primary-text); font-size: 0.8rem; font-weight: 800;">
                ${prod.discount_percentage}% Dcto
              </span>
            </div>

            <div class="progress-bar-bg" style="margin: 8px 0 6px;">
              <div class="progress-bar-fill" style="width: ${pct}%;"></div>
            </div>

            <div class="board-card-meta">
              <span><strong>${current} / ${target} ${prod.unit}</strong> reunidos (${pct}%)</span>
              <div style="display: flex; align-items: center; gap: 8px;">
                <span>${prod.stores_count} tienda${prod.stores_count === 1 ? '' : 's'}</span>
                <span class="board-chevron">▼</span>
              </div>
            </div>
          </div>

          <div class="board-card-body">
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 12px;">
              <div style="background: #ffffff; padding: 10px 12px; border-radius: 12px; border: 1px solid var(--border);">
                <div style="font-size: 0.78rem; color: var(--text-muted); font-weight: 700;">Ahorro mayorista:</div>
                <div style="font-size: 0.95rem; font-weight: 800; color: #047857;">$${Number(prod.savings_cop).toLocaleString('es-CO')} COP</div>
              </div>
              <div style="background: #ffffff; padding: 10px 12px; border-radius: 12px; border: 1px solid var(--border);">
                <div style="font-size: 0.78rem; color: var(--text-muted); font-weight: 700;">Flete por tienda:</div>
                <div style="font-size: 0.95rem; font-weight: 800; color: #92400e;">$${Number(data.freight_per_store_cop || 30000).toLocaleString('es-CO')} COP</div>
              </div>
            </div>

            <div style="font-size: 0.88rem; font-weight: 800; margin: 10px 0 6px; color: var(--text);">
              🏪 Comercios participantes (${prod.stores_count}):
            </div>
            <div style="max-height: 160px; overflow-y: auto; margin-bottom: 12px;">
              ${contributionsHtml}
            </div>

            <div class="board-stepper-box">
              <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="font-size: 0.88rem; font-weight: 800; color: #1c1917;">
                  ${myContribution ? `Tu aporte actual: ${myContribution.quantity} ${prod.unit}` : '¿Necesitas este producto?'}
                </span>
                <span style="font-size: 0.78rem; color: var(--primary); font-weight: 700;">Pides directo al molino</span>
              </div>
              <div class="board-stepper-row">
                <button type="button" class="btn-step" onclick="OrigoCommunity.adjustStep('${prod.product_id}', -5)">−</button>
                <span class="stepper-val" style="font-size: 1.15rem; font-weight: 900;">+${myStepQty} ${prod.unit}</span>
                <button type="button" class="btn-step" onclick="OrigoCommunity.adjustStep('${prod.product_id}', 5)">+</button>
              </div>
              <button type="button" class="btn-participate-submit" onclick="OrigoCommunity.joinWithProduct('${prod.product_id}', '${prod.product_name}', '${prod.unit}')">
                🤝 ${myContribution ? `Aumentar pedido (+${myStepQty} ${prod.unit})` : `Participar con ${myStepQty} ${prod.unit}`}
              </button>
            </div>
          </div>
        </div>
      `;
    }).join('');
  }

  function toggleCard(idx) {
    expandedCardIndex = expandedCardIndex === idx ? -1 : idx;
    if (lastData) render(lastData);
  }

  function adjustStep(productId, delta) {
    const cur = cardSteppers[productId] || 10;
    const next = Math.max(1, cur + delta);
    cardSteppers[productId] = next;
    if (lastData) render(lastData);
  }

  async function joinWithProduct(productId, productName, unit) {
    const qty = cardSteppers[productId] || 10;
    try {
      const data = await window.OrigoAPI.joinCollectiveOrder(productId, qty, productName, unit);
      render(data);
      window.OrigoApp.showToast(`🎉 ¡Sumaste +${qty} ${unit} a ${productName}! Guardado en el servidor.`);
    } catch (err) {
      window.OrigoApp.showToast(`⚠️ ${err.message}`);
    }
  }

  async function refresh() {
    const data = await window.OrigoAPI.getCollectiveSummary();
    render(data);
  }

  // --- MODAL PROPONER COMPRA ---

  function openProposeModal() {
    const modal = document.getElementById('proposePurchaseModal');
    if (modal) modal.classList.add('open');
  }

  function closeProposeModal() {
    const modal = document.getElementById('proposePurchaseModal');
    if (modal) modal.classList.remove('open');
  }

  function onProposeProductChange(val) {
    const customRow = document.getElementById('propCustomRow');
    if (customRow) {
      customRow.style.display = val === 'custom' ? 'block' : 'none';
    }
  }

  async function submitProposePurchase(e) {
    if (e) e.preventDefault();
    const sel = document.getElementById('propProductSelect').value;
    let productId = sel;
    let productName = '';

    if (sel === 'custom') {
      const customName = document.getElementById('propCustomName').value.trim();
      if (customName.length < 2) {
        window.OrigoApp.showToast('⚠️ Escribe el nombre del producto.');
        return;
      }
      productName = customName;
      productId = `prod_custom_${Date.now()}`;
    } else {
      const opt = document.querySelector(`#propProductSelect option[value="${sel}"]`);
      productName = opt ? opt.innerText.replace(/^[^\w]+/, '').trim() : sel;
    }

    const unit = document.getElementById('propUnit').value;
    const qty = Number(document.getElementById('propMyQty').value) || 10;

    try {
      const data = await window.OrigoAPI.joinCollectiveOrder(productId, qty, productName, unit);
      closeProposeModal();
      render(data);
      window.OrigoApp.showToast(`🎉 ¡Compra colectiva de "${productName}" publicada en el tablón!`);
    } catch (err) {
      window.OrigoApp.showToast(`⚠️ ${err.message}`);
    }
  }

  return {
    render,
    refresh,
    toggleCard,
    adjustStep,
    joinWithProduct,
    openProposeModal,
    closeProposeModal,
    onProposeProductChange,
    submitProposePurchase
  };
})();
