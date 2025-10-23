# Query Plan Analyzer - Changelog

## Enhanced Comparison Features

### New Comparisons Added

#### 1. Row Count Comparison
Shows changes in actual and planned row counts between two query plans:
- **Actual Rows**: Number of rows actually processed (runtime)
- **Planned Rows**: Number of rows PostgreSQL estimated
- **Estimation Accuracy**: Tracks if planner got better/worse at predicting
  - Accurate estimates: Within 2x of actual
  - Inaccurate estimates: More than 2x off
  - Average ratio: Overall estimation quality

**Why it matters**: Large differences between planned and actual rows indicate the query planner is making poor decisions, which can lead to inefficient execution plans.

#### 2. I/O Timing Comparison
Tracks changes in actual I/O time (requires `track_io_timing = ON`):
- **I/O Read Time**: Time spent reading from disk
- **I/O Write Time**: Time spent writing to disk

**Why it matters**: Direct measurement of disk I/O impact on query performance. High I/O time suggests need for better indexes or increased cache.

#### 3. Sort Comparison
Analyzes sorting operations:
- **Sort Count**: Number of sort operations
- **Disk Sorts**: Sorts that spilled to disk (bad!)
- **Total Sort Time**: Time spent in sort operations
- Special alerts for sorts moving to/from disk

**Why it matters**: Disk sorts are extremely slow. If sorts spill to disk, consider increasing `work_mem` or adding indexes to avoid sorts.

#### 4. Plan Complexity
Measures query plan structure:
- **Plan Depth**: Maximum nesting level of operations
- **Total Nodes**: Total number of operations in the plan

**Why it matters**: Simpler plans are usually better. If complexity increases, the optimizer might be choosing a more convoluted path.

### Updated Export Formats

**CSV Export** now includes:
- Row count metrics
- I/O timing
- All buffer statistics
- Categorized by metric type

**JSON Export** now includes:
- Complete row comparison data
- Sort statistics
- Plan complexity metrics
- Estimation accuracy details

### Example Output

```
# Row Count Comparison
  Actual Rows:   11,531 → 11,938 (+3.5%)
  Planned Rows:  11,000 → 11,500 (+4.5%)

  Estimation Accuracy:
    Before: 45 accurate, 5 inaccurate (avg ratio: 2.34)
    After:  48 accurate, 2 inaccurate (avg ratio: 1.89)
    ✓ Estimation improved!

# I/O Timing Comparison
  io_read_time    234.56 ms → 89.23 ms (-62.0%)
  io_write_time   12.34 ms  → 5.67 ms  (-54.1%)

# Sort Comparison
  Sort Count:      3 → 2 (-1)
  Disk Sorts:      1 → 0 (-1)
  Total Sort Time: 456.78 ms → 234.56 ms
  ✓ All sorts now in memory!

# Plan Complexity
  Plan Depth:   6 → 4 (-2)
  Total Nodes:  23 → 18 (-5)
  ✓ Plan simplified
```

## What Was Previously Missing

Before these enhancements, the comparison **did not show**:
1. Whether row estimates improved or got worse
2. Actual I/O timing (only showed buffer reads, not time)
3. Sort memory usage and disk spills
4. Plan structure changes (depth, node count)

These metrics are crucial for understanding:
- Query planner effectiveness
- I/O bottlenecks
- Memory pressure issues
- Overall query plan quality

## How to Use

All comparisons are automatically included when comparing two plans:

```bash
./bin/analyze_plan before.json after.json
```

The tool will now show:
- ✓ Green checkmarks for improvements
- ✗ Red X marks for regressions
- Specific feedback on estimation accuracy, sorts, and complexity

## Key Metrics to Watch

### Red Flags After Optimization
- **Estimation got worse**: Inaccurate estimates increased
- **Sorts spilling to disk**: Disk sorts > 0
- **Plan became more complex**: Depth or node count increased
- **I/O time increased**: More time reading/writing

### Good Signs
- **Estimation improved**: More accurate row estimates
- **All sorts now in memory**: Disk sorts = 0
- **Plan simplified**: Fewer nodes or less depth
- **I/O time decreased**: Less disk activity
