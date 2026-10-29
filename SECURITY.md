# Security policy

## Supported versions

`0.1.0-alpha` is the only supported line while LocalStat is in alpha. Alpha
software may contain defects and is not intended for clinical, regulated, or
production-critical work.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting flow from the repository's
Security tab. Do not include a working exploit or sensitive data in a public
issue. If private reporting is not yet enabled, open a public issue containing
only a request for a private contact channel.

Include the affected version, macOS version, reproduction conditions, impact,
and the smallest non-sensitive sample that demonstrates the problem. Reports
will be acknowledged when maintainers are available; this alpha project does
not promise a response or remediation deadline.

## Trust boundary

Treat SAS programs and project folders as executable content, not inert data.
LocalStat runs the bundled interpreter with the selected project folder as its
working directory. A program can read and write files available to that
process, `%INCLUDE` can read additional source, and `%SYSGET` can read inherited
environment variables. Only run programs and open projects you trust. Avoid
launching LocalStat from a shell that contains sensitive environment variables.
The alpha build is not sandboxed.

LocalStat does not upload programs or results. Each run starts a new local
runtime process, but process isolation is not a security sandbox.
