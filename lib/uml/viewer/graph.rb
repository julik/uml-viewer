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
          "version" => 1,
          "title" => policy["title"].to_s.empty? ? File.basename(workspace.root) : policy["title"],
          "namespaces" => scan["namespaces"],
          "proposals" => policy["proposals"],
          "summary" => { "classes" => applied["classes"].size, "skipped" => scan["skipped"], "foreign" => scan["foreign"] }
        }.merge(applied)
        workspace.write_atomic("graph.json", JSON.generate(graph))
        graph
      end

      def self.ids(graph)
        Set.new(graph["classes"].map { |entry| entry["id"] } + graph["boxes"].map { |box| box["id"] } + graph["namespaces"])
      end
    end
  end
end
