# uml-viewer

A live UML diagram of a Ruby or Rails project in the browser. Red arrows break the Dependency Rule. A Claude Code session handles your clicks.

    gem build uml-viewer.gemspec && gem install ./uml-viewer-0.1.0.gem
    uml-viewer install-skill
    uml-viewer path/to/project

Double-click a box to open it, Esc to go back. Double-click a class for its card; click an op for its source. Hover an arrow for its pairs. Right-click a box or a class to send Explain or Omit to Claude.

Box colors show test quality: green is a good grade, red a poor one, and grey means no data. The class card says why. Run your tests with SimpleCov to get coverage and CRAP; put a mutation snapshot in the state folder (`uml-viewer path`) as `mutation.json` to get M grades.

Nothing is written into the viewed project. State lives in `~/.uml-viewer/projects/`.

The ideas come from unclebob/uml-viewer (Clojure). No code is copied. elkjs (EPL-2.0) is vendored in `lib/uml/viewer/web/`.
