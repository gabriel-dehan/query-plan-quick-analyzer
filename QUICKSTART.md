# Quick Start Guide

## Generate Query Plans from Your SQL

You have a SQL query in `.claude/local/thirdparties/queries/basic_with_changes.sql`. Here's how to generate and analyze its execution plan:

### Step 1: Generate the Plan

```bash
# Using psql directly
psql -d your_database -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) $(cat queries/query.sql)" > plan_before.json

# Or in a psql session
\i queries/query.sql

# Then wrap it with EXPLAIN
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT ... (your query here) ...
\g plan_before.json
```

### Step 2: Analyze the Plan

```bash
cd tmp/query_plan_analyzer
./bin/analyze_plan plan_before.json
```

### Step 3: Make Optimizations

Based on the analysis, you might:

1. **Add indexes** if you see sequential scans on large tables
2. **Update statistics** if estimation accuracy is poor
3. **Adjust query** if you see expensive operations

Example - add an index:
```sql
-- If you see: "Sequential Scans (1) on items"
CREATE INDEX idx_items_company_date
ON items(company_id, date);
```

### Step 4: Generate New Plan and Compare

```bash
# Generate plan after optimization
psql -d your_database -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) $(cat queries/query.sql)" > plan_after.json

# Compare the two plans
./bin/analyze_plan plan_before.json plan_after.json

# Export comparison for documentation
./bin/analyze_plan plan_before.json plan_after.json --export-csv comparison.csv
```

## Using with Rails Console

If you're working in a Rails environment:

```ruby
# In rails console
sql = File.read('queries/query.sql')
explain_sql = "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}"

result = ActiveRecord::Base.connection.execute(explain_sql)
File.write('plan.json', result.to_a.to_json)
```

Then analyze:
```bash
./bin/analyze_plan plan.json
```

## What to Look For

### 🔴 Red Flags
- Sequential scans on tables with >10k rows
- Buffer hit ratio < 95%
- Large temp block usage (disk spills)
- Estimation accuracy with ratio > 10x off
- High I/O read time

### 🟢 Good Signs
- Index scans on large tables
- Buffer hit ratio > 99%
- No temp blocks
- Accurate row estimates (ratio < 2x)
- Low I/O timing

## Tips

- **Always run ANALYZE twice**: First run may be slower due to cold cache
- **Compare apples to apples**: Clear cache or run both queries in same session
- **Watch for parameter changes**: Same query with different date ranges may behave differently
- **Track over time**: Export results to CSV to track performance trends

## Troubleshooting

**Q: My plans are huge and hard to read**
A: Use `--export-json` to export and explore in a JSON viewer

**Q: Comparison shows regression but query feels faster**
A: Check if buffer hit ratio improved - fewer reads from disk

**Q: Getting "Invalid JSON format" error**
A: Make sure you used `FORMAT JSON` in the EXPLAIN command

**Q: Plans show improvement but production is still slow**
A: Production might have different data distribution, check with production-like data volume
