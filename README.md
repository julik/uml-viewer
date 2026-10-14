# uml-viewer

A live UML diagram of a Ruby or Rails project in the browser. Red arrows break the Dependency Rule. A Claude Code session handles your clicks.

    gem build uml-viewer.gemspec && gem install ./uml-viewer-0.1.0.gem
    uml-viewer install-skill
    uml-viewer path/to/project

Nothing is written into the viewed project. State lives in `~/.uml-viewer/projects/`.

The ideas come from unclebob/uml-viewer (Clojure). No code is copied. elkjs (EPL-2.0) is vendored in `lib/uml/viewer/web/`.
