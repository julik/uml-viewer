# uml-viewer

A live UML diagram of a Ruby or Rails project in the browser. Red arrows break the Dependency Rule. A Claude Code session handles your clicks.

    gem install uml-viewer
    uml-viewer install-skill
    uml-viewer path/to/project

Double-click a box to open it, Esc to go back. Double-click a class for its card; click an op for its source. Hover an arrow for its pairs. Right-click a box or a class to send Explain or Omit to Claude.

Box colors show test quality: green is a good grade, red a poor one, and grey dots mean no data. The class card says why. Run your tests with SimpleCov to get coverage and CRAP; put a mutation snapshot in the state folder (`uml-viewer path`) as `mutation.json` to get M grades.

Proposals regroup the code without changing it. Press "New proposal" or ask Claude for one; Claude writes it into `policy.yml`. A proposal lists components in rank order (the first is level 0); a member is a class id, a namespace or a folder box such as `folder:models`. Choose the proposal in the diagram list to see the code in its components, with red arrows by the proposal's ranks. Classes in no component wait in "Unassigned".

Press `d` or the declutter button to cycle: one arrow per pair, triangles, hide members, hide classes, none.

Nothing is written into the viewed project. State lives in `~/.uml-viewer/projects/`.

To check the skill text itself, `bundle exec rake eval:skill` runs it with `claude -p` on a copy of the fixture project and checks what it changed. It needs a logged-in `claude` and costs a few cents per run; `EVAL_MODEL`, `EVAL_BUDGET` and `EVAL_TIMEOUT` tune it.

The ideas come from unclebob/uml-viewer (Clojure). No code is copied. elkjs (EPL-2.0) is vendored in `lib/uml/viewer/web/`.
