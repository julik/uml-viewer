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

  const api = (path, options = {}) =>
    fetch(path, { ...options, headers: { "X-UML-Token": token, "Content-Type": "application/json", ...(options.headers || {}) } });

  const el = (name, attrs = {}, parent = svg) => {
    const node = document.createElementNS(NS, name);
    Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
    parent.appendChild(node);
    return node;
  };

  const levelText = (levels) => (levels ? (levels[0] === levels[1] ? `${levels[0]}` : `${levels[0]}..${levels[1]}`) : "");

  const chain = (id) => {
    const ids = [];
    for (let view = graph.views[id]; view; view = graph.views[view.parent]) ids.unshift(view.id);
    return ids;
  };

  const settleDrill = () => {
    const existing = [...drill].reverse().find((id) => graph.views[id]) || "root";
    drill = chain(existing);
  };

  const memberLines = (node) => {
    const members = node.members || [];
    const lines = members.slice(0, MAX_MEMBERS).map((member) => ({ id: member.id, kind: member.type, text: (member.type === "namespace" ? "▸ " : "") + member.label }));
    if (members.length > MAX_MEMBERS) lines.push({ more: true, text: `+${members.length - MAX_MEMBERS} more` });
    return lines;
  };

  const caption = (node) => (node.type === "class" && node.stereotype !== "class" ? `«${node.stereotype}» ` : "") + node.label;

  const sized = (node) => {
    const lines = memberLines(node);
    const title = caption(node);
    const width = 24 + 7.4 * Math.max(title.length + 6, ...lines.map((line) => line.text.length));
    return { node, lines, title, width, height: 30 + LINE * lines.length };
  };

  const showBanner = () => {
    banner.textContent = drawError || (scanError ? `${scanError}; showing last good graph` : "");
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
      api("/session", { method: "PUT", body: JSON.stringify({ drill, zoom, scroll: { x: scrollX, y: scrollY } }) }).catch(() => {});
    }, 1000);
  };

  const renderCrumbs = () => {
    crumbs.replaceChildren(...drill.map((id, index) => {
      const crumb = document.createElement("button");
      crumb.className = "crumb";
      crumb.dataset.id = id;
      crumb.textContent = id === "root" ? graph.title : graph.views[id].label;
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
    el("rect", { width: placed.width, height: placed.height, rx: 4 }, group);
    el("text", { class: "title", x: 10, y: 18 }, group).textContent = title;
    el("text", { class: "level", x: placed.width - 10, y: 18, "text-anchor": "end" }, group).textContent = levelText(node.levels);
    lines.forEach((line, index) => {
      const attrs = { x: 14, y: 36 + LINE * index, class: line.more ? "more" : "member" };
      if (!line.more) Object.assign(attrs, { "data-id": line.id, "data-kind": line.kind });
      el("text", attrs, group).textContent = line.text;
    });
  };

  function drawArrow(edge, arrow) {
    (edge.sections || []).forEach((section) => {
      const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint];
      const d = points.map((point, i) => `${i ? "L" : "M"}${point.x + 20},${point.y + 20}`).join(" ");
      const path = el("path", { class: `arrow${arrow.violating ? " violating" : ""}`, d });
      el("title", {}, path).textContent = arrow.pairs.map((pair) => `${pair.from} -> ${pair.to} (${pair.kind})`).join("\n");
    });
  }

  async function draw() {
    settleDrill();
    renderCrumbs();
    const view = graph.views[drill[drill.length - 1]];
    const nodes = view.nodes.map(sized);
    const top = Math.max(0, ...view.nodes.flatMap((node) => node.levels || [])) + 1;
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
      edges: view.arrows.map((arrow, index) => ({ id: `a${index}`, sources: [arrow.from], targets: [arrow.to] }))
    });
    svg.replaceChildren();
    const defs = el("defs");
    [["head", "var(--line)"], ["head-red", "var(--red)"]].forEach(([id, color]) => {
      const marker = el("marker", { id, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto" }, defs);
      el("path", { d: "M0,0 L10,5 L0,10 z", fill: color }, marker);
    });
    size = { width: layout.width + 40, height: layout.height + 40 };
    applyZoom();
    const byId = Object.fromEntries(nodes.map((entry) => [entry.node.id, entry]));
    layout.children.forEach((placed) => drawNode(placed, byId[placed.id]));
    (layout.edges || []).forEach((edge, index) => drawArrow(edge, view.arrows[index], index));
    if (pendingScroll) {
      scrollTo(pendingScroll.x, pendingScroll.y);
      pendingScroll = null;
    }
  }

  async function render() {
    if (drawing) return;
    drawing = true;
    try {
      await draw();
      drawError = null;
    } catch (error) {
      drawError = `could not draw the graph: ${error.message}`;
    } finally {
      drawing = false;
    }
    showBanner();
    if (pendingView) {
      const id = pendingView;
      pendingView = null;
      openView(id);
    }
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
        await render();
      } catch (error) {
        drawError = error instanceof TypeError ? "server not reachable" : `could not draw the graph: ${error.message}`;
      }
    }
    showBanner();
  }

  const openView = (id) => {
    if (!graph || !graph.views[id]) return;
    if (drawing) {
      pendingView = id;
      return;
    }
    drill = chain(id);
    render();
    saveSession();
  };

  function toast(text) {
    const node = document.getElementById("toast");
    node.textContent = text;
    setTimeout(() => { if (node.textContent === text) node.textContent = ""; }, 4000);
  }

  function openMenu(x, y) {
    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;
    menu.classList.add("open");
  }

  function onKey(event) {
    if (event.key === "Escape" && drill.length > 1) {
      openView(drill[drill.length - 2]);
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
    if (member && member.dataset.kind === "namespace") return openView(member.dataset.id);
    if (!member && box && ["namespace", "folder"].includes(box.dataset.type)) return openView(box.dataset.id);
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
    menuTarget = { id: member ? member.dataset.id : box.dataset.id, kind: type === "class" ? "class" : "box", proposal_id: null };
    openMenu(event.clientX, event.clientY);
  });

  menu.addEventListener("click", async (event) => {
    const op = event.target.dataset.op;
    menu.classList.remove("open");
    if (!op || !menuTarget) return;
    let response;
    try {
      response = await api("/commands", { method: "POST", body: JSON.stringify({ op, target: menuTarget }) });
    } catch (error) {
      return toast("command not sent: server not reachable");
    }
    if (response.status !== 201) {
      const body = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
      toast(response.status === 429 ? body.error : `command not sent: ${body.error}`);
    }
  });

  document.addEventListener("click", (event) => { if (!menu.contains(event.target)) menu.classList.remove("open"); });

  const restore = (session) => {
    if (Array.isArray(session.drill) && session.drill.length) drill = session.drill;
    if (typeof session.zoom === "number" && session.zoom > 0) zoom = session.zoom;
    if (session.scroll) pendingScroll = session.scroll;
  };

  async function start() {
    if (!token) return expired();
    try {
      const response = await api("/session");
      if (response.ok) restore(await response.json().catch(() => ({})));
    } catch (error) {
      banner.textContent = "server not reachable";
    }
    poll();
    setInterval(poll, 1000);
  }

  start();
})();
