/**
 * Cafe de Casa - Customer QR/NFC Ordering System Controller
 * Handles table token resolution, reactive cart management, item selection,
 * special instructions, and server-side order submission.
 */

(function () {
  let currentTable = null;
  let currentTableToken = null;
  let cart = []; // Array of { name, price, quantity, notes }
  let isPlacingOrder = false;

  // Initialize on DOM ready
  document.addEventListener('DOMContentLoaded', () => {
    initTableFromUrl();
    bindMenuAddButtons();
    bindCartTriggers();
    renderCart();
  });

  /**
   * 1. Detect and Resolve Table Token from URL
   */
  async function initTableFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const token = params.get('table_token') || params.get('token') || params.get('t') || params.get('table');

    if (!token) {
      console.info('No table token in URL. Browsing in guest preview mode.');
      updateTableUI(null);
      return;
    }

    currentTableToken = token.trim();
    console.log('Resolving table token:', currentTableToken);

    try {
      const res = await window.RestaurantAPI.resolveTableByToken(currentTableToken);
      if (res && res.success && res.table) {
        currentTable = res.table;
        console.log('✅ Table resolved:', currentTable.table_number, currentTable.section);
        updateTableUI(currentTable);
      } else {
        console.warn('Invalid table token:', res?.error);
        updateTableUI(null, res?.error || 'Invalid Table Token');
      }
    } catch (e) {
      console.error('Failed to resolve table token:', e);
      updateTableUI(null, 'Could not verify table');
    }
  }

  function updateTableUI(table, errorMessage = null) {
    const bannerContainer = document.getElementById('table-banner-pill');
    const drawerTableLabel = document.getElementById('cart-drawer-table');

    if (table) {
      const label = `${table.table_number} • ${table.section || 'Dining'}`;
      if (bannerContainer) {
        bannerContainer.classList.remove('hidden');
        bannerContainer.innerHTML = `
          <span class="inline-block w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          <span>Ordering for <strong class="text-brand-goldLight">${label}</strong></span>
        `;
      }
      if (drawerTableLabel) {
        drawerTableLabel.textContent = label;
        drawerTableLabel.className = 'text-xs uppercase tracking-wider font-bold text-brand-goldDark bg-brand-gold/10 px-2.5 py-1 rounded inline-block';
      }
    } else {
      if (bannerContainer) {
        bannerContainer.classList.remove('hidden');
        if (errorMessage) {
          bannerContainer.innerHTML = `
            <span class="inline-block w-2 h-2 rounded-full bg-rose-400"></span>
            <span class="text-rose-300">${errorMessage} — Scan QR to Order</span>
          `;
        } else {
          bannerContainer.innerHTML = `
            <span class="inline-block w-2 h-2 rounded-full bg-brand-gold/60"></span>
            <span>Scan Table QR Code or <a href="?table_token=UNIQUE_TOKEN_04" class="underline text-brand-goldLight font-semibold hover:text-white">Order at Table 04</a></span>
          `;
        }
      }
      if (drawerTableLabel) {
        drawerTableLabel.textContent = 'No Table Selected (Scan QR Code)';
        drawerTableLabel.className = 'text-xs text-brand-muted italic';
      }
    }
  }

  /**
   * 2. Bind "+ Add" buttons across all menu cards
   */
  function bindMenuAddButtons() {
    // Menu category cards
    document.querySelectorAll('.menu-item-card').forEach(card => {
      const btn = card.querySelector('button');
      if (!btn) return;

      const titleEl = card.querySelector('h4') || card.querySelector('h3');
      const priceEl = card.querySelector('.font-serif.font-semibold') || card.querySelector('.font-serif.font-bold');

      if (titleEl && priceEl) {
        const name = titleEl.textContent.trim();
        const priceText = priceEl.textContent.replace(/[^\d.]/g, '');
        const price = parseFloat(priceText) || 0;

        btn.addEventListener('click', (e) => {
          e.preventDefault();
          addToCart(name, price);
        });
      }
    });

    // Signature Pasta cards
    document.querySelectorAll('article.ornate-border').forEach(card => {
      const btn = card.querySelector('button');
      const titleEl = card.querySelector('h3');
      const priceEl = card.querySelector('.font-serif.text-base, .font-serif.text-lg, .font-serif.font-bold');

      if (btn && titleEl && priceEl) {
        const name = titleEl.textContent.trim();
        const priceText = priceEl.textContent.replace(/[^\d.]/g, '');
        const price = parseFloat(priceText) || 0;

        btn.addEventListener('click', (e) => {
          e.preventDefault();
          addToCart(name, price);
        });
      }
    });
  }

  /**
   * 3. Cart State Management
   */
  function addToCart(name, price, quantity = 1) {
    const existing = cart.find(item => item.name.toLowerCase() === name.toLowerCase());
    if (existing) {
      existing.quantity += quantity;
    } else {
      cart.push({
        name,
        price,
        quantity: quantity,
        notes: ''
      });
    }

    renderCart();
    showToast(`Added to cart: ${name} (×${quantity})`);
  }

  function updateQuantity(index, delta) {
    if (!cart[index]) return;
    cart[index].quantity += delta;
    if (cart[index].quantity <= 0) {
      cart.splice(index, 1);
    }
    renderCart();
  }

  function removeItem(index) {
    if (cart[index]) {
      cart.splice(index, 1);
      renderCart();
    }
  }

  function renderCart() {
    const totalCount = cart.reduce((sum, item) => sum + item.quantity, 0);
    const subtotal = cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);

    // Update navbar and floating cart badges
    const navBadge = document.getElementById('nav-cart-badge');
    const floatingBadge = document.getElementById('floating-cart-badge');
    if (navBadge) navBadge.textContent = totalCount;
    if (floatingBadge) floatingBadge.textContent = totalCount;

    // Render items list inside drawer
    const listEl = document.getElementById('cart-items-container');
    const emptyEl = document.getElementById('cart-empty-state');
    const footerEl = document.getElementById('cart-footer');
    const subtotalEl = document.getElementById('cart-subtotal');
    const totalEl = document.getElementById('cart-total');

    if (subtotalEl) subtotalEl.textContent = `₹${subtotal}`;
    if (totalEl) totalEl.textContent = `₹${subtotal}`;

    if (!listEl) return;

    if (cart.length === 0) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      if (footerEl) footerEl.classList.add('hidden');
      listEl.innerHTML = '';
      return;
    }

    if (emptyEl) emptyEl.classList.add('hidden');
    if (footerEl) footerEl.classList.remove('hidden');

    listEl.innerHTML = cart.map((item, index) => `
      <div class="py-3 border-b border-brand-gold/15 flex items-center justify-between gap-3">
        <div class="flex-1 min-w-0">
          <h4 class="font-serif font-bold text-sm text-brand-espresso truncate">${item.name}</h4>
          <span class="text-xs text-brand-muted">₹${item.price} each</span>
        </div>
        <div class="flex items-center gap-2">
          <div class="inline-flex items-center border border-brand-gold/40 rounded-full bg-white shadow-xs">
            <button onclick="window.CustomerOrdering.updateQuantity(${index}, -1)" 
                    class="w-7 h-7 flex items-center justify-center text-brand-espresso hover:bg-brand-gold/20 rounded-l-full font-bold text-sm transition active:scale-95">−</button>
            <span class="w-7 text-center font-bold text-xs text-brand-espresso">${item.quantity}</span>
            <button onclick="window.CustomerOrdering.updateQuantity(${index}, 1)" 
                    class="w-7 h-7 flex items-center justify-center text-brand-espresso hover:bg-brand-gold/20 rounded-r-full font-bold text-sm transition active:scale-95">+</button>
          </div>
          <span class="w-16 text-right font-serif font-bold text-xs text-brand-espresso">₹${item.price * item.quantity}</span>
          <button onclick="window.CustomerOrdering.removeItem(${index})" 
                  class="text-brand-muted hover:text-red-600 p-1 text-sm transition" title="Remove item">✕</button>
        </div>
      </div>
    `).join('');
  }

  /**
   * 4. Cart Drawer Show / Hide
   */
  function bindCartTriggers() {
    const navBtn = document.getElementById('nav-cart-btn');
    const floatingBtn = document.getElementById('floating-cart-btn');
    const closeBtn = document.getElementById('close-cart-btn');
    const backdrop = document.getElementById('cart-backdrop');

    if (navBtn) navBtn.addEventListener('click', openCartDrawer);
    if (floatingBtn) floatingBtn.addEventListener('click', openCartDrawer);
    if (closeBtn) closeBtn.addEventListener('click', closeCartDrawer);
    if (backdrop) backdrop.addEventListener('click', closeCartDrawer);
  }

  function openCartDrawer() {
    const drawer = document.getElementById('cart-drawer');
    const backdrop = document.getElementById('cart-backdrop');
    if (drawer && backdrop) {
      backdrop.classList.remove('hidden');
      drawer.classList.remove('translate-x-full');
      document.body.classList.add('overflow-hidden');
    }
  }

  function closeCartDrawer() {
    const drawer = document.getElementById('cart-drawer');
    const backdrop = document.getElementById('cart-backdrop');
    if (drawer && backdrop) {
      drawer.classList.add('translate-x-full');
      backdrop.classList.add('hidden');
      document.body.classList.remove('overflow-hidden');
    }
  }

  /**
   * 5. Submit Order (Customer -> Kitchen Flow)
   */
  async function submitCustomerOrder() {
    if (isPlacingOrder) return;

    const errorBanner = document.getElementById('cart-error-banner');
    if (errorBanner) errorBanner.classList.add('hidden');

    // Token requirement check
    if (!currentTableToken) {
      showCartError('Please scan your table QR code or select Table 04 to place an order.');
      return;
    }

    if (cart.length === 0) {
      showCartError('Your cart is empty. Please add items before placing order.');
      return;
    }

    const specialInstructions = (document.getElementById('cart-special-instructions')?.value || '').trim();
    const btn = document.getElementById('place-order-btn');
    const btnText = document.getElementById('place-order-text');

    try {
      isPlacingOrder = true;
      if (btn) btn.disabled = true;
      if (btnText) btnText.innerHTML = '<span class="inline-block animate-spin mr-2">⏳</span> Sending to Kitchen...';

      const res = await window.RestaurantAPI.placeOrder(
        currentTableToken,
        cart,
        specialInstructions
      );

      if (res && res.success && res.order) {
        // Clear cart
        cart = [];
        renderCart();
        closeCartDrawer();
        if (document.getElementById('cart-special-instructions')) {
          document.getElementById('cart-special-instructions').value = '';
        }

        // Show genuine Order Confirmation Modal
        showOrderConfirmation(res.order);
      } else {
        showCartError(res?.error || 'Failed to place order. Please try again.');
      }
    } catch (err) {
      console.error('Order error:', err);
      showCartError(err.message || 'Network error while placing order.');
    } finally {
      isPlacingOrder = false;
      if (btn) btn.disabled = false;
      if (btnText) btnText.textContent = 'Place Order';
    }
  }

  function showCartError(msg) {
    const banner = document.getElementById('cart-error-banner');
    if (banner) {
      banner.textContent = msg;
      banner.classList.remove('hidden');
    } else {
      alert(msg);
    }
  }

  /**
   * 6. Order Confirmation Modal
   */
  function showOrderConfirmation(order) {
    const modal = document.getElementById('order-confirmation-modal');
    if (!modal) return;

    document.getElementById('conf-order-number').textContent = order.order_number;
    document.getElementById('conf-table-info').textContent = `${order.table_number} • ${order.table_section || 'Bistro Hall'}`;
    document.getElementById('conf-total-amount').textContent = `₹${order.total_amount}`;

    const itemsContainer = document.getElementById('conf-items-list');
    if (itemsContainer && order.items) {
      itemsContainer.innerHTML = order.items.map(it => `
        <div class="flex justify-between py-1.5 border-b border-brand-gold/10 text-xs">
          <span class="font-medium text-brand-espresso">${it.item_name} <strong class="text-brand-goldDark">× ${it.quantity}</strong></span>
          <span class="font-mono text-brand-espresso font-semibold">₹${it.subtotal || (it.unit_price * it.quantity)}</span>
        </div>
      `).join('');
    }

    const instructionsEl = document.getElementById('conf-instructions');
    if (instructionsEl) {
      if (order.special_instructions) {
        instructionsEl.innerHTML = `<span class="italic text-brand-muted">Note: "${order.special_instructions}"</span>`;
        instructionsEl.classList.remove('hidden');
      } else {
        instructionsEl.classList.add('hidden');
      }
    }

    // Reset confirmation modal elements to initial state
    const titleEl = document.getElementById('conf-main-title');
    const subtitleEl = document.getElementById('conf-subtitle');
    const statusBox = document.getElementById('conf-status-box');
    const statusText = document.getElementById('conf-status-text');
    const statusDot = document.getElementById('conf-status-dot');
    const continueBtn = document.getElementById('conf-continue-btn');

    if (subtitleEl) subtitleEl.textContent = 'Order Confirmed';
    if (titleEl) {
      titleEl.textContent = 'Sent to Kitchen';
      titleEl.className = 'font-serif text-2xl font-bold text-brand-espresso';
    }
    if (statusBox) {
      statusBox.className = 'p-2.5 rounded bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs font-medium flex items-center justify-center gap-2 transition-all';
    }
    if (statusDot) {
      statusDot.className = 'w-2 h-2 rounded-full bg-emerald-500 animate-ping';
    }
    if (statusText) {
      statusText.textContent = 'Kitchen preparing your delicacies';
    }
    if (continueBtn) {
      continueBtn.textContent = 'Continue Dining';
      continueBtn.className = 'w-full py-3 bg-brand-gold hover:bg-brand-goldDark text-white text-xs font-bold uppercase tracking-wider rounded transition shadow-sm cursor-pointer';
    }

    modal.classList.remove('hidden');
    document.body.classList.add('overflow-hidden');

    // Subscribe to status changes for this order (Realtime + BroadcastChannel + LocalStorage + Fast Polling)
    window.RestaurantAPI.subscribeToOrderStatus(order.id, (update) => {
      if (!update || !update.status) return;

      const s = String(update.status).toLowerCase();
      if (s === 'completed') {
        if (subtitleEl) subtitleEl.textContent = 'Order Ready & Served';
        if (titleEl) {
          titleEl.textContent = 'Your Order is Completed!';
          titleEl.className = 'font-serif text-2xl font-bold text-emerald-800';
        }

        if (statusBox) {
          statusBox.className = 'p-3 rounded-xl bg-emerald-100 border border-emerald-400 text-emerald-900 text-xs sm:text-sm font-bold flex items-center justify-center gap-2 transition-all shadow-sm';
        }
        if (statusDot) {
          statusDot.className = 'w-2.5 h-2.5 rounded-full bg-emerald-600';
        }
        if (statusText) {
          statusText.innerHTML = '✓ Delicacies Prepared &amp; Served • Enjoy Your Meal!';
        }
        if (continueBtn) {
          continueBtn.innerHTML = '<span>✓</span> Your Order is Completed (Continue Dining)';
          continueBtn.className = 'w-full py-3.5 bg-emerald-700 hover:bg-emerald-600 text-white text-xs font-bold uppercase tracking-wider rounded-xl transition shadow-md cursor-pointer active:scale-98 flex items-center justify-center gap-1.5';
        }

        showToast('🎉 Chef Henri has completed your order! Enjoy your meal.');
      } else {
        if (statusText) statusText.textContent = `Kitchen Status: ${update.status.toUpperCase()}`;
      }
    });
  }

  function closeConfirmationModal() {
    const modal = document.getElementById('order-confirmation-modal');
    if (modal) {
      modal.classList.add('hidden');
      document.body.classList.remove('overflow-hidden');
    }
  }

  /**
   * 7. Lightweight Toast Notifications
   */
  function showToast(message) {
    let toast = document.getElementById('ordering-toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'ordering-toast';
      toast.className = 'fixed bottom-20 left-1/2 -translate-x-1/2 z-50 bg-brand-espresso text-brand-goldLight px-4 py-2 rounded-full text-xs font-semibold shadow-2xl border border-brand-gold/50 transition-all duration-300 pointer-events-none opacity-0 translate-y-3';
      document.body.appendChild(toast);
    }
    toast.textContent = message;
    toast.classList.remove('opacity-0', 'translate-y-3');
    toast.classList.add('opacity-100', 'translate-y-0');

    setTimeout(() => {
      toast.classList.remove('opacity-100', 'translate-y-0');
      toast.classList.add('opacity-0', 'translate-y-3');
    }, 2200);
  }

  // Public API
  window.CustomerOrdering = {
    addToCart,
    updateQuantity,
    removeItem,
    openCartDrawer,
    closeCartDrawer,
    submitCustomerOrder,
    closeConfirmationModal
  };
})();

