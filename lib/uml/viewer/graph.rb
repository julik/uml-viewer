require "json"
require "set"

module Uml
  module Viewer
    module Graph
      def self.prepare(workspace)
        return if File.exist?(workspace.path("policy.yml"))

        scan = Scanner.new(workspace.root).scan
        PolicyInit.write(workspace, class_ids: scan["classes"].map { |entry| entry["id"] })
      end

      def self.build(workspace)
        policy = PolicyFile.load(workspace.path("policy.yml"))
        scan = Scanner.new(workspace.root, sources: policy["sources"], skip: policy["skip"]).scan
        applied = Policy.apply(scan, policy)
        graph = {
          "version" => 2,
          "title" => policy["title"].empty? ? File.basename(workspace.root) : policy["title"],
          "proposals" => policy["proposals"],
          "summary" => summary(scan, applied, policy),
          "namespaces" => applied["namespaces"],
          "classes" => applied["classes"],
          "edges" => applied["edges"],
          "views" => applied["views"]
        }
        workspace.write_atomic("graph.json", JSON.generate(graph))
        graph
      end

      def self.summary(scan, applied, policy)
        {
          "classes" => applied["classes"].size,
          "skipped" => scan["skipped"],
          "foreign" => scan["foreign"].reject { |name, _| policy["foreign"].include?(name) }.first(20),
          "unresolved" => scan["unresolved"],
          "polymorphic" => scan["polymorphic"],
          "warnings" => applied["warnings"] + scan["unreadable"].map { |file| "unreadable file: #{file}" }
        }
      end

      def self.ids(graph)
        boxes = graph["views"].values.flat_map { |view| view["nodes"] }
                              .select { |node| %w[namespace folder].include?(node["type"]) }.map { |node| node["id"] }
        { "class" => Set.new(graph["classes"].map { |entry| entry["id"] }), "box" => Set.new(boxes) }
      end

      def self.inputs(workspace)
        sources = begin
          PolicyFile.load(workspace.path("policy.yml"))["sources"]
        rescue PolicyFile::Invalid
          PolicyFile::DEFAULTS["sources"]
        end
        files = sources.flat_map { |source| Dir.glob("#{source}/**/*.rb", base: workspace.root) }
        ([workspace.path("policy.yml")] + files.map { |file| File.join(workspace.root, file) }).to_h { |path| [path, mtime(path)] }
      end

      def self.mtime(path)
        File.mtime(path).to_f
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
