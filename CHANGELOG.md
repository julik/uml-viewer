# Changelog

All notable changes are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-10-23

### Added
- A box and a member name that open on a double-click show the hand cursor.
- A hovered box gets a border in the text color, and a hovered member name gets a light background behind its line, as in the original tool.
- A double-click beside a member name, on its line, also opens it.
- A click on empty space closes the source panel and the class card.

## [0.1.1] - 2026-10-23

### Changed
- The gem description credits unclebob/uml-viewer by Robert C. Martin (Uncle Bob), as the README does.

## [0.1.0] - 2026-10-23

### Added
- `uml-viewer <project>` scans a Ruby or Rails project with Prism and opens a live UML diagram in the browser. You drill down from folder and namespace boxes to classes and to source lines.
- Levels come from `policy.yml`. A dependency from an inner level to an outer level is a red arrow. Associations are never red.
- Box colors show CRAP from `coverage/.resultset.json` (SimpleCov) and M grades from an optional `mutation.json`. Grey means no data.
- Proposals regroup the code into ranked components without a change to the code.
- Declutter cycles through five modes on the `d` key.
- A right-click sends Explain or Omit to a Claude Code session through a mailbox. `uml-viewer install-skill` installs the skill, and `uml-viewer watch` wakes the session through the Monitor tool.
- State lives in `~/.uml-viewer/projects/`. Nothing is written into the viewed project.
