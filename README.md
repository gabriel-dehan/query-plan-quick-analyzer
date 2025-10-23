# PostgreSQL Query Plan Analyzer

A Ruby tool for analyzing and comparing PostgreSQL query execution plans. Get quick insights into query performance, identify bottlenecks, and compare optimizations at a glance.

## Features

- **Single Plan Analysis**: Detailed breakdown of timing, costs, buffers, and operations
- **Plan Comparison**: Side-by-side comparison of two query plans with improvement/regression detection
- **Bottleneck Detection**: Automatically identifies expensive operations, sequential scans, and estimation issues
- **Export Options**: Save comparisons to CSV or JSON for further analysis
- **Color-coded Output**: Easy-to-read terminal output with visual indicators

## Installation

No installation needed! Just requires Ruby (2.7+).

```bash
# Make the script executable
chmod +x bin/analyze_plan

# Run it
./bin/analyze_plan --help
```

## Generating Query Plans

To use this tool, you need to generate query execution plans in JSON format:

```sql
-- In PostgreSQL, run your query with EXPLAIN
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM your_table WHERE conditions;

-- Save to a file using psql
\o plan.json
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT ...;
\o

-- Or redirect output
psql -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT ..." > plan.json
```

**Important**: Always use these flags:
- `ANALYZE` - Actually execute the query and get real timings
- `BUFFERS` - Include buffer hit/miss statistics
- `FORMAT JSON` - Output in JSON format (required by this tool)

## Usage

### Analyze a Single Plan

```bash
./bin/analyze_plan query_plan.json
```

Output includes:
- Summary metrics (timing, cost, rows)
- Timing breakdown (planning vs execution)
- Buffer statistics (hit ratio, I/O blocks)
- I/O timing (if available)
- Node type analysis
- Top 5 most expensive operations
- Sequential scans
- Row estimation accuracy

### Compare Two Plans

```bash
./bin/analyze_plan before_optimization.json after_optimization.json
```

Output includes:
- Overall verdict (improved/regressed/similar)
- Key changes with impact indicators
- Timing comparison
- Cost comparison
- Buffer comparison
- Node type changes
- Sequential scan comparison

### Export Comparison Results

```bash
# Export to CSV
./bin/analyze_plan before.json after.json --export-csv results.csv

# Export to JSON
./bin/analyze_plan before.json after.json --export-json results.json

# Export to both
./bin/analyze_plan before.json after.json --export-csv results.csv --export-json results.json
```

### Disable Colors

```bash
./bin/analyze_plan plan.json --no-color
```

## Example Workflow

```bash
# 1. Generate baseline plan
psql -d mydb -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
  SELECT * FROM orders WHERE customer_id = 123" > before.json

# 2. Add an index
psql -d mydb -c "CREATE INDEX idx_orders_customer ON orders(customer_id)"

# 3. Generate new plan
psql -d mydb -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
  SELECT * FROM orders WHERE customer_id = 123" > after.json

# 4. Compare the plans
./bin/analyze_plan before.json after.json
```

## Understanding the Output

### Metrics Explained

- **Planning Time**: Time PostgreSQL spent generating the query plan
- **Execution Time**: Actual time spent executing the query
- **Total Cost**: PostgreSQL's internal cost estimate (higher = more expensive)
- **Startup Cost**: Cost before first row is returned
- **Actual Rows**: Number of rows actually processed
- **Plan Rows**: Number of rows PostgreSQL estimated

### Buffer Statistics

- **Shared Hit Blocks**: Data found in cache (good!)
- **Shared Read Blocks**: Data read from disk (slower)
- **Hit Ratio**: Percentage of data found in cache (aim for >95%)
- **Temp Blocks**: Temporary disk usage (indicates memory overflow)

### Node Types

- **Seq Scan**: Full table scan (slow for large tables)
- **Index Scan**: Using an index (usually faster)
- **Nested Loop**: Join method (can be slow with many rows)
- **Hash Join**: Join using hash table (often faster)
- **Sort**: Sorting operation (may use disk if data is large)

### Performance Indicators

✓ Green: Improvement
✗ Red: Regression
≈ Yellow: No significant change
↓ Green: Decrease (good for time/cost)
↑ Red: Increase (bad for time/cost)

## Key Metrics for Comparison

When comparing two query plans, focus on:

1. **Total Time**: Overall execution speed
2. **Buffer Hit Ratio**: Cache efficiency
3. **Sequential Scans**: Potential missing indexes
4. **I/O Blocks**: Disk activity
5. **Estimation Accuracy**: Query planner effectiveness

A good optimization should show:
- Decreased total time
- Higher buffer hit ratio (or at least same)
- Fewer sequential scans (if they were on large tables)
- Lower I/O block counts
- Better estimation accuracy

## Project Structure

```
query_plan_analyzer/
├── bin/
│   └── analyze_plan          # CLI executable
├── lib/
│   ├── query_plan_analyzer.rb # JSON parser and metrics extractor
│   ├── plan_analyzer.rb       # Tree traversal and analysis
│   ├── plan_comparator.rb     # Comparison logic
│   └── plan_reporter.rb       # Output formatting
├── examples/                  # Example query plans
└── README.md
```

## Advanced Usage

### Programmatic Use

You can also use the classes directly in Ruby scripts:

```ruby
require_relative 'lib/query_plan_analyzer'
require_relative 'lib/plan_analyzer'
require_relative 'lib/plan_comparator'

# Analyze a single plan
plan = QueryPlanAnalyzer.new('plan.json')
analyzer = PlanAnalyzer.new(plan.plan_node)

puts "Total time: #{plan.total_time}ms"
puts "Buffer hit ratio: #{analyzer.total_buffer_stats[:buffer_hit_ratio]}%"

# Compare two plans
comparator = PlanComparator.new('before.json', 'after.json')
verdict = comparator.verdict

if verdict[:status] == :improved
  puts "Query improved by #{-verdict[:time_improvement]}%"
end
```

## Troubleshooting

### "File not found" error
Make sure the file path is correct and the file exists.

### "Invalid JSON format" error
Ensure you used `FORMAT JSON` in your EXPLAIN command.

### Missing buffer statistics
Use the `BUFFERS` flag in EXPLAIN: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`

### Missing I/O timing
Enable in PostgreSQL: `SET track_io_timing = ON;` before running EXPLAIN.

## Tips for Query Optimization

1. **High buffer reads**: Add indexes or increase shared_buffers
2. **Sequential scans on large tables**: Add appropriate indexes
3. **Poor estimation accuracy**: Run ANALYZE on tables to update statistics
4. **High temp block usage**: Increase work_mem to avoid disk sorts
5. **Many nested loops**: Consider enabling hash joins or merge joins

## Contributing

Feel free to extend this tool with additional analysis features, export formats, or visualizations.

## License

MIT License - feel free to use and modify as needed.
