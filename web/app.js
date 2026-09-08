(() => {
  'use strict';

  const initialState = {
    balance: 12480,
    purchased: [],
    activatedWorlds: [],
    activity: [
      { title: '3D Building Pack', detail: 'Shop purchase', amount: -350, icon: '3D' },
      { title: 'From @Alex', detail: '3D model work', amount: 500, icon: '@' },
      { title: 'World access', detail: 'Gallery session', amount: -80, icon: 'W' },
      { title: 'Sold texture pack', detail: 'Creator sale', amount: 120, icon: '＋' }
    ]
  };

  const products = {
    cyberpunk: { title: 'Cyberpunk Building Pack', price: 350, creator: '@Maya' },
    studio: { title: 'Soft Studio Lights', price: 180, creator: '@Noah' }
  };

  const storageKey = 'blocks-prototype-v0.1.0';
  let state = loadState();
  let dialogStep = null;
  let pending = null;

  const dialog = document.querySelector('#flow-dialog');
  const dialogTitle = document.querySelector('#dialog-title');
  const dialogContent = document.querySelector('#dialog-content');
  const dialogBack = document.querySelector('[data-dialog-back]');
  const toast = document.querySelector('.toast');

  function loadState() {
    try {
      const stored = JSON.parse(localStorage.getItem(storageKey) || 'null');
      if (!stored || typeof stored.balance !== 'number' || !Array.isArray(stored.activity)) return structuredClone(initialState);
      return { ...structuredClone(initialState), ...stored };
    } catch {
      return structuredClone(initialState);
    }
  }

  function saveState() {
    localStorage.setItem(storageKey, JSON.stringify(state));
  }

  function formatNumber(value) {
    return new Intl.NumberFormat('en-GB').format(value);
  }

  function render() {
    document.querySelectorAll('[data-balance]').forEach((node) => {
      node.textContent = formatNumber(state.balance);
    });

    document.querySelectorAll('[data-activity-list]').forEach((list) => {
      const limit = list.dataset.activityList === 'home' ? 4 : state.activity.length;
      list.replaceChildren(...state.activity.slice(0, limit).map(activityRow));
    });

    document.querySelectorAll('[data-buy]').forEach((button) => {
      const key = button.dataset.buy;
      const bought = state.purchased.includes(key);
      button.disabled = bought;
      button.textContent = bought ? 'Purchased' : `Buy for ${formatNumber(products[key].price)} Blocks`;
    });

    const worldButton = document.querySelector('[data-activate-world]');
    if (worldButton) {
      const active = state.activatedWorlds.includes('neon-studio');
      worldButton.disabled = active;
      worldButton.textContent = active ? 'Active' : 'Activate';
    }
  }

  function activityRow(item) {
    const row = document.createElement('div');
    row.className = 'activity-row';

    const icon = document.createElement('div');
    icon.className = 'activity-icon';
    icon.textContent = item.icon;

    const copy = document.createElement('div');
    copy.className = 'activity-copy';
    const title = document.createElement('strong');
    title.textContent = item.title;
    const detail = document.createElement('small');
    detail.textContent = item.detail;
    copy.append(title, detail);

    const amount = document.createElement('div');
    amount.className = `activity-amount${item.amount > 0 ? ' positive' : ''}`;
    amount.textContent = `${item.amount > 0 ? '+' : '−'}${formatNumber(Math.abs(item.amount))}`;

    row.append(icon, copy, amount);
    return row;
  }

  function navigate(page) {
    document.querySelectorAll('.page').forEach((section) => section.classList.toggle('active', section.dataset.page === page));
    document.querySelectorAll('[data-nav]').forEach((button) => button.classList.toggle('active', button.dataset.nav === page));
    history.replaceState(null, '', `#${page}`);
    window.scrollTo({ top: 0, behavior: 'smooth' });
    document.querySelector('#main').focus({ preventScroll: true });
  }

  function openDialog(title, html, step, canGoBack = false) {
    dialogTitle.textContent = title;
    dialogContent.innerHTML = html;
    dialogStep = step;
    dialogBack.hidden = !canGoBack;
    if (!dialog.open) dialog.showModal();
  }

  function closeDialog() {
    if (dialog.open) dialog.close();
    dialogStep = null;
    pending = null;
  }

  function sendStart() {
    pending = { recipient: '', amount: '', note: '' };
    openDialog('Send Blocks', `
      <form class="flow-stack" id="send-form" novalidate>
        <div class="field"><label for="send-to">To</label><input id="send-to" name="recipient" autocomplete="off" placeholder="@username" maxlength="33" required></div>
        <div class="field"><label for="send-amount">Amount</label><input id="send-amount" name="amount" inputmode="numeric" autocomplete="off" placeholder="500" required></div>
        <div class="field"><label for="send-note">Note</label><textarea id="send-note" name="note" maxlength="120" placeholder="3D model work"></textarea></div>
        <div class="form-error" aria-live="polite"></div>
        <button class="primary" type="submit">Continue</button>
      </form>`, 'send-form');
    document.querySelector('#send-to').focus();
  }

  function sendReview(form) {
    const data = new FormData(form);
    const recipient = String(data.get('recipient') || '').trim();
    const amountText = String(data.get('amount') || '').replace(/,/g, '').trim();
    const note = String(data.get('note') || '').trim();
    const amount = Number(amountText);
    const error = form.querySelector('.form-error');

    if (!/^@[A-Za-z0-9._-]{2,32}$/.test(recipient)) {
      error.textContent = 'Enter a username beginning with @.';
      return;
    }
    if (!Number.isSafeInteger(amount) || amount <= 0) {
      error.textContent = 'Enter a whole number greater than zero.';
      return;
    }
    if (amount > state.balance) {
      error.textContent = 'That amount is higher than your current Blocks balance.';
      return;
    }

    pending = { recipient, amount, note };
    openDialog('Check before sending', `
      <div class="flow-stack">
        <div><p class="eyebrow">You are sending</p><p class="review-amount">${formatNumber(amount)} Blocks</p></div>
        <div class="review-list">
          <div class="review-row"><span>To</span><strong>${escapeHtml(recipient)}</strong></div>
          <div class="review-row"><span>For</span><strong>${escapeHtml(note || 'No note')}</strong></div>
          <div class="review-row"><span>Balance after</span><strong>${formatNumber(state.balance - amount)} Blocks</strong></div>
        </div>
        <button class="primary" data-confirm-send>Send</button>
      </div>`, 'send-review', true);
  }

  function confirmSend() {
    if (!pending || !Number.isSafeInteger(pending.amount) || pending.amount <= 0 || pending.amount > state.balance) return;
    state.balance -= pending.amount;
    state.activity.unshift({ title: `To ${pending.recipient}`, detail: pending.note || 'Sent Blocks', amount: -pending.amount, icon: '↑' });
    saveState();
    render();
    openDialog('Sent', `
      <div class="success-state">
        <div class="success-mark">✓</div>
        <h3>${formatNumber(pending.amount)} Blocks sent</h3>
        <p>Sent to ${escapeHtml(pending.recipient)}.</p>
        <button class="primary" data-dialog-close>Done</button>
      </div>`, 'send-success');
  }

  function requestStart() {
    openDialog('Request Blocks', `
      <form class="flow-stack" id="request-form" novalidate>
        <div class="field"><label for="request-from">From</label><input id="request-from" name="from" autocomplete="off" placeholder="@username" maxlength="33" required></div>
        <div class="field"><label for="request-amount">Amount</label><input id="request-amount" name="amount" inputmode="numeric" autocomplete="off" placeholder="500" required></div>
        <div class="field"><label for="request-note">Note</label><textarea id="request-note" name="note" maxlength="120" placeholder="3D model work"></textarea></div>
        <div class="form-error" aria-live="polite"></div>
        <button class="primary" type="submit">Create request</button>
      </form>`, 'request-form');
  }

  function createRequest(form) {
    const data = new FormData(form);
    const from = String(data.get('from') || '').trim();
    const amount = Number(String(data.get('amount') || '').replace(/,/g, '').trim());
    const error = form.querySelector('.form-error');
    if (!/^@[A-Za-z0-9._-]{2,32}$/.test(from)) {
      error.textContent = 'Enter a username beginning with @.';
      return;
    }
    if (!Number.isSafeInteger(amount) || amount <= 0) {
      error.textContent = 'Enter a whole number greater than zero.';
      return;
    }
    openDialog('Request created', `
      <div class="success-state">
        <div class="success-mark">✓</div>
        <h3>${formatNumber(amount)} Blocks requested</h3>
        <p>${escapeHtml(from)} can now review the request. No balance has changed.</p>
        <button class="primary" data-dialog-close>Done</button>
      </div>`, 'request-success');
  }

  function addStart() {
    openDialog('Add Blocks', `
      <div class="flow-stack">
        <div><p class="eyebrow">Choose an amount</p><h3>Add Blocks</h3></div>
        <div class="package-list">
          <button class="package" data-package="500"><span>500 Blocks</span><small>£5</small></button>
          <button class="package" data-package="1000"><span>1,000 Blocks</span><small>£10</small></button>
          <button class="package" data-package="2500"><span>2,500 Blocks</span><small>£25</small></button>
        </div>
        <p class="eyebrow">Prototype only — no payment is taken.</p>
      </div>`, 'add-select');
  }

  function addBlocks(amount) {
    if (![500, 1000, 2500].includes(amount)) return;
    state.balance += amount;
    state.activity.unshift({ title: 'Blocks added', detail: 'Prototype payment', amount, icon: '＋' });
    saveState();
    render();
    openDialog('Blocks added', `
      <div class="success-state">
        <div class="success-mark">✓</div>
        <h3>${formatNumber(amount)} Blocks added</h3>
        <p>Your prototype balance is now ${formatNumber(state.balance)} Blocks.</p>
        <button class="primary" data-dialog-close>Done</button>
      </div>`, 'add-success');
  }

  function buyProduct(key) {
    const product = products[key];
    if (!product || state.purchased.includes(key)) return;
    if (state.balance < product.price) {
      showToast('Not enough Blocks for this purchase.');
      return;
    }
    openDialog('Check purchase', `
      <div class="flow-stack">
        <div><p class="eyebrow">${escapeHtml(product.creator)}</p><p class="review-amount">${escapeHtml(product.title)}</p></div>
        <div class="review-list">
          <div class="review-row"><span>Price</span><strong>${formatNumber(product.price)} Blocks</strong></div>
          <div class="review-row"><span>Balance after</span><strong>${formatNumber(state.balance - product.price)} Blocks</strong></div>
        </div>
        <button class="primary" data-confirm-buy="${key}">Buy for ${formatNumber(product.price)} Blocks</button>
      </div>`, 'buy-review');
  }

  function confirmBuy(key) {
    const product = products[key];
    if (!product || state.purchased.includes(key) || state.balance < product.price) return;
    state.balance -= product.price;
    state.purchased.push(key);
    state.activity.unshift({ title: product.title, detail: `Paid to ${product.creator}`, amount: -product.price, icon: '3D' });
    saveState();
    render();
    openDialog('Purchase complete', `
      <div class="success-state">
        <div class="success-mark">✓</div>
        <h3>${escapeHtml(product.title)}</h3>
        <p>${formatNumber(product.price)} Blocks paid to ${escapeHtml(product.creator)}.</p>
        <button class="primary" data-add-to-world>Add to World</button>
      </div>`, 'buy-success');
  }

  function activateWorld() {
    const price = 1000;
    if (state.activatedWorlds.includes('neon-studio')) return;
    if (state.balance < price) {
      showToast('Not enough Blocks to activate this World.');
      return;
    }
    openDialog('Activate World', `
      <div class="flow-stack">
        <div><p class="eyebrow">Monthly access</p><p class="review-amount">Neon Studio</p></div>
        <div class="review-list">
          <div class="review-row"><span>Access</span><strong>1,000 Blocks</strong></div>
          <div class="review-row"><span>Balance after</span><strong>${formatNumber(state.balance - price)} Blocks</strong></div>
        </div>
        <button class="primary" data-confirm-world>Activate</button>
      </div>`, 'world-review');
  }

  function confirmWorld() {
    const price = 1000;
    if (state.activatedWorlds.includes('neon-studio') || state.balance < price) return;
    state.balance -= price;
    state.activatedWorlds.push('neon-studio');
    state.activity.unshift({ title: 'Neon Studio', detail: 'World access activated', amount: -price, icon: 'W' });
    saveState();
    render();
    closeDialog();
    showToast('Neon Studio activated.');
  }

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add('show');
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => toast.classList.remove('show'), 2200);
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));
  }

  document.addEventListener('click', (event) => {
    const target = event.target.closest('button');
    if (!target) return;

    if (target.dataset.nav) navigate(target.dataset.nav);
    if (target.dataset.go) navigate(target.dataset.go);
    if (target.dataset.action === 'send') sendStart();
    if (target.dataset.action === 'request') requestStart();
    if (target.dataset.action === 'add') addStart();
    if (target.dataset.buy) buyProduct(target.dataset.buy);
    if (target.hasAttribute('data-activate-world')) activateWorld();
    if (target.hasAttribute('data-dialog-close')) closeDialog();
    if (target.hasAttribute('data-confirm-send')) confirmSend();
    if (target.dataset.package) addBlocks(Number(target.dataset.package));
    if (target.dataset.confirmBuy) confirmBuy(target.dataset.confirmBuy);
    if (target.hasAttribute('data-confirm-world')) confirmWorld();
    if (target.hasAttribute('data-add-to-world')) {
      closeDialog();
      navigate('worlds');
      showToast('Choose a World to continue.');
    }
    if (target.hasAttribute('data-dialog-back')) {
      if (dialogStep === 'send-review') sendStart();
      else closeDialog();
    }
  });

  document.addEventListener('submit', (event) => {
    event.preventDefault();
    if (event.target.id === 'send-form') sendReview(event.target);
    if (event.target.id === 'request-form') createRequest(event.target);
  });

  dialog.addEventListener('cancel', () => {
    dialogStep = null;
    pending = null;
  });

  const requestedPage = location.hash.replace('#', '');
  navigate(['home', 'blocks', 'shop', 'worlds', 'profile'].includes(requestedPage) ? requestedPage : 'home');
  render();
})();
