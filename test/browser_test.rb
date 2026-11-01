require "test_helper"
require "ferrum"
require "yaml"
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

      def press(key, ctrl: false)
        @browser.evaluate(%(document.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, ctrlKey: #{ctrl} }))))
      end

      def click(css)
        wait_for(css).click
      end

      def double_click(css)
        wait_for(css).click(mode: :double)
      end

      def crumbs
        @browser.css("#crumbs button.crumb").map(&:text)
      end

      def box_y(id)
        @browser.at_css(%(g.box[data-id="#{id}"])).attribute("transform")[/translate\([\d.]+,([\d.]+)\)/, 1].to_f
      end

      def slow_down_layouts(milliseconds)
        @browser.evaluate(<<~JS)
          (() => {
            window.layouts = 0;
            const layout = ELK.prototype.layout;
            ELK.prototype.layout = function (...args) {
              window.layouts += 1;
              return new Promise((resolve) => setTimeout(resolve, #{milliseconds})).then(() => layout.apply(this, args));
            };
          })()
        JS
      end

      def delay_graph_fetches(milliseconds)
        @browser.evaluate(<<~JS)
          (() => {
            window.graphFetches = 0;
            const original = window.fetch;
            window.fetch = (url, ...rest) => {
              if (!String(url).includes("/graph.json")) return original(url, ...rest);
              window.graphFetches += 1;
              return new Promise((resolve) => setTimeout(resolve, #{milliseconds})).then(() => original(url, ...rest));
            };
          })()
        JS
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

      def test_a_poll_during_a_slow_layout_starts_no_second_layout
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        slow_down_layouts(2500)
        Graph.build(@workspace)
        wait_until(-> { "the changed graph never started a layout" }) { @browser.evaluate("window.layouts").positive? }
        sleep 3.5
        assert_equal 1, @browser.evaluate("window.layouts")
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
        @browser.evaluate('document.querySelectorAll(\'text.member[data-id="Order"], rect.wash[data-id="Order"]\').forEach((node) => { node.dataset.id = "Gone"; })')
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

      def test_double_click_on_a_namespace_box_opens_its_view_and_escape_goes_back
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
        press("Escape")
        wait_for('g.box[data-id="folder:models"]')
        assert_equal ["rails_shapes"], crumbs
      end

      def test_double_click_on_a_namespace_member_opens_that_view_with_its_parents_in_the_crumbs
        boot_nested_namespace_project
        @browser.goto(@server.url)
        double_click('text.member[data-id="Shop::Billing"]')
        wait_for('g.box.class[data-id="Shop::Billing::Invoice"]')
        assert_equal ["extra", "Shop", "Billing"], crumbs
        press("Escape")
        wait_for('g.box.namespace[data-id="Shop::Billing"]')
      end

      def test_opening_a_view_starts_at_the_top_left_and_escape_returns_to_the_scroll_of_the_view_left
        reboot(build_project((1..30).to_h { |number| [format("app/models/ns%02d/item.rb", number), "module Ns#{format('%02d', number)}\n  class Item\n  end\nend\n"] }))
        @browser.goto(@server.url)
        wait_for('g.box[data-id="Ns30"]')
        4.times { press("=", ctrl: true) }
        @browser.evaluate("scrollTo(400, 300)")
        wait_until(-> { "the first screen did not scroll: #{@browser.evaluate('[scrollX, scrollY]')}" }) { @browser.evaluate("[scrollX, scrollY]") == [400, 300] }
        @browser.evaluate(%(document.querySelector('g.box[data-id="Ns01"] text.title').dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))))
        wait_for('g.box.class[data-id="Ns01::Item"]')
        assert_equal [0, 0], @browser.evaluate("[scrollX, scrollY]")
        press("Escape")
        wait_for('g.box[data-id="Ns30"]')
        wait_until(-> { "scroll stayed at #{@browser.evaluate('[scrollX, scrollY]')}" }) { @browser.evaluate("[scrollX, scrollY]") == [400, 300] }
      end

      def test_a_crumb_opens_its_view
        boot_nested_namespace_project
        @browser.goto(@server.url)
        double_click('text.member[data-id="Shop::Billing"]')
        wait_for('g.box.class[data-id="Shop::Billing::Invoice"]')
        @browser.at_css('#crumbs button.crumb[data-id="root"]').click
        wait_for('g.box.namespace[data-id="Shop"]')
      end

      def test_the_open_view_survives_a_graph_change
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        File.write(File.join(@workspace.root, "app/services/reports/late.rb"), "module Reports\n  class Late\n  end\nend\n")
        Graph.build(@workspace)
        wait_for('g.box.class[data-id="Reports::Late"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def test_a_reload_without_the_token_in_the_url_draws_the_page_and_restores_the_open_view
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        wait_until(-> { "session.json never held the open view" }) do
          File.exist?(@workspace.path("session.json")) && JSON.parse(File.read(@workspace.path("session.json")))["drill"] == ["root", "Reports"]
        end
        @browser.goto("http://127.0.0.1:#{@server.port}/")
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal "", @browser.at_css("#banner").text
      end

      def test_a_saved_view_that_no_longer_exists_opens_its_nearest_parent
        @workspace.write_atomic("session.json", JSON.generate("drill" => ["root", "Reports", "Reports::Gone"]))
        @browser.goto(@server.url)
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def test_a_page_without_any_token_says_the_session_expired
        @browser.goto("http://127.0.0.1:#{@server.port}/")
        wait_for_text("#banner", "session expired: reopen with uml-viewer")
      end

      def test_ctrl_plus_zooms_in_and_ctrl_zero_resets
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        width = @browser.at_css("#diagram").attribute("width").to_f
        press("=", ctrl: true)
        wait_until(-> { "the diagram did not zoom in" }) { (@browser.at_css("#diagram").attribute("width").to_f - width * 1.25).abs < 0.5 }
        press("0", ctrl: true)
        wait_until(-> { "the zoom did not reset" }) { (@browser.at_css("#diagram").attribute("width").to_f - width).abs < 0.5 }
      end

      def test_a_box_without_a_level_sits_above_the_boxes_with_levels
        reboot(build_project("app/models/order.rb" => "class Order\nend\n", "app/workers/sync.rb" => "class Sync\n  def run = Order.first\nend\n"))
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:workers"]')
        assert_operator box_y("folder:workers"), :<, box_y("folder:models")
      end

      def test_a_listed_foreign_name_is_an_oval_on_the_first_screen
        reboot(build_project("app/models/order.rb" => "class Order\n  def dump = JSON.generate({})\nend\n"))
        @workspace.write_atomic("policy.yml", File.read(@workspace.path("policy.yml")).sub(/^foreign:.*$/, "foreign: [JSON]"))
        Graph.build(@workspace)
        @browser.goto(@server.url)
        wait_for('g.box.foreign[data-id="foreign:JSON"] ellipse')
        assert_equal "JSON", @browser.at_css('g.box.foreign[data-id="foreign:JSON"] text.title').text
        assert @browser.at_css("path.arrow")
      end

      def test_a_project_without_classes_draws_an_empty_diagram_without_an_error
        reboot(build_project("lib/scripts/run_once.rb" => "puts 1\n"))
        @browser.goto(@server.url)
        wait_until(-> { "the title crumb never showed" }) { crumbs == ["extra"] }
        assert_equal "", @browser.at_css("#banner").text
        assert_empty @browser.css("g.box")
      end

      def test_a_double_click_during_a_slow_layout_opens_the_view_when_the_layout_ends
        @browser.goto(@server.url)
        wait_for('g.box[data-id="Reports"]')
        slow_down_layouts(2000)
        Graph.build(@workspace)
        wait_until(-> { "the changed graph never started a layout" }) { @browser.evaluate("window.layouts").positive? }
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def test_a_view_opened_while_the_graph_is_fetched_shows_the_new_graph_when_the_fetch_ends
        @browser.goto(@server.url)
        wait_for('g.box[data-id="Reports"]')
        slow_down_layouts(1500)
        delay_graph_fetches(800)
        File.write(File.join(@workspace.root, "app/services/reports/late.rb"), "module Reports\n  class Late\n  end\nend\n")
        Graph.build(@workspace)
        wait_until(-> { "the changed graph was never fetched" }) { @browser.evaluate("window.graphFetches").positive? }
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        wait_for('g.box.class[data-id="Reports::Late"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def test_a_corrupt_saved_view_opens_the_first_screen_without_an_error
        @workspace.write_atomic("session.json", "{")
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        assert_equal "", @browser.at_css("#banner").text
      end

      def test_a_failed_graph_fetch_says_server_not_reachable
        @browser.network.intercept
        @browser.on(:request) { |request| request.url.include?("/graph.json") ? request.abort : request.continue }
        @browser.goto(@server.url)
        wait_for_text("#banner", "server not reachable")
        refute_includes @browser.at_css("#banner").text, "Failed to fetch"
      end

      def op_texts
        @browser.css("#card li.op").map(&:text)
      end

      def cursor(css)
        @browser.evaluate("getComputedStyle(document.querySelector(#{css.to_json})).cursor")
      end

      def test_boxes_and_names_that_open_on_a_click_show_the_hand_cursor
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        assert_equal "pointer", cursor('g.box[data-id="folder:models"] rect')
        assert_equal "pointer", cursor('g.box[data-id="Reports"] rect')
        assert_equal "pointer", cursor('text.member[data-id="Order"]')
        double_click('g.box[data-id="folder:models"] text.title')
        wait_for('g.box.class[data-id="Order"]')
        assert_equal "pointer", cursor('g.box.class[data-id="Order"] rect')
      end

      def test_a_foreign_oval_that_opens_nothing_keeps_the_default_cursor_and_border_on_hover
        reboot(build_project("app/models/order.rb" => "class Order\n  def dump = JSON.generate({})\nend\n"))
        @workspace.write_atomic("policy.yml", File.read(@workspace.path("policy.yml")).sub(/^foreign:.*$/, "foreign: [JSON]"))
        Graph.build(@workspace)
        @browser.goto(@server.url)
        wait_for('g.box.foreign[data-id="foreign:JSON"] ellipse')
        assert_equal "auto", cursor('g.box.foreign[data-id="foreign:JSON"] ellipse')
        before = style_of('g.box.foreign[data-id="foreign:JSON"] ellipse', "stroke")
        hover('g.box.foreign[data-id="foreign:JSON"] text.title')
        assert_equal before, style_of('g.box.foreign[data-id="foreign:JSON"] ellipse', "stroke")
      end

      def style_of(css, property)
        @browser.evaluate("getComputedStyle(document.querySelector(#{css.to_json})).#{property}")
      end

      def color_of(token)
        @browser.evaluate(<<~JS)
          (() => { const probe = document.createElement("div"); probe.style.color = "var(#{token})"; document.body.append(probe); const color = getComputedStyle(probe).color; probe.remove(); return color; })()
        JS
      end

      def hover(css)
        x, y = @browser.evaluate("(() => { const box = document.querySelector(#{css.to_json}).getBoundingClientRect(); return [box.x + box.width / 2, box.y + box.height / 2]; })()")
        @browser.mouse.move(x: x, y: y)
      end

      def open_models_view
        @browser.goto(@server.url)
        double_click('g.box[data-id="folder:models"] text.title')
        wait_for('g.box.class[data-id="Order"]')
      end

      def test_hovering_a_class_box_draws_its_border_in_the_text_color
        open_models_view
        refute_equal color_of("--fg"), style_of('g.box.class[data-id="Order"] rect', "stroke")
        hover('g.box.class[data-id="Order"] text.title')
        assert_equal color_of("--fg"), style_of('g.box.class[data-id="Order"] rect', "stroke")
      end

      def test_a_member_line_has_no_border_or_fill_until_it_is_hovered
        @browser.goto(@server.url)
        wait_for('rect.wash[data-id="Order"]')
        assert_equal "none", style_of('rect.wash[data-id="Order"]', "stroke")
        assert_equal "rgba(0, 0, 0, 0)", style_of('rect.wash[data-id="Order"]', "fill")
        hover('text.member[data-id="Order"]')
        assert_equal color_of("--hl"), style_of('rect.wash[data-id="Order"]', "fill")
      end

      def test_a_click_on_the_wash_beside_a_name_opens_that_class
        @browser.goto(@server.url)
        wait_for('rect.wash[data-id="Order"]')
        @browser.evaluate(%(document.querySelector('rect.wash[data-id="Order"]').dispatchEvent(new MouseEvent("click", { bubbles: true }))))
        wait_for_text("#card h2", "Order")
      end

      def test_a_single_click_on_a_class_opens_its_card_with_ops_level_and_files
        @browser.goto(@server.url)
        click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        assert_includes @browser.at_css("#card").text, "«class» · models · level 0"
        assert_equal ["app/models/order.rb"], @browser.css("#card p.file").map(&:text)
        assert_includes op_texts, "+ total  cc 1"
        assert_includes @browser.at_css("#card").text, "static scan: dynamic references (constantize, send) are not seen"
      end

      def test_the_card_shows_each_visibility_sign
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        click('g.box.class[data-id="Reports::Exporter"] text.title')
        wait_for_text("#card h2", "Reports::Exporter")
        ["+ self.build  cc 1", "- self.secret  cc 1", "+ run  cc 2", "# rows  cc 1", "- format  cc 1"].each do |text|
          assert_includes op_texts, text
        end
      end

      def test_the_card_of_a_broken_file_shows_its_parse_errors
        @browser.goto(@server.url)
        click('text.member[data-id="Broken"]')
        wait_for("#card h3.error")
        assert_match(/\Aline \d+: /, @browser.at_css("#card p.error").text)
      end

      def test_a_click_on_an_op_opens_the_source_at_its_line
        @browser.goto(@server.url)
        click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        @browser.css("#card li.op").find { |op| op.text.start_with?("+ total") }.click
        wait_for_text("#source h2", "app/models/order.rb:7")
        assert_includes @browser.at_css("#source .line.current").text, "def total = Order.sum(:amount)"
      end

      def test_a_refused_source_file_shows_the_reason_in_the_panel
        @browser.goto(@server.url)
        click('text.member[data-id="Order"]')
        wait_for("#card li.op")
        @browser.evaluate('document.querySelector("#card li.op").dataset.file = "Gemfile"')
        @browser.at_css("#card li.op").click
        wait_for_text("#source", "not a scanned file")
      end

      def test_a_class_that_left_the_graph_shows_a_toast_instead_of_a_card
        @browser.goto(@server.url)
        wait_for('text.member[data-id="Order"]')
        @browser.evaluate('document.querySelectorAll(\'text.member[data-id="Order"], rect.wash[data-id="Order"]\').forEach((node) => { node.dataset.id = "Gone"; })')
        click('text.member[data-id="Gone"]')
        wait_for_text("#toast", "class Gone is not in the graph")
      end

      def test_escape_closes_the_card_before_it_leaves_the_view
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        click('g.box.class[data-id="Reports::Summary"] text.title')
        wait_for_text("#card h2", "Reports::Summary")
        press("Escape")
        wait_until(-> { "the card stayed open" }) { @browser.at_css("#card")["hidden"] }
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def click_empty_space
        x, y = @browser.evaluate(<<~JS)
          (() => {
            for (let y = 60; y < innerHeight; y += 20) for (let x = 10; x < innerWidth - 400; x += 20) if (document.elementFromPoint(x, y)?.id === "diagram") return [x, y];
          })()
        JS
        @browser.mouse.click(x: x, y: y)
      end

      def test_a_click_on_empty_space_closes_the_source_and_the_card
        @browser.goto(@server.url)
        click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        @browser.css("#card li.op").find { |op| op.text.start_with?("+ total") }.click
        wait_for_text("#source h2", "app/models/order.rb:7")
        click_empty_space
        wait_until(-> { "the source panel stayed open" }) { @browser.at_css("#source")["hidden"] }
        assert @browser.at_css("#card")["hidden"]
        assert_equal ["rails_shapes"], crumbs
      end

      def test_a_click_on_a_box_keeps_the_card_open
        @browser.goto(@server.url)
        click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        wait_for('g.box[data-id="Reports"] text.title').click
        sleep 0.3
        refute @browser.at_css("#card")["hidden"]
      end

      def test_hovering_a_red_arrow_lists_its_pairs_with_the_red_ones_marked
        @browser.goto(@server.url)
        hit = 'path.hit.violating[data-from="folder:models"][data-to="folder:services"]'
        wait_for(hit)
        @browser.evaluate(%(document.querySelector('#{hit}').dispatchEvent(new MouseEvent("mouseover", { bubbles: true, clientX: 100, clientY: 100 }))))
        wait_for("#popup .pair.violating")
        assert_includes @browser.css("#popup .pair.violating").map(&:text), "Order -> Pricing (dependency)"
      end

      def test_hovering_an_arrow_lists_all_kinds_of_a_pair_and_leaving_it_hides_the_popup
        reboot(build_project(
          "app/models/order.rb" => "class Order\n  belongs_to :pricing\n  def price = Pricing.new\nend\n",
          "app/services/pricing.rb" => "class Pricing\nend\n"
        ))
        @browser.goto(@server.url)
        hit = 'path.hit.violating[data-from="folder:models"][data-to="folder:services"]'
        wait_for(hit)
        @browser.evaluate(%(document.querySelector('#{hit}').dispatchEvent(new MouseEvent("mouseover", { bubbles: true, clientX: 100, clientY: 100 }))))
        wait_for("#popup .pair.violating")
        assert_equal ["Order -> Pricing (association, dependency)"], @browser.css("#popup .pair").map(&:text)
        @browser.evaluate(%(document.querySelector('#{hit}').dispatchEvent(new MouseEvent("mouseout", { bubbles: true }))))
        wait_until(-> { "the popup stayed visible" }) { @browser.at_css("#popup")["hidden"] }
      end

      def test_hovering_an_arrow_without_a_red_pair_marks_no_pair_red
        reboot(build_project(
          "app/services/pricing.rb" => "class Pricing\n  def order = Order.new\nend\n",
          "app/models/order.rb" => "class Order\nend\n"
        ))
        @browser.goto(@server.url)
        hit = 'path.hit[data-from="folder:services"][data-to="folder:models"]'
        wait_for(hit)
        @browser.evaluate(%(document.querySelector('#{hit}').dispatchEvent(new MouseEvent("mouseover", { bubbles: true, clientX: 100, clientY: 100 }))))
        wait_for("#popup .pair")
        assert_equal ["Pricing -> Order (dependency)"], @browser.css("#popup .pair").map(&:text)
        assert_empty @browser.css("#popup .pair.violating")
      end

      def test_regen_rescans
        @browser.goto(@server.url)
        wait_for("#regen")
        before = File.mtime(@workspace.path("graph.json"))
        sleep 1.1
        @browser.at_css("#regen").click
        wait_until(-> { "Regen never rewrote graph.json" }) { File.mtime(@workspace.path("graph.json")) > before }
      end

      def test_regen_with_the_server_gone_shows_a_toast
        @browser.goto(@server.url)
        wait_for("#regen")
        shutdown_server
        @browser.at_css("#regen").click
        wait_for_text("#toast", "rescan not started: server not reachable")
      end

      def test_the_context_menu_stays_inside_the_window
        @browser.goto(@server.url)
        wait_for('text.member[data-id="Order"]')
        @browser.evaluate(<<~JS)
          document.querySelector('text.member[data-id="Order"]').dispatchEvent(
            new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: innerWidth - 2, clientY: innerHeight - 2 }))
        JS
        wait_for("#menu.open")
        assert @browser.evaluate('(() => { const r = document.getElementById("menu").getBoundingClientRect(); return r.right <= innerWidth && r.bottom <= innerHeight; })()')
      end

      def test_a_covered_class_shows_its_grade_color_dots_and_metrics_on_the_card
        boot_coverage_project
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"][data-grade="10"]')
        assert_equal "10", @browser.at_css('g.box[data-id="folder:models"] circle.dot.c').attribute("data-grade")
        assert_equal "", @browser.at_css('g.box[data-id="folder:models"] circle.dot.m').attribute("data-grade")
        click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        assert_includes @browser.at_css("#card").text, "C grade 10 (mu 1.0, sigma 0.0)"
        assert_includes @browser.at_css("#card").text, "M grade: no data"
        assert_includes op_texts, "+ total  cc 1  cov 100%  crap 1.0"
      end

      def test_a_class_the_tests_never_loaded_shows_coverage_zero_and_the_note
        boot_coverage_project
        @browser.goto(@server.url)
        click('text.member[data-id="Pricing"]')
        wait_for_text("#card h2", "Pricing")
        assert_includes op_texts, "+ rate  cc 2  cov 0%  crap 6.0"
        assert_equal ["not loaded by the tests"], @browser.css("#card p.note.coverage").map(&:text)
      end

      def test_a_project_without_coverage_shows_grey_dots_and_the_simplecov_note
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"] circle.dot.c')
        assert_equal "", @browser.at_css('g.box[data-id="folder:models"]').attribute("data-grade")
        click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        assert_includes @browser.at_css("#card").text, "C grade: no data"
        assert_includes @browser.css("#card p.note.coverage").map(&:text), "no coverage: run your tests with SimpleCov"
      end

      def test_a_never_loaded_class_is_a_red_node_and_its_dots_sit_below_the_level_text
        boot_coverage_project
        @browser.goto(@server.url)
        double_click('g.box[data-id="folder:services"] text.title')
        node = wait_for('g.box.class[data-id="Pricing"]')
        assert_equal "1", node.attribute("data-grade")
        assert_includes @browser.at_css('g.box.class[data-id="Pricing"] rect').attribute("style"), "hsl(0,"
        clear = @browser.evaluate(<<~JS)
          (() => {
            const level = document.querySelector('g.box.class[data-id="Pricing"] text.level').getBBox();
            const dot = document.querySelector('g.box.class[data-id="Pricing"] circle.dot.m').getBBox();
            return dot.y >= level.y + level.height;
          })()
        JS
        assert clear, "the M dot overlaps the level text"
      end

      def test_an_unreadable_coverage_file_shows_the_banner
        boot_coverage_project(resultset: :broken)
        @browser.goto(@server.url)
        wait_for_text("#banner", "coverage file unreadable:")
      end

      def test_the_dots_sit_below_the_last_member_line
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"] text.member')
        clear = @browser.evaluate(<<~JS)
          (() => {
            const box = document.querySelector('g.box[data-id="folder:models"]');
            const members = box.querySelectorAll("text.member");
            const last = members[members.length - 1].getBBox();
            const dot = box.querySelector("circle.dot.m").getBBox();
            return dot.y >= last.y + last.height;
          })()
        JS
        assert clear, "the M dot overlaps the last member line"
      end

      def add_proposal(proposal, live: false)
        policy = YAML.safe_load(File.read(@workspace.path("policy.yml")))
        policy["proposals"] = [proposal].compact
        @workspace.write_atomic("policy.yml", YAML.dump(policy))
        live ? Graph.build(@workspace) : reboot(@workspace.root)
      end

      def reports_first
        { "id" => "p1", "name" => "Reports first", "components" => [{ "id" => "reports", "members" => ["Reports"] }, { "id" => "orders", "members" => ["Order"] }] }
      end

      def choose(value)
        @browser.execute(%(const s = document.getElementById("proposal"); s.focus(); s.value = #{value.to_json}; s.dispatchEvent(new Event("change"))))
      end

      def queued_ops
        Mailbox.new(@workspace).queue.map { |command| [command["op"], command.dig("target", "proposal_id")] }
      end

      def test_choosing_a_proposal_draws_its_components_with_its_own_red_arrows_and_posts_context
        add_proposal(reports_first)
        @browser.goto(@server.url)
        wait_for('#proposal option[value="p1"]')
        choose("p1")
        wait_for('g.box.component[data-id="component:p1/reports"]')
        assert @browser.at_css('path.hit.violating[data-from="component:p1/reports"][data-to="component:p1/orders"]')
        assert_equal ["Reports first"], crumbs
        wait_until(-> { "the queue held #{queued_ops.inspect}" }) { queued_ops == [["context", "p1"]] }
        choose("")
        wait_for('g.box[data-id="folder:models"]')
        wait_until(-> { "the queue held #{queued_ops.inspect}" }) { queued_ops.last == ["context", nil] }
      end

      def test_a_right_click_in_a_proposal_view_names_the_proposal
        add_proposal(reports_first)
        @browser.goto(@server.url)
        wait_for('#proposal option[value="p1"]')
        choose("p1")
        right_click_menu('g.box.component[data-id="component:p1/orders"] text.title', "omit")
        wait_until(-> { "the queue held #{Mailbox.new(@workspace).queue.inspect}" }) do
          Mailbox.new(@workspace).queue.any? { |command| command["op"] == "omit" && command["target"] == { "id" => "component:p1/orders", "kind" => "box", "proposal_id" => "p1" } }
        end
      end

      def test_a_double_click_on_a_component_opens_it
        add_proposal(reports_first)
        @browser.goto(@server.url)
        wait_for('#proposal option[value="p1"]')
        choose("p1")
        double_click('g.box.component[data-id="component:p1/reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal ["Reports first", "reports"], crumbs
        click('g.box.class[data-id="Reports::Summary"] text.title')
        wait_for_text("#card", "real level 1")
      end

      def test_a_folder_line_inside_unassigned_is_marked_and_opens_on_a_double_click
        add_proposal(reports_first)
        @browser.goto(@server.url)
        wait_for('#proposal option[value="p1"]')
        choose("p1")
        line = wait_for('g.box[data-id="unassigned:p1"] text.member[data-id="folder:services"]')
        assert_equal "▸ services", line.text
        double_click('g.box[data-id="unassigned:p1"] text.member[data-id="folder:services"]')
        wait_for('g.box.class[data-id="Pricing"]')
      end

      def test_d_cycles_declutter_right_after_a_proposal_is_chosen
        add_proposal(reports_first)
        @browser.goto(@server.url)
        wait_for('#proposal option[value="p1"]')
        choose("p1")
        wait_for('g.box.component[data-id="component:p1/reports"]')
        press("d")
        wait_for_text("#declutter", "declutter: one arrow per pair")
      end

      def test_new_proposal_posts_a_propose_command
        @browser.goto(@server.url)
        wait_for("#propose").click
        wait_until(-> { "the queue held #{queued_ops.inspect}" }) { queued_ops == [["propose", nil]] }
      end

      def test_the_chosen_proposal_survives_a_reload
        add_proposal(reports_first)
        @browser.goto(@server.url)
        wait_for('#proposal option[value="p1"]')
        choose("p1")
        wait_for('g.box.component[data-id="component:p1/reports"]')
        wait_until(-> { "session.json never held the proposal" }) do
          File.exist?(@workspace.path("session.json")) && JSON.parse(File.read(@workspace.path("session.json")))["proposal"] == "p1"
        end
        @browser.goto("http://127.0.0.1:#{@server.port}/")
        wait_for('g.box.component[data-id="component:p1/reports"]')
        assert_equal "p1", @browser.evaluate(%(document.getElementById("proposal").value))
      end

      def test_a_proposal_that_leaves_the_policy_falls_back_to_the_real_diagram_with_a_toast
        add_proposal(reports_first)
        @browser.goto(@server.url)
        wait_for('#proposal option[value="p1"]')
        choose("p1")
        wait_for('g.box.component[data-id="component:p1/reports"]')
        add_proposal(nil, live: true)
        wait_for_text("#toast", "proposal p1 is gone: showing the real diagram")
        wait_for('g.box[data-id="folder:models"]')
        assert_equal ["rails_shapes"], crumbs
        wait_until(-> { "session.json still names the gone proposal" }) { File.exist?(@workspace.path("session.json")) && JSON.parse(File.read(@workspace.path("session.json")))["proposal"].nil? }
      end

      def test_a_stored_proposal_that_is_gone_falls_back_to_the_real_diagram_without_a_draw_error
        @workspace.write_atomic("session.json", JSON.generate("proposal" => "gone", "drill" => ["root", "component:gone/x"]))
        @browser.goto(@server.url)
        wait_for_text("#toast", "proposal gone is gone: showing the real diagram")
        wait_for('g.box[data-id="folder:models"]')
        assert_equal ["rails_shapes"], crumbs
        refute_includes @browser.at_css("#banner").text, "could not draw"
      end

      def test_escape_closes_an_open_context_menu_before_it_leaves_the_view
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"] text.title').click(mode: :right)
        wait_for("#menu.open")
        press("Escape")
        wait_until(-> { "the menu stayed open" }) { @browser.at_css("#menu.open").nil? }
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def boot_two_way_project
        reboot(build_project("app/models/order.rb" => "class Order\n  def price = Pricing.new\nend\n",
                             "app/services/pricing.rb" => "class Pricing\n  def order = Order.new\nend\n"))
      end

      DECLUTTER_MODES = ["none", "one arrow per pair", "triangles", "hide members", "hide classes"].freeze

      def declutter_to(mode)
        mode.times { press("d") }
        wait_for_text("#declutter", "declutter: #{DECLUTTER_MODES[mode]}")
      end

      def test_d_cycles_the_five_declutter_modes_and_the_button_names_each
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        assert_equal "declutter: none", @browser.at_css("#declutter").text
        ["one arrow per pair", "triangles", "hide members", "hide classes", "none"].each do |mode|
          press("d")
          wait_for_text("#declutter", "declutter: #{mode}")
        end
        @browser.at_css("#declutter").click
        wait_for_text("#declutter", "declutter: one arrow per pair")
      end

      def test_one_arrow_per_pair_merges_both_directions_into_one_red_line_with_two_heads
        boot_two_way_project
        @browser.goto(@server.url)
        wait_for('path.hit[data-from="folder:services"][data-to="folder:models"]')
        assert_equal 2, @browser.css("path.hit").size
        declutter_to(1)
        wait_until(-> { "still #{@browser.css('path.hit').size} arrows" }) { @browser.css("path.hit").size == 1 }
        assert @browser.at_css("path.arrow.violating.both")
        assert_match(/#head-red/, @browser.evaluate(%(getComputedStyle(document.querySelector("path.arrow.both")).markerStart)))
        hit = "path.hit"
        @browser.evaluate(%(document.querySelector('#{hit}').dispatchEvent(new MouseEvent("mouseover", { bubbles: true, clientX: 100, clientY: 100 }))))
        wait_for("#popup .pair")
        assert_equal ["Order -> Pricing (dependency)", "Pricing -> Order (dependency)"], @browser.css("#popup .pair").map(&:text).sort
      end

      def test_triangles_hide_the_lines_and_keep_the_heads
        boot_two_way_project
        @browser.goto(@server.url)
        wait_for("path.arrow")
        declutter_to(2)
        wait_until(-> { "the line is still drawn" }) do
          @browser.evaluate(%(getComputedStyle(document.querySelector("path.arrow")).stroke)) == "rgba(0, 0, 0, 0)"
        end
        assert_match(/url\("?#head/, @browser.evaluate(%(getComputedStyle(document.querySelector("path.arrow")).markerEnd)))
      end

      def test_hide_members_draws_boxes_without_member_lines
        @browser.goto(@server.url)
        wait_for("text.member")
        declutter_to(3)
        wait_until(-> { "#{@browser.css('text.member').size} member lines left" }) { @browser.css("text.member").empty? }
        assert @browser.at_css('g.box[data-id="Reports"]')
      end

      def test_hide_classes_leaves_only_boxes_and_says_why_a_view_of_classes_is_empty
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        declutter_to(4)
        wait_for_text("text.note", "declutter hides all 2 classes in this view: press d")
        assert_empty @browser.css("g.box.class")
      end

      def boot_mixed_view_project
        reboot(build_project("app/services/billing/counter.rb" => "module Billing\n  class Counter\n    def client = Billing::Gateway::Client.new\n  end\nend\n",
                             "app/services/billing/gateway/client.rb" => "module Billing\n  module Gateway\n    class Client\n      def counter = Billing::Counter.new\n    end\n  end\nend\n"))
      end

      def test_each_declutter_mode_keeps_the_effects_of_the_modes_before_it
        boot_mixed_view_project
        @browser.goto(@server.url)
        double_click('g.box[data-id="Billing"] text.title')
        wait_for('g.box.class[data-id="Billing::Counter"]')
        assert_equal 2, @browser.css("path.hit").size
        declutter_to(3)
        wait_until(-> { "#{@browser.css('path.hit').size} arrows at hide members" }) { @browser.css("path.hit").size == 1 }
        assert @browser.at_css("svg.triangles path.arrow.both")
        assert_match(/#head"?\)/, @browser.evaluate(%(getComputedStyle(document.querySelector("svg.triangles path.arrow.both")).markerStart)))
        assert_empty @browser.css("text.member")
        press("d")
        wait_for_text("#declutter", "declutter: hide classes")
        wait_until(-> { "class nodes are still drawn" }) { @browser.css("g.box.class").empty? }
        assert_empty @browser.css("text.member")
        assert @browser.at_css("svg.triangles")
        assert @browser.at_css('g.box[data-id="Billing::Gateway"]')
        assert_empty @browser.css("path.hit")
        assert_nil @browser.at_css("text.note")
      end

      def test_the_d_key_ignores_ctrl_and_a_focused_select
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        press("d", ctrl: true)
        @browser.execute(%(document.getElementById("proposal").focus()))
        press("d")
        press("d", ctrl: true)
        assert_equal "declutter: none", @browser.at_css("#declutter").text
        @browser.execute(%(document.activeElement.blur()))
        press("d")
        wait_for_text("#declutter", "declutter: one arrow per pair")
      end

      def test_the_declutter_mode_survives_a_reload
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        declutter_to(3)
        wait_until(-> { "session.json never held the mode" }) do
          File.exist?(@workspace.path("session.json")) && JSON.parse(File.read(@workspace.path("session.json")))["declutter"] == 3
        end
        @browser.goto("http://127.0.0.1:#{@server.port}/")
        wait_for_text("#declutter", "declutter: hide members")
        assert_empty @browser.css("text.member")
      end

      def test_a_proposal_warning_shows_in_the_banner
        add_proposal(reports_first.merge("components" => [{ "id" => "ghosts", "members" => ["Ghost"] }]))
        @browser.goto(@server.url)
        wait_for_text("#banner", "scan warning: proposal p1: member Ghost matches no class in the diagram (check the name and the policy omit)")
      end

      def test_many_scan_warnings_show_a_count_and_the_first_one
        add_proposal(reports_first.merge("components" => [{ "id" => "ghosts", "members" => ["Ghost", "Spook"] }]))
        @browser.goto(@server.url)
        wait_for_text("#banner", "2 scan warnings: proposal p1: member Ghost matches no class in the diagram (check the name and the policy omit); run uml-viewer scan for all")
      end

      private

      def boot_coverage_project(resultset: :valid)
        project = build_project(
          "app/models/order.rb" => "class Order\n  def total\n    1\n  end\nend\n",
          "app/services/pricing.rb" => "class Pricing\n  def rate(x)\n    x ? 1 : 2\n  end\nend\n"
        )
        FileUtils.mkdir_p(File.join(project, "coverage"))
        text = if resultset == :valid
                 JSON.generate("RSpec" => { "coverage" => { File.join(File.realpath(project), "app/models/order.rb") => [nil, 1, 1, nil, nil] }, "timestamp" => Time.now.to_i + 60 })
               else
                 "{\"RSpec\": {"
               end
        File.write(File.join(project, "coverage", ".resultset.json"), text)
        reboot(project)
      end

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
