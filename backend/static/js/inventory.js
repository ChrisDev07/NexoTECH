/**
 * Módulo de Inventario Diario (00:00 - 23:59) y Movimientos Recientes de Origo
 */
window.OrigoInventory = (() => {
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

  let allStock = [];
  let activeCategory = 'Todos';

  function getIcon(productId) {
    return PRODUCT_ICONS[productId] || '📦';
  }

  function applyDailyStock(daily) {
    allStock = daily.items || [];

    const todayFormatted = new Date().toLocaleDateString('es-CO', {
      weekday: 'long', day: 'numeric', month: 'short', year: 'numeric'
    });
    document.getElementById('dailyDateLabel').innerText =
      `📅 ${todayFormatted.charAt(0).toUpperCase() + todayFormatted.slice(1)}`;
    document.getElementById('kpiInToday').innerText = `+${daily.summary.total_in_today}`;
    document.getElementById('kpiOutToday').innerText = `-${daily.summary.total_out_today}`;
    document.getElementById('kpiMovesToday').innerText = `${daily.summary.movements_count_today}`;

    updateLowStockBanner();
    renderFullStock();
  }

  async function refreshStock() {
    const daily = await window.OrigoAPI.getDailyStock();
    applyDailyStock(daily);
  }

  function updateLowStockBanner() {
    const lowItems = allStock.filter(i => i.needs_reorder);
    const banner = document.getElementById('lowStockBanner');
    if (lowItems.length > 0) {
      banner.classList.add('visible');
      document.getElementById('lowStockText').innerText =
        lowItems.length === 1
          ? `⚠️ Queda poco ${lowItems[0].product_name} (${lowItems[0].current_stock} ${lowItems[0].unit})`
          : `⚠️ ${lowItems.length} productos necesitan reposición pronto`;
    } else {
      banner.classList.remove('visible');
    }
  }

  function renderProductCard(item) {
    const icon = getIcon(item.product_id);
    const isLow = item.needs_reorder;
    const dailyDetail = item.has_activity_today
      ? `<div class="daily-breakdown">
           <span>00:00: ${item.opening_stock}</span>
           <span class="tag-in-day">📥 +${item.today_in}</span>
           <span class="tag-out-day">📤 -${item.today_out}</span>
           ${item.last_movement_time ? `<span>· ${item.last_movement_time}</span>` : ''}
         </div>`
      : `<div class="daily-breakdown">
           <span>00:00: ${item.opening_stock} · Sin movimientos hoy</span>
         </div>`;

    return `
      <div class="product-card ${isLow ? 'critical' : ''}" onclick="OrigoApp.triggerPhrase('venta de 1 ${item.unit} de ${item.product_name.toLowerCase()}')">
        <div class="product-left">
          <div class="product-icon">${icon}</div>
          <div>
            <div class="product-name">${item.product_name}</div>
            <div class="product-meta">Mínimo: ${item.min_threshold} ${item.unit} · ${item.category}</div>
            ${dailyDetail}
          </div>
        </div>
        <div class="stock-pill ${isLow ? 'low' : 'ok'}">
          ${isLow ? '⚠️ ' : '✔ '}${item.current_stock} ${item.unit}
        </div>
      </div>
    `;
  }

  function filterCategory(cat, btn) {
    activeCategory = cat;
    document.querySelectorAll('.filter-pill').forEach(p => p.classList.remove('active'));
    if (btn) btn.classList.add('active');
    renderFullStock();
  }

  function renderFullStock() {
    let filtered = allStock;
    if (activeCategory === 'MOVIDOS_HOY') {
      filtered = allStock.filter(i => i.has_activity_today);
    } else if (activeCategory !== 'Todos') {
      filtered = allStock.filter(i => i.category === activeCategory);
    }

    document.getElementById('bodegaCountTag').innerText =
      `${filtered.length} producto${filtered.length === 1 ? '' : 's'}`;

    if (filtered.length === 0) {
      document.getElementById('fullStockList').innerHTML = `
        <div style="text-align: center; padding: 28px 16px; color: var(--text-muted); background: var(--card); border-radius: 16px; border: 1px dashed var(--border);">
          Aún no hay productos movidos en esta categoría hoy (00:00 – 23:59).
        </div>
      `;
      return;
    }

    document.getElementById('fullStockList').innerHTML = filtered.map(renderProductCard).join('');
  }

  async function refreshMovements() {
    const moves = await window.OrigoAPI.getMovements();
    const pendingCount = moves.filter(m => !m.synced).length;
    const syncTag = document.getElementById('pendingSyncTag');
    if (pendingCount > 0) {
      syncTag.innerText = `⏳ ${pendingCount} pendiente${pendingCount > 1 ? 's' : ''} local`;
      syncTag.style.color = '#b45309';
    } else {
      syncTag.innerText = '☁️ Al día';
      syncTag.style.color = '#047857';
    }

    const todayMoves = moves.filter(m => m.is_today);
    const displayMoves = todayMoves.length > 0 ? todayMoves : moves;

    document.getElementById('historyList').innerHTML = displayMoves.slice(0, 8).map(m => `
      <div class="history-card">
        <div style="display: flex; align-items: center; gap: 12px;">
          <div class="product-icon" style="width: 42px; height: 42px; font-size: 1.35rem;">${getIcon(m.product_id)}</div>
          <div>
            <div style="font-weight: 800; font-size: 0.95rem;">
              ${m.type === 'OUT' ? '📤 Venta' : '📥 Entrada'} · ${m.quantity} ${m.unit}
            </div>
            <div style="font-size: 0.85rem; color: var(--text-muted);">${m.product_name} · 🕒 ${m.time_str || 'Hoy'}</div>
          </div>
        </div>
        <span class="sync-badge ${m.synced ? 'synced' : 'pending'}">
          ${m.synced ? '☁️ Sync' : '⏳ Offline'}
        </span>
      </div>
    `).join('');
  }

  function toggleHistory() {
    const btn = document.getElementById('historyToggleBtn');
    const body = document.getElementById('historyList');
    const isNowCollapsed = body.classList.toggle('collapsed');
    btn.classList.toggle('collapsed', isNowCollapsed);
    btn.setAttribute('aria-expanded', String(!isNowCollapsed));
  }

  function openNewProductModal() {
    document.getElementById('npName').value = '';
    document.getElementById('npSynonyms').value = '';
    document.getElementById('npMin').value = '5';
    document.getElementById('newProductModal').classList.add('open');
  }

  function closeNewProductModal() {
    document.getElementById('newProductModal').classList.remove('open');
  }

  async function submitNewProduct(e) {
    if (e) e.preventDefault();
    const name = document.getElementById('npName').value.trim();
    const category = document.getElementById('npCategory').value;
    const default_unit = document.getElementById('npUnit').value;
    const min_threshold = Number(document.getElementById('npMin').value) || 5;
    const rawSyn = document.getElementById('npSynonyms').value.trim();
    const synonyms = rawSyn ? rawSyn.split(',').map(s => s.trim()).filter(Boolean) : [name.toLowerCase()];

    try {
      const res = await window.OrigoAPI.createCustomProduct({
        name,
        category,
        default_unit,
        min_threshold,
        synonyms
      });
      closeNewProductModal();
      if (res.daily_stock) applyDailyStock(res.daily_stock);
      else await refreshStock();
      window.OrigoApp.showToast(`✅ Producto "${name}" agregado a tu bodega y al dictado por voz`);
    } catch (err) {
      window.OrigoApp.showToast(`⚠️ ${err.message}`);
    }
  }

  return {
    getIcon,
    applyDailyStock,
    refreshStock,
    refreshMovements,
    filterCategory,
    toggleHistory,
    openNewProductModal,
    closeNewProductModal,
    submitNewProduct
  };
})();
