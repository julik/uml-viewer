require "yaml"

module Uml
  module Viewer
    module PolicyInit
      DEFAULT_LEVELS = [
        %w[models],
        %w[services queries policies lib uploaders validators inputs],
        %w[jobs mailers channels presenters decorators serializers],
        %w[controllers helpers components admin graphql]
      ].freeze
      SKIPPED_KINDS = %w[assets views javascript frontend].freeze
      OMIT_CANDIDATES = %w[ApplicationRecord ApplicationController ApplicationJob ApplicationMailer].freeze

      def self.folder_kinds(root)
        kinds = Dir.glob("app/*/", base: root).map { |folder| File.basename(folder) } - SKIPPED_KINDS
        kinds << "lib" if File.directory?(File.join(root, "lib"))
        kinds.uniq.sort
      end

      def self.write(workspace, class_ids:)
        return false if File.exist?(workspace.path("policy.yml"))

        kinds = folder_kinds(workspace.root)
        levels = DEFAULT_LEVELS.map { |row| row & kinds }.reject(&:empty?)
        unlisted = kinds - DEFAULT_LEVELS.flatten
        policy = {
          "title" => File.basename(workspace.root),
          "sources" => %w[app lib],
          "skip" => [],
          "levels" => levels,
          "foreign" => [],
          "omit" => OMIT_CANDIDATES & class_ids,
          "edge_kinds" => {},
          "omit_edges" => [],
          "proposals" => []
        }
        workspace.write_atomic("policy.yml", with_unlisted_comment(YAML.dump(policy), unlisted))
        true
      end

      def self.with_unlisted_comment(text, unlisted)
        return text if unlisted.empty?

        lines = text.lines
        position = lines.index { |line| line.start_with?("levels:") }
        lines.insert(position + 1, "# not compared: #{unlisted.join(', ')}\n").join
      end
    end
  end
end
