require "prism"
require "set"

module Uml
  module Viewer
    class Scanner
      SKIPPED_FOLDERS = %w[app/assets app/views app/javascript app/frontend lib/tasks vendor node_modules tmp test spec].freeze
      DATA_CALLS = { "Data" => :define, "Struct" => :new, "Class" => :new }.freeze

      def self.constant_name(node)
        case node
        when Prism::ConstantReadNode then node.name.to_s
        when Prism::ConstantPathNode then node.full_name
        end
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError, Prism::ConstantPathNode::MissingNodesInConstantPathError
        nil
      end

      def self.qualify(name, nesting)
        return name.delete_prefix("::") if name.start_with?("::") || nesting.empty?

        "#{nesting.last}::#{name}"
      end

      def initialize(root, sources: %w[app lib], skip: [])
        @root = root
        @sources = sources
        @skip = SKIPPED_FOLDERS + skip
      end

      def scan
        files = ruby_files
        parsed = files.to_h { |file| [file, Prism.parse_file(File.join(@root, file))] }
        declarations = parsed.to_h { |file, result| [file, Declarations.new(result.value).collect] }
        classes, aliases, skipped = build_classes(parsed, declarations)
        namespaces = declarations.values.flat_map { |found| found[:namespaces] }.to_set
        resolver = Resolver.new(classes: aliases.keys.to_set, namespaces: namespaces)
        edges, foreign = build_edges(parsed, declarations, aliases, resolver)
        {
          "classes" => classes.values.sort_by { |entry| entry["id"] },
          "namespaces" => namespaces.to_a.sort,
          "edges" => edges,
          "skipped" => skipped.sort,
          "foreign" => foreign.sort_by { |name, count| [-count, name] }.first(20)
        }
      end

      private

      def ruby_files
        @sources.flat_map { |source| Dir.glob("#{source}/**/*.rb", base: @root) }
                .reject { |file| @skip.any? { |folder| file == folder || file.start_with?("#{folder}/") } }
                .sort
      end

      def build_classes(parsed, declarations)
        classes = {}
        aliases = {}
        skipped = []
        parsed.each do |file, result|
          declared = declarations[file][:declared]
          if declared.empty?
            skipped << file
            next
          end
          main = main_constant(file, declared)
          (declared.map { |entry| entry[:id] } + declarations[file][:secondary]).each { |id| aliases[id] = main[:id] }
          if classes.key?(main[:id])
            classes[main[:id]]["files"] << file
          else
            classes[main[:id]] = {
              "id" => main[:id], "file" => file, "files" => [file], "kind_folder" => kind_folder(file),
              "stereotype" => main[:stereotype], "parse_errors" => parse_errors(result)
            }
          end
        end
        classes.each_key { |id| aliases[id] = id }
        [classes, aliases, skipped]
      end

      def main_constant(file, declared)
        base = File.basename(file, ".rb")
        declared.find { |entry| snake(entry[:id].split("::").last) == base } || declared.first
      end

      def snake(name)
        name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      def kind_folder(file)
        parts = file.split("/")
        return "lib" if parts.first == "lib"
        return "app" if parts.size < 3
        return "lib" if parts[1] == "lib"

        parts[1]
      end

      def parse_errors(result)
        result.errors.map { |error| "line #{error.location.start_line}: #{error.message}" }
      end

      def build_edges(parsed, declarations, aliases, resolver)
        pairs = Set.new
        foreign = Hash.new(0)
        parsed.each do |file, result|
          declared = declarations[file][:declared]
          next if declared.empty?

          own = declared.map { |entry| entry[:id] } + declarations[file][:secondary]
          main = main_constant(file, declared)[:id]
          References.new(result.value).collect.each do |reference|
            from = own.include?(reference[:owner]) ? aliases[reference[:owner]] : main
            found = resolver.resolve(reference[:name], nesting: reference[:nesting], enclosing: reference[:nesting].last)
            if found.nil?
              foreign[reference[:name].delete_prefix("::").split("::").first] += 1
            elsif found.first == :class
              to = aliases.fetch(found.last, found.last)
              pairs << [from, to] unless from == to
            end
          end
        end
        edges = pairs.to_a.sort.map { |from, to| { "from" => from, "to" => to, "kind" => "dependency" } }
        [edges, foreign]
      end

      class Declarations
        def initialize(program)
          @program = program
          @declared = []
          @secondary = []
          @namespaces = Set.new
        end

        def collect
          walk(@program.statements.body, [])
          { declared: @declared, secondary: @secondary, namespaces: @namespaces.to_a }
        end

        private

        def walk(statements, nesting)
          statements.each do |node|
            case node
            when Prism::ClassNode, Prism::ModuleNode then declare_scope(node, nesting)
            when Prism::ConstantWriteNode then declare_constant(node, nesting)
            end
          end
        end

        def declare_scope(node, nesting)
          name = Scanner.constant_name(node.constant_path)
          return if name.nil?

          full = Scanner.qualify(name, nesting)
          segments = full.split("::")
          1.upto(segments.size - 1) { |count| @namespaces << segments.first(count).join("::") }
          body = node.body&.body || []
          if wrapper?(body)
            @namespaces << full
          else
            @declared << { id: full, stereotype: stereotype(node, body) }
          end
          walk(body, nesting + [full])
        end

        def declare_constant(node, nesting)
          full = Scanner.qualify(node.name.to_s, nesting)
          if data_call?(node.value)
            @declared << { id: full, stereotype: "data" }
          elsif !nesting.empty?
            @secondary << full
          end
        end

        def wrapper?(body)
          !body.empty? && body.all? do |child|
            child.is_a?(Prism::ClassNode) || child.is_a?(Prism::ModuleNode) ||
              (child.is_a?(Prism::ConstantWriteNode) && data_call?(child.value))
          end
        end

        def data_call?(value)
          value.is_a?(Prism::CallNode) && value.receiver.is_a?(Prism::ConstantReadNode) &&
            DATA_CALLS[value.receiver.name.to_s] == value.name
        end

        def stereotype(node, body)
          return "class" if node.is_a?(Prism::ClassNode)

          concern = body.any? do |child|
            child.is_a?(Prism::CallNode) && child.name == :extend &&
              child.arguments&.arguments&.any? { |argument| Scanner.constant_name(argument) == "ActiveSupport::Concern" }
          end
          concern ? "concern" : "module"
        end
      end

      class References < Prism::Visitor
        def initialize(program)
          @program = program
          @nesting = []
          @found = []
          super()
        end

        def collect
          @program.accept(self)
          @found
        end

        def visit_class_node(node)
          node.superclass&.accept(self)
          enter(node) { node.body&.accept(self) }
        end

        def visit_module_node(node)
          enter(node) { node.body&.accept(self) }
        end

        def visit_constant_read_node(node)
          record(node.name.to_s)
        end

        def visit_constant_path_node(node)
          name = Scanner.constant_name(node)
          name.nil? ? super : record(name)
        end

        private

        def enter(node)
          name = Scanner.constant_name(node.constant_path)
          return yield if name.nil?

          @nesting.push(Scanner.qualify(name, @nesting))
          yield
        ensure
          @nesting.pop unless name.nil?
        end

        def record(name)
          @found << { name: name, nesting: @nesting.dup, owner: @nesting.last }
        end
      end
    end
  end
end
