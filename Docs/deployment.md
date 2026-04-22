# Deployment And Operations

## Initial Deployment Model

A typical deployment includes:

- one SQL Server instance for the monitoring database
- one or more Windows hosts running scheduled PowerShell collectors
- a reporting or dashboard consumer layer

## Setup Sequence

### 1. Create Database Objects

Deploy the required tables, schemas, and migrations for the monitoring database.

### 2. Grant Service Permissions

Grant the monitoring service account only the database permissions required for collector execution.

### 3. Prepare Remote Access

Enable the necessary remote management protocols for target systems where collectors depend on them.

### 4. Configure Scheduled Execution

Register Task Scheduler jobs for each collector according to the expected cadence.

## Typical Scheduling Strategy

- firewall and certificate checks: daily
- directory and DNS changes: frequent recurring tasks
- backup checks: daily
- software inventory: weekly
- license analytics: monthly
- reboot tracking: at startup

## Security Considerations

The internal project uses service accounts, connection strings, cloud API credentials, and scheduled jobs. In this public version:

- all secrets are removed
- all IDs are replaced with placeholders
- all usernames and passwords are removed
- server names and internal IP ranges are generalized
- cloud project and bucket names are anonymized

## Public Repository Scope

This repository is intended as a project showcase, not as a production-ready deployment bundle. It focuses on architecture, capabilities, and operating model rather than environment-specific implementation details.

