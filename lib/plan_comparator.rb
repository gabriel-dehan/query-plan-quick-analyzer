require_relative 'query_plan_analyzer'
require_relative 'plan_analyzer'

# Compares two query plans and identifies improvements/regressions
class PlanComparator
  attr_reader :plan1, :plan2, :analyzer1, :analyzer2

  SIGNIFICANT_THRESHOLD = 0.10 # 10% change is considered significant

  def initialize(plan_file1, plan_file2)
    @plan1 = QueryPlanAnalyzer.new(plan_file1)
    @plan2 = QueryPlanAnalyzer.new(plan_file2)
    @analyzer1 = PlanAnalyzer.new(@plan1.plan_node)
    @analyzer2 = PlanAnalyzer.new(@plan2.plan_node)
  end

  # Compare high-level timing metrics
  def timing_comparison
    compare_metrics(
      {
        planning_time: plan1.planning_time,
        execution_time: plan1.execution_time,
        total_time: plan1.total_time
      },
      {
        planning_time: plan2.planning_time,
        execution_time: plan2.execution_time,
        total_time: plan2.total_time
      }
    )
  end

  # Compare cost metrics
  def cost_comparison
    compare_metrics(
      plan1.summary_metrics.slice(:total_cost, :startup_cost),
      plan2.summary_metrics.slice(:total_cost, :startup_cost)
    )
  end

  # Compare row counts and estimation accuracy
  def row_comparison
    metrics1 = plan1.summary_metrics
    metrics2 = plan2.summary_metrics

    {
      actual_rows: {
        before: metrics1[:actual_rows],
        after: metrics2[:actual_rows],
        change: metrics2[:actual_rows] - metrics1[:actual_rows],
        percent_change: percent_change(metrics1[:actual_rows], metrics2[:actual_rows])
      },
      planned_rows: {
        before: metrics1[:plan_rows],
        after: metrics2[:plan_rows],
        change: metrics2[:plan_rows] - metrics1[:plan_rows],
        percent_change: percent_change(metrics1[:plan_rows], metrics2[:plan_rows])
      },
      estimation_accuracy: {
        before: analyzer1.estimation_accuracy,
        after: analyzer2.estimation_accuracy
      }
    }
  end

  # Compare sort operations
  def sort_comparison
    sorts1 = analyzer1.sorts
    sorts2 = analyzer2.sorts

    {
      count: {
        before: sorts1.count,
        after: sorts2.count,
        change: sorts2.count - sorts1.count
      },
      disk_sorts: {
        before: sorts1.count { |s| s[:sort_space_type] == 'Disk' },
        after: sorts2.count { |s| s[:sort_space_type] == 'Disk' }
      },
      total_time: {
        before: sorts1.sum { |s| s[:total_time] },
        after: sorts2.sum { |s| s[:total_time] }
      }
    }
  end

  # Compare plan complexity
  def complexity_comparison
    {
      plan_depth: {
        before: analyzer1.plan_depth,
        after: analyzer2.plan_depth,
        change: analyzer2.plan_depth - analyzer1.plan_depth
      },
      total_nodes: {
        before: analyzer1.all_nodes.count,
        after: analyzer2.all_nodes.count,
        change: analyzer2.all_nodes.count - analyzer1.all_nodes.count
      }
    }
  end

  # Compare buffer statistics
  def buffer_comparison
    compare_metrics(
      analyzer1.total_buffer_stats,
      analyzer2.total_buffer_stats
    )
  end

  # Compare I/O operations
  def io_comparison
    compare_metrics(
      plan1.io_timing,
      plan2.io_timing
    )
  end

  # Compare node type usage
  def node_type_comparison
    types1 = analyzer1.node_type_counts
    types2 = analyzer2.node_type_counts
    all_types = (types1.keys + types2.keys).uniq

    all_types.map do |type|
      count1 = types1[type] || 0
      count2 = types2[type] || 0

      {
        type: type,
        before: count1,
        after: count2,
        change: count2 - count1,
        percent_change: percent_change(count1, count2)
      }
    end.sort_by { |c| -c[:change].abs }
  end

  # Compare sequential scans
  def sequential_scan_comparison
    scans1 = analyzer1.sequential_scans
    scans2 = analyzer2.sequential_scans

    {
      before: {
        count: scans1.count,
        total_time: scans1.sum { |s| s[:total_time] },
        total_rows: scans1.sum { |s| s[:rows] }
      },
      after: {
        count: scans2.count,
        total_time: scans2.sum { |s| s[:total_time] },
        total_rows: scans2.sum { |s| s[:rows] }
      }
    }
  end

  # Overall verdict: improved, regressed, or similar
  def verdict
    time_change = percent_change(plan1.total_time, plan2.total_time)
    cost_change = percent_change(
      plan1.summary_metrics[:total_cost],
      plan2.summary_metrics[:total_cost]
    )

    if time_change < -SIGNIFICANT_THRESHOLD || cost_change < -SIGNIFICANT_THRESHOLD
      {
        status: :improved,
        time_improvement: -time_change,
        cost_improvement: -cost_change
      }
    elsif time_change > SIGNIFICANT_THRESHOLD || cost_change > SIGNIFICANT_THRESHOLD
      {
        status: :regressed,
        time_regression: time_change,
        cost_regression: cost_change
      }
    else
      {
        status: :similar,
        time_change: time_change,
        cost_change: cost_change
      }
    end
  end

  # Get the most impactful changes
  def key_changes
    changes = []

    # Check timing changes
    time_pct = percent_change(plan1.total_time, plan2.total_time)
    if time_pct.abs > SIGNIFICANT_THRESHOLD
      changes << {
        category: :timing,
        metric: 'Total Time',
        before: plan1.total_time,
        after: plan2.total_time,
        change_percent: time_pct,
        impact: classify_impact(time_pct)
      }
    end

    # Check buffer hit ratio changes
    buffer1 = analyzer1.total_buffer_stats
    buffer2 = analyzer2.total_buffer_stats
    hit_ratio_change = buffer2[:buffer_hit_ratio] - buffer1[:buffer_hit_ratio]
    if hit_ratio_change.abs > 5 # 5 percentage points
      changes << {
        category: :buffers,
        metric: 'Buffer Hit Ratio',
        before: buffer1[:buffer_hit_ratio],
        after: buffer2[:buffer_hit_ratio],
        change_percent: hit_ratio_change,
        impact: classify_impact(-hit_ratio_change) # Negative because higher is better
      }
    end

    # Check I/O block changes
    io_change = percent_change(
      buffer1[:total_io_blocks],
      buffer2[:total_io_blocks]
    )
    if io_change.abs > SIGNIFICANT_THRESHOLD
      changes << {
        category: :io,
        metric: 'Total I/O Blocks',
        before: buffer1[:total_io_blocks],
        after: buffer2[:total_io_blocks],
        change_percent: io_change,
        impact: classify_impact(io_change)
      }
    end

    changes.sort_by { |c| -c[:change_percent].abs }
  end

  private

  def compare_metrics(metrics1, metrics2)
    metrics1.keys.map do |key|
      val1 = metrics1[key] || 0
      val2 = metrics2[key] || 0
      pct_change = percent_change(val1, val2)

      {
        metric: key,
        before: val1,
        after: val2,
        difference: val2 - val1,
        percent_change: pct_change,
        significant: pct_change.abs > SIGNIFICANT_THRESHOLD
      }
    end
  end

  def percent_change(before_val, after_val)
    return 0.0 if before_val == after_val
    return 100.0 if before_val.zero? && after_val > 0
    return -100.0 if before_val > 0 && after_val.zero?
    return 0.0 if before_val.zero? && after_val.zero?

    ((after_val - before_val).to_f / before_val * 100).round(2)
  end

  def classify_impact(percent_change)
    if percent_change > SIGNIFICANT_THRESHOLD
      :negative
    elsif percent_change < -SIGNIFICANT_THRESHOLD
      :positive
    else
      :neutral
    end
  end
end
