// Turn captured frames into the posted file: framing (auto-crop or zoom),
// encode, GIF-or-MP4, contact sheet, end frame, and pacing warnings.
import { writeFileSync, statSync, existsSync, rmSync, mkdirSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import path from "node:path";

const FPS = 30;
const EASE = 0.7;
const even = (n) => Math.max(2, Math.round(n / 2) * 2);
const ff = (args) => execFileSync("ffmpeg", ["-v", "error", "-y", ...args], { stdio: ["ignore", "ignore", "pipe"] });
const num = (n) => (Math.round(n * 1000) / 1000).toString();

// Concat list: each frame held until the next arrived (the screencast emits
// only on change, so a still page is one long-held frame).
function writeConcat(frames, t0, t1, file) {
  const lines = [];
  for (let i = 0; i < frames.length; i++) {
    const start = i === 0 ? t0 : frames[i].t;
    const next = i + 1 < frames.length ? frames[i + 1].t : t1;
    lines.push(`file '${frames[i].file}'`, `duration ${Math.max(0.001, next - start).toFixed(4)}`);
  }
  lines.push(`file '${frames[frames.length - 1].file}'`);
  writeFileSync(file, lines.join("\n") + "\n");
}

// Did anything inside `rect` (device px) change between two frames? Used for
// canvases (WebGL maps), which the DOM change tracker cannot see.
export function regionChanged(a, b, rect) {
  const crop = `crop=${even(rect.w)}:${even(rect.h)}:${even(rect.x)}:${even(rect.y)}`;
  const r = spawnSync("ffmpeg", ["-hide_banner", "-nostats", "-i", a, "-i", b, "-filter_complex", `[0]${crop}[x];[1]${crop}[y];[x][y]psnr`, "-f", "null", "-"], { encoding: "utf8" });
  return /average:(inf|[\d.]+)/.exec(r.stderr ?? "")?.[1] ?? null;
}

export function psnrSaysChanged(v) {
  return v != null && v !== "inf" && Number(v) < 38;
}

// --- framing ------------------------------------------------------------

export function chooseCrop({ cfg, viewport, dsf, take, changes, navigated, zooms }) {
  const cropCfg = cfg.crop ?? "auto";
  const pad = cfg.cropPadding ?? 48;
  const toCrop = (x1, y1, x2, y2) => {
    x1 -= pad; y1 -= pad; x2 += pad; y2 += pad;
    let w = Math.max(x2 - x1, 360), h = Math.max(y2 - y1, 220);
    const aspect = viewport.width / viewport.height;
    if (w / h > aspect * 1.6) h = w / (aspect * 1.6);
    if (h / w > 1.25) w = h / 1.25;
    const cx = (x1 + x2) / 2, cy = (y1 + y2) / 2;
    w = Math.min(w, viewport.width); h = Math.min(h, viewport.height);
    const x = Math.min(Math.max(0, cx - w / 2), viewport.width - w);
    const y = Math.min(Math.max(0, cy - h / 2), viewport.height - h);
    return { x: even(x * dsf), y: even(y * dsf), w: even(w * dsf), h: even(h * dsf), css: { x: Math.round(x), y: Math.round(y), width: Math.round(w), height: Math.round(h) } };
  };
  if (cropCfg === "off" || cropCfg === false) return { crop: null, why: "crop off" };
  if (zooms.length) return { crop: null, why: "zoom in take" };
  if (typeof cropCfg === "object" && cropCfg.x != null) {
    return { crop: toCrop(cropCfg.x + pad, cropCfg.y + pad, cropCfg.x + cropCfg.width - pad, cropCfg.y + cropCfg.height - pad), why: "explicit" };
  }
  if (navigated) return { crop: null, why: "navigation in take" };
  if (take.some((e) => e.type === "scroll" || e.type === "cut")) return { crop: null, why: "scroll or cut in take" };
  const boxes = take.filter((e) => e.rect).map((e) => ({ x1: e.rect.x, y1: e.rect.y, x2: e.rect.x + e.rect.width, y2: e.rect.y + e.rect.height }));
  boxes.push(...changes);
  if (!boxes.length) return { crop: null, why: "nothing located" };
  const u = boxes.reduce((a, b) => ({ x1: Math.min(a.x1, b.x1), y1: Math.min(a.y1, b.y1), x2: Math.max(a.x2, b.x2), y2: Math.max(a.y2, b.y2) }));
  const c = toCrop(u.x1, u.y1, u.x2, u.y2);
  const share = (c.css.width * c.css.height) / (viewport.width * viewport.height);
  const why = `action region is ${Math.round(share * 100)}% of the frame`;
  return share <= (cfg.cropMaxShare ?? 0.7) ? { crop: c, why } : { crop: null, why: `${why} (the app changed most of the screen); set \`crop\` to a box if the story lives in one part` };
}

// A camera path as keyframes {t, z, cx, cy} (device px), eased between.
// Ease in over EASE s at a zoom's start, out over EASE s after its end; a
// zoom that starts before the previous one has eased out pans straight to it.
export function cameraKeyframes(zooms, { W, H, viewport, dsf, maxZoom }) {
  const full = { z: 1, cx: W / 2, cy: H / 2 };
  const segs = [...zooms].sort((a, b) => a.t0 - b.t0);
  const keys = [{ t: 0, ...full }];
  const skipped = [];
  const push = (t, s) => {
    const last = keys[keys.length - 1];
    if (t <= last.t + 0.01) { keys[keys.length - 1] = { t: last.t, ...s }; return; }
    keys.push({ t, ...s });
  };
  segs.forEach((z, i) => {
    const fit = Math.min(viewport.width / (z.rect.width + 2 * z.padding), viewport.height / (z.rect.height + 2 * z.padding));
    const Z = Math.min(z.scale ?? fit, maxZoom);
    if (Z < 1.15) { skipped.push(z.t0); return; }
    const hw = W / (2 * Z), hh = H / (2 * Z);
    const cx = Math.min(Math.max((z.rect.x + z.rect.width / 2) * dsf, hw), W - hw);
    const cy = Math.min(Math.max((z.rect.y + z.rect.height / 2) * dsf, hh), H - hh);
    const target = { z: Z, cx, cy };
    const prev = keys[keys.length - 1];
    push(Math.max(z.t0, prev.t), { z: prev.z, cx: prev.cx, cy: prev.cy });
    push(Math.max(z.t0, prev.t) + EASE, target);
    const next = segs[i + 1];
    const t1 = Math.max(z.t1, z.t0 + EASE);
    push(t1, target);
    if (!next || next.t0 > t1 + EASE) push(t1 + EASE, full);
  });
  return { keys, skipped };
}

function exprFor(keys, field) {
  const T = `(on/${FPS})`;
  let e = num(keys[keys.length - 1][field]);
  for (let k = keys.length - 2; k >= 0; k--) {
    const a = keys[k], b = keys[k + 1];
    const v0 = num(a[field]), dv = num(b[field] - a[field]);
    const u = `clip((${T}-${num(a.t)})/${num(b.t - a.t)},0,1)`;
    const seg = dv === "0" ? v0 : `${v0}+${dv}*(${u})*(${u})*(3-2*(${u}))`;
    e = `if(lt(${T},${num(b.t)}),${seg},${e})`;
  }
  return `(${e})`;
}

export function zoomFilter(keys, W, H) {
  const Z = exprFor(keys, "z"), CX = exprFor(keys, "cx"), CY = exprFor(keys, "cy");
  const X0 = `clip(${CX}-${W}/(2*${Z}),0,${W}-${W}/${Z})`;
  const Y0 = `clip(${CY}-${H}/(2*${Z}),0,${H}-${H}/${Z})`;
  const X1 = `(${X0}+${W}/${Z})`, Y1 = `(${Y0}+${H}/${Z})`;
  // Sub-pixel (zoompan rounds to whole source pixels and jitters).
  return `perspective=x0='${X0}':y0='${Y0}':x1='${X1}':y1='${Y0}':x2='${X0}':y2='${Y1}':x3='${X1}':y3='${Y1}':eval=frame:sense=source:interpolation=cubic`;
}

// --- look-at artifacts -----------------------------------------------------

// The spotlight's on-screen span [fade-in start, fade-out end], in take s.
const spotSpan = (e) => [e.on ?? e.t + (e.delay ?? 700) / 1000, (e.off ?? e.t + ((e.delay ?? 700) + (e.fade ?? 320) + (e.ms ?? 2800)) / 1000) + (e.out ?? 150) / 1000];
// A moment inside the full-strength hold.
const spotAt = (e, k) => { const [a] = spotSpan(e); const b = e.off ?? spotSpan(e)[1]; const s = a + (e.fade ?? 320) / 1000; return s + (Math.max(b, s) - s) * k; };

// Twelve sheet times: one inside every spotlight (a proof the sheet skips
// cannot be checked from it), then each step's start (a short beat between
// evenly spaced frames is otherwise missed), then the widest gaps. Each pass
// takes the candidate farthest from what is chosen, so a pass with more
// candidates than slots still spreads out.
export function sheetTimes({ take, steps = [], duration, slots = 12 }) {
  const clamp = (t) => Math.min(Math.max(t, 0.05), Math.max(0.05, duration - 0.05));
  const times = [];
  const pick = (cands, minGap) => {
    let left = [...new Set(cands.map(clamp))];
    while (times.length < slots && left.length) {
      let best = null, gap = -1;
      for (const c of left) {
        const d = times.length ? Math.min(...times.map((t) => Math.abs(t - c))) : Infinity;
        if (d > gap) { gap = d; best = c; }
      }
      if (gap < minGap) break;
      times.push(best);
      left = left.filter((c) => c !== best);
    }
  };
  pick(take.filter((e) => e.type === "spotlight").map((e) => spotAt(e, 0.5)), 0);
  pick(steps.map((t) => t + 0.15), 0.4);
  pick(Array.from({ length: Math.max(slots, Math.ceil(duration * 10)) }, (_, i) => (i + 0.5) * duration / Math.max(slots, Math.ceil(duration * 10))), 0);
  return times.sort((a, b) => a - b);
}

// When the take ends in a spotlight, the end frame is inside it (label up):
// that is the proof the viewer is left with. Otherwise null (the last frame).
export function endFrameTime({ take, steps = [], duration }) {
  const last = take.filter((e) => e.type === "spotlight").at(-1);
  if (!last || steps.some((t) => t > last.t)) return null;
  return Math.min(Math.max(0.05, spotAt(last, 0.85)), duration - 0.05);
}

// --- assemble -------------------------------------------------------------

export function assemble(o) {
  const { cfg, viewport, dsf, frames, t0, t1, outDir, outName, framesDir, take, steps, zooms, crop, warnings } = o;
  const W = even(viewport.width * dsf), H = even(viewport.height * dsf);
  const outWidth = cfg.output?.width ?? 1920;
  const list = path.join(framesDir, "list.txt");
  writeConcat(frames, t0, t1, list);

  let vf, outW, outH;
  if (crop) {
    outW = even(Math.min(crop.w, outWidth));
    outH = even((crop.h * outW) / crop.w);
    vf = `fps=${FPS},crop=${crop.w}:${crop.h}:${crop.x}:${crop.y},scale=${outW}:${outH}:flags=lanczos`;
  } else {
    outW = even(Math.min(W, outWidth));
    outH = even((H * outW) / W);
    const base = `fps=${FPS},scale=${W}:${H}`;
    if (zooms.length) {
      const { keys, skipped } = cameraKeyframes(zooms, { W, H, viewport, dsf, maxZoom: cfg.maxZoom ?? 2.5 });
      for (const t of skipped) warnings.push(`zoom at t+${t.toFixed(1)}s skipped: the target already fills the frame`);
      vf = keys.length > 1 ? `${base},${zoomFilter(keys, W, H)},scale=${outW}:${outH}:flags=lanczos` : `${base},scale=${outW}:${outH}:flags=lanczos`;
    } else {
      vf = `${base},scale=${outW}:${outH}:flags=lanczos`;
    }
  }

  const mp4 = path.join(outDir, `${outName}.mp4`);
  ff(["-f", "concat", "-safe", "0", "-i", list, "-vf", `${vf},format=yuv420p`,
    "-c:v", "libx264", "-preset", "slow", "-crf", String(cfg.output?.crf ?? 20), "-movflags", "+faststart", mp4]);
  const duration = Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1", mp4]).toString().trim());

  // Look-at artifacts: twelve frames on one sheet, and the end frame alone
  // (the end state is what the take must prove).
  const sheet = path.join(outDir, `${outName}-sheet.png`);
  const endFrame = path.join(outDir, `${outName}-end.png`);
  try {
    const times = sheetTimes({ take, steps, duration });
    const dir = path.join(framesDir, "sheet");
    mkdirSync(dir, { recursive: true });
    times.forEach((t, i) => ff(["-ss", t.toFixed(3), "-i", mp4, "-frames:v", "1", "-vf", "scale=480:-2", path.join(dir, `${String(i).padStart(2, "0")}.png`)]));
    ff(["-framerate", "1", "-i", path.join(dir, "%02d.png"), "-vf", "tile=4x3:padding=6:color=white", "-frames:v", "1", sheet]);
  } catch { warnings.push("contact sheet failed"); }
  try {
    const at = endFrameTime({ take, steps, duration });
    if (at != null) ff(["-ss", at.toFixed(3), "-i", mp4, "-frames:v", "1", "-update", "1", endFrame]);
    else ff(["-sseof", "-0.2", "-i", mp4, "-frames:v", "1", "-update", "1", endFrame]);
  } catch { warnings.push("end frame failed"); }

  if (duration > 45) warnings.push(`take is ${duration.toFixed(0)}s; over 45s drags — cut waits or split the story`);
  const tailMs = cfg.tailMs ?? 1600;
  // A still page is expected while a zoom moves (it is added in post) or a
  // spotlight holds; anywhere else a long still stretch is dead air.
  const busy = [
    ...zooms.map((z) => [z.t0, z.t1 + EASE]),
    ...take.filter((e) => e.type === "spotlight").map((e) => [e.t, spotSpan(e)[1] + 0.5]),
  ];
  for (let i = 1; i < frames.length; i++) {
    const a = frames[i - 1].t, b = frames[i].t;
    if (b - a <= 3 || busy.some(([s, e]) => a < e && b > s)) continue;
    warnings.push(`nothing moves for ${(b - a).toFixed(1)}s at t+${(a - t0).toFixed(1)}s`);
  }
  const lastGap = t1 - frames[frames.length - 1].t;
  if (lastGap > tailMs / 1000 + 3) warnings.push(`nothing moves for ${lastGap.toFixed(1)}s at the end`);
  // Measured on screen, fades included (the default is about 3.3 s); the
  // cursor's `delay` before it is not part of it.
  for (const e of take.filter((x) => x.type === "spotlight")) {
    const [a, b] = spotSpan(e);
    if (b - a > 3.5) warnings.push(`spotlight at t+${a.toFixed(1)}s is on screen ${(b - a).toFixed(1)}s (fades included); over 3.5s drags — lower \`ms\``);
  }

  // Format: a short plain take reads best as a GIF; a guided one (zoom or
  // spotlight) or a long one stays MP4.
  const spotlights = take.filter((e) => e.type === "spotlight").length;
  const formatCfg = cfg.format ?? "auto";
  let format = formatCfg === "gif" ? "gif" : formatCfg === "mp4" ? "mp4"
    : duration <= (cfg.gifMaxSeconds ?? 12) && !zooms.length && !spotlights ? "gif" : "mp4";
  let gif = null;
  if (format === "gif") {
    gif = path.join(outDir, `${outName}.gif`);
    const LIMIT = 9.5 * 1024 * 1024; // GitHub's image cap is 10MB
    const widths = [...new Set([1200, 960, 720].map((w) => Math.min(outW, w)))];
    // Give up quality before width: a smaller GIF of crisp UI beats a blurry one.
    const ladder = widths.flatMap((w) => [[w, 90], [w, 80], [w, 70]]);
    let fit = false;
    for (const [w, q] of ladder) {
      try {
        execFileSync("gifski", ["--quiet", "--fps", "15", "--quality", String(q), "--width", String(w), "-o", gif, mp4], { stdio: ["ignore", "ignore", "pipe"] });
      } catch {
        ff(["-i", mp4, "-vf", `fps=15,scale=${w}:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a`, gif]);
      }
      if (statSync(gif).size <= LIMIT) { fit = true; break; }
    }
    if (!fit) {
      warnings.push("GIF over 10MB even at 720px; posting the MP4");
      rmSync(gif, { force: true });
      gif = null;
      format = "mp4";
    }
  }
  const mb = (f) => +(statSync(f).size / 1048576).toFixed(2);
  return {
    post: format === "gif" ? gif : mp4,
    format,
    mp4, mp4MB: mb(mp4),
    gif, gifMB: gif ? mb(gif) : null,
    sheet: existsSync(sheet) ? sheet : null,
    endFrame: existsSync(endFrame) ? endFrame : null,
    duration: +duration.toFixed(1),
    size: `${outW}x${outH}`,
    zooms: zooms.length,
    spotlights,
  };
}
