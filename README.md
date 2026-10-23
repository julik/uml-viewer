# uml-viewer

A live UML diagram of a Ruby or Rails project in the browser. Red arrows break the Dependency Rule. A Claude Code session handles your clicks.

> Based on the ideas of [unclebob/uml-viewer](https://github.com/unclebob/uml-viewer) by Robert C. Martin (Uncle Bob), a Clojure tool. This gem reuses its ideas and its observed behavior for Ruby and Rails. No code is copied.

## Install

```sh
gem install uml-viewer
uml-viewer install-skill
uml-viewer path/to/project
```

`install-skill` installs the Claude Code skill that handles the clicks from the diagram. Nothing is written into the viewed project. State lives in `~/.uml-viewer/projects/`.

## Navigate

- Double-click a box to open it. Press `Esc` to go back.
- Double-click a class to open its card. Click an operation to see its source.
- Hover an arrow to see the class pairs behind it.
- Right-click a box or a class to send **Explain** or **Omit** to Claude.

## Test quality

Box colors show test quality: green is a good grade, red is a poor grade, and grey dots mean no data. The class card says why.

- **Coverage and CRAP:** run your tests with [SimpleCov](https://github.com/simplecov-ruby/simplecov). The viewer reads `coverage/.resultset.json` in the project.
- **Mutation grades:** put a mutation snapshot as `mutation.json` in the state folder. `uml-viewer path` prints that folder.

## Proposals

Proposals regroup the code without a change to the code.

1. Press **New proposal**, or ask Claude for one. Claude writes it into `policy.yml`.
2. A proposal lists components in rank order. The first component is level 0.
3. A member is a class id, a namespace, or a folder box such as `folder:models`.
4. Choose the proposal in the diagram list. The diagram shows the code in its components, with red arrows by the ranks of the proposal.

Classes in no component wait in **Unassigned**.

## Declutter

Press `d` or the declutter button to cycle through five modes: one arrow per pair, triangles, hide members, hide classes, none.

## Check the skill

```sh
bundle exec rake eval:skill
```

This runs the skill with `claude -p` on a copy of the fixture project and checks what it changed. It needs a logged-in `claude` and costs a few cents per run. `EVAL_MODEL`, `EVAL_BUDGET` and `EVAL_TIMEOUT` tune it.

## Credits and licence

- The ideas come from [unclebob/uml-viewer](https://github.com/unclebob/uml-viewer) by Robert C. Martin. No code is copied.
- [elkjs](https://github.com/kieler/elkjs) (EPL-2.0) does the layout. It is vendored in `lib/uml/viewer/web/`.
- uml-viewer is released under the [MIT licence](LICENSE).
