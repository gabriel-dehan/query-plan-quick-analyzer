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

  # Get actual time by node type
  def time_by_node_type
    all_nodes.group_by { |n| n['Node Type'] }.transform_values do |nodes|
      nodes.sum { |n| (n['Actual Total Time'] || 0) * (n['Actual Loops'] || 1) }
    end
  end

  # Identify expensive operations (top N by actual time)
  def expensive_operations(limit = 5)
    all_nodes
      .select { |n| n['Actual Total Time'] }
      .map do |node|
        {
          node_type: node['Node Type'],
          relation_name: node['Relation Name'],
          total_time: node['Actual Total Time'] * (node['Actual Loops'] || 1),
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
        total_time: node['Actual Total Time'] * (node['Actual Loops'] || 1),
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
        total_time: node['Actual Total Time'] * (node['Actual Loops'] || 1),
        loops: node['Actual Loops'] || 1
      }
    end
  end

  # Find sorts and their memory usage
  def sorts
    all_nodes.select { |n| n['Node Type'] == 'Sort' }.map do |node|
      {
        sort_key: node['Sort Key'],
        sort_method: node['Sort Method'],
        sort_space_used: node['Sort Space Used'],
        sort_space_type: node['Sort Space Type'],
        rows: node['Actual Rows'],
        total_time: node['Actual Total Time'] * (node['Actual Loops'] || 1),
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
        total_time: node['Actual Total Time'] * (node['Actual Loops'] || 1),
        loops: node['Actual Loops'] || 1
      }
    end
  end

  # Calculate total buffer usage across all nodes
  def total_buffer_stats
    stats = {
      shared_hit_blocks: 0,
      shared_read_blocks: 0,
      shared_dirtied_blocks: 0,
      shared_written_blocks: 0,
      temp_read_blocks: 0,
      temp_written_blocks: 0,
      local_hit_blocks: 0,
      local_read_blocks: 0
    }

    all_nodes.each do |node|
      stats[:shared_hit_blocks] += node['Shared Hit Blocks'] || 0
      stats[:shared_read_blocks] += node['Shared Read Blocks'] || 0
      stats[:shared_dirtied_blocks] += node['Shared Dirtied Blocks'] || 0
      stats[:shared_written_blocks] += node['Shared Written Blocks'] || 0
      stats[:temp_read_blocks] += node['Temp Read Blocks'] || 0
      stats[:temp_written_blocks] += node['Temp Written Blocks'] || 0
      stats[:local_hit_blocks] += node['Local Hit Blocks'] || 0
      stats[:local_read_blocks] += node['Local Read Blocks'] || 0
    end

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
