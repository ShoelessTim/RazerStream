# Security Policy

## Supported versions

Only the latest release receives fixes. If you are on an older version, update
first and confirm the issue still exists.

## Reporting a vulnerability

Please do not open a public issue for security problems. Instead use GitHub's
private reporting: the Security tab of this repository, then "Report a
vulnerability". That opens a private thread only the maintainer can see.

What to expect:

- An acknowledgment within a week; this is a spare-time community project,
  not a company with an on-call rotation
- If confirmed, a fix lands in the next release and the report is credited
  (or kept anonymous if you prefer)
- If declined, you get an explanation, and after 90 days you are welcome to
  disclose publicly either way

## Scope worth knowing

RazerStream deliberately runs shell commands, AppleScript, and synthetic
keystrokes that the user configures; that is the product, not a vulnerability.
Reports in scope are things like: crafted device input causing memory
unsafety, profile files executing actions the user did not configure, or the
serial protocol parser being exploitable by a malicious device.
