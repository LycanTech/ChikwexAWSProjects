# VPC Flow Logs + Athena – Cost Calculation

## Resources and Pricing (us-east-1, as of 2025)

### VPC Flow Logs
| Item | Rate | Notes |
|------|------|-------|
| Flow log data ingested | $0.50 / GB | Charged per GB of log data published |
| S3 PUT requests | $0.005 / 1,000 requests | Flow log delivery triggers PUTs |

**Lab estimate (light traffic, ~1 hour):**
- ~5 MB of raw log data at $0.50/GB = **~$0.003**

### S3 Storage
| Item | Rate |
|------|------|
| Standard storage | $0.023 / GB / month |
| Intelligent-Tiering | $0.023 / GB (frequent) → $0.0125 (infrequent) |

**Lab estimate (~50 MB Parquet files):**
- 0.05 GB × $0.023 = **~$0.001 / month**

### Athena Queries
| Item | Rate | Notes |
|------|------|-------|
| Data scanned | $5.00 / TB | Billed per query, rounded up to 10 MB |
| Parquet compression benefit | ~10–20x reduction | Columnar format skips irrelevant columns |
| Partition pruning benefit | Varies | year/month/day/hour filter avoids full scan |

**Plain-text log query example:**
- 100 MB raw logs × $5/TB = $0.00050 per query

**Parquet equivalent (15x compression):**
- 100 MB ÷ 15 = ~6.7 MB scanned
- 6.7 MB × $5/TB = **$0.000034 per query** → ~15x cheaper

**Running all 5 saved queries once on a day's worth of lab data:**
- Estimated total: **< $0.01**

### EC2 (lab instances, t3.micro)
| Item | Rate |
|------|------|
| t3.micro on-demand | $0.0104 / hour |
| 2 instances × 2 hours | **~$0.04** |

### NAT Gateway
| Item | Rate |
|------|------|
| Hourly charge | $0.045 / hour |
| Data processed | $0.045 / GB |
| 2 hours | **~$0.09** |

---

## Total Estimated Lab Cost

| Component | Estimate |
|-----------|----------|
| VPC Flow Log ingestion | < $0.01 |
| S3 storage | < $0.01 |
| Athena queries (all 5) | < $0.01 |
| EC2 (2 × t3.micro, 2h) | ~$0.04 |
| NAT Gateway (2h + data) | ~$0.09 |
| **Total** | **~$0.15** |

> **Note:** Destroy all resources immediately after the lab with `terraform destroy`
> to avoid ongoing NAT Gateway and EC2 charges.

## Cost Optimization Applied in This Lab

1. **Parquet format** – columnar storage, Snappy-compressed → ~10–20x less data scanned
2. **Hive partitions** (`year/month/day/hour`) → Athena skips entire time windows
3. **Partition projection** in the table definition → no `MSCK REPAIR TABLE` needed
4. **Bytes-scanned cap** in the workgroup (1 GB) → prevents runaway queries
5. **S3 lifecycle policy** → moves to Intelligent-Tiering at 30 days, expires at 90
6. **`per_hour_files = true`** → smaller files, better parallel scan performance
