require "test_helper"
require "ferrum"
require "timeout"

module Uml
  module Viewer
    class BrowserTest < TestCase
      def setup
        super
        boot(project_copy)
        @browser = Ferrum::Browser.new(headless: true, timeout: 10)
      end

      def teardown
        @browser&.quit
        shutdown_server
        super
      end

      def boot(project)
        @workspace = Workspace.new(project)
        Graph.prepare(@workspace)
        Graph.build(@workspace)
        @server = Server.new(@workspace).start
        @thread = Thread.new { @server.run }
      end

      def shutdown_server
        @server.shutdown
        @thread.join(2)
      end

      def build_project(files)
        parent = Dir.mktmpdir("uml-viewer-project")
        @project_parents << parent
        dir = File.join(parent, "extra")
        files.each do |relative, content|
          FileUtils.mkdir_p(File.dirname(File.join(dir, relative)))
          File.write(File.join(dir, relative), content)
        end
        dir
      end

      def wait_for(css)
        wait_until(-> { "no element matches #{css}" }) { @browser.at_css(css) }
        @browser.at_css(css)
      end

      def wait_until(message, seconds: 10)
        Timeout.timeout(seconds) { sleep 0.1 until yield }
      rescue Timeout::Error
        flunk message.call
      end

      def wait_for_text(css, text, seconds: 10)
        last = nil
        wait_until(-> { "expected #{css} to include #{text.inspect}, last text: #{last.inspect}" }, seconds: seconds) do
          last = @browser.at_css(css)&.text
          last&.include?(text)
        end
        assert_includes last, text
      end

      def wait_for_queue_size(size)
        wait_until(-> { "queue size stayed #{Mailbox.new(@workspace).size}, expected #{size}" }, seconds: 5) { Mailbox.new(@workspace).size == size }
      end

      def right_click_menu(member_css, op)
        wait_for(member_css).click(mode: :right)
        wait_for(%(#menu button[data-op="#{op}"])).click
      end

      def test_first_screen_shows_kind_and_namespace_boxes_and_a_red_arrow
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        assert @browser.at_css('g.box[data-id="Reports"]')
        assert @browser.at_css("path.arrow.violating")
        refute_includes @browser.current_url, "token="
      end

      def test_right_click_explain_on_a_class_queues_one_command
        @browser.goto(@server.url)
        right_click_menu('text.member[data-id="Order"]', "explain")
        wait_for_queue_size(1)
        command = Mailbox.new(@workspace).peek
        assert_equal ["explain", { "id" => "Order", "kind" => "class", "proposal_id" => nil }], [command["op"], command["target"]]
      end

      def test_right_click_omit_on_a_box_queues_an_omit_for_the_box
        @browser.goto(@server.url)
        right_click_menu('g.box[data-id="Reports"] text.title', "omit")
        wait_for_queue_size(1)
        assert_equal({ "id" => "Reports", "kind" => "box", "proposal_id" => nil }, Mailbox.new(@workspace).peek["target"])
      end

      def test_right_click_on_a_namespace_member_queues_a_box_target
        boot_nested_namespace_project
        @browser.goto(@server.url)
        right_click_menu('text.member[data-kind="namespace"]', "omit")
        wait_for_queue_size(1)
        assert_equal({ "id" => "Shop::Billing", "kind" => "box", "proposal_id" => nil }, Mailbox.new(@workspace).peek["target"])
      end

      def test_status_says_no_agent_and_counts_the_queue
        Mailbox.new(@workspace).append(op: "propose")
        @browser.goto(@server.url)
        wait_for_text("#status", "no agent: 1 commands wait in the queue")
      end

      def test_status_says_watcher_running_when_the_heartbeat_is_fresh
        Mailbox.new(@workspace).append(op: "propose")
        @workspace.write_atomic("agent.json", JSON.generate("heartbeat" => Time.now.to_f))
        @browser.goto(@server.url)
        wait_for_text("#status", "watcher running (1 waiting)")
      end

      def test_status_shows_the_last_failed_command_and_its_reason
        mailbox = Mailbox.new(@workspace)
        id = mailbox.append(op: "propose")
        mailbox.done(id, failed: "no such proposal")
        @browser.goto(@server.url)
        wait_for_text("#status", "command #{id} failed: no such proposal")
      end

      def test_a_scan_error_shows_as_a_banner
        @workspace.write_atomic("policy.yml", "levels: [\n")
        @browser.goto(@server.url)
        wait_for_text("#banner", "policy.yml line")
        wait_for_text("#banner", "; showing last good graph")
      end

      def test_a_graph_that_cannot_be_drawn_keeps_its_banner_through_the_next_polls_and_clears_after_recovery
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        @workspace.write_atomic("graph.json", JSON.generate("title" => "broken"))
        wait_for_text("#banner", "could not draw the graph:")
        sleep 2.5
        assert_includes @browser.at_css("#banner").text, "could not draw the graph:"
        Graph.build(@workspace)
        wait_until(-> { "banner stayed #{@browser.at_css('#banner').text.inspect} after the graph was repaired" }) { @browser.at_css("#banner").text.empty? }
      end

      def test_a_box_of_exactly_fifteen_classes_lists_all_of_them_and_no_more_line
        boot_box_project(15)
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        assert_equal 15, @browser.css('g.box[data-id="folder:models"] text.member').size
        assert_nil @browser.at_css("text.more")
      end

      def test_a_box_of_sixteen_classes_lists_fifteen_and_a_plus_one_more_line
        boot_box_project(16)
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        assert_equal 15, @browser.css('g.box[data-id="folder:models"] text.member').size
        assert_equal "+1 more", @browser.at_css('g.box[data-id="folder:models"] text.more').text
      end

      def test_a_refused_command_shows_the_server_reason_in_a_toast
        @browser.goto(@server.url)
        wait_for('text.member[data-id="Order"]')
        @browser.evaluate('document.querySelector(\'text.member[data-id="Order"]\').dataset.id = "Gone"')
        right_click_menu('text.member[data-id="Gone"]', "explain")
        wait_for_text("#toast", "command not sent: unknown target: Gone")
        assert_equal 0, Mailbox.new(@workspace).size
      end

      def test_a_full_queue_shows_the_queue_full_toast
        mailbox = Mailbox.new(@workspace)
        Mailbox::CAP.times { mailbox.append(op: "propose") }
        @browser.goto(@server.url)
        right_click_menu('text.member[data-id="Order"]', "explain")
        wait_for_text("#toast", "queue full: start Claude or clear the queue")
        assert_equal Mailbox::CAP, mailbox.size
      end

      def test_a_command_to_a_server_that_is_gone_shows_a_not_reachable_toast
        @browser.goto(@server.url)
        wait_for('text.member[data-id="Order"]')
        shutdown_server
        right_click_menu('text.member[data-id="Order"]', "explain")
        wait_for_text("#toast", "command not sent: server not reachable")
      end

      def test_a_wrong_token_shows_the_session_expired_banner
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        @browser.headers.set("X-UML-Token" => "stale")
        wait_for_text("#banner", "session expired: reopen with uml-viewer")
      end

      private

      def boot_box_project(count)
        files = (1..count).to_h { |number| [format("app/models/item%02d.rb", number), "class Item#{format('%02d', number)}\nend\n"] }
        reboot(build_project(files))
      end

      def boot_nested_namespace_project
        reboot(build_project(
          "app/models/shop/customer.rb" => "module Shop\n  class Customer\n  end\nend\n",
          "app/models/shop/billing/invoice.rb" => "module Shop\n  module Billing\n    class Invoice\n    end\n  end\nend\n"
        ))
      end

      def reboot(project)
        shutdown_server
        boot(project)
      end
    end
  end
end
