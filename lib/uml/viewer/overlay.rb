module Uml
  module Viewer
    module Overlay
      NO_COVERAGE = "no coverage: run your tests with SimpleCov".freeze
      STALE = "coverage older than this file".freeze
      NOT_LOADED = "not loaded by the tests".freeze
      UNTESTED = "no test runs these methods".freeze
      PARTIAL = "coverage looks partial: run the full suite".freeze
      COUNTS = %w[killed survived uncovered].freeze

      def self.apply(classes, coverage:, mtimes:, mutation:, cutoffs:, missing_note: NO_COVERAGE)
        files = classes.flat_map { |entry| entry["files"] }.uniq
        present = coverage ? files.count { |file| coverage["lines"].key?(file) } : 0
        partial = !coverage.nil? && present < files.size / 2.0
        states = files.to_h { |file| [file, file_state(file, coverage, mtimes, partial)] }
        notes = { none: missing_note, stale: STALE, absent: NOT_LOADED, partial: PARTIAL }
        graded = classes.map do |entry|
          ops = entry["ops"].map { |op| with_metrics(op, states[op["file"]], coverage) }
          crap = class_crap(ops, cutoffs)
          counts = mutation_counts(entry["id"], ops, mutation)
          tested = counts && mutation_grade(counts)
          entry.merge(
            "ops" => ops, "coverage_notes" => coverage_notes(entry["files"], states, notes, ops),
            "crap" => crap, "mutation" => tested, "grade" => mean_grade(crap, tested)
          )
        end
        { "classes" => graded, "coverage" => summary(coverage, present, files.size, partial) }
      end

      def self.coverage_notes(files, states, notes, ops)
        listed = files.filter_map { |file| notes[states[file]] }.uniq
        loaded = files.any? { |file| states[file] == :lines }
        loaded && no_test_runs?(measured_ops(ops)) ? listed + [UNTESTED] : listed
      end

      def self.measured_ops(ops)
        ops.reject { |op| op["coverage"].nil? }
      end

      def self.no_test_runs?(measured)
        measured.any? && measured.all? { |op| op["coverage"].zero? }
      end

      def self.class_crap(ops, cutoffs)
        measured = measured_ops(ops)
        return nil if measured.empty?

        untested(stats(measured.map { |op| op["crap"] }, cutoffs), measured)
      end

      def self.untested(crap, measured)
        no_test_runs?(measured) ? crap.merge("grade" => 1) : crap
      end

      def self.file_state(file, coverage, mtimes, partial)
        return :none if coverage.nil?
        return :stale if mtimes[file].to_f > coverage["time"].to_f
        return :lines if coverage["lines"].key?(file)

        partial ? :partial : :absent
      end

      def self.with_metrics(op, state, coverage)
        value = case state
                when :absent then 0.0
                when :lines then body_coverage(op, coverage["lines"][op["file"]])
                end
        op.merge("coverage" => value, "crap" => value && crap(op["cc"], value))
      end

      def self.body_coverage(op, hits)
        body = ((op["line_start"] + 1)..(op["line_end"] - 1)).filter_map { |line| hits[line - 1] }
        body.empty? ? nil : body.count(&:positive?).fdiv(body.size)
      end

      def self.crap(cc, coverage)
        (cc**2) * ((1 - coverage)**3) + cc.to_f
      end

      def self.stats(values, cutoffs)
        mu = values.sum.fdiv(values.size)
        sigma = Math.sqrt(values.sum { |value| (value - mu)**2 }.fdiv(values.size))
        { "mu" => mu, "sigma" => sigma, "grade" => grade(mu + sigma, cutoffs) }
      end

      def self.grade(value, cutoffs)
        index = cutoffs.index { |cutoff| value <= cutoff }
        index ? 10 - index : 1
      end

      def self.mutation_counts(class_id, ops, mutation)
        return nil if mutation.nil?

        found = ops.filter_map { |op| mutation[mutation_key(class_id, op["name"])] }
        return nil if found.empty?

        COUNTS.to_h { |key| [key, found.sum { |entry| entry[key].to_i }] }
      end

      def self.mutation_key(class_id, name)
        name.start_with?("self.") ? "#{class_id}.#{name.delete_prefix('self.')}" : "#{class_id}##{name}"
      end

      def self.mutation_grade(counts)
        total = counts.values.sum
        return nil if total.zero?

        score = counts["killed"].fdiv(total)
        { "score" => score, "grade" => [1, (score * 10).ceil].max, "counts" => counts }
      end

      def self.mean_grade(crap, tested)
        grades = [crap&.fetch("grade"), tested&.fetch("grade")].compact
        grades.empty? ? nil : grades.sum.fdiv(grades.size)
      end

      def self.summary(coverage, present, scanned, partial)
        return { "time" => nil, "files" => 0, "scanned" => scanned, "banner" => nil } if coverage.nil?

        banner = partial ? "coverage looks partial: #{present} of #{scanned} files; run the full suite" : nil
        { "time" => coverage["time"], "files" => present, "scanned" => scanned, "banner" => banner }
      end

      def self.boxes(views, classes, cutoffs)
        by_id = classes.to_h { |entry| [entry["id"], entry] }
        memo = {}
        views.transform_values do |view|
          view.merge("nodes" => view["nodes"].map { |node| node.merge(node_grades(node, views, by_id, cutoffs, memo)) })
        end
      end

      def self.node_grades(node, views, by_id, cutoffs, memo)
        return class_grades(by_id[node["id"]]) if node["type"] == "class"
        return {} unless %w[namespace folder].include?(node["type"])

        entries = classes_under(node["id"], views, memo).filter_map { |id| by_id[id] }
        pooled(entries, cutoffs)
      end

      def self.class_grades(entry)
        return { "c_grade" => nil, "m_grade" => nil, "grade" => nil } if entry.nil?

        { "c_grade" => entry["crap"]&.fetch("grade"), "m_grade" => entry["mutation"]&.fetch("grade"), "grade" => entry["grade"] }
      end

      def self.pooled(entries, cutoffs)
        measured = entries.flat_map { |entry| measured_ops(entry["ops"]) }
        counts = entries.filter_map { |entry| entry.dig("mutation", "counts") }
        crap = measured.empty? ? nil : untested(stats(measured.map { |op| op["crap"] }, cutoffs), measured)
        tested = counts.empty? ? nil : mutation_grade(COUNTS.to_h { |key| [key, counts.sum { |count| count[key] }] })
        { "c_grade" => crap&.fetch("grade"), "m_grade" => tested&.fetch("grade"), "grade" => mean_grade(crap, tested) }
      end

      def self.classes_under(view_id, views, memo)
        memo[view_id] ||= views[view_id]["nodes"].flat_map do |node|
          case node["type"]
          when "class" then [node["id"]]
          when "namespace", "folder" then classes_under(node["id"], views, memo)
          else []
          end
        end
      end
    end
  end
end
