# Security Pentest Reports — Sure

## Report Summary

| Date | CRIT | HIGH | MED | LOW | INFO | Fixes Applied | New Findings |
|------|------|------|-----|-----|------|---------------|--------------|
| 2026-03-29 | 1 | 2 | 16 | 11 | 3 | 0 | 6 |
| 2026-03-26 | 1 | 2 | 13 | 8 | 3 | 4 | 5 |
| 2026-03-25 | 2 | 5 | 10 | 6 | 3 | 0 | 23 |
| 2026-03-13 | 2 | 0 | 1 | 0 | 0 | 12 | 3 |
| 2026-03-02 | 0 | 0 | 0 | 0 | 0 | 16 | 12 |

---

## Latest: PENTEST-2026-03-29

**Status**: Analysis only — no code changes applied

### Open Critical/High Findings (unchanged since 2026-03-25)
- **CRIT-01**: Password change without current password verification
- **HIGH-01**: Account deletion without password re-auth
- **HIGH-02**: Email change without password re-auth

### New Findings This Session
| # | Finding | Severity |
|---|---------|----------|
| MED-14 | SSO identity unlink without re-auth | MEDIUM |
| MED-15 | API key revocation without re-auth | MEDIUM |
| MED-16 | Stored XSS via innerHTML in confirm dialog | MEDIUM |
| LOW-09 | Admin can remove members without re-auth | LOW |
| LOW-10 | Provider form double `.html_safe` | LOW |
| LOW-11 | Guides view `.html_safe` without sanitize | LOW |

### Verified Fixes (No Regressions)
- CRIT-02: SQL injection ORDER BY (fixed 2026-03-26)
- HIGH-03: LIKE wildcard injection (fixed 2026-03-26)
- HIGH-04: Markdown XSS (fixed 2026-03-26)
- HIGH-05: Guides filter_html (fixed 2026-03-26)
- F-01 through F-12: All original fixes from 2026-03-02

### Top Priority Remediation
1. **CRIT-01**: Add password verification to password change flow
2. **MED-16**: Replace `innerHTML` with `textContent` in confirm dialog
3. **HIGH-01/02**: Add password verification to account deletion and email change

---

## Report History

- [PENTEST-2026-03-29](./PENTEST-2026-03-29.md) — 6 new findings, 0 fixes (analysis only)
- [PENTEST-2026-03-26](./PENTEST-2026-03-26.md) — 5 new findings, 4 fixes
- [PENTEST-2026-03-25](./PENTEST-2026-03-25.md) — 23 new findings, 0 fixes (analysis only)
- [PENTEST-2026-03-13](./PENTEST-2026-03-13.md) — 3 new findings, 12 fixes
- [PENTEST-2026-03-02](./PENTEST-2026-03-02.md) — 12 findings identified and fixed

---

## Total Open Findings: 33

| Severity | Count |
|----------|-------|
| CRITICAL | 1 |
| HIGH | 2 |
| MEDIUM | 16 |
| LOW | 11 |
| INFO | 3 |

**Next scheduled pentest**: 2026-04-12 (biweekly)
