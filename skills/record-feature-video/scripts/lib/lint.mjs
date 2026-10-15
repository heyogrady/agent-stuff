// Shot-list lint: runs before any browser starts, so a malformed list or a
// take that would jump the page without the cursor costs a second, not a take.

// The cursor performs these; they are what the viewer watches.
export const CURSOR = new Set([
  "click", "type", "paste", "select", "upload", "drop", "hover", "move",
  "down", "up", "scroll", "scrollTo", "spotlight", "zoom", "zoomOut",
]);
// Change the page with no cursor: setup only, unless the step says why.
export const NO_CURSOR = new Set(["goto", "hash", "eval"]);
// Neutral anywhere: timing, assertions, presentation, keyboard.
export const NEUTRAL = new Set(["wait", "waitFor", "expect", "css", "press", "cut", "mark"]);
export const KNOWN = new Set([...CURSOR, ...NO_CURSOR, ...NEUTRAL]);

const NEEDS_SELECTOR = new Set([
  "click", "type", "paste", "select", "upload", "drop", "hover", "scrollTo",
  "spotlight", "zoom", "waitFor",
]);
const TAKE_ONLY = new Set(["spotlight", "zoom", "zoomOut", "cut"]);

const COMMON = ["type", "note", "frame", "selector", "hasText", "nth", "timeout", "after", "ms", "allowNoCursor", "expect", "force", "scrollIntoView"];
const FIELDS = {
  goto: ["url", "waitUntil", "settle"],
  hash: ["value", "settle"],
  eval: ["script"],
  mark: [],
  wait: [],
  waitFor: ["state", "settle"],
  expect: ["text", "state", "count", "value"],
  css: ["css", "id", "remove"],
  press: ["key"],
  cut: ["url", "hash", "script", "fade", "settle", "color", "label"],
  click: ["xFrac", "yFrac", "offsetX", "offsetY", "pause"],
  type: ["text", "delay", "clear", "xFrac", "yFrac", "offsetX", "offsetY"],
  paste: ["text", "clear"],
  select: ["option", "label", "value", "pause"],
  upload: ["file", "files", "via"],
  drop: ["file", "files", "text", "leave", "hold"],
  hover: ["hold", "xFrac", "yFrac", "offsetX", "offsetY"],
  move: ["x", "y", "xFrac", "yFrac", "offsetX", "offsetY"],
  down: [], up: [],
  scroll: ["x", "y", "to", "block", "offset", "container"],
  scrollTo: ["scrollMs", "block"],
  spotlight: ["label", "delay", "padding", "position", "fade"],
  zoom: ["stay", "scale", "padding", "ease"],
  zoomOut: ["ease"],
};
const TOP_LEVEL = new Set([
  "baseUrl", "viewport", "deviceScaleFactor", "cookies", "cookiesFile", "storageState",
  "frames", "actions", "output", "styleTag", "filePicker", "launchArgs", "headless", "cdp",
  "tailMs", "gifMinSeconds", "maxZoom", "crop", "cropPadding", "cropMaxShare", "format", "gifMaxSeconds",
  "allowForeignServer", "timezoneId", "devServer", "maxSeconds", "rehearseTimeout",
  "repo", "proxy", "locale", "leadInMs", "$comment",
]);

export function takeStartIndex(actions) {
  const mark = actions.findIndex((a) => a.type === "mark");
  if (mark >= 0) return mark + 1;
  // No mark: leading navigation, scripting, and readiness checks are setup.
  const setup = new Set([...NO_CURSOR, "waitFor", "expect", "css"]);
  const first = actions.findIndex((a) => !setup.has(a.type));
  return first < 0 ? actions.length : first;
}

// Name the cursor action that does what a rejected script was doing.
export function hintFor(a) {
  if (a.type === "goto" || a.type === "hash") {
    return "click the link or control a user would use; if no user path reaches this state, use `cut`";
  }
  const s = a.script ?? "";
  if (/\blocation\b|history\.(push|replace)State/.test(s)) return "click the link a user would use; if there is none, use `cut` with this script";
  if (/DataTransfer|['"]drop['"]|dragover|dragenter|drag|ghost/i.test(s)) return "use `drop` (drags a file, or `text`, onto the target with the cursor; `leave: true` for a refusal)";
  if (/ClipboardEvent|['"]paste['"]/.test(s)) return "use `paste` (fires a real paste event)";
  if (/scroll(Top|Left|To|By|IntoView)\b|scrollTop\s*=|center|nudge/i.test(s)) return "use `scroll` with `to` (a target), `to: \"top\"`, or `y`/`x` on the pane, or `scrollTo`";
  if (/\.value\s*=|nativeInputValueSetter|HTMLInputElement\.prototype/.test(s)) return "use `type` with `clear: true` (or `select` for a <select>)";
  if (/\.click\(\)|dispatchEvent\(\s*new\s+(Mouse|Pointer)Event|['"]click['"]/.test(s)) return "use `click` so the cursor does it";
  if (/\.style\b|classList|setAttribute|\.size\s*=/.test(s)) return "use `css` (allowed during the take) or do it before `mark`";
  return "do it before `mark`, or use `cut` for a deliberate scene change";
}

// `role=row[name=/x/] td`: after a role= selector a space is not a descendant
// step; Playwright rejects the whole selector. Returns the ` >> ` form, or null.
export function roleSpaceFix(sel) {
  if (typeof sel !== "string") return null;
  for (const m of sel.matchAll(/(?:^|>>\s*)role=[\w-]+/g)) {
    let i = m.index + m[0].length;
    while (sel[i] === "[") {
      // One [...] group; quoted strings and /regex/ may hold ] or spaces.
      let q = null;
      for (i++; i < sel.length; i++) {
        const c = sel[i];
        if (q) { if (c === "\\") i++; else if (c === q) q = null; }
        else if (c === '"' || c === "'" || c === "/") q = c;
        else if (c === "]") break;
      }
      i++;
    }
    if (/^\s+(?!>>)\S/.test(sel.slice(i))) return `${sel.slice(0, i)} >> ${sel.slice(i).trim()}`;
  }
  return null;
}

export function lint(cfg) {
  const errors = [];
  const warnings = [];
  const actions = Array.isArray(cfg.actions) ? cfg.actions : null;
  if (!actions) return { errors: ["`actions` must be an array"], warnings, takeStart: 0 };
  const relative = actions.some((a) => (a.type === "goto" || a.type === "cut") && a.url && !/^[a-z]+:/i.test(a.url));
  if (!cfg.baseUrl && relative) errors.push("`baseUrl` is required when a `goto` or `cut` url is relative");
  for (const k of Object.keys(cfg)) if (!TOP_LEVEL.has(k)) warnings.push(`top-level \`${k}\` is not a recorder option and is ignored`);

  const vp = cfg.viewport;
  if (vp?.width > 0 && vp?.height > 0 && (vp.width / vp.height < 1.5 || vp.width / vp.height > 1.9)) {
    // An uncropped take has the viewport's aspect.
    warnings.push(`viewport ${vp.width}x${vp.height} gives an uncropped take a ${(vp.width / vp.height).toFixed(2)}:1 aspect; 1440x900 (16:10) reads as a normal screen, so use it unless the story needs the height`);
  }

  const start = takeStartIndex(actions);
  const marks = actions.filter((a) => a.type === "mark").length;
  if (marks > 1) errors.push("more than one `mark`");

  actions.forEach((a, i) => {
    const where = `step ${i + 1} (${a.type})`;
    if (!KNOWN.has(a.type)) { errors.push(`${where}: unknown action type`); return; }
    for (const k of Object.keys(a)) {
      if (COMMON.includes(k) || FIELDS[a.type]?.includes(k)) continue;
      const tip = k === "label" ? " (only `spotlight` shows a label; use `note` for a comment)" : "";
      warnings.push(`${where}: \`${k}\` is ignored${tip}`);
    }
    if (Array.isArray(a.selector) && (a.type !== "spotlight" || !a.selector.length || !a.selector.every((x) => typeof x === "string" && x))) {
      errors.push(`${where}: a list of selectors is for \`spotlight\` only, each a non-empty string`);
    }
    for (const sel of [a.selector, a.expect?.selector, a.to, a.container, a.via].flat()) {
      const fix = roleSpaceFix(sel);
      if (fix) errors.push(`${where}: \`${sel}\` — a space after a \`role=\` selector is not a descendant step and Playwright rejects it; chain with \` >> \`: \`${fix}\``);
    }
    if (NEEDS_SELECTOR.has(a.type) && !a.selector) {
      const tip = a.type === "scrollTo" && (a.y != null || a.x != null) ? " (to scroll by pixels, use `scroll` with `y`/`x`)" : "";
      errors.push(`${where}: needs \`selector\`${tip}`);
    }
    if (a.type === "move" && !a.selector && !(Number.isFinite(a.x) && Number.isFinite(a.y))) errors.push(`${where}: needs \`selector\` or \`x\` and \`y\``);
    if (a.type === "expect" && !a.selector && a.text == null) errors.push(`${where}: needs \`selector\` or \`text\``);
    if (a.type === "upload" && !(a.file ?? a.files ?? cfg.filePicker)) errors.push(`${where}: needs \`file\` (or \`files\`, or top-level \`filePicker\`)`);
    if (a.type === "drop" && !(a.file ?? a.files ?? a.text != null)) errors.push(`${where}: needs \`file\`, \`files\`, or \`text\``);
    if ((a.type === "type" || a.type === "paste") && typeof a.text !== "string") errors.push(`${where}: needs \`text\``);
    if (a.type === "press" && !a.key) errors.push(`${where}: needs \`key\``);
    if (a.type === "css" && !a.css && !a.remove) errors.push(`${where}: needs \`css\` (or \`remove\`)`);
    if (a.type === "cut" && !(a.url || a.hash || a.script)) errors.push(`${where}: needs \`url\`, \`hash\`, or \`script\``);
    if (a.type === "cut" && !a.label) warnings.push(`${where}: a cut with no \`label\` shows a bare blank that reads as a glitch; add a few words saying where we are going`);
    if (a.type === "scroll" && a.to == null && a.y == null && a.x == null) errors.push(`${where}: needs \`to\`, \`y\`, or \`x\``);
    if (a.frame && a.frame !== "page" && !cfg.frames?.[a.frame]) errors.push(`${where}: frame \`${a.frame}\` is not in \`frames\``);
    if (i < start && TAKE_ONLY.has(a.type)) errors.push(`${where}: only means something during the take — move it after \`mark\``);
    if (i >= start && NO_CURSOR.has(a.type) && !a.allowNoCursor) {
      // A jump right after `mark` with nothing on camera before it is setup
      // that landed on the wrong side of the mark.
      const onCameraBefore = actions.slice(start, i).some((b) => CURSOR.has(b.type) || b.type === "cut");
      const fix = onCameraBefore ? hintFor(a) : "move `mark` below this step (it is setup)";
      errors.push(`${where}: changes the page without the cursor during the take — ${fix}. Or add "allowNoCursor": "<why>".`);
    }
  });
  return { errors, warnings, takeStart: start };
}
