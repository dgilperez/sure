# TODO - Gimli Pentest 2026-03-29

## Active

- [x] Biweekly pentest — Sure (completed 2026-03-29)
  - Read skill at ~/.claude/skills/pentest-analysis
  - Verify recent fixes still hold (CRIT-02 SQL injection, HIGH-03/04/05 fixed 2026-03-26)
  - Re-check still-open issues: CRIT-01 (CWE-620 password change no verify), HIGH-01 (account delete no re-auth), HIGH-02 (email change no re-auth)
  - Full white-box analysis of the Rails codebase
  - Focus: authentication flows, account management, re-auth requirements
  - Regression check: ensure F-01..F-12 (fixed 2026-03-02) still solid
  - Write PENTEST-2026-03-29.md in docs/security/ — structured: FIXED ✅, NEW findings, REGRESSIONS
  - Mark fixed issues as [x], document any new findings with CWE + severity
  - No changes to prod code — analysis only, document findings for David review
  - When done: openclaw system event --text "TASK_COMPLETE: Sure pentest 2026-03-29" --mode now

## Done
