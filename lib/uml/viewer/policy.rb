module Uml
  module Viewer
    module Policy
      def self.apply(scan, policy)
        namespaces = scan["namespaces"]
        classes = scan["classes"].reject { |entry| omitted?(entry, policy["omit"], namespaces) }
        kept = classes.to_h { |entry| [entry["id"], entry] }
        levels = level_index(policy["levels"])
        classes = classes.map { |entry| entry.merge("level" => levels[entry["kind_folder"]]) }
        by_id = classes.to_h { |entry| [entry["id"], entry] }
        edges = scan["edges"].select { |edge| kept.key?(edge["from"]) && kept.key?(edge["to"]) }
                             .map { |edge| edge.merge("violating" => violating?(edge, by_id)) }
        box_of = classes.to_h { |entry| [entry["id"], box_id(entry, namespaces)] }
        {
          "classes" => classes,
          "edges" => edges,
          "boxes" => boxes(classes, box_of, namespaces, policy["omit"]),
          "arrows" => arrows(edges, box_of)
        }
      end

      def self.omitted?(entry, omit, namespaces)
        id = entry["id"]
        omit.any? { |name| id == name || id.start_with?("#{name}::") || name == "folder:#{entry['kind_folder']}" && !id.include?("::") && !namespaces.include?(id) }
      end

      def self.level_index(levels)
        levels.each_with_index.flat_map { |row, index| row.map { |folder| [folder, index] } }.to_h
      end

      def self.violating?(edge, by_id)
        return false if edge["kind"] == "association"

        from = by_id[edge["from"]]["level"]
        to = by_id[edge["to"]]["level"]
        !from.nil? && !to.nil? && from < to
      end

      def self.box_id(entry, namespaces)
        id = entry["id"]
        return id.split("::").first if id.include?("::")
        return id if namespaces.include?(id)

        "folder:#{entry['kind_folder']}"
      end

      def self.boxes(classes, box_of, namespaces, omit)
        classes.group_by { |entry| box_of[entry["id"]] }.sort.map do |id, members|
          folder = id.start_with?("folder:")
          member_classes = members.select { |entry| folder || entry["id"] == id || entry["id"].split("::").size == 2 }
                                  .map { |entry| { "id" => entry["id"], "type" => "class" } }
          child_namespaces = folder ? [] : namespaces.select { |name| name.start_with?("#{id}::") && name.split("::").size == 2 && !omit.include?(name) }
                                                     .map { |name| { "id" => name, "type" => "namespace" } }
          found = members.map { |entry| entry["level"] }.compact
          {
            "id" => id,
            "label" => folder ? id.delete_prefix("folder:") : id,
            "type" => folder ? "folder" : "namespace",
            "levels" => found.empty? ? nil : [found.min, found.max],
            "members" => (member_classes + child_namespaces).sort_by { |member| member["id"] }
          }
        end
      end

      def self.arrows(edges, box_of)
        edges.group_by { |edge| [box_of[edge["from"]], box_of[edge["to"]]] }
             .reject { |(from, to), _| from == to }
             .sort.map do |(from, to), grouped|
          {
            "from" => from, "to" => to,
            "violating" => grouped.any? { |edge| edge["violating"] },
            "pairs" => grouped.map { |edge| [edge["from"], edge["to"]] }.sort
          }
        end
      end
    end
  end
end
