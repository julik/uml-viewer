(() => {
  const params = new URLSearchParams(location.search);
  const token = params.get("token") || sessionStorage.getItem("uml-token");
  if (params.get("token")) {
    sessionStorage.setItem("uml-token", params.get("token"));
    history.replaceState(null, "", location.pathname);
  }
  const svg = document.getElementById("diagram");
  const menu = document.getElementById("menu");
  const NS = "http://www.w3.org/2000/svg";
  const LINE = 16;
  const MAX_MEMBERS = 15;
  let graphTime = null;
  let menuTarget = null;

  const api = (path, options = {}) =>
    fetch(path, { ...options, headers: { "X-UML-Token": token, "Content-Type": "application/json", ...(options.headers || {}) } });

  const el = (name, attrs = {}, parent = svg) => {
    const node = document.createElementNS(NS, name);
    Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
    parent.appendChild(node);
    return node;
  };

  const shortName = (id) => id.split("::").pop();

  const boxLines = (box) => {
    const shown = box.members.slice(0, MAX_MEMBERS);
    const lines = shown.map((member) => ({ id: member.id, kind: member.type, text: (member.type === "namespace" ? "▸ " : "") + shortName(member.id) }));
    if (box.members.length > MAX_MEMBERS) lines.push({ more: true, text: `+${box.members.length - MAX_MEMBERS} more` });
    return lines;
  };

  const levelText = (levels) => (levels ? (levels[0] === levels[1] ? `${levels[0]}` : `${levels[0]}..${levels[1]}`) : "");

  async function draw(graph) {
    document.getElementById("title").textContent = graph.title;
    const boxes = graph.boxes.map((box) => {
      const lines = boxLines(box);
      const width = 24 + 7.4 * Math.max(box.label.length + 6, ...lines.map((line) => line.text.length));
      return { box, lines, width, height: 30 + LINE * lines.length };
    });
    const layout = await new ELK().layout({
      id: "root",
      layoutOptions: {
        "elk.algorithm": "layered", "elk.direction": "UP", "elk.edgeRouting": "ORTHOGONAL",
        "elk.partitioning.activate": "true", "elk.spacing.nodeNode": "40", "elk.layered.spacing.nodeNodeBetweenLayers": "60"
      },
      children: boxes.map(({ box, width, height }) => ({
        id: box.id, width, height,
        layoutOptions: { "elk.partitioning.partition": String(box.levels ? box.levels[0] : 0) }
      })),
      edges: graph.arrows.map((arrow, index) => ({ id: `a${index}`, sources: [arrow.from], targets: [arrow.to] }))
    });
    svg.replaceChildren();
    const defs = el("defs");
    [["head", "var(--line)"], ["head-red", "var(--red)"]].forEach(([id, color]) => {
      const marker = el("marker", { id, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto" }, defs);
      el("path", { d: "M0,0 L10,5 L0,10 z", fill: color }, marker);
    });
    svg.setAttribute("width", layout.width + 40);
    svg.setAttribute("height", layout.height + 40);
    const byId = Object.fromEntries(boxes.map((entry) => [entry.box.id, entry]));
    layout.children.forEach((node) => {
      const { box, lines } = byId[node.id];
      const group = el("g", { class: `box ${box.type}`, "data-id": box.id, transform: `translate(${node.x + 20},${node.y + 20})` });
      el("rect", { width: node.width, height: node.height, rx: 4 }, group);
      el("text", { class: "title", x: 10, y: 18 }, group).textContent = box.label;
      el("text", { class: "level", x: node.width - 10, y: 18, "text-anchor": "end" }, group).textContent = levelText(box.levels);
      lines.forEach((line, index) => {
        const attrs = { x: 14, y: 36 + LINE * index, class: line.more ? "more" : "member" };
        if (!line.more) Object.assign(attrs, { "data-id": line.id, "data-kind": line.kind });
        el("text", attrs, group).textContent = line.text;
      });
    });
    (layout.edges || []).forEach((edge, index) => {
      const arrow = graph.arrows[index];
      (edge.sections || []).forEach((section) => {
        const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint];
        const d = points.map((point, i) => `${i ? "L" : "M"}${point.x + 20},${point.y + 20}`).join(" ");
        const path = el("path", { class: `arrow${arrow.violating ? " violating" : ""}`, d });
        el("title", {}, path).textContent = arrow.pairs.map((pair) => pair.join(" -> ")).join("\n");
      });
    });
  }

  async function refresh() {
    const response = await api("/graph.json");
    if (response.status === 403) return expired();
    await draw(await response.json());
  }

  function expired() {
    document.getElementById("banner").textContent = "session expired: reopen with uml-viewer";
  }

  async function poll() {
    try {
      const response = await api("/version");
      if (response.status === 403) return expired();
      const version = await response.json();
      const alive = version.agent && Date.now() / 1000 - version.agent < 10;
      document.getElementById("status").textContent = alive
        ? `watcher running (${version.queue} waiting)`
        : `no agent: ${version.queue} commands wait in the queue`;
      const failed = version.failed ? ` · command ${version.failed.id} failed: ${version.failed.reason}` : "";
      document.getElementById("status").textContent += failed;
      document.getElementById("banner").textContent = version.error ? `${version.error}; showing last good graph` : "";
      if (version.graph !== graphTime) {
        graphTime = version.graph;
        await refresh();
      }
    } catch (error) {
      document.getElementById("banner").textContent = "server not reachable";
    }
  }

  function toast(text) {
    const node = document.getElementById("toast");
    node.textContent = text;
    setTimeout(() => { if (node.textContent === text) node.textContent = ""; }, 4000);
  }

  svg.addEventListener("contextmenu", (event) => {
    const member = event.target.closest("text.member");
    const box = event.target.closest("g.box");
    if (!member && !box) return;
    event.preventDefault();
    menuTarget = member
      ? { id: member.dataset.id, kind: member.dataset.kind === "namespace" ? "box" : "class", proposal_id: null }
      : { id: box.dataset.id, kind: "box", proposal_id: null };
    menu.style.left = `${event.clientX}px`;
    menu.style.top = `${event.clientY}px`;
    menu.classList.add("open");
  });

  menu.addEventListener("click", async (event) => {
    const op = event.target.dataset.op;
    menu.classList.remove("open");
    if (!op || !menuTarget) return;
    const response = await api("/commands", { method: "POST", body: JSON.stringify({ op, target: menuTarget }) });
    if (response.status !== 201) {
      const body = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
      toast(response.status === 429 ? body.error : `command not sent: ${body.error}`);
    }
  });

  document.addEventListener("click", (event) => { if (!menu.contains(event.target)) menu.classList.remove("open"); });

  poll();
  setInterval(poll, 1000);
})();
