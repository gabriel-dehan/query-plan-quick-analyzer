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

### Analyze output
```markdown
======================================================================
                         Query Plan Analysis
======================================================================

# Summary
  Total Time:    2.55 s
  Planning Time: 59.49 ms
  Execution Time: 2.49 s
  Total Cost:    155270.98
  Rows (actual): 11,531
  Rows (planned): 11,938

# Timing
  Planning:   59.49 ms (2.3%)
  Execution:  2.49 s (97.7%)
  Total:      2.55 s

# Buffer Statistics
  Shared Blocks:
    Hit:      840,427 blocks
    Read:     18,115 blocks
    Dirtied:  0 blocks
    Written:  0 blocks
  Hit Ratio:  97.89%

# Node Analysis
  Index Scan                     17
  Hash Join                      12
  Hash                           12
  Nested Loop                    9
  Sort                           5
  Seq Scan                       3
  Merge Join                     2
  Index Only Scan                2
  Bitmap Heap Scan               2
  Bitmap Index Scan              2
  Aggregate                      1
  Gather Merge                   1

# Top 5 Most Expensive Operations
  1. Index Only Scan on menu_item_tags
     Time: 2.11 s, Cost: 11509.63, Rows: 127,888
  2. Index Scan on restaurants
     Time: 657.98 ms, Cost: 2.59, Rows: 0
  3. Index Scan on items
     Time: 565.02 ms, Cost: 2.6, Rows: 1
  4. Index Only Scan on menu_tags
     Time: 438.72 ms, Cost: 4368.97, Rows: 38,633
  5. Hash
     Time: 365.05 ms, Cost: 110190.42, Rows: 10,973

# Sequential Scans (3)
  leases                         31,266 rows, 82.05 ms, loops: 3
  doubtful_debt_addendums        2,546 rows, 0.57 ms, loops: 1
  doubtful_debts                 2,491 rows, 0.74 ms, loops: 1

# Row Estimation Accuracy
  Accurate estimates:   22
  Inaccurate estimates: 46
  Average ratio:        1.97
  Worst estimates:
    Index Scan (tags): 73 → 507 (6.9x off)
    Hash: 73 → 507 (6.9x off)
    Index Scan (tags): 73 → 507 (6.9x off)
```

### Comparison output

```markdown
======================================================================
                        Query Plan Comparison
======================================================================

# Overall Verdict
✓ IMPROVED (Time: -29.5%, Cost: +126.5%)

# Key Changes
  ↓ Total Time: 2550.23 → 1797.1 (-29.5%)
  ↓ Total I/O Blocks: 18,115 → 14,126 (-22.0%)

# Timing Comparison
  planning_time                       59.49 →           43.66     -26.6%
  execution_time                    2490.74 →         1753.45     -29.6%
  total_time                        2550.23 →          1797.1     -29.5%

# Cost Comparison
  total_cost                      155270.98 →       351713.22    +126.5%
  startup_cost                    155241.13 →       351683.37    +126.5%

# Buffer Comparison
  shared_hit_blocks                 840,427 →         539,047     -35.9%
  shared_read_blocks                 18,115 →          14,126     -22.0%
  shared_dirtied_blocks                   0 →               0       0.0%
  shared_written_blocks                   0 →               0       0.0%
  temp_read_blocks                        0 →               0       0.0%
  temp_written_blocks                     0 →               0       0.0%
  local_hit_blocks                        0 →               0       0.0%
  local_read_blocks                       0 →               0       0.0%
  buffer_hit_ratio                    97.89 →           97.45      -0.5%
  total_io_blocks                    18,115 →          14,126     -22.0%

# Node Type Changes
  - Hash Join                      12 → 8 (-4)
  - Hash                           12 → 8 (-4)
  + Limit                          0 → 4 (+4)
  - Seq Scan                       3 → 0 (-3)
  - Sort                           5 → 3 (-2)
  + Index Scan                     17 → 19 (+2)
  - Gather Merge                   1 → 0 (-1)
  - Merge Join                     2 → 1 (-1)
  + Gather                         0 → 1 (+1)

# Row Count Comparison
  Actual Rows:   11,531 → 11,531 (0.0%)
  Planned Rows:  11,938 → 11,938 (0.0%)

  Estimation Accuracy:
    Before: 22 accurate, 46 inaccurate (avg ratio: 1.97)
    After:  20 accurate, 40 inaccurate (avg ratio: 1.65)
    ✓ Estimation improved!

# Sequential Scan Comparison
  Count:      3 → 0 (-3)
  Total Time: 83.37 ms → 0 ms
  Total Rows: 36,303 → 0

# Sort Comparison
  Sort Count:      5 → 3 (-2)
  Disk Sorts:      0 → 0 (0)
  Total Sort Time: 283.59 ms → 252.44 ms

# Plan Complexity
  Plan Depth:   30 → 19 (-11)
  Total Nodes:  68 → 60 (-8)
  ✓ Plan simplified
```


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
