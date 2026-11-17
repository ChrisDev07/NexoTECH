/**
 * Coordinador Principal de Origo (Navegación, Modo Avión y Modal de Confirmación)
 */
window.OrigoApp = (() => {
  let isAirplaneMode = false;
  let pendingParsedItems = [];

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

  async function toggleAirplaneMode() {
    isAirplaneMode = !isAirplaneMode;
    const pill = document.getElementById('connPill');
    const icon = document.getElementById('connIcon');
    const text = document.getElementById('connText');

    if (isAirplaneMode) {
      pill.classList.add('offline');
      icon.innerText = '✈️';
      text.innerText = 'Sin Internet';
      showToast('✈️ Modo Avión activo · Tus registros se guardan en el equipo');
    } else {
      pill.classList.remove('offline');
      icon.innerText = '🟢';
      text.innerText = 'Conectado';
      const data = await window.OrigoAPI.syncMovements();
      showToast(
        data.synced_count > 0
          ? `☁️ ¡Señal recuperada! ${data.synced_count} movimientos sincronizados`
          : '🟢 Conectado · Inventario al día'
      );
      window.OrigoInventory.refreshStock();
      window.OrigoInventory.refreshMovements();
    }
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

    pendingParsedItems.forEach((item, idx) => {
      const isOut = item.action === 'SALIDA';
      const icon = window.OrigoInventory.getIcon(item.product_id);
      const div = document.createElement('div');
      div.className = 'receipt-item';
      div.innerHTML = `
        <div class="receipt-top">
          <button class="action-toggle ${isOut ? 'out' : 'in'}" onclick="OrigoApp.toggleItemAction(${idx})">
            ${isOut ? '📤 Venta realizada' : '📥 Mercancía recibida'} ⇄
          </button>
          <span class="certainty-badge">✨ ${Math.round(item.confidence * 100)}% Entendido</span>
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
      `;
      container.appendChild(div);
    });
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
    const saveData = await window.OrigoAPI.saveMovements(pendingParsedItems, !isAirplaneMode);
    document.getElementById('confirmModal').classList.remove('open');
    window.OrigoVoice.clearTranscript();
    pendingParsedItems = [];

    showToast(isAirplaneMode
      ? '💾 Guardado en tu teléfono (se sincronizará al volver la señal)'
      : '✅ ¡Guardado en el inventario del día!');

    if (saveData && saveData.daily_stock) {
      window.OrigoInventory.applyDailyStock(saveData.daily_stock);
    } else {
      await window.OrigoInventory.refreshStock();
    }
    await window.OrigoInventory.refreshMovements();
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
    toggleAirplaneMode,
    triggerPhrase,
    adjustQty,
    toggleItemAction,
    confirmMovement,
    cancelMovement
  };
})();

document.addEventListener('DOMContentLoaded', () => window.OrigoApp.boot());
