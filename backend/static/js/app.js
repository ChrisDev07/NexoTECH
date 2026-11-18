/**
 * Coordinador Principal de Origo (Navegación, Modo Avión y Modal de Confirmación)
 */
window.OrigoApp = (() => {
  let pendingParsedItems = [];

  function isOnline() {
    return typeof navigator !== 'undefined' ? navigator.onLine : true;
  }

  function showToast(msg) {
    const t = document.getElementById('toast');
    t.innerText = msg;
    t.classList.add('show');
    clearTimeout(window._toastTimer);
    window._toastTimer = setTimeout(() => t.classList.remove('show'), 3200);
  }

  function switchTab(tabName) {
    document.querySelectorAll('.tab-view').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.nav-btn').forEach(el => el.classList.remove('active'));
    document.getElementById(`tab-${tabName}`).classList.add('active');
    document.getElementById(`nav-${tabName}`).classList.add('active');

    if (tabName === 'home') window.OrigoInventory.refreshMovements();
    if (tabName === 'inventory') window.OrigoInventory.refreshStock();
    if (tabName === 'community') window.OrigoCommunity.refresh();
  }

  async function syncOnReconnect() {
    try {
      const data = await window.OrigoAPI.syncMovements();
      if (data.synced_count > 0) {
        showToast(`☁️ ¡Conexión recuperada! ${data.synced_count} movimientos sincronizados`);
      }
      window.OrigoInventory.refreshStock();
      window.OrigoInventory.refreshMovements();
    } catch (_) {}
  }

  async function triggerPhrase(phrase) {
    const clean = (phrase || '').trim();
    if (!clean) return;
    pendingParsedItems = await window.OrigoAPI.parsePhrase(clean);
    if (!pendingParsedItems || pendingParsedItems.length === 0) {
      showToast('⚠️ No reconocí ese producto en tu catálogo');
      return;
    }
    renderConfirmationSheet();
    document.getElementById('confirmModal').classList.add('open');
  }

  function renderConfirmationSheet() {
    const container = document.getElementById('receiptItemsContainer');
    container.innerHTML = '';

    let hasInsufficientStock = false;

    pendingParsedItems.forEach((item, idx) => {
      const isOut = item.action === 'SALIDA';
      const icon = window.OrigoInventory.getIcon(item.product_id);
      const available = window.OrigoInventory.getProductStock(item.product_id);
      const exceeds = isOut && item.quantity > available;
      if (exceeds) hasInsufficientStock = true;

      const stockWarning = exceeds
        ? `<div style="margin-top: 10px; padding: 10px 12px; border-radius: 12px; background: #fee2e2; color: #991b1b; font-size: 0.85rem; font-weight: 700;">
             ${available <= 0
               ? `⚠️ Sin existencias en bodega (Stock: 0 ${item.unit}). Registra primero una entrada.`
               : `⚠️ Stock insuficiente: solo tienes ${available} ${item.unit} disponibles.`}
           </div>`
        : '';

      const div = document.createElement('div');
      div.className = 'receipt-item';
      div.innerHTML = `
        <div class="receipt-top">
          <button class="action-toggle ${isOut ? 'out' : 'in'}" onclick="OrigoApp.toggleItemAction(${idx})">
            ${isOut ? '📤 Venta realizada' : '📥 Mercancía recibida'} ⇄
          </button>
          <span class="certainty-badge">📦 Stock: ${available} ${item.unit}</span>
        </div>
        <div class="receipt-prod">
          <span>${icon}</span>
          <span>${item.product_name}</span>
        </div>
        <div class="stepper-row">
          <button class="btn-step" onclick="OrigoApp.adjustQty(${idx}, -1)">−</button>
          <span class="stepper-val">${item.quantity} ${item.unit}</span>
          <button class="btn-step" onclick="OrigoApp.adjustQty(${idx}, 1)">+</button>
        </div>
        ${stockWarning}
      `;
      container.appendChild(div);
    });

    const confirmBtn = document.querySelector('#confirmModal .btn-confirm-big');
    if (confirmBtn) {
      confirmBtn.disabled = hasInsufficientStock;
      confirmBtn.style.opacity = hasInsufficientStock ? '0.45' : '1';
      confirmBtn.style.cursor = hasInsufficientStock ? 'not-allowed' : 'pointer';
    }
  }

  function adjustQty(idx, delta) {
    pendingParsedItems[idx].quantity = Math.max(0.5, Number((pendingParsedItems[idx].quantity + delta).toFixed(1)));
    renderConfirmationSheet();
  }

  function toggleItemAction(idx) {
    pendingParsedItems[idx].action = pendingParsedItems[idx].action === 'SALIDA' ? 'ENTRADA' : 'SALIDA';
    renderConfirmationSheet();
  }

  async function confirmMovement() {
    if (!pendingParsedItems.length) return;
    const online = isOnline();
    try {
      const saveData = await window.OrigoAPI.saveMovements(pendingParsedItems, online);
      document.getElementById('confirmModal').classList.remove('open');
      window.OrigoVoice.clearTranscript();
      pendingParsedItems = [];

      showToast(online
        ? '✅ ¡Guardado y sincronizado en el inventario del día!'
        : '💾 Sin internet: guardado localmente (se subirá al recuperar señal)');

      if (saveData && saveData.daily_stock) {
        window.OrigoInventory.applyDailyStock(saveData.daily_stock);
      } else {
        await window.OrigoInventory.refreshStock();
      }
      await window.OrigoInventory.refreshMovements();
    } catch (err) {
      showToast(`⚠️ ${err.message}`);
    }
  }

  function cancelMovement() {
    pendingParsedItems = [];
    document.getElementById('confirmModal').classList.remove('open');
  }

  function loadDashboardData() {
    window.OrigoInventory.refreshStock();
    window.OrigoInventory.refreshMovements();
    window.OrigoCommunity.refresh();
  }

  function boot() {
    window.addEventListener('online', syncOnReconnect);
    window.addEventListener('offline', () => {
      showToast('✈️ Sin conexión: tus movimientos se guardarán localmente');
    });
    window.OrigoVoice.init(triggerPhrase);
    window.OrigoAuth.init(() => {
      switchTab('home');
      loadDashboardData();
    });
  }

  return {
    boot,
    showToast,
    switchTab,
    triggerPhrase,
    adjustQty,
    toggleItemAction,
    confirmMovement,
    cancelMovement
  };
})();

document.addEventListener('DOMContentLoaded', () => window.OrigoApp.boot());
