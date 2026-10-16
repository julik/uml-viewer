require "prism"

module Uml
  module Viewer
    class Operations
      VISIBILITIES = %i[public private protected].freeze

      def initialize(program, file)
        @program = program
        @file = file
        @ops = []
      end

      def collect
        scope(@program.statements.body, singleton: false)
        @ops
      end

      private

      def scope(statements, singleton:)
        state = { visibility: "public", named: {}, private_singletons: [], added: [] }
        statements.each { |node| visit(node, state, singleton) }
        state[:added].each { |op, receiver| settle(op, receiver, state) }
      end

      def visit(node, state, singleton)
        case node
        when Prism::DefNode then state[:added] << add(node, state[:visibility], singleton)
        when Prism::ClassNode, Prism::ModuleNode then scope(statements_of(node.body), singleton: false)
        when Prism::SingletonClassNode then scope(statements_of(node.body), singleton: true)
        when Prism::ConstantWriteNode, Prism::ConstantPathWriteNode then scope_block(node.value, singleton: false)
        when Prism::CallNode then visit_call(node, state, singleton)
        end
      end

      def visit_call(node, state, singleton)
        arguments = node.arguments&.arguments
        if node.receiver.nil? && VISIBILITIES.include?(node.name)
          set_visibility(node.name.to_s, arguments, state, singleton)
        elsif node.receiver.nil? && node.name == :private_class_method
          arguments.to_a.each do |argument|
            state[:added] << add(argument, "public", singleton) if argument.is_a?(Prism::DefNode)
            name = argument.is_a?(Prism::DefNode) ? argument.name.to_s : literal(argument)
            state[:private_singletons] << name if name
          end
        else
          scope_block(node, singleton: node.name == :class_methods)
        end
      end

      def set_visibility(visibility, arguments, state, singleton)
        if arguments.nil?
          state[:visibility] = visibility
          return
        end

        arguments.each do |argument|
          if argument.is_a?(Prism::DefNode)
            state[:added] << add(argument, visibility, singleton)
          elsif (name = literal(argument))
            state[:named][name] = visibility
          end
        end
      end

      def settle(op, receiver, state)
        name = op["name"].delete_prefix("self.")
        if receiver
          op["visibility"] = "private" if state[:private_singletons].include?(name)
        elsif state[:named].key?(name)
          op["visibility"] = state[:named][name]
        end
      end

      def add(node, visibility, singleton)
        receiver = !node.receiver.nil?
        op = {
          "name" => receiver || singleton ? "self.#{node.name}" : node.name.to_s,
          "visibility" => receiver ? "public" : visibility,
          "cc" => Complexity.of(node),
          "file" => @file,
          "line_start" => node.location.start_line,
          "line_end" => node.location.end_line
        }
        @ops << op
        [op, receiver]
      end

      def scope_block(node, singleton:)
        return unless node.is_a?(Prism::CallNode) && node.block.is_a?(Prism::BlockNode)

        scope(statements_of(node.block.body), singleton: singleton)
      end

      def statements_of(body)
        body.is_a?(Prism::StatementsNode) ? body.body : []
      end

      def literal(node)
        node.unescaped if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)
      end
    end
  end
end
