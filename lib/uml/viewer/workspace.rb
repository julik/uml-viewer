require "digest"
require "fileutils"
require "json"
require "socket"

module Uml
  module Viewer
    class Workspace
      class MissingProject < StandardError; end

      attr_reader :root, :dir

      def self.home
        File.expand_path(ENV.fetch("UML_VIEWER_HOME") { File.join(Dir.home, ".uml-viewer") })
      end

      def self.pid_alive?(pid)
        pid = Integer(pid)
        return false unless pid.positive?

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, ArgumentError, TypeError
        false
      rescue Errno::EPERM
        true
      end

      def self.port_open?(port)
        Socket.tcp("127.0.0.1", Integer(port), connect_timeout: 0.5).close
        true
      rescue SystemCallError, SocketError, ArgumentError, TypeError
        false
      end

      def initialize(project_path)
        raise MissingProject, "no such project folder: #{project_path}" unless File.directory?(project_path)

        @root = File.realpath(project_path)
        digest = Digest::SHA256.hexdigest(@root)[0, 8]
        @dir = File.join(self.class.home, "projects", "#{File.basename(@root)}-#{digest}")
        FileUtils.mkdir_p(@dir, mode: 0o700)
        File.chmod(0o700, @dir)
      end

      def path(name)
        File.join(@dir, name)
      end

      def write_atomic(name, string)
        target = path(name)
        temp = "#{target}.#{Process.pid}.#{Thread.current.object_id}.tmp"
        File.open(temp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(string) }
        File.rename(temp, target)
      end

      def read_json(name, default)
        JSON.parse(File.read(path(name)))
      rescue Errno::ENOENT
        default
      end

      def server_info
        read_json("server.json", nil)
      rescue JSON::ParserError
        nil
      end

      def server_alive?
        info = server_info
        info.is_a?(Hash) && self.class.pid_alive?(info["pid"]) && self.class.port_open?(info["port"])
      end
    end
  end
end
