# Architecture

## Solution Model

The monitoring platform is organized into three layers.

### 1. Collector Layer

PowerShell collectors gather data from infrastructure services, operating systems, domain controllers, Microsoft 365, and backup targets.

Typical collector responsibilities include:

- reading event logs
- querying system configuration
- checking certificates
- validating backup presence
- pulling cloud or Microsoft 365 metadata

### 2. Data Layer

All collected data is written into a centralized SQL Server monitoring database.

The schema is designed around:

- `fact` tables for measurements, events, and snapshots
- `dim` tables for normalized reference entities such as servers and users

This structure supports both operational troubleshooting and historical analytics.

### 3. Reporting Layer

A reporting or dashboard layer reads from the monitoring database to provide:

- centralized visibility
- audit-oriented views
- trend analysis
- issue investigation support

## Data Flow

```text
PowerShell Collectors
    -> INSERT INTO monitoring database
    -> fact and dim tables
    -> reporting queries and dashboards
```

## Design Characteristics

- modular collector pattern
- SQL-backed historical storage
- automation through Windows Task Scheduler
- extensible monitoring scope
- separation between collection, storage, and presentation

## Sanitization Note

This public repository intentionally replaces internal server names, environment identifiers, account names, credentials, and infrastructure-specific paths with neutral placeholders and generalized descriptions.

