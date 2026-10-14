require "test_helper"

module Uml
  module Viewer
    class MailboxTest < TestCase
      def mailbox
        @mailbox ||= Mailbox.new(Workspace.new(fixture))
      end

      def test_append_peek_and_done_work_in_order
        first = mailbox.append(op: "explain", target: { "id" => "Order", "kind" => "class", "proposal_id" => nil })
        second = mailbox.append(op: "propose")
        assert_equal [1, 2], [first, second]
        assert_equal "explain", mailbox.peek["op"]
        mailbox.done(first)
        assert_equal second, mailbox.peek["id"]
      end

      def test_peek_without_done_shows_the_same_command_again
        mailbox.append(op: "propose")
        assert_equal mailbox.peek, mailbox.peek
        assert_equal 1, mailbox.size
      end

      def test_done_twice_changes_nothing
        id = mailbox.append(op: "propose")
        mailbox.append(op: "propose")
        mailbox.done(id)
        mailbox.done(id)
        assert_equal 1, mailbox.size
      end

      def test_done_failed_removes_the_command_and_logs_the_reason
        id = mailbox.append(op: "omit", target: { "id" => "Gone", "kind" => "class", "proposal_id" => nil })
        nxt = mailbox.append(op: "propose")
        mailbox.done(id, failed: "target gone")
        assert_equal nxt, mailbox.peek["id"]
        assert_equal({ "id" => id, "op" => "omit", "reason" => "target gone" }, mailbox.last_failed.slice("id", "op", "reason"))
        assert_equal %w[id op reason at], mailbox.last_failed.keys
      end

      def test_done_with_a_missing_id_and_a_reason_logs_nothing
        mailbox.append(op: "propose")
        mailbox.done(99, failed: "x")
        assert_nil mailbox.last_failed
        refute File.exist?(Workspace.new(fixture).path("failed.json"))
        assert_equal 1, mailbox.size
      end

      def test_mutating_the_returned_queue_does_not_change_later_reads
        mailbox.queue << { "id" => 7 }
        assert_empty mailbox.queue
      end

      def test_peek_on_an_empty_queue_returns_nil_and_writes_nothing
        assert_nil mailbox.peek
        refute File.exist?(Workspace.new(fixture).path("to-agent.json"))
      end

      def test_the_queue_refuses_a_command_at_the_cap
        Mailbox::CAP.times { mailbox.append(op: "propose") }
        error = assert_raises(Mailbox::QueueFull) { mailbox.append(op: "propose") }
        assert_equal "queue full: start Claude or clear the queue", error.message
        assert_equal Mailbox::CAP, mailbox.size
      end

      def test_ids_keep_growing_after_the_queue_empties
        mailbox.done(mailbox.append(op: "propose"))
        assert_equal 2, mailbox.append(op: "propose")
      end

      def test_a_command_without_a_target_has_no_target_key
        mailbox.append(op: "propose")
        assert_equal %w[id op at], mailbox.peek.keys
      end

      def test_state_files_have_mode_0600
        id = mailbox.append(op: "propose")
        mailbox.done(id, failed: "gone")
        workspace = Workspace.new(fixture)
        modes = %w[to-agent.json failed.json to-agent.lock].map { |name| File.stat(workspace.path(name)).mode & 0o777 }
        assert_equal [0o600] * 3, modes
      end

      def test_two_processes_appending_200_each_give_400_distinct_ids
        stub_const_cap = "Uml::Viewer::Mailbox.send(:remove_const, :CAP); Uml::Viewer::Mailbox.const_set(:CAP, 1000)"
        script = "require 'uml/viewer'; #{stub_const_cap}; m = Uml::Viewer::Mailbox.new(Uml::Viewer::Workspace.new(ARGV[0])); 200.times { m.append(op: 'propose') }"
        pids = 2.times.map { Process.spawn({ "UML_VIEWER_HOME" => @home }, RbConfig.ruby, "-Ilib", "-e", script, fixture) }
        pids.each { |pid| Process.wait(pid) }
        ids = mailbox.queue.map { |command| command["id"] }
        assert_equal 400, ids.uniq.size
      end

      def test_done_while_another_process_appends_loses_no_command
        count = 50
        script = "require 'uml/viewer'; m = Uml::Viewer::Mailbox.new(Uml::Viewer::Workspace.new(ARGV[0])); #{count}.times { m.append(op: 'propose') }"
        pid = Process.spawn({ "UML_VIEWER_HOME" => @home }, RbConfig.ruby, "-Ilib", "-e", script, fixture)
        handled = []
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
        finished = false
        until (finished && mailbox.peek.nil?) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          finished = true if Process.wait(pid, Process::WNOHANG)
          command = mailbox.peek
          next unless command

          mailbox.done(command["id"])
          handled << command["id"]
        end
        Process.wait(pid) unless finished
        remaining = mailbox.queue.map { |command| command["id"] }
        assert_equal (1..count).to_a, (handled + remaining).sort
      end
    end
  end
end
