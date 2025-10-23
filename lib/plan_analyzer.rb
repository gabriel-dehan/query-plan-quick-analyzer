# Analyzes query plan tree structure and identifies bottlenecks
class PlanAnalyzer
  attr_reader :plan_node

  def initialize(plan_node)
    @plan_node = plan_node
  end

  # Traverse the entire plan tree and collect all nodes
  def all_nodes
    @all_nodes ||= collect_nodes(plan_node)
  end

  # Count nodes by type
  def node_type_counts
    all_nodes.group_by { |n| n['Node Type'] }.transform_values(&:count)
  end

  # Get total cost by node type
  def cost_by_node_type
    all_nodes.group_by { |n| n['Node Type'] }.transform_values do |nodes|
      nodes.sum { |n| n['Total Cost'] || 0 }
    end
  end

  # Get actual time by node type (exclusive time - not including children)
  # This avoids double-counting since Actual Total Time includes child times
  def time_by_node_type
    all_nodes.group_by { |n| n['Node Type'] }.transform_values do |nodes|
      nodes.sum { |n| calculate_exclusive_time(n) }
    end
  end

  # Identify expensive operations (top N by actual time)
  # Uses exclusive time to avoid counting parent overhead that includes children
  def expensive_operations(limit = 5)
    all_nodes
      .select { |n| n['Actual Total Time'] }
      .map do |node|
        {
          node_type: node['Node Type'],
          relation_name: node['Relation Name'],
          total_time: calculate_exclusive_time(node),
          rows: node['Actual Rows'],
          cost: node['Total Cost']
        }
      end
      .sort_by { |n| -n[:total_time] }
      .take(limit)
  end

  # Find sequential scans (potential optimization targets)
  def sequential_scans
    all_nodes.select { |n| n['Node Type'] == 'Seq Scan' }.map do |node|
      {
        relation: node['Relation Name'],
        rows: node['Actual Rows'],
        total_time: calculate_exclusive_time(node),
        loops: node['Actual Loops'] || 1,
        filter: node['Filter']
      }
    end
  end

  # Find index scans
  def index_scans
    all_nodes.select { |n| n['Node Type'] =~ /Index.*Scan/ }.map do |node|
      {
        type: node['Node Type'],
        relation: node['Relation Name'],
        index_name: node['Index Name'],
        rows: node['Actual Rows'],
        total_time: calculate_exclusive_time(node),
        loops: node['Actual Loops'] || 1
      }
    end
  end

  # Find sorts and their memory usage
  # Returns exclusive time (not including children) to avoid double-counting
  def sorts
    all_nodes.select { |n| n['Node Type'] == 'Sort' }.map do |node|
      {
        sort_key: node['Sort Key'],
        sort_method: node['Sort Method'],
        sort_space_used: node['Sort Space Used'],
        sort_space_type: node['Sort Space Type'],
        rows: node['Actual Rows'],
        total_time: calculate_exclusive_time(node),
        loops: node['Actual Loops'] || 1
      }
    end
  end

  # Find joins and their types
  def joins
    all_nodes.select { |n| n['Node Type'] =~ /Join/ }.map do |node|
      {
        type: node['Node Type'],
        join_type: node['Join Type'],
        rows_estimated: node['Plan Rows'],
        rows_actual: node['Actual Rows'],
        estimation_accuracy: calculate_estimation_accuracy(node['Plan Rows'], node['Actual Rows']),
        total_time: calculate_exclusive_time(node),
        loops: node['Actual Loops'] || 1
      }
    end
  end

  # Calculate total buffer usage from root node
  # Note: PostgreSQL's EXPLAIN buffer statistics are cumulative - parent nodes
  # include all child node buffers. So we only need the root node's statistics.
  def total_buffer_stats
    stats = {
      shared_hit_blocks: plan_node['Shared Hit Blocks'] || 0,
      shared_read_blocks: plan_node['Shared Read Blocks'] || 0,
      shared_dirtied_blocks: plan_node['Shared Dirtied Blocks'] || 0,
      shared_written_blocks: plan_node['Shared Written Blocks'] || 0,
      temp_read_blocks: plan_node['Temp Read Blocks'] || 0,
      temp_written_blocks: plan_node['Temp Written Blocks'] || 0,
      local_hit_blocks: plan_node['Local Hit Blocks'] || 0,
      local_read_blocks: plan_node['Local Read Blocks'] || 0
    }

    total_shared = stats[:shared_hit_blocks] + stats[:shared_read_blocks]
    stats[:buffer_hit_ratio] = total_shared.zero? ? 100.0 : (stats[:shared_hit_blocks].to_f / total_shared * 100).round(2)
    stats[:total_io_blocks] = stats[:shared_read_blocks] + stats[:shared_written_blocks] +
                               stats[:temp_read_blocks] + stats[:temp_written_blocks]

    stats
  end

  # Calculate plan depth (max nesting level)
  def plan_depth
    calculate_depth(plan_node, 0)
  end

  # Get estimation accuracy statistics
  def estimation_accuracy
    nodes_with_estimates = all_nodes.select { |n| n['Plan Rows'] && n['Actual Rows'] }
    return { accurate: 0, inaccurate: 0, avg_ratio: 0 } if nodes_with_estimates.empty?

    ratios = nodes_with_estimates.map do |node|
      calculate_estimation_accuracy(node['Plan Rows'], node['Actual Rows'])
    end

    accurate = ratios.count { |r| r >= 0.5 && r <= 2.0 }
    inaccurate = ratios.count { |r| r < 0.5 || r > 2.0 }

    {
      accurate: accurate,
      inaccurate: inaccurate,
      avg_ratio: (ratios.sum / ratios.count.to_f).round(2),
      worst_nodes: find_worst_estimates(nodes_with_estimates, 3)
    }
  end

  private

  # Calculate exclusive time for a node (time spent in this node, not including children)
  # PostgreSQL's Actual Total Time includes all child times, so we subtract them
  def calculate_exclusive_time(node)
    # Total time for this node (inclusive of children) multiplied by loops
    total_inclusive_time = (node['Actual Total Time'] || 0) * (node['Actual Loops'] || 1)

    # Sum up all children's times
    children_time = 0
    if node['Plans']
      node['Plans'].each do |child|
        children_time += (child['Actual Total Time'] || 0) * (child['Actual Loops'] || 1)
      end
    end

    # Exclusive time is the difference (with a floor of 0 to handle rounding errors)
    [total_inclusive_time - children_time, 0].max
  end

  def collect_nodes(node, collection = [])
    collection << node

    if node['Plans']
      node['Plans'].each do |child|
        collect_nodes(child, collection)
      end
    end

    collection
  end

  def calculate_depth(node, current_depth)
    return current_depth unless node['Plans']

    max_child_depth = node['Plans'].map { |child| calculate_depth(child, current_depth + 1) }.max
    max_child_depth || current_depth
  end

  def calculate_estimation_accuracy(plan_rows, actual_rows)
    return 1.0 if plan_rows == actual_rows
    return 0.0 if plan_rows.zero? || actual_rows.zero?

    ratio = actual_rows.to_f / plan_rows
    ratio > 1.0 ? ratio : 1.0 / ratio
  end

  def find_worst_estimates(nodes, limit)
    nodes
      .map do |node|
        ratio = calculate_estimation_accuracy(node['Plan Rows'], node['Actual Rows'])
        {
          node_type: node['Node Type'],
          relation: node['Relation Name'],
          estimated: node['Plan Rows'],
          actual: node['Actual Rows'],
          ratio: ratio
        }
      end
      .sort_by { |n| -n[:ratio] }
      .take(limit)
  end
end
