require "prism"

module Uml
  module Viewer
    module Complexity
      BRANCHES = [
        Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode, Prism::WhenNode,
        Prism::InNode, Prism::RescueNode, Prism::RescueModifierNode, Prism::AndNode, Prism::OrNode
      ].freeze
      SHORT_CIRCUIT_WRITES = Prism.constants.grep(/(And|Or)WriteNode\z/).map { |name| Prism.const_get(name) }.freeze

      def self.of(definition)
        1 + count(definition.body)
      end

      def self.count(node)
        return 0 if node.nil?

        (branch?(node) ? 1 : 0) + node.compact_child_nodes.sum { |child| count(child) }
      end

      def self.branch?(node)
        BRANCHES.include?(node.class) || SHORT_CIRCUIT_WRITES.include?(node.class) ||
          (node.respond_to?(:safe_navigation?) && node.safe_navigation?)
      end
    end
  end
end
