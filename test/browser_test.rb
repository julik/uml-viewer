require "test_helper"
require "ferrum"
require "timeout"

module Uml
  module Viewer
    class BrowserTest < TestCase
      def setup
        super
        @project = project_copy
        @workspace = Workspace.new(@project)
        Graph.prepare(@workspace)
        Graph.build(@workspace)
        @server = Server.new(@workspace).start
        @thread = Thread.new { @server.run }
        @browser = Ferrum::Browser.new(headless: true, timeout: 10)
      end

      def teardown
        @browser&.quit
        @server.shutdown
        @thread.join(2)
        super
      end

      def wait_for(css)
        Timeout.timeout(10) { sleep 0.1 until @browser.at_css(css) }
        @browser.at_css(css)
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
        member = wait_for('text.member[data-id="Order"]')
        member.click(mode: :right)
        wait_for('#menu button[data-op="explain"]').click
        Timeout.timeout(5) { sleep 0.1 until Mailbox.new(@workspace).size == 1 }
        command = Mailbox.new(@workspace).peek
        assert_equal ["explain", { "id" => "Order", "kind" => "class", "proposal_id" => nil }], [command["op"], command["target"]]
      end

      def test_right_click_omit_on_a_box_queues_an_omit_for_the_box
        @browser.goto(@server.url)
        wait_for('g.box[data-id="Reports"] text.title').click(mode: :right)
        wait_for('#menu button[data-op="omit"]').click
        Timeout.timeout(5) { sleep 0.1 until Mailbox.new(@workspace).size == 1 }
        assert_equal({ "id" => "Reports", "kind" => "box", "proposal_id" => nil }, Mailbox.new(@workspace).peek["target"])
      end

      def test_status_says_no_agent_and_counts_the_queue
        Mailbox.new(@workspace).append(op: "propose")
        @browser.goto(@server.url)
        Timeout.timeout(5) { sleep 0.1 until @browser.at_css("#status")&.text&.include?("no agent: 1 commands wait in the queue") }
      end

      def test_a_scan_error_shows_as_a_banner
        @workspace.write_atomic("policy.yml", "levels: [\n")
        @browser.goto(@server.url)
        Timeout.timeout(8) { sleep 0.1 until @browser.at_css("#banner")&.text&.include?("policy.yml line") }
      end
    end
  end
end
