module Uml
  module Viewer
    module Proposals
      EXACT = 1_000

      def self.build(proposals, classes:, namespaces:, edges:, foreign_edges:)
        real_paths = Views.paths(classes, namespaces)
        proposals.map { |proposal| view_of(proposal, classes, namespaces, edges, foreign_edges, real_paths) }
      end

      def self.view_of(proposal, classes, namespaces, edges, foreign_edges, real_paths)
        members = members_of(proposal)
        placed = classes.to_h { |entry| [entry["id"], place(entry, proposal["id"], members, namespaces, real_paths[entry["id"]])] }
        kept = classes.reject { |entry| omitted?(entry, placed[entry["id"]][:path], proposal["omit"], namespaces) }
                      .map { |entry| entry.merge("level" => placed[entry["id"]][:rank]) }
        by_id = kept.to_h { |entry| [entry["id"], entry] }
        kept_edges = edges.select { |edge| by_id.key?(edge["from"]) && by_id.key?(edge["to"]) }
                          .map { |edge| edge.merge("violating" => Policy.violating?(edge, by_id)) }
        {
          "id" => proposal["id"],
          "name" => proposal["name"],
          "views" => Views.build(kept, namespaces, kept_edges, foreign_edges.select { |edge| by_id.key?(edge["from"]) },
                                 paths: kept.to_h { |entry| [entry["id"], placed[entry["id"]][:path]] }),
          "warnings" => unmatched(members, classes, namespaces).map { |name| "proposal #{proposal['id']}: member #{name} matches no class in the diagram (check the name and the policy omit)" }
        }
      end

      def self.members_of(proposal)
        list = []
        walk = lambda do |components, chain, rank|
          components.each_with_index do |component, index|
            own_rank = rank || index
            own_chain = chain + [["component", "component:#{proposal['id']}/#{component['id']}", component["label"]]]
            component["members"].each do |member|
              next walk.call([member], own_chain, own_rank) if member.is_a?(Hash)

              list << { name: member, chain: own_chain, rank: own_rank, order: list.size }
            end
          end
        end
        walk.call(proposal["components"], [], nil)
        list
      end

      def self.place(entry, proposal_id, members, namespaces, real_path)
        best = members.filter_map { |member| (score = specificity(member[:name], entry, namespaces)) && [score, -member[:order], member] }
                      .max_by { |score, order, _| [score, order] }
        return { path: [["component", "unassigned:#{proposal_id}", "Unassigned"]] + real_path, rank: nil } if best.nil?

        member = best.last
        below = real_path.select { |type, id| type == "namespace" && id.start_with?("#{member[:name]}::") }
        { path: member[:chain] + below + [real_path.last], rank: member[:rank] }
      end

      def self.specificity(name, entry, namespaces)
        id = entry["id"]
        return EXACT if name == id
        return name.split("::").size if id.start_with?("#{name}::")
        return 0 if name == "folder:#{entry['kind_folder']}" && Policy.top_level?(entry, namespaces)

        nil
      end

      def self.omitted?(entry, path, omit, namespaces)
        omit.any? do |name|
          Policy.omitted_by_name?(entry["id"], [name]) ||
            (name == "folder:#{entry['kind_folder']}" && Policy.top_level?(entry, namespaces)) ||
            path.any? { |_, id| id == name }
        end
      end

      def self.unmatched(members, classes, namespaces)
        members.map { |member| member[:name] }.uniq
               .reject { |name| classes.any? { |entry| specificity(name, entry, namespaces) } }
      end
    end
  end
end
