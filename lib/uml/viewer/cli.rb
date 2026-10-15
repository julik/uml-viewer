require "json"
require "optparse"

module Uml
  module Viewer
    class CLI
      COMMANDS = %w[scan inbox done watch path init install-skill].freeze
      USAGE = "usage: uml-viewer [path] | scan|inbox|watch|path|init [path] | done <id> [path] [--failed reason] | install-skill"

      def initialize(argv, out: $stdout, err: $stderr)
        @argv = argv.dup
        @out = out
        @err = err
      end

      def run
        command = COMMANDS.include?(@argv.first) ? @argv.shift : "open"
        send("run_#{command.tr('-', '_')}")
      rescue Interrupt
        130
      rescue Workspace::MissingProject, PolicyFile::Invalid => error
        @err.puts error.message
        1
      end

      private

      def workspace
        @workspace ||= Workspace.new(@argv.first || ".")
      end

      def run_path
        @out.puts workspace.dir
        0
      end

      def run_init
        policy = workspace.path("policy.yml")
        if File.exist?(policy)
          @out.puts "policy.yml exists: #{policy}"
        else
          Graph.prepare(workspace)
          @out.puts "wrote #{policy}"
        end
        0
      end

      def run_scan
        Graph.prepare(workspace)
        graph = Graph.build(workspace)
        violating = graph["edges"].count { |edge| edge["violating"] }
        @out.puts "#{graph['classes'].size} classes, #{graph['edges'].size} edges, #{violating} violating, " \
                  "skipped #{graph['summary']['skipped'].size} files, no constant"
        @out.puts "unlisted foreign: #{graph['summary']['foreign'].map { |name, count| "#{name} (#{count})" }.join(', ')}"
        0
      end

      def run_inbox
        command = Mailbox.new(workspace).peek
        @out.puts JSON.generate(command) if command
        0
      end

      def run_done
        id, failed = parse_done_arguments
        return usage unless id

        if Mailbox.new(workspace).done(id, failed: failed)
          0
        else
          @err.puts "no command with id #{id}"
          1
        end
      end

      def parse_done_arguments
        failed = nil
        OptionParser.new { |opts| opts.on("--failed REASON") { |reason| failed = reason } }.parse!(@argv)
        [Integer(@argv.shift, 10), failed]
      rescue OptionParser::ParseError, ArgumentError, TypeError
        nil
      end

      def usage
        @err.puts USAGE
        2
      end

      def run_watch
        Watcher.new(workspace).run
      end

      def run_install_skill
        installer = SkillInstaller.new(executable: File.expand_path($PROGRAM_NAME))
        @out.puts "wrote #{installer.install}"
        installer.allowed_tools.each { |rule| @out.puts "  #{rule}" }
        0
      end

      def run_open
        if workspace.server_alive?
          info = workspace.server_info
          url = "http://127.0.0.1:#{info['port']}/?token=#{info['token']}"
          @out.puts "already running at #{url}"
          open_browser(url)
          return 0
        end
        Graph.prepare(workspace)
        Graph.build(workspace)
        server = Server.new(workspace).start
        @out.puts "uml-viewer: #{server.url}"
        open_browser(server.url)
        trap("INT") { Thread.new { server.shutdown } }
        trap("TERM") { Thread.new { server.shutdown } }
        begin
          server.run
        ensure
          server.shutdown
        end
        0
      end

      def open_browser(url)
        system("open", url) unless ENV["UML_VIEWER_NO_BROWSER"] == "1"
      end
    end
  end
end
