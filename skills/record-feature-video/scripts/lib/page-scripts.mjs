// Scripts evaluated inside the recorded page. Strings so they can be
// re-injected after navigations with `window.eval`; functions where they run
// once per call through Playwright's evaluate.

// The cursor lives in the TOP document above everything (an app inside an
// iframe included); a click ripple and an optional file badge for drags.
export const CURSOR = `
(() => {
  if (window.__fr_cursor && document.body && document.body.contains(window.__fr_cursor)) return;
  if (!document.body) return;
  const c = document.createElement('div');
  c.id = '__fr_cursor';
  c.dataset.fr = '1';
  c.style.cssText = 'position:fixed;left:0;top:0;width:22px;height:22px;pointer-events:none;z-index:2147483647;margin:0;padding:0;will-change:transform;transition:none';
  c.innerHTML = '<svg width="22" height="22" viewBox="0 0 22 22" xmlns="http://www.w3.org/2000/svg"><path d="M4 2 L4 17.2 L8.1 13.4 L10.7 19.4 L13.3 18.2 L10.8 12.4 L16.4 12.2 Z" fill="#111827" stroke="#ffffff" stroke-width="1.4" stroke-linejoin="round"/></svg>';
  const badge = document.createElement('div');
  badge.style.cssText = 'position:absolute;left:18px;top:18px;display:none;white-space:nowrap;padding:5px 9px;border-radius:7px;background:rgba(15,23,42,0.92);color:#f8fafc;font:600 12px/1.2 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;box-shadow:0 6px 18px rgba(0,0,0,0.35)';
  c.appendChild(badge);
  document.body.appendChild(c);
  window.__fr_cursor = c;
  window.__fr_move = (x, y) => { window.__fr_x = x; window.__fr_y = y; c.style.transform = 'translate(' + (x - 2) + 'px,' + (y - 2) + 'px)'; };
  window.__fr_move(window.__fr_x ?? 60, window.__fr_y ?? 60);
  window.__fr_badge = (text) => { badge.textContent = text || ''; badge.style.display = text ? 'block' : 'none'; };
  window.__fr_badge(window.__fr_badgeText || '');
  window.__fr_click = (x, y) => {
    const r = document.createElement('div');
    r.dataset.fr = '1';
    r.style.cssText = 'position:fixed;left:' + (x - 4) + 'px;top:' + (y - 4) + 'px;width:8px;height:8px;border-radius:50%;background:rgba(56,189,248,0.55);border:2px solid rgba(2,132,199,0.9);pointer-events:none;z-index:2147483646;transition:transform 380ms ease-out, opacity 380ms ease-out;opacity:1';
    document.body.appendChild(r);
    r.offsetHeight;
    r.style.transform = 'scale(4.5)';
    r.style.opacity = '0';
    setTimeout(() => r.remove(), 420);
  };
})();
`;

// Union of the viewport boxes of everything the app changes during the take,
// so auto-crop never cuts away an effect that lands outside the clicked area.
export const CHANGE_TRACKER = `
(() => {
  if (window.__fr_changes) return;
  const u = window.__fr_changes = { x1: Infinity, y1: Infinity, x2: -Infinity, y2: -Infinity, n: 0 };
  const ours = (el) => el && el.nodeType === 1 && (el.id === '__fr_cursor' || el.classList.contains('__fr_spot') || (el.dataset && el.dataset.fr) || (el.closest && el.closest('[data-fr]')));
  const add = (node) => {
    const el = node && node.nodeType === 1 ? node : node && node.parentElement;
    if (!el || ours(el) || !el.isConnected) return;
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return;
    const x1 = Math.max(0, r.left), y1 = Math.max(0, r.top);
    const x2 = Math.min(innerWidth, r.right), y2 = Math.min(innerHeight, r.bottom);
    if (x2 <= x1 || y2 <= y1) return;
    u.x1 = Math.min(u.x1, x1); u.y1 = Math.min(u.y1, y1);
    u.x2 = Math.max(u.x2, x2); u.y2 = Math.max(u.y2, y2); u.n++;
  };
  new MutationObserver((ms) => {
    for (const m of ms) {
      if (m.type === 'childList') {
        m.addedNodes.forEach(add);
        if ([...m.removedNodes].some((n) => !ours(n))) add(m.target);
      } else add(m.target);
    }
  }).observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
})();
`;

export function spotlightOn({ rect, label, padding, position, fade }) {
  const pad = padding ?? 10;
  const box = document.createElement("div");
  box.className = "__fr_spot";
  box.dataset.fr = "1";
  box.style.cssText = [
    "position:fixed", `left:${rect.x - pad}px`, `top:${rect.y - pad}px`,
    `width:${rect.width + pad * 2}px`, `height:${rect.height + pad * 2}px`,
    "border-radius:10px", "box-shadow:0 0 0 9999px rgba(15,23,42,0.62)",
    "outline:2px solid rgba(56,189,248,0.95)", "pointer-events:none",
    "z-index:2147483640", "opacity:0", `transition:opacity ${fade}ms ease`,
  ].join(";");
  document.body.appendChild(box);
  let card = null;
  if (label) {
    card = document.createElement("div");
    card.className = "__fr_spot";
    card.dataset.fr = "1";
    card.textContent = label;
    // Sized for where it is watched: GitHub plays the video about 900px wide,
    // so the label must read at 17px there whatever the viewport.
    const k = Math.max(1, innerWidth / 900);
    card.style.cssText = [
      "position:fixed", `max-width:${Math.round(520 * k)}px`, `padding:${Math.round(12 * k)}px ${Math.round(18 * k)}px`,
      `border-radius:${Math.round(12 * k)}px`, "background:rgba(15,23,42,0.96)", "color:#f8fafc",
      `font:600 ${Math.round(17 * k)}px/1.3 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif`,
      "box-shadow:0 10px 30px rgba(0,0,0,0.45)", "pointer-events:none", "z-index:2147483641",
      "opacity:0", `transition:opacity ${fade}ms ease`,
    ].join(";");
    document.body.appendChild(card);
    const cw = card.offsetWidth, ch = card.offsetHeight;
    const vw = innerWidth, vh = innerHeight;
    const place = (side) => {
      let x, y;
      if (side === "top") { x = rect.x + rect.width / 2 - cw / 2; y = rect.y - pad - ch - 12; }
      else if (side === "left") { x = rect.x - pad - cw - 12; y = rect.y + rect.height / 2 - ch / 2; }
      else if (side === "right") { x = rect.x + rect.width + pad + 12; y = rect.y + rect.height / 2 - ch / 2; }
      else { x = rect.x + rect.width / 2 - cw / 2; y = rect.y + rect.height + pad + 12; }
      return { x: Math.max(12, Math.min(x, vw - cw - 12)), y: Math.max(12, Math.min(y, vh - ch - 12)) };
    };
    // `auto`: the side where the card covers least. Covering the spotlit
    // target is worst; covering other text or controls is bad; room breaks ties.
    let side = position ?? "auto";
    if (side === "auto") {
      const t = { x1: rect.x - pad, y1: rect.y - pad, x2: rect.x + rect.width + pad, y2: rect.y + rect.height + pad };
      const overlap = (p) => Math.max(0, Math.min(p.x + cw, t.x2) - Math.max(p.x, t.x1)) * Math.max(0, Math.min(p.y + ch, t.y2) - Math.max(p.y, t.y1));
      const busy = (p) => {
        let n = 0;
        for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) {
          const el = document.elementFromPoint(p.x + (cw * (i + 0.5)) / 4, p.y + (ch * (j + 0.5)) / 3);
          if (el && el.closest('button,a,input,select,textarea,label,[role],h1,h2,h3,h4,h5,h6,p,li,td,th,span')) n++;
        }
        // The cursor (drawn with pointer-events off) counts as content too.
        const cx = window.__fr_x, cy = window.__fr_y;
        if (cx >= p.x - 20 && cx <= p.x + cw + 20 && cy >= p.y - 20 && cy <= p.y + ch + 20) n += 4;
        return n;
      };
      const room = { bottom: vh - t.y2, top: t.y1, right: vw - t.x2, left: t.x1 };
      side = Object.keys(room)
        .map((k) => { const p = place(k); return { k, score: overlap(p) * 10 + busy(p) * 400 - room[k] }; })
        .sort((a, b) => a.score - b.score)[0].k;
    }
    const at = place(side);
    card.style.left = at.x + "px";
    card.style.top = at.y + "px";
  }
  box.offsetHeight;
  box.style.opacity = "1";
  if (card) card.style.opacity = "1";
  // The label's box, so an auto-crop keeps it in frame.
  if (!card) return null;
  const c = card.getBoundingClientRect();
  return { x: c.x, y: c.y, width: c.width, height: c.height };
}

// The fade-out sets its own (short) transition: inheriting the fade-in's left
// the dim and label fading over the start of the next beat.
export function spotlightOff(fade) {
  document.querySelectorAll(".__fr_spot").forEach((el) => {
    el.style.transition = `opacity ${fade}ms ease`;
    el.style.opacity = "0";
    setTimeout(() => el.remove(), fade + 20);
  });
}

// A deliberate scene change: fade to a solid color, change state, fade back.
export function cutCover({ on, color, fade, label }) {
  let veil = document.getElementById("__fr_cut");
  if (!veil) {
    veil = document.createElement("div");
    veil.id = "__fr_cut";
    veil.dataset.fr = "1";
    veil.style.cssText = `position:fixed;inset:0;z-index:2147483645;pointer-events:none;opacity:0;transition:opacity ${fade}ms ease;background:${color};display:flex;align-items:center;justify-content:center`;
    if (label) {
      // A title card says why the scene changed; a bare blank reads as a glitch.
      const t = document.createElement("div");
      t.textContent = label;
      t.style.cssText = `color:#fff;font:600 ${Math.round(26 * Math.max(1, innerWidth / 900))}px/1.3 system-ui,-apple-system,sans-serif;max-width:70%;text-align:center`;
      veil.appendChild(t);
    }
    document.documentElement.appendChild(veil);
    veil.offsetHeight;
  }
  veil.style.opacity = on ? "1" : "0";
  if (!on) setTimeout(() => veil.remove(), fade + 40);
}

// Is the point (as a fraction of the element's box) really the element, or
// is something on top of it? Runs in the element's own frame.
// A hit on the control that wraps the target (a link or button around an icon
// or label, a <label> around an input) clicks the same thing, so it counts.
export function hitTest(el, [fx, fy]) {
  const r = el.getBoundingClientRect();
  const x = r.left + r.width * fx, y = r.top + r.height * fy;
  if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) return { ok: false, why: "outside the visible area" };
  const hit = document.elementFromPoint(x, y);
  const CONTROL = "a[href],button,label,summary,select,[role=button],[role=link],[role=tab],[role=menuitem],[role=option],[role=checkbox],[role=radio],[role=switch]";
  if (!hit || hit === el || el.contains(hit)) return { ok: true };
  if (hit.contains(el) && hit.matches(CONTROL)) return { ok: true };
  const ctl = el.closest(CONTROL);
  if (ctl && ctl === hit.closest(CONTROL)) return { ok: true };
  const tag = hit.tagName.toLowerCase();
  const id = hit.id ? `#${hit.id}` : "";
  const cls = typeof hit.className === "string" && hit.className.trim() ? "." + hit.className.trim().split(/\s+/).slice(0, 2).join(".") : "";
  const text = (hit.innerText || "").trim().slice(0, 40);
  return { ok: false, why: `covered by <${tag}${id}${cls}>${text ? ` "${text}"` : ""}` };
}

// For each [x, y] in page coordinates: 1 when the point rests on text or a
// control (into same-origin iframes), else 0. A parked cursor on a label reads
// as pointing at it.
export function busyAt(points) {
  const TEXTY = "button,a,input,select,textarea,label,summary,h1,h2,h3,h4,h5,h6,p,li,td,th,dt,dd,span,b,strong,em,code,img,svg,canvas,video,"
    + "[role=button],[role=link],[role=tab],[role=menuitem],[role=option],[role=row],[role=cell],[role=gridcell],[role=checkbox]";
  return points.map(([x, y]) => {
    let doc = document, px = x, py = y, el = null;
    for (let depth = 0; depth < 4; depth++) {
      el = doc.elementFromPoint(px, py);
      if (!el || el.tagName !== "IFRAME") break;
      let inner = null;
      try { inner = el.contentDocument; } catch { inner = null; }
      if (!inner) return 1;
      const r = el.getBoundingClientRect();
      px -= r.left + el.clientLeft; py -= r.top + el.clientTop; doc = inner;
    }
    if (!el || el === doc.body || el === doc.documentElement) return 0;
    if (el.closest(TEXTY)) return 1;
    // Bare text in a block (a div holding a text node) counts too.
    for (const n of el.childNodes) {
      if (n.nodeType !== 3 || !n.textContent.trim()) continue;
      const rg = doc.createRange();
      rg.selectNodeContents(n);
      for (const r of rg.getClientRects()) if (px >= r.left - 8 && px <= r.right + 8 && py >= r.top - 8 && py <= r.bottom + 8) return 1;
    }
    return 0;
  });
}

// Drag a file (or a text selection) onto an element with real drag events
// carrying a real DataTransfer, built in the element's own frame.
export function dragEvent(el, { phase, fx, fy, files, text }) {
  const r = el.getBoundingClientRect();
  const x = r.left + r.width * fx, y = r.top + r.height * fy;
  const target = document.elementFromPoint(x, y) || el;
  const dt = new DataTransfer();
  for (const f of files ?? []) {
    const bin = atob(f.b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    dt.items.add(new File([bytes], f.name, { type: f.mime }));
  }
  if (text != null) dt.setData("text/plain", text);
  const ev = new DragEvent(phase, { bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, dataTransfer: dt });
  target.dispatchEvent(ev);
  return ev.defaultPrevented;
}

// A paste the way the browser delivers one: a `paste` event carrying the
// text first; only if the app does not take it does the text get inserted.
export function pasteInto(el, text) {
  const target = document.activeElement && el.contains(document.activeElement) ? document.activeElement : el;
  const dt = new DataTransfer();
  dt.setData("text/plain", text);
  const ev = new ClipboardEvent("paste", { bubbles: true, cancelable: true, composed: true, clipboardData: dt });
  target.dispatchEvent(ev);
  return ev.defaultPrevented;
}

// How far to scroll `container` (or the page) so `target` lands at `block`
// (start | center | end | a 0..1 fraction of the pane), then `offset` CSS px
// lower. The pane's top is taken below what stays pinned there: its
// scroll-padding-top, else a sticky or fixed header measured at the top edge.
export function scrollPlan({ target, container, block, offset, to, x, y }) {
  const scrollable = (el) => {
    for (let n = el && el.parentElement; n; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (/(auto|scroll|overlay)/.test(s.overflowY + s.overflowX) && (n.scrollHeight > n.clientHeight + 1 || n.scrollWidth > n.clientWidth + 1)) return n;
    }
    return document.scrollingElement;
  };
  const pane = container ?? (target ? scrollable(target) : document.scrollingElement);
  const isDoc = pane === document.scrollingElement || pane === document.documentElement || pane === document.body;
  document.querySelectorAll("[data-fr-pane]").forEach((n) => n.removeAttribute("data-fr-pane"));
  if (!isDoc) pane.setAttribute("data-fr-pane", "1");
  const pr = isDoc ? { top: 0, left: 0, height: innerHeight, width: innerWidth } : pane.getBoundingClientRect();
  let dx = x ?? 0, dy = y ?? 0;
  if (to === "top") dy = -pane.scrollTop;
  else if (to === "bottom") dy = pane.scrollHeight - pane.clientHeight - pane.scrollTop;
  else if (target) {
    const tr = target.getBoundingClientRect();
    const frac = block === "center" || block == null ? 0.5 : block === "start" ? 0 : block === "end" ? 1 : Number(block);
    const cs = getComputedStyle(isDoc ? document.documentElement : pane);
    let padTop = parseFloat(cs.scrollPaddingTop) || 0;
    const padBottom = parseFloat(cs.scrollPaddingBottom) || 0;
    if (!padTop) {
      for (const fx of [0.25, 0.5, 0.75]) {
        for (let n = document.elementFromPoint(pr.left + pr.width * fx, pr.top + 2); n && n !== pane && n !== document.body && n !== document.documentElement; n = n.parentElement) {
          if (!/sticky|fixed/.test(getComputedStyle(n).position) || n.contains(target) || target.contains(n)) continue;
          padTop = Math.max(padTop, Math.min(n.getBoundingClientRect().bottom - pr.top, pr.height / 2));
          break;
        }
      }
    }
    const top = pr.top + padTop, height = pr.height - padTop - padBottom;
    dy = tr.top - top - (height - tr.height) * frac - (offset ?? 0);
    if (tr.left < pr.left || tr.right > pr.left + pr.width) dx = tr.left - pr.left - (pr.width - tr.width) / 2;
  }
  const maxY = pane.scrollHeight - pane.clientHeight - pane.scrollTop;
  const maxX = pane.scrollWidth - pane.clientWidth - pane.scrollLeft;
  dy = Math.max(-pane.scrollTop, Math.min(dy, maxY));
  dx = Math.max(-pane.scrollLeft, Math.min(dx, maxX));
  return { dx, dy, pane: { x: pr.left, y: pr.top, width: pr.width, height: pr.height }, isDoc, startTop: pane.scrollTop, startLeft: pane.scrollLeft };
}
