# Collectors And Monitoring Domains

## Active Directory Monitoring

The platform includes collectors for:

- Active Directory user and group change tracking
- Group Policy change monitoring
- insecure LDAP authentication detection
- AD and LDAPS certificate expiration checks

These collectors help support both operational monitoring and security visibility.

## DNS Monitoring

DNS collectors track:

- zone-level changes
- record-level changes

This is useful for troubleshooting, audit trails, and identifying unexpected configuration drift.

## Server Monitoring

Server-focused collectors gather:

- reboot events and reboot causes
- firewall status by profile
- installed software inventory

This provides a baseline for infrastructure health and asset awareness.

## Microsoft 365 Monitoring

Microsoft 365 collectors support:

- inactive user analysis
- license distribution and cost reporting by department

These scripts are designed to support administrative visibility and optimization work.

## Backup Validation

Backup validation collectors check whether expected database backups are present in configured cloud storage locations.

The purpose is to detect missing or incomplete backup chains before recovery is needed.

## Certificate Monitoring

Certificate-oriented collectors validate:

- domain controller certificates
- LDAPS certificate health
- public-facing web server TLS certificates

## Execution Model

Collectors are typically executed through Task Scheduler on recurring intervals such as:

- every 15 minutes
- every 30 minutes
- hourly
- daily
- weekly
- monthly
- at system startup

## Operational Pattern

Each collector follows the same basic pattern:

1. gather data from one or more sources
2. normalize or enrich the result set
3. write results into SQL Server
4. allow dashboards and reports to consume the data later

