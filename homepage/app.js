const STORAGE={name:'pride.identity.name',username:'pride.identity.username',salt:'pride.pin.salt',hash:'pride.pin.hash'};
const state={screen:'splash',pin:'',pendingPin:'',error:'',tab:'home',sheet:null};
const app=document.querySelector('#app');
const activity=[['3D Building Pack','Shop',-350],['From @Alex','Received',500],['World access','Gallery World',-80],['Texture Pack sale','Creator',120]];
const balance=12480;
const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const name=()=>localStorage.getItem(STORAGE.name)||'';
const username=()=>localStorage.getItem(STORAGE.username)||'';
const onboarded=()=>Boolean(name()&&username()&&localStorage.getItem(STORAGE.hash)&&localStorage.getItem(STORAGE.salt));
const initials=s=>s.trim().split(/\s+/).slice(0,2).map(x=>x[0]||'').join('').toUpperCase();
const fmt=n=>new Intl.NumberFormat('en-GB').format(n);
function shell(content,cls=''){app.innerHTML=`<div class="app-shell"><section class="screen ${cls}">${content}</section></div>`;bind();}
function render(){
 if(state.screen==='splash')return shell(`<div class="mark"></div><div class="brand">PRIDE</div>`,'splash');
 if(state.screen==='welcome')return shell(`<div class="mark small"></div><h1 class="title">Welcome to Pride</h1><p class="copy">Create, explore and participate using Blocks.</p><div class="spacer"></div><button class="primary" data-go="identity">Get started</button>`,'welcome');
 if(state.screen==='identity')return identityScreen();
 if(['create-pin','confirm-pin','locked'].includes(state.screen))return pinScreen();
 return mainScreen();
}
function identityScreen(){shell(`<div class="form-head"><div class="eyebrow">SET UP</div><h1 class="title">Your identity</h1><p class="copy">This is how other members will find and recognise you.</p></div><div class="fields"><div class="field"><label>Display name</label><input id="displayName" autocomplete="name" maxlength="40" placeholder="Sylwester"></div><div class="field"><label>Username</label><input id="username" autocapitalize="none" autocomplete="off" maxlength="24" placeholder="@sylwester"></div></div><div class="hint" id="usernameHint"></div><div class="form-actions"><button class="primary" id="identityContinue" disabled>Continue</button></div>`);}
function pinScreen(){
 const locked=state.screen==='locked';
 const title=state.screen==='create-pin'?'Create a PIN':state.screen==='confirm-pin'?'Confirm your PIN':`Good evening, ${esc(name())}`;
 const copy=state.screen==='create-pin'?'Use 6 digits to protect access to your Blocks.':state.screen==='confirm-pin'?'Enter the same 6 digits again.':'Enter your PIN to continue.';
 const avatar=locked?`<div class="identity-avatar">${esc(initials(name()))}</div>`:'';
 const dots=Array.from({length:6},(_,i)=>`<span class="dot ${i<state.pin.length?'filled':''}"></span>`).join('');
 const keys=['1','2','3','4','5','6','7','8','9','','0','delete'].map(k=>k===''?'<button class="key blank"></button>':`<button class="key" data-key="${k}">${k==='delete'?'⌫':k}</button>`).join('');
 shell(`${avatar}<h1 class="title">${title}</h1><p class="copy">${copy}</p><div class="dots">${dots}</div><div class="pin-error">${esc(state.error)}</div><div class="keypad">${keys}</div>`,`pin-screen ${locked?'':'setup'}`);
}
function mainScreen(){
 const tab=state.tab;
 let content='';
 if(tab==='home')content=home();
 if(tab==='blocks')content=blocks();
 if(tab==='shop')content=shop();
 if(tab==='worlds')content=worlds();
 if(tab==='profile')content=profile();
 const nav=[['home','⌂','Home'],['blocks','◈','Blocks'],['shop','▣','Shop'],['worlds','✦','Worlds'],['profile','●','Profile']].map(([id,g,l])=>`<button class="nav-item ${tab===id?'active':''}" data-tab="${id}"><span class="nav-glyph">${g}</span><span>${l}</span></button>`).join('');
 shell(`${content}<nav class="bottom-nav">${nav}</nav>${sheet()}`,'main');
}
function topbar(){return `<header class="topbar"><div class="avatar">${esc(initials(name()))}</div><div><div class="hello">Good evening</div><div class="name">${esc(name())}</div></div><div class="spacer"></div><button class="icon-button" aria-label="Notifications">•</button></header>`;}
function home(){return `${topbar()}<section class="card balance-card"><div class="balance-label">Blocks</div><div class="balance">${fmt(balance)}</div><div class="actions"><button class="action" data-sheet="send"><span class="action-icon">↑</span>Send</button><button class="action" data-sheet="request"><span class="action-icon">↓</span>Request</button><button class="action" data-sheet="add"><span class="action-icon">+</span>Add</button></div></section><div class="section-head"><div class="section-title">Recent activity</div><div class="section-link">See all</div></div><section class="card activity">${activity.map(([t,s,a])=>`<div class="activity-row"><div class="activity-icon">${a>0?'↙':'◇'}</div><div><div class="activity-title">${esc(t)}</div><div class="activity-sub">${esc(s)}</div></div><div class="amount ${a>0?'plus':''}">${a>0?'+':''}${fmt(a)}</div></div>`).join('')}</section>`;}
function blocks(){return `${topbar()}<h1 class="page-title">Blocks</h1><section class="card"><div class="balance-label">Blocks balance</div><div class="balance">${fmt(balance)}</div></section><div class="section-head"><div class="section-title">Activity</div></div><section class="card activity">${activity.map(([t,s,a])=>`<div class="activity-row"><div class="activity-icon">${a>0?'↙':'◇'}</div><div><div class="activity-title">${esc(t)}</div><div class="activity-sub">${esc(s)}</div></div><div class="amount ${a>0?'plus':''}">${a>0?'+':''}${fmt(a)}</div></div>`).join('')}</section>`;}
function shop(){return `${topbar()}<h1 class="page-title">Shop</h1><section class="card list-card"><article class="product"><div class="product-art">◇</div><div class="product-title">Cyberpunk Building Pack</div><div class="product-sub">Created by @Maya · 12 3D models · Textures included</div><div class="product-price">350 Blocks</div></article><article class="product"><div class="product-art">▦</div><div class="product-title">Studio Material Set</div><div class="product-sub">Created by @Alex · 36 materials · 4K textures</div><div class="product-price">180 Blocks</div></article></section>`;}
function worlds(){return `${topbar()}<h1 class="page-title">Worlds</h1><section class="card list-card"><div class="world"><div class="world-copy"><div class="product-title">Gallery World</div><div class="product-sub">Your creative space</div></div><span class="pill">Open</span></div><div class="world"><div class="world-copy"><div class="product-title">Night City</div><div class="product-sub">Explore · 284 people</div></div><span class="pill">Enter</span></div><div class="world"><div class="world-copy"><div class="product-title">Design Commons</div><div class="product-sub">Events today</div></div><span class="pill">Explore</span></div></section>`;}
function profile(){return `${topbar()}<h1 class="page-title">Profile</h1><section class="card"><div class="profile-head"><div class="avatar">${esc(initials(name()))}</div><div><div class="product-title">${esc(name())}</div><div class="product-sub">${esc(username())}</div></div></div><div class="menu-row"><span>Personal info</span><span>›</span></div><div class="menu-row"><span>Security</span><span>›</span></div><div class="menu-row"><span>Activity</span><span>›</span></div><button class="danger" data-lock>Lock app</button><br><button class="danger" data-reset>Reset demo</button></section>`;}
function sheet(){
 if(!state.sheet)return '';
 let body='';
 if(state.sheet==='send')body=`<input class="member-input" placeholder="@username"><input class="amount-input" inputmode="numeric" placeholder="0"><input class="member-input" placeholder="Note (optional)"><p class="note">A confirmation screen will be required before Blocks are sent.</p>`;
 if(state.sheet==='request')body=`<input class="member-input" placeholder="@username"><input class="amount-input" inputmode="numeric" placeholder="0"><p class="note">Requests identify the member, amount and optional reason before they are created.</p>`;
 if(state.sheet==='add')body=`<div class="package"><strong>500 Blocks</strong><span>£5</span></div><div class="package"><strong>1,000 Blocks</strong><span>£10</span></div><div class="package"><strong>2,500 Blocks</strong><span>£25</span></div><p class="note">Blocks have a service price. This demo does not show market charts or speculative pricing.</p>`;
 const title=state.sheet==='send'?'Send Blocks':state.sheet==='request'?'Request Blocks':'Add Blocks';
 return `<div class="sheet-backdrop" data-sheet-close><div class="sheet" onclick="event.stopPropagation()"><div class="grabber"></div><div class="sheet-title">${title}</div>${body}<button class="secondary sheet-close" data-sheet-close>Close</button></div></div>`;
}
function bind(){
 document.querySelector('[data-go="identity"]')?.addEventListener('click',()=>{state.screen='identity';render()});
 const dn=document.querySelector('#displayName'),un=document.querySelector('#username'),cont=document.querySelector('#identityContinue'),hint=document.querySelector('#usernameHint');
 if(dn&&un&&cont){const validate=()=>{const clean=un.value.trim().replace(/^@+/,'').toLowerCase().replace(/[^a-z0-9_.]/g,'');hint.textContent=clean?`@${clean}`:'';cont.disabled=!dn.value.trim()||clean.length<3};dn.addEventListener('input',validate);un.addEventListener('input',validate);cont.addEventListener('click',()=>{const clean=un.value.trim().replace(/^@+/,'').toLowerCase().replace(/[^a-z0-9_.]/g,'');if(!dn.value.trim()||clean.length<3)return;localStorage.setItem(STORAGE.name,dn.value.trim());localStorage.setItem(STORAGE.username,`@${clean}`);state.screen='create-pin';state.pin='';state.error='';render()})}
 document.querySelectorAll('[data-key]').forEach(b=>b.addEventListener('click',()=>handleKey(b.dataset.key)));
 document.querySelectorAll('[data-tab]').forEach(b=>b.addEventListener('click',()=>{state.tab=b.dataset.tab;state.sheet=null;render()}));
 document.querySelectorAll('[data-sheet]').forEach(b=>b.addEventListener('click',()=>{state.sheet=b.dataset.sheet;render()}));
 document.querySelectorAll('[data-sheet-close]').forEach(b=>b.addEventListener('click',()=>{state.sheet=null;render()}));
 document.querySelector('[data-lock]')?.addEventListener('click',()=>{state.screen='locked';state.pin='';state.error='';render()});
 document.querySelector('[data-reset]')?.addEventListener('click',()=>{Object.values(STORAGE).forEach(k=>localStorage.removeItem(k));state.screen='welcome';state.pin='';state.pendingPin='';state.error='';state.tab='home';render()});
}
async function handleKey(key){
 if(key==='delete'){state.pin=state.pin.slice(0,-1);state.error='';return render()}
 if(state.pin.length>=6)return;state.pin+=key;render();if(state.pin.length<6)return;
 const completed=state.pin;
 if(state.screen==='create-pin'){state.pendingPin=completed;state.pin='';state.screen='confirm-pin';return setTimeout(render,120)}
 if(state.screen==='confirm-pin'){
   if(completed!==state.pendingPin){state.pin='';state.pendingPin='';state.error='PINs did not match. Create it again.';state.screen='create-pin';return setTimeout(render,140)}
   await savePin(completed);state.pin='';state.pendingPin='';state.error='';state.screen='locked';return setTimeout(render,140)
 }
 if(state.screen==='locked'){
   const ok=await verifyPin(completed);state.pin='';state.error=ok?'':'Incorrect PIN';state.screen=ok?'main':'locked';return setTimeout(render,150)
 }
}
function bytesToB64(bytes){return btoa(String.fromCharCode(...bytes))}function b64ToBytes(s){return Uint8Array.from(atob(s),c=>c.charCodeAt(0))}
async function digest(pin,salt){const material=new Uint8Array(salt.length+pin.length);material.set(salt);material.set(new TextEncoder().encode(pin),salt.length);return new Uint8Array(await crypto.subtle.digest('SHA-256',material))}
async function savePin(pin){const salt=crypto.getRandomValues(new Uint8Array(16));const hash=await digest(pin,salt);localStorage.setItem(STORAGE.salt,bytesToB64(salt));localStorage.setItem(STORAGE.hash,bytesToB64(hash))}
async function verifyPin(pin){try{const salt=b64ToBytes(localStorage.getItem(STORAGE.salt)||'');const expected=b64ToBytes(localStorage.getItem(STORAGE.hash)||'');const actual=await digest(pin,salt);if(actual.length!==expected.length)return false;let diff=0;for(let i=0;i<actual.length;i++)diff|=actual[i]^expected[i];return diff===0}catch{return false}}
setTimeout(()=>{state.screen=onboarded()?'locked':'welcome';render()},1050);render();
