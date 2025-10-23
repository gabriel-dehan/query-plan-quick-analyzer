require 'json'

# Main class for loading and parsing PostgreSQL EXPLAIN (FORMAT JSON) output
class QueryPlanAnalyzer
  attr_reader :raw_data, :plan_data, :file_path

  def initialize(file_path)
    @file_path = file_path
    @raw_data = load_file(file_path)
    @plan_data = parse_json(@raw_data)
  end

  def planning_time
    @plan_data[0]['Planning Time'] || 0
  end

  def execution_time
    @plan_data[0]['Execution Time'] || 0
  end

  def total_time
    planning_time + execution_time
  end

  def plan_node
    @plan_data[0]['Plan']
  end

  def triggers
    @plan_data[0]['Triggers'] || []
  end

  def jit_info
    @plan_data[0]['JIT'] || {}
  end

  # Get high-level summary metrics
  def summary_metrics
    {
      planning_time: planning_time,
      execution_time: execution_time,
      total_time: total_time,
      total_cost: plan_node['Total Cost'],
      startup_cost: plan_node['Startup Cost'],
      actual_rows: plan_node['Actual Rows'],
      plan_rows: plan_node['Plan Rows'],
      actual_loops: plan_node['Actual Loops'] || 1
    }
  end

  # Get buffer statistics from the plan
  def buffer_stats
    shared_hit_blocks = plan_node.dig('Shared Hit Blocks') || 0
    shared_read_blocks = plan_node.dig('Shared Read Blocks') || 0
    shared_dirtied_blocks = plan_node.dig('Shared Dirtied Blocks') || 0
    shared_written_blocks = plan_node.dig('Shared Written Blocks') || 0
    temp_read_blocks = plan_node.dig('Temp Read Blocks') || 0
    temp_written_blocks = plan_node.dig('Temp Written Blocks') || 0
    local_hit_blocks = plan_node.dig('Local Hit Blocks') || 0
    local_read_blocks = plan_node.dig('Local Read Blocks') || 0

    {
      shared_hit_blocks: shared_hit_blocks,
      shared_read_blocks: shared_read_blocks,
      shared_dirtied_blocks: shared_dirtied_blocks,
      shared_written_blocks: shared_written_blocks,
      temp_read_blocks: temp_read_blocks,
      temp_written_blocks: temp_written_blocks,
      local_hit_blocks: local_hit_blocks,
      local_read_blocks: local_read_blocks,
      total_shared_blocks: shared_hit_blocks + shared_read_blocks,
      buffer_hit_ratio: calculate_buffer_hit_ratio(shared_hit_blocks, shared_read_blocks)
    }
  end

  # Get I/O timing information
  def io_timing
    {
      io_read_time: plan_node.dig('I/O Read Time') || 0,
      io_write_time: plan_node.dig('I/O Write Time') || 0
    }
  end

  private

  def load_file(path)
    unless File.exist?(path)
      raise ArgumentError, "File not found: #{path}"
    end

    File.read(path)
  end

  def parse_json(content)
    JSON.parse(content)
  rescue JSON::ParserError => e
    raise ArgumentError, "Invalid JSON format: #{e.message}"
  end

  def calculate_buffer_hit_ratio(hits, reads)
    total = hits + reads
    return 100.0 if total.zero?
    (hits.to_f / total * 100).round(2)
  end
end
