require "set"

module Uml
  module Viewer
    module Views
      def self.build(classes, namespaces, edges, foreign_edges)
        known = namespaces.to_set
        paths = classes.to_h { |entry| [entry["id"], path(entry, known)] }
        views = { "root" => view("root", nil, nil) }
        classes.each { |entry| place(views, paths[entry["id"]], entry) }
        foreign_edges.map { |edge| edge["to"] }.uniq.each do |name|
          views["root"]["nodes"]["foreign:#{name}"] = { "id" => "foreign:#{name}", "type" => "foreign", "label" => name, "levels" => nil }
        end
        edges.each { |edge| add_arrow(views, paths[edge["from"]], paths[edge["to"]], edge) }
        foreign_edges.each do |edge|
          add_arrow(views, paths[edge["from"]], [["foreign", "foreign:#{edge['to']}"]], edge.merge("violating" => false))
        end
        views.transform_values { |entry| finish(entry, views) }
      end

      def self.path(entry, namespaces)
        segments = entry["id"].split("::")
        containers = (1...segments.size).map { |count| ["namespace", segments.first(count).join("::")] }
        containers << ["namespace", entry["id"]] if namespaces.include?(entry["id"])
        containers = [["folder", "folder:#{entry['kind_folder']}"]] if containers.empty?
        containers + [["class", entry["id"]]]
      end

      def self.view(id, label, parent)
        { "id" => id, "label" => label, "parent" => parent, "nodes" => {}, "arrows" => {} }
      end

      def self.place(views, path, entry)
        parent = "root"
        path.each do |type, id|
          node = views[parent]["nodes"][id] ||= node(type, id, entry)
          node["levels"] = widen(node["levels"], entry["level"])
          next if type == "class"

          views[id] ||= view(id, node["label"], parent)
          parent = id
        end
      end

      def self.node(type, id, entry)
        case type
        when "class"
          { "id" => id, "type" => "class", "label" => id.split("::").last, "stereotype" => entry["stereotype"], "level" => entry["level"], "levels" => nil }
        when "folder" then { "id" => id, "type" => "folder", "label" => id.delete_prefix("folder:"), "levels" => nil }
        else { "id" => id, "type" => "namespace", "label" => id.split("::").last, "levels" => nil }
        end
      end

      def self.widen(levels, level)
        return levels if level.nil?
        return [level, level] if levels.nil?

        [[levels[0], level].min, [levels[1], level].max]
      end

      def self.add_arrow(views, from_path, to_path, edge)
        index = (0...[from_path.size, to_path.size].min).find { |position| from_path[position] != to_path[position] }
        view_id = index.zero? ? "root" : from_path[index - 1][1]
        key = [from_path[index][1], to_path[index][1]]
        arrow = views[view_id]["arrows"][key] ||= { "from" => key[0], "to" => key[1], "violating" => false, "pairs" => [] }
        arrow["violating"] ||= edge["violating"]
        arrow["pairs"] << { "from" => edge["from"], "to" => edge["to"], "kind" => edge["kind"], "violating" => edge["violating"] }
      end

      def self.finish(entry, views)
        nodes = entry["nodes"].values.sort_by { |node| node["id"] }.map do |node|
          next node unless %w[namespace folder].include?(node["type"])

          members = views[node["id"]]["nodes"].values.sort_by { |member| member["id"] }
          node.merge("members" => members.map { |member| member.slice("id", "type", "label") })
        end
        arrows = entry["arrows"].values.sort_by { |arrow| [arrow["from"], arrow["to"]] }
                                .map { |arrow| arrow.merge("pairs" => arrow["pairs"].sort_by { |pair| [pair["from"], pair["to"]] }) }
        entry.merge("nodes" => nodes, "arrows" => arrows)
      end
    end
  end
end
