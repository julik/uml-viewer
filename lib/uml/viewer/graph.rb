require "json"
require "set"
require "time"

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
        files = applied["classes"].flat_map { |entry| entry["files"] }.uniq
        coverage, coverage_error = load_coverage(workspace, files)
        mutation, mutation_error = load_mutation(workspace)
        overlay = Overlay.apply(applied["classes"], coverage: coverage, mutation: mutation, cutoffs: policy["crap_cutoffs"],
                                                    mtimes: files.to_h { |file| [file, mtime(File.join(workspace.root, file))] },
                                                    missing_note: coverage_error || Overlay::NO_COVERAGE)
        summary = summary(scan, applied, policy)
        summary["coverage"] = overlay["coverage"].merge("banner" => coverage_error || overlay["coverage"]["banner"])
        summary["warnings"] += [mutation_error].compact
        graph = {
          "version" => 2,
          "title" => policy["title"].empty? ? File.basename(workspace.root) : policy["title"],
          "proposals" => policy["proposals"],
          "summary" => summary,
          "namespaces" => applied["namespaces"],
          "classes" => overlay["classes"],
          "edges" => applied["edges"],
          "views" => Overlay.boxes(applied["views"], overlay["classes"], policy["crap_cutoffs"])
        }
        workspace.write_atomic("graph.json", JSON.generate(graph))
        graph
      end

      def self.load_coverage(workspace, files)
        [Coverage.load(workspace.root, files), nil]
      rescue Coverage::Unreadable => error
        [nil, error.message]
      end

      def self.load_mutation(workspace)
        path = workspace.path("mutation.json")
        return [nil, nil] unless File.exist?(path)

        data = JSON.parse(File.read(path))
        mutation_snapshot?(data) ? [data, nil] : [nil, "mutation snapshot unreadable: #{path}"]
      rescue JSON::ParserError, SystemCallError
        [nil, "mutation snapshot unreadable: #{path}"]
      end

      def self.mutation_snapshot?(data)
        data.is_a?(Hash) && data.values.all? do |entry|
          entry.is_a?(Hash) && Overlay::COUNTS.all? { |key| !entry.key?(key) || (entry[key].is_a?(Integer) && entry[key] >= 0) }
        end
      end

      def self.coverage_line(coverage)
        return "coverage: none" if coverage["time"].nil?

        "coverage: #{coverage['files']} of #{coverage['scanned']} files from #{Time.at(coverage['time']).utc.iso8601}"
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
        extra = [File.join(workspace.root, "coverage", ".resultset.json"), workspace.path("mutation.json")]
        ([workspace.path("policy.yml")] + extra + files.map { |file| File.join(workspace.root, file) }).to_h { |path| [path, mtime(path)] }
      end

      def self.mtime(path)
        File.mtime(path).to_f
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
