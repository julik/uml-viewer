module Uml
  module Viewer
    module Policy
      def self.apply(scan, policy)
        omit = policy["omit"]
        classes = scan["classes"].reject { |entry| omitted_by_name?(entry["id"], omit) }
        namespaces = scan["namespaces"].select { |name| classes.any? { |entry| entry["id"].start_with?("#{name}::") } }
        classes = classes.reject { |entry| omit.include?("folder:#{entry['kind_folder']}") && top_level?(entry, namespaces) }
        levels = level_index(policy["levels"])
        classes = classes.map { |entry| entry.merge("level" => levels[entry["kind_folder"]]) }
        by_id = classes.to_h { |entry| [entry["id"], entry] }
        edges = scan["edges"].select { |edge| by_id.key?(edge["from"]) && by_id.key?(edge["to"]) }
        edges = adjust_edges(edges, policy["edge_kinds"], policy["omit_edges"])
                .map { |edge| edge.merge("violating" => violating?(edge, by_id)) }
        foreign_edges = scan["foreign_edges"].select { |edge| policy["foreign"].include?(edge["to"]) && by_id.key?(edge["from"]) }
        proposals = Proposals.build(policy["proposals"], classes: classes, namespaces: namespaces, edges: edges, foreign_edges: foreign_edges)
        {
          "classes" => classes,
          "edges" => edges,
          "namespaces" => namespaces,
          "views" => Views.build(classes, namespaces, edges, foreign_edges),
          "foreign_edges" => foreign_edges,
          "proposals" => proposals,
          "warnings" => (policy["levels"].flatten.uniq - scan["folders"]).map { |name| "levels: unknown folder #{name}" } +
                        proposals.flat_map { |proposal| proposal["warnings"] }
        }
      end

      def self.omitted_by_name?(id, omit)
        omit.any? { |name| id == name || id.start_with?("#{name}::") }
      end

      def self.top_level?(entry, namespaces)
        !entry["id"].include?("::") && !namespaces.include?(entry["id"])
      end

      def self.adjust_edges(edges, edge_kinds, omit_edges)
        edges.reject { |edge| omit_edges.include?(pair_key(edge)) }
             .map { |edge| edge_kinds.key?(pair_key(edge)) ? edge.merge("kind" => edge_kinds[pair_key(edge)], "kinds" => [edge_kinds[pair_key(edge)]]) : edge }
      end

      def self.pair_key(edge)
        "#{edge['from']} -> #{edge['to']}"
      end

      def self.level_index(levels)
        levels.each_with_index.flat_map { |row, index| row.map { |folder| [folder, index] } }.to_h
      end

      def self.violating?(edge, by_id)
        from = by_id[edge["from"]]["level"]
        to = by_id[edge["to"]]["level"]
        return false if from.nil? || to.nil? || from >= to

        edge["kinds"].any? { |kind| kind != "association" }
      end
    end
  end
end
