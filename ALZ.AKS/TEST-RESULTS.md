# ALZ.AKS Module — Test Results

> Last updated: 2026-02-21

## Summary

| Metric | Value |
|--------|-------|
| Total Tests | 10 |
| Passed | 0 |
| Failed | 0 |
| Pending | 10 |

## Test Matrix

| ID | Scenario | Options Delta | Status | Bootstrap | CI | CD | Resources | Duration | Notes |
|----|----------|--------------|--------|-----------|----|----|-----------|----------|-------|
| T01 | single_region_baseline | defaults | ⏳ Pending | — | — | — | — | — | — |
| T02 | multi_region_baseline | Flux, VPA, Backup, GeoRepl | ⏳ Pending | — | — | — | — | — | — |
| T03 | single_region_regulated | Premium, FIPS, Istio, Backup, CostAnalysis | ⏳ Pending | — | — | — | — | — | — |
| T04 | multi_region_regulated | All features on | ⏳ Pending | — | — | — | — | — | — |
| T05 | single_region_baseline | AppGW=off | ⏳ Pending | — | — | — | — | — | — |
| T06 | single_region_baseline | Istio=on | ⏳ Pending | — | — | — | — | — | — |
| T07 | single_region_baseline | Flux=on | ⏳ Pending | — | — | — | — | — | — |
| T08 | single_region_baseline | Defender+Prometheus=off | ⏳ Pending | — | — | — | — | — | — |
| T09 | single_region_baseline | KEDA=off, VPA=on | ⏳ Pending | — | — | — | — | — | — |
| T10 | single_region_baseline | Corp mode (hub peering) | ⏳ Pending | — | — | — | — | — | — |

## Detailed Results

### T01: single_region_baseline (defaults)
- **Status:** ⏳ Pending
- **Repo:** `akstest-t01`

### T02: multi_region_baseline
- **Status:** ⏳ Pending
- **Repo:** `akstest-t02`

### T03: single_region_regulated
- **Status:** ⏳ Pending
- **Repo:** `akstest-t03`

### T04: multi_region_regulated
- **Status:** ⏳ Pending
- **Repo:** `akstest-t04`

### T05: App Gateway disabled
- **Status:** ⏳ Pending
- **Repo:** `akstest-t05`

### T06: Istio enabled
- **Status:** ⏳ Pending
- **Repo:** `akstest-t06`

### T07: Flux enabled
- **Status:** ⏳ Pending
- **Repo:** `akstest-t07`

### T08: Monitoring disabled
- **Status:** ⏳ Pending
- **Repo:** `akstest-t08`

### T09: Scaling swapped
- **Status:** ⏳ Pending
- **Repo:** `akstest-t09`

### T10: Corp mode
- **Status:** ⏳ Pending
- **Repo:** `akstest-t10`
