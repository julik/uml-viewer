(() => {
  const params = new URLSearchParams(location.search);
  const token = params.get("token") || sessionStorage.getItem("uml-token");
  if (params.get("token")) {
    sessionStorage.setItem("uml-token", params.get("token"));
    history.replaceState(null, "", location.pathname);
  }
  const svg = document.getElementById("diagram");
  const menu = document.getElementById("menu");
  const banner = document.getElementById("banner");
  const crumbs = document.getElementById("crumbs");
  const popup = document.getElementById("popup");
  const choice = document.getElementById("proposal");
  const BOXES = ["namespace", "folder", "component"];
  const DECLUTTER = ["none", "one arrow per pair", "triangles", "hide members", "hide classes"];
  const declutterButton = document.getElementById("declutter");
  const NS = "http://www.w3.org/2000/svg";
  const LINE = 16;
  const MAX_MEMBERS = 15;
  const ZOOM_STEP = 1.25;
  let graph = null;
  let graphTime = null;
  let drawError = null;
  let scanError = null;
  let drawing = false;
  let menuTarget = null;
  let drill = ["root"];
  let zoom = 1;
  let size = { width: 0, height: 0 };
  let pendingScroll = null;
  let saveTimer = null;
  let pendingView = null;
  let dirty = false;
  let currentArrows = [];
  let proposalId = null;
  let declutter = 0;
  const scrolls = {};

  const api = (path, options = {}) =>
    fetch(path, { ...options, headers: { "X-UML-Token": token, "Content-Type": "application/json", ...(options.headers || {}) } });

  const el = (name, attrs = {}, parent = svg) => {
    const node = document.createElementNS(NS, name);
    Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
    parent.appendChild(node);
    return node;
  };

  const levelText = (levels) => (levels ? (levels[0] === levels[1] ? `${levels[0]}` : `${levels[0]}..${levels[1]}`) : "");

  const hue = (grade) => Math.round(((grade - 1) / 9) * 120);
  const hasGrade = (grade) => grade !== null && grade !== undefined;
  const boxFill = (grade) => (hasGrade(grade) ? `hsl(${hue(grade)}, 55%, var(--grade-l))` : "var(--box)");
  const dotFill = (grade) => (hasGrade(grade) ? `hsl(${hue(grade)}, 65%, 45%)` : "var(--muted)");
  const proposalOf = (id) => (graph.proposals || []).find((proposal) => proposal.id === id);
  const views = () => (proposalId && proposalOf(proposalId) ? proposalOf(proposalId).views : graph.views);

  const chain = (id) => {
    const ids = [];
    for (let view = views()[id]; view; view = views()[view.parent]) ids.unshift(view.id);
    return ids;
  };

  const settleDrill = () => {
    const existing = [...drill].reverse().find((id) => views()[id]) || "root";
    drill = chain(existing);
  };

  const memberLines = (node) => {
    const members = declutter >= 3 ? [] : node.members || [];
    const lines = members.slice(0, MAX_MEMBERS).map((member) => ({ id: member.id, kind: member.type, text: (BOXES.includes(member.type) ? "▸ " : "") + member.label }));
    if (members.length > MAX_MEMBERS) lines.push({ more: true, text: `+${members.length - MAX_MEMBERS} more` });
    return lines;
  };

  const pairArrows = (arrows) => {
    const merged = new Map();
    arrows.forEach((arrow) => {
      const key = [arrow.from, arrow.to].sort().join("\n");
      const seen = merged.get(key);
      merged.set(key, seen
        ? { ...seen, both: true, violating: seen.violating || arrow.violating, pairs: [...seen.pairs, ...arrow.pairs] }
        : { ...arrow, both: false });
    });
    return [...merged.values()];
  };

  const showDeclutter = () => {
    declutterButton.textContent = `declutter: ${DECLUTTER[declutter]}`;
  };

  const cycleDeclutter = () => {
    declutter = (declutter + 1) % DECLUTTER.length;
    showDeclutter();
    render();
    saveSession();
  };

  const caption = (node) => (node.type === "class" && node.stereotype !== "class" ? `«${node.stereotype}» ` : "") + node.label;

  const sized = (node) => {
    const lines = memberLines(node);
    const title = caption(node);
    const width = 24 + 7.4 * Math.max(title.length + 6, ...lines.map((line) => line.text.length));
    return { node, lines, title, width, height: 40 + LINE * lines.length };
  };

  const showBanner = () => {
    const coverage = graph && graph.summary && graph.summary.coverage && graph.summary.coverage.banner;
    banner.textContent = drawError || (scanError ? `${scanError}; showing last good graph` : "") || coverage || "";
  };

  const expired = () => {
    banner.textContent = "session expired: reopen with uml-viewer";
  };

  const applyZoom = () => {
    svg.setAttribute("viewBox", `0 0 ${size.width} ${size.height}`);
    svg.setAttribute("width", size.width * zoom);
    svg.setAttribute("height", size.height * zoom);
  };

  const saveSession = () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      api("/session", { method: "PUT", body: JSON.stringify({ drill, zoom, scroll: { x: scrollX, y: scrollY }, proposal: proposalId, declutter }) }).catch(() => {});
    }, 1000);
  };

  const renderCrumbs = () => {
    crumbs.replaceChildren(...drill.map((id, index) => {
      const crumb = document.createElement("button");
      crumb.className = "crumb";
      crumb.dataset.id = id;
      crumb.textContent = id === "root" ? (proposalId ? proposalOf(proposalId).name : graph.title) : views()[id].label;
      crumb.disabled = index === drill.length - 1;
      return crumb;
    }));
  };

  const drawNode = (placed, { node, lines, title }) => {
    const group = el("g", { class: `box ${node.type}`, "data-id": node.id, "data-type": node.type, transform: `translate(${placed.x + 20},${placed.y + 20})` });
    if (node.type === "foreign") {
      el("ellipse", { cx: placed.width / 2, cy: placed.height / 2, rx: placed.width / 2, ry: placed.height / 2 }, group);
      el("text", { class: "title", x: placed.width / 2, y: placed.height / 2 + 4, "text-anchor": "middle" }, group).textContent = title;
      return;
    }
    group.setAttribute("data-grade", hasGrade(node.grade) ? node.grade : "");
    el("rect", { width: placed.width, height: placed.height, rx: 4, style: `fill: ${boxFill(node.grade)}` }, group);
    [["c", node.c_grade], ["m", node.m_grade]].forEach(([kind, grade], index) => {
      el("circle", { class: `dot ${kind}`, cx: placed.width - 26 + 12 * index, cy: placed.height - 8, r: 4, "data-grade": hasGrade(grade) ? grade : "", style: `fill: ${dotFill(grade)}` }, group);
    });
    el("text", { class: "title", x: 10, y: 18 }, group).textContent = title;
    el("text", { class: "level", x: placed.width - 10, y: 18, "text-anchor": "end" }, group).textContent = levelText(node.levels);
    lines.forEach((line, index) => {
      const attrs = { x: 14, y: 36 + LINE * index, class: line.more ? "more" : "member" };
      if (!line.more) Object.assign(attrs, { "data-id": line.id, "data-kind": line.kind });
      el("text", attrs, group).textContent = line.text;
    });
  };

  function drawArrow(edge, arrow, index) {
    (edge.sections || []).forEach((section) => {
      const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint];
      const d = points.map((point, i) => `${i ? "L" : "M"}${point.x + 20},${point.y + 20}`).join(" ");
      el("path", { class: `arrow${arrow.violating ? " violating" : ""}${arrow.both ? " both" : ""}`, d });
      el("path", { class: `hit${arrow.violating ? " violating" : ""}`, d, "data-index": index, "data-from": arrow.from, "data-to": arrow.to });
    });
  }

  async function draw() {
    settleDrill();
    renderCrumbs();
    const view = views()[drill[drill.length - 1]];
    const shown = declutter >= 4 ? view.nodes.filter((node) => node.type !== "class") : view.nodes;
    const ids = new Set(shown.map((node) => node.id));
    const kept = view.arrows.filter((arrow) => ids.has(arrow.from) && ids.has(arrow.to));
    const arrows = declutter >= 1 ? pairArrows(kept) : kept;
    const nodes = shown.map(sized);
    const top = Math.max(0, ...shown.flatMap((node) => node.levels || [])) + 1;
    const layout = await new ELK().layout({
      id: "root",
      layoutOptions: {
        "elk.algorithm": "layered", "elk.direction": "UP", "elk.edgeRouting": "ORTHOGONAL",
        "elk.partitioning.activate": "true", "elk.spacing.nodeNode": "40", "elk.layered.spacing.nodeNodeBetweenLayers": "60"
      },
      children: nodes.map(({ node, width, height }) => ({
        id: node.id, width, height,
        layoutOptions: { "elk.partitioning.partition": String(node.levels ? node.levels[0] : top) }
      })),
      edges: arrows.map((arrow, index) => ({ id: `a${index}`, sources: [arrow.from], targets: [arrow.to] }))
    });
    currentArrows = arrows;
    svg.replaceChildren();
    svg.classList.toggle("triangles", declutter >= 2);
    const defs = el("defs");
    [["head", "var(--line)"], ["head-red", "var(--red)"]].forEach(([id, color]) => {
      const marker = el("marker", { id, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto-start-reverse" }, defs);
      el("path", { d: "M0,0 L10,5 L0,10 z", fill: color }, marker);
    });
    const hidesAll = !shown.length && view.nodes.length > 0;
    size = hidesAll ? { width: 560, height: 60 } : { width: layout.width + 40, height: layout.height + 40 };
    applyZoom();
    if (hidesAll) el("text", { class: "note", x: 20, y: 34 }).textContent = `declutter hides all ${view.nodes.length} classes in this view: press d`;
    const byId = Object.fromEntries(nodes.map((entry) => [entry.node.id, entry]));
    layout.children.forEach((placed) => drawNode(placed, byId[placed.id]));
    (layout.edges || []).forEach((edge, index) => drawArrow(edge, arrows[index], index));
    if (pendingScroll) {
      scrollTo(pendingScroll.x, pendingScroll.y);
      pendingScroll = null;
    }
  }

  async function render() {
    if (drawing) {
      dirty = true;
      return;
    }
    drawing = true;
    dirty = false;
    try {
      await draw();
      drawError = null;
    } catch (error) {
      drawError = `could not draw the graph: ${error.message}`;
    } finally {
      drawing = false;
    }
    showBanner();
    const id = pendingView;
    pendingView = null;
    if (id) openView(id);
    if (dirty && !drawing) render();
  }

  async function loadGraph() {
    const response = await api("/graph.json");
    if (response.status === 403) {
      expired();
      return false;
    }
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    graph = await response.json();
    return true;
  }

  const showStatus = (version) => {
    const alive = version.agent && Date.now() / 1000 - version.agent < 10;
    const failed = version.failed ? ` · command ${version.failed.id} failed: ${version.failed.reason}` : "";
    document.getElementById("status").textContent =
      (alive ? `watcher running (${version.queue} waiting)` : `no agent: ${version.queue} commands wait in the queue`) + failed;
  };

  function renderChoice() {
    if (proposalId && !proposalOf(proposalId)) {
      toast(`proposal ${proposalId} is gone: showing the real diagram`);
      proposalId = null;
      drill = ["root"];
      saveSession();
    }
    choice.replaceChildren(...[{ id: "", name: "Real diagram" }, ...(graph.proposals || [])].map((proposal) => {
      const option = document.createElement("option");
      option.value = proposal.id;
      option.textContent = proposal.name;
      return option;
    }));
    choice.value = proposalId || "";
  }

  async function poll() {
    let version;
    try {
      const response = await api("/version");
      if (response.status === 403) return expired();
      version = await response.json();
    } catch (error) {
      banner.textContent = "server not reachable";
      return;
    }
    showStatus(version);
    scanError = version.error;
    if (version.graph !== graphTime && !drawing) {
      try {
        if (!(await loadGraph())) return;
        graphTime = version.graph;
        renderChoice();
        await render();
      } catch (error) {
        drawError = error instanceof TypeError ? "server not reachable" : `could not draw the graph: ${error.message}`;
      }
    }
    showBanner();
  }

  const openView = (id) => {
    if (!graph || !views()[id]) return;
    if (drawing) {
      pendingView = id;
      return;
    }
    scrolls[drill[drill.length - 1]] = { x: scrollX, y: scrollY };
    drill = chain(id);
    pendingScroll = scrolls[id] || { x: 0, y: 0 };
    render();
    saveSession();
  };

  function toast(text) {
    const node = document.getElementById("toast");
    node.textContent = text;
    setTimeout(() => { if (node.textContent === text) node.textContent = ""; }, 4000);
  }

  const SIGNS = { public: "+", private: "-", protected: "#" };

  const append = (parent, tag, text, className) => {
    const node = document.createElement(tag);
    node.textContent = text;
    if (className) node.className = className;
    parent.appendChild(node);
    return node;
  };

  function openCard(id) {
    const entry = graph && graph.classes.find((item) => item.id === id);
    if (!entry) return toast(`class ${id} is not in the graph`);
    const card = document.getElementById("card");
    card.replaceChildren();
    append(card, "h2", entry.id);
    const level = entry.level === null || entry.level === undefined ? "no level" : `${proposalId ? "real level" : "level"} ${entry.level}`;
    append(card, "p", `«${entry.stereotype}» · ${entry.kind_folder} · ${level}`);
    append(card, "p", entry.crap ? `C grade ${entry.crap.grade} (mu ${entry.crap.mu.toFixed(1)}, sigma ${entry.crap.sigma.toFixed(1)})` : "C grade: no data", "grade c");
    append(card, "p", entry.mutation ? `M grade ${entry.mutation.grade} (score ${Math.round(entry.mutation.score * 100)}%)` : "M grade: no data", "grade m");
    (entry.coverage_notes || []).forEach((note) => append(card, "p", note, "note coverage"));
    entry.files.forEach((file) => append(card, "p", file, "file"));
    if (entry.parse_errors.length) {
      append(card, "h3", "parse errors", "error");
      entry.parse_errors.forEach((error) => append(card, "p", error, "error"));
    }
    const list = append(card, "ul", "");
    entry.ops.forEach((op) => {
      const metrics = hasGrade(op.coverage) ? `  cov ${Math.round(op.coverage * 100)}%  crap ${op.crap.toFixed(1)}` : "";
      const item = append(list, "li", `${SIGNS[op.visibility]} ${op.name}  cc ${op.cc}${metrics}`, "op");
      item.dataset.file = op.file;
      item.dataset.line = op.line_start;
    });
    append(card, "p", "static scan: dynamic references (constantize, send) are not seen", "note");
    card.hidden = false;
  }

  async function openSource(file, line) {
    const panel = document.getElementById("source");
    panel.replaceChildren();
    append(panel, "h2", `${file}:${line}`);
    panel.hidden = false;
    let response;
    try {
      response = await api(`/source?file=${encodeURIComponent(file)}&line=${line}`);
    } catch (error) {
      return append(panel, "p", "server not reachable", "error");
    }
    const body = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    if (!response.ok) return append(panel, "p", body.error, "error");
    const pre = append(panel, "pre", "");
    body.text.split("\n").forEach((text, index) => {
      append(pre, "div", `${String(index + 1).padStart(4)}  ${text}`, index + 1 === line ? "line current" : "line");
    });
    pre.querySelector(".current")?.scrollIntoView({ block: "center" });
  }

  document.getElementById("card").addEventListener("click", (event) => {
    const op = event.target.closest("li.op");
    if (op) openSource(op.dataset.file, Number(op.dataset.line));
  });

  svg.addEventListener("mouseover", (event) => {
    const hit = event.target.closest("path.hit");
    if (!hit) return;
    const arrow = currentArrows[Number(hit.dataset.index)];
    if (!arrow) return;
    popup.replaceChildren();
    arrow.pairs.forEach((pair) => append(popup, "div", `${pair.from} -> ${pair.to} (${pair.kinds.join(", ")})`, pair.violating ? "pair violating" : "pair"));
    popup.style.left = `${event.clientX + 12}px`;
    popup.style.top = `${event.clientY + 12}px`;
    popup.hidden = false;
  });

  svg.addEventListener("mouseout", (event) => {
    if (event.target.closest("path.hit")) popup.hidden = true;
  });

  document.getElementById("regen").addEventListener("click", async () => {
    try {
      const response = await api("/scans", { method: "POST" });
      if (response.status !== 202) toast(`rescan not started: HTTP ${response.status}`);
    } catch (error) {
      toast("rescan not started: server not reachable");
    }
  });

  function openMenu(x, y) {
    menu.classList.add("open");
    const { width, height } = menu.getBoundingClientRect();
    menu.style.left = `${Math.max(0, Math.min(x, innerWidth - width - 4))}px`;
    menu.style.top = `${Math.max(0, Math.min(y, innerHeight - height - 4))}px`;
  }

  function onKey(event) {
    if (event.key === "Escape" && menu.classList.contains("open")) {
      menu.classList.remove("open");
      return;
    }
    if (event.key === "Escape") {
      const source = document.getElementById("source");
      const card = document.getElementById("card");
      if (!source.hidden) {
        source.hidden = true;
        return;
      }
      if (!card.hidden) {
        card.hidden = true;
        return;
      }
    }
    if (event.key === "Escape" && drill.length > 1) {
      openView(drill[drill.length - 2]);
      return;
    }
    if (event.key === "d" && !event.ctrlKey && !event.metaKey && !event.altKey && !["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement?.tagName)) {
      cycleDeclutter();
      return;
    }
    if ((event.ctrlKey || event.metaKey) && ["=", "+", "-", "0"].includes(event.key)) {
      event.preventDefault();
      zoom = event.key === "0" ? 1 : event.key === "-" ? zoom / ZOOM_STEP : zoom * ZOOM_STEP;
      applyZoom();
      saveSession();
    }
  }

  function onDoubleClick(event) {
    const member = event.target.closest("text.member");
    const box = event.target.closest("g.box");
    if (member && BOXES.includes(member.dataset.kind)) return openView(member.dataset.id);
    if (!member && box && BOXES.includes(box.dataset.type)) return openView(box.dataset.id);
    if (member && member.dataset.kind === "class") return openCard(member.dataset.id);
    if (!member && box && box.dataset.type === "class") return openCard(box.dataset.id);
  }

  svg.addEventListener("dblclick", (event) => onDoubleClick(event));
  document.addEventListener("keydown", (event) => onKey(event));
  crumbs.addEventListener("click", (event) => {
    const crumb = event.target.closest("button.crumb");
    if (crumb && !crumb.disabled) openView(crumb.dataset.id);
  });
  addEventListener("scroll", saveSession);

  svg.addEventListener("contextmenu", (event) => {
    const member = event.target.closest("text.member");
    const box = event.target.closest("g.box");
    if (!member && (!box || box.dataset.type === "foreign")) return;
    event.preventDefault();
    const type = member ? member.dataset.kind : box.dataset.type;
    menuTarget = { id: member ? member.dataset.id : box.dataset.id, kind: type === "class" ? "class" : "box", proposal_id: proposalId };
    openMenu(event.clientX, event.clientY);
  });

  async function sendCommand(body) {
    let response;
    try {
      response = await api("/commands", { method: "POST", body: JSON.stringify(body) });
    } catch (error) {
      toast("command not sent: server not reachable");
      return;
    }
    if (response.status === 201) return;
    const reply = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    toast(response.status === 429 ? reply.error : `command not sent: ${reply.error}`);
  }

  menu.addEventListener("click", (event) => {
    const op = event.target.dataset.op;
    menu.classList.remove("open");
    if (op && menuTarget) sendCommand({ op, target: menuTarget });
  });

  choice.addEventListener("change", () => {
    proposalId = choice.value || null;
    drill = ["root"];
    pendingScroll = { x: 0, y: 0 };
    render();
    saveSession();
    sendCommand({ op: "context", target: { proposal_id: proposalId } });
    choice.blur();
  });

  document.getElementById("propose").addEventListener("click", () => sendCommand({ op: "propose" }));
  declutterButton.addEventListener("click", cycleDeclutter);

  document.addEventListener("click", (event) => { if (!menu.contains(event.target)) menu.classList.remove("open"); });

  const restore = (session) => {
    if (Array.isArray(session.drill) && session.drill.length) drill = session.drill;
    if (typeof session.zoom === "number" && session.zoom > 0) zoom = session.zoom;
    if (session.scroll) pendingScroll = session.scroll;
    if (typeof session.proposal === "string") proposalId = session.proposal;
    if (Number.isInteger(session.declutter) && session.declutter >= 0 && session.declutter < DECLUTTER.length) declutter = session.declutter;
  };

  async function start() {
    if (!token) return expired();
    try {
      const response = await api("/session");
      if (response.ok) restore(await response.json().catch(() => ({})));
    } catch (error) {
      banner.textContent = "server not reachable";
    }
    showDeclutter();
    poll();
    setInterval(poll, 1000);
  }

  start();
})();
