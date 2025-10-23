require 'json'
require 'csv'

# Formats and reports query plan analysis results
class PlanReporter
  # ANSI color codes
  COLORS = {
    reset: "\e[0m",
    bold: "\e[1m",
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    cyan: "\e[36m",
    gray: "\e[90m"
  }

  def initialize(use_colors: true)
    @use_colors = use_colors
  end

  # Report on a single plan
  def report_single_plan(plan, analyzer)
    output = []

    output << header("Query Plan Analysis")
    output << ""

    # Summary metrics
    output << section_title("Summary")
    output << format_summary(plan.summary_metrics)
    output << ""

    # Timing breakdown
    output << section_title("Timing")
    output << format_timing(plan)
    output << ""

    # Buffer statistics
    output << section_title("Buffer Statistics")
    output << format_buffers(analyzer.total_buffer_stats)
    output << ""

    # I/O timing
    io = plan.io_timing
    if io[:io_read_time] > 0 || io[:io_write_time] > 0
      output << section_title("I/O Timing")
      output << format_io_timing(io)
      output << ""
    end

    # Node analysis
    output << section_title("Node Analysis")
    output << format_node_counts(analyzer.node_type_counts)
    output << ""

    # Expensive operations
    expensive = analyzer.expensive_operations
    if expensive.any?
      output << section_title("Top 5 Most Expensive Operations")
      output << format_expensive_operations(expensive)
      output << ""
    end

    # Sequential scans
    seq_scans = analyzer.sequential_scans
    if seq_scans.any?
      output << section_title("Sequential Scans (#{seq_scans.count})")
      output << format_sequential_scans(seq_scans)
      output << ""
    end

    # Estimation accuracy
    output << section_title("Row Estimation Accuracy")
    output << format_estimation_accuracy(analyzer.estimation_accuracy)

    output.join("\n")
  end

  # Report comparison between two plans
  def report_comparison(comparator)
    output = []

    output << header("Query Plan Comparison")
    output << ""

    # Verdict
    verdict = comparator.verdict
    output << section_title("Overall Verdict")
    output << format_verdict(verdict)
    output << ""

    # Key changes
    key_changes = comparator.key_changes
    if key_changes.any?
      output << section_title("Key Changes")
      output << format_key_changes(key_changes)
      output << ""
    end

    # Timing comparison
    output << section_title("Timing Comparison")
    output << format_comparison_table(comparator.timing_comparison)
    output << ""

    # Cost comparison
    output << section_title("Cost Comparison")
    output << format_comparison_table(comparator.cost_comparison)
    output << ""

    # Buffer comparison
    output << section_title("Buffer Comparison")
    output << format_comparison_table(comparator.buffer_comparison)
    output << ""

    # Node type changes
    node_changes = comparator.node_type_comparison.select { |c| c[:change] != 0 }
    if node_changes.any?
      output << section_title("Node Type Changes")
      output << format_node_changes(node_changes)
      output << ""
    end

    # Row comparison
    output << section_title("Row Count Comparison")
    output << format_row_comparison(comparator.row_comparison)
    output << ""

    # I/O timing comparison
    io_comp = comparator.io_comparison
    if io_comp.any? { |item| item[:before] > 0 || item[:after] > 0 }
      output << section_title("I/O Timing Comparison")
      output << format_comparison_table(io_comp)
      output << ""
    end

    # Sequential scan comparison
    seq_comparison = comparator.sequential_scan_comparison
    output << section_title("Sequential Scan Comparison")
    output << format_seq_scan_comparison(seq_comparison)
    output << ""

    # Sort comparison
    sort_comp = comparator.sort_comparison
    if sort_comp[:count][:before] > 0 || sort_comp[:count][:after] > 0
      output << section_title("Sort Comparison")
      output << format_sort_comparison(sort_comp)
      output << ""
    end

    # Complexity comparison
    output << section_title("Plan Complexity")
    output << format_complexity_comparison(comparator.complexity_comparison)

    output.join("\n")
  end

  # Export comparison to CSV
  def export_comparison_csv(comparator, output_path)
    CSV.open(output_path, 'wb') do |csv|
      csv << ['Category', 'Metric', 'Before', 'After', 'Difference', 'Change %', 'Significant']

      # Timing
      comparator.timing_comparison.each do |item|
        csv << ['Timing', item[:metric], item[:before], item[:after],
                item[:difference], item[:percent_change], item[:significant]]
      end

      # Cost
      comparator.cost_comparison.each do |item|
        csv << ['Cost', item[:metric], item[:before], item[:after],
                item[:difference], item[:percent_change], item[:significant]]
      end

      # Rows
      row_comp = comparator.row_comparison
      csv << ['Rows', 'actual_rows', row_comp[:actual_rows][:before], row_comp[:actual_rows][:after],
              row_comp[:actual_rows][:change], row_comp[:actual_rows][:percent_change],
              row_comp[:actual_rows][:percent_change].abs > 10]
      csv << ['Rows', 'planned_rows', row_comp[:planned_rows][:before], row_comp[:planned_rows][:after],
              row_comp[:planned_rows][:change], row_comp[:planned_rows][:percent_change],
              row_comp[:planned_rows][:percent_change].abs > 10]

      # Buffers
      comparator.buffer_comparison.each do |item|
        csv << ['Buffers', item[:metric], item[:before], item[:after],
                item[:difference], item[:percent_change], item[:significant]]
      end

      # I/O
      comparator.io_comparison.each do |item|
        csv << ['I/O', item[:metric], item[:before], item[:after],
                item[:difference], item[:percent_change], item[:significant]]
      end
    end
  end

  # Export comparison to JSON
  def export_comparison_json(comparator, output_path)
    data = {
      verdict: comparator.verdict,
      timing: comparator.timing_comparison,
      cost: comparator.cost_comparison,
      rows: comparator.row_comparison,
      buffers: comparator.buffer_comparison,
      io_timing: comparator.io_comparison,
      node_changes: comparator.node_type_comparison,
      sort_comparison: comparator.sort_comparison,
      complexity: comparator.complexity_comparison,
      key_changes: comparator.key_changes
    }

    File.write(output_path, JSON.pretty_generate(data))
  end

  private

  def colorize(text, color)
    return text unless @use_colors
    "#{COLORS[color]}#{text}#{COLORS[:reset]}"
  end

  def header(text)
    colorize("=" * 70, :blue) + "\n" +
    colorize(text.center(70), :bold) + "\n" +
    colorize("=" * 70, :blue)
  end

  def section_title(text)
    colorize("# #{text}", :cyan)
  end

  def format_summary(metrics)
    lines = []
    lines << "  Total Time:    #{format_time(metrics[:total_time])}"
    lines << "  Planning Time: #{format_time(metrics[:planning_time])}"
    lines << "  Execution Time: #{format_time(metrics[:execution_time])}"
    lines << "  Total Cost:    #{format_number(metrics[:total_cost])}"
    lines << "  Rows (actual): #{format_number(metrics[:actual_rows])}"
    lines << "  Rows (planned): #{format_number(metrics[:plan_rows])}"
    lines.join("\n")
  end

  def format_timing(plan)
    total = plan.total_time
    planning = plan.planning_time
    execution = plan.execution_time

    planning_pct = (planning / total * 100).round(1)
    execution_pct = (execution / total * 100).round(1)

    lines = []
    lines << "  Planning:   #{format_time(planning)} (#{planning_pct}%)"
    lines << "  Execution:  #{format_time(execution)} (#{execution_pct}%)"
    lines << "  Total:      #{format_time(total)}"
    lines.join("\n")
  end

  def format_buffers(stats)
    lines = []
    lines << "  Shared Blocks:"
    lines << "    Hit:      #{format_number(stats[:shared_hit_blocks])} blocks"
    lines << "    Read:     #{format_number(stats[:shared_read_blocks])} blocks"
    lines << "    Dirtied:  #{format_number(stats[:shared_dirtied_blocks])} blocks"
    lines << "    Written:  #{format_number(stats[:shared_written_blocks])} blocks"
    lines << "  Hit Ratio:  #{colorize_buffer_hit_ratio(stats[:buffer_hit_ratio])}"

    if stats[:temp_read_blocks] > 0 || stats[:temp_written_blocks] > 0
      lines << "  Temp Blocks:"
      lines << "    Read:     #{format_number(stats[:temp_read_blocks])} blocks"
      lines << "    Written:  #{format_number(stats[:temp_written_blocks])} blocks"
    end

    lines.join("\n")
  end

  def format_io_timing(io)
    lines = []
    lines << "  Read Time:  #{format_time(io[:io_read_time])}"
    lines << "  Write Time: #{format_time(io[:io_write_time])}"
    lines.join("\n")
  end

  def format_node_counts(counts)
    sorted = counts.sort_by { |_, v| -v }
    sorted.map { |type, count| "  #{type.ljust(30)} #{count}" }.join("\n")
  end

  def format_expensive_operations(operations)
    lines = []
    operations.each_with_index do |op, idx|
      relation = op[:relation_name] ? " on #{op[:relation_name]}" : ""
      lines << "  #{idx + 1}. #{op[:node_type]}#{relation}"
      lines << "     Time: #{format_time(op[:total_time])}, Cost: #{format_number(op[:cost])}, Rows: #{format_number(op[:rows])}"
    end
    lines.join("\n")
  end

  def format_sequential_scans(scans)
    scans.take(10).map do |scan|
      "  #{scan[:relation].ljust(30)} #{format_number(scan[:rows])} rows, #{format_time(scan[:total_time])}, loops: #{scan[:loops]}"
    end.join("\n")
  end

  def format_estimation_accuracy(accuracy)
    lines = []
    lines << "  Accurate estimates:   #{accuracy[:accurate]}"
    lines << "  Inaccurate estimates: #{accuracy[:inaccurate]}"
    lines << "  Average ratio:        #{accuracy[:avg_ratio]}"

    if accuracy[:worst_nodes]&.any?
      lines << "  Worst estimates:"
      accuracy[:worst_nodes].each do |node|
        relation = node[:relation] ? " (#{node[:relation]})" : ""
        lines << "    #{node[:node_type]}#{relation}: #{node[:estimated]} → #{node[:actual]} (#{node[:ratio].round(1)}x off)"
      end
    end

    lines.join("\n")
  end

  def format_verdict(verdict)
    case verdict[:status]
    when :improved
      colorize("✓ IMPROVED", :green) +
        " (Time: #{format_percent(-verdict[:time_improvement])}, Cost: #{format_percent(-verdict[:cost_improvement])})"
    when :regressed
      colorize("✗ REGRESSED", :red) +
        " (Time: #{format_percent(verdict[:time_regression])}, Cost: #{format_percent(verdict[:cost_regression])})"
    when :similar
      colorize("≈ SIMILAR", :yellow) +
        " (Time: #{format_percent(verdict[:time_change])}, Cost: #{format_percent(verdict[:cost_change])})"
    end
  end

  def format_key_changes(changes)
    changes.map do |change|
      indicator = case change[:impact]
      when :positive then colorize("↓", :green)
      when :negative then colorize("↑", :red)
      else colorize("→", :yellow)
      end

      "  #{indicator} #{change[:metric]}: #{format_number(change[:before])} → #{format_number(change[:after])} " +
      "(#{format_percent(change[:change_percent])})"
    end.join("\n")
  end

  def format_comparison_table(comparisons)
    lines = []
    comparisons.each do |comp|
      metric = comp[:metric].to_s.ljust(25)
      before = format_number(comp[:before]).rjust(15)
      after = format_number(comp[:after]).rjust(15)
      change = format_percent(comp[:percent_change]).rjust(10)

      change_colored = if comp[:percent_change] < -10
        colorize(change, :green)
      elsif comp[:percent_change] > 10
        colorize(change, :red)
      else
        colorize(change, :yellow)
      end

      lines << "  #{metric} #{before} → #{after} #{change_colored}"
    end
    lines.join("\n")
  end

  def format_node_changes(changes)
    changes.take(10).map do |change|
      indicator = change[:change] > 0 ? colorize("+", :red) : colorize("-", :green)
      change_str = change[:change] > 0 ? "+#{change[:change]}" : change[:change].to_s
      "  #{indicator} #{change[:type].ljust(30)} #{change[:before]} → #{change[:after]} (#{change_str})"
    end.join("\n")
  end

  def format_row_comparison(row_comp)
    lines = []

    actual = row_comp[:actual_rows]
    planned = row_comp[:planned_rows]

    lines << "  Actual Rows:   #{format_number(actual[:before])} → #{format_number(actual[:after])} (#{format_percent(actual[:percent_change])})"
    lines << "  Planned Rows:  #{format_number(planned[:before])} → #{format_number(planned[:after])} (#{format_percent(planned[:percent_change])})"

    est_before = row_comp[:estimation_accuracy][:before]
    est_after = row_comp[:estimation_accuracy][:after]

    lines << ""
    lines << "  Estimation Accuracy:"
    lines << "    Before: #{est_before[:accurate]} accurate, #{est_before[:inaccurate]} inaccurate (avg ratio: #{est_before[:avg_ratio]})"
    lines << "    After:  #{est_after[:accurate]} accurate, #{est_after[:inaccurate]} inaccurate (avg ratio: #{est_after[:avg_ratio]})"

    if est_before[:inaccurate] > est_after[:inaccurate]
      lines << "    #{colorize('✓ Estimation improved!', :green)}"
    elsif est_before[:inaccurate] < est_after[:inaccurate]
      lines << "    #{colorize('✗ Estimation got worse', :red)}"
    end

    lines.join("\n")
  end

  def format_sort_comparison(sort_comp)
    lines = []

    count = sort_comp[:count]
    disk = sort_comp[:disk_sorts]
    time = sort_comp[:total_time]

    count_str = count[:change] > 0 ? "+#{count[:change]}" : count[:change].to_s
    disk_str = (disk[:after] - disk[:before]) > 0 ? "+#{disk[:after] - disk[:before]}" : (disk[:after] - disk[:before]).to_s

    lines << "  Sort Count:      #{count[:before]} → #{count[:after]} (#{count_str})"
    lines << "  Disk Sorts:      #{disk[:before]} → #{disk[:after]} (#{disk_str})"
    lines << "  Total Sort Time: #{format_time(time[:before])} → #{format_time(time[:after])}"

    if disk[:before] > 0 && disk[:after] == 0
      lines << "  #{colorize('✓ All sorts now in memory!', :green)}"
    elsif disk[:before] == 0 && disk[:after] > 0
      lines << "  #{colorize('✗ Sorts spilling to disk', :red)}"
    end

    lines.join("\n")
  end

  def format_complexity_comparison(complexity)
    depth = complexity[:plan_depth]
    nodes = complexity[:total_nodes]

    lines = []
    lines << "  Plan Depth:   #{depth[:before]} → #{depth[:after]} (#{depth[:change] > 0 ? '+' : ''}#{depth[:change]})"
    lines << "  Total Nodes:  #{nodes[:before]} → #{nodes[:after]} (#{nodes[:change] > 0 ? '+' : ''}#{nodes[:change]})"

    if depth[:change] < 0 || nodes[:change] < 0
      lines << "  #{colorize('✓ Plan simplified', :green)}"
    elsif depth[:change] > 0 || nodes[:change] > 0
      lines << "  #{colorize('Plan became more complex', :yellow)}"
    end

    lines.join("\n")
  end

  def format_seq_scan_comparison(comparison)
    before = comparison[:before]
    after = comparison[:after]

    count_diff = after[:count] - before[:count]
    count_str = count_diff > 0 ? "+#{count_diff}" : count_diff.to_s

    lines = []
    lines << "  Count:      #{before[:count]} → #{after[:count]} (#{count_str})"
    lines << "  Total Time: #{format_time(before[:total_time])} → #{format_time(after[:total_time])}"
    lines << "  Total Rows: #{format_number(before[:total_rows])} → #{format_number(after[:total_rows])}"
    lines.join("\n")
  end

  def format_time(ms)
    return "0 ms" if ms.zero?

    if ms < 1000
      "#{ms.round(2)} ms"
    else
      "#{(ms / 1000.0).round(2)} s"
    end
  end

  def format_number(num)
    return "0" if num.zero?

    if num.is_a?(Float)
      num.round(2).to_s
    else
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end

  def format_percent(pct)
    sign = pct > 0 ? "+" : ""
    "#{sign}#{pct.round(1)}%"
  end

  def colorize_buffer_hit_ratio(ratio)
    text = "#{ratio.round(2)}%"
    if ratio >= 99
      colorize(text, :green)
    elsif ratio >= 95
      colorize(text, :yellow)
    else
      colorize(text, :red)
    end
  end
end
