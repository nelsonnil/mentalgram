# Bot Detection Log — MentalGram

Track every Instagram bot detection incident to find patterns and optimize upload timing.

---

## How to fill in each incident

Copy the template below, fill it in after each incident, and add it to the **Incidents** section.

---

## Incident Template

```
### Incident #N — YYYY-MM-DD

**Error type**: login_required / checkpoint_required / spam / challenge_required / other
**Error code**: 403 / 400 / other
**Time of error**: HH:MM
**Photo number that failed**: #N
**Total photos uploaded before error**: N

**Session duration**: X min (from first upload to error)
**Network at time of error**: WiFi / Cellular / switching
**Network changes during session**: yes (WiFi→Cellular at HH:MM) / no

**Upload rate**:
- Total uploads: N
- Session duration: X min
- Average interval between uploads: X min
- Shortest interval: X min
- Longest interval: X min

**Cooldowns used**: X–Y seconds (range)
**Actions used (rate limit counter)**: used=X, remaining=Y

**Other API actions during session**:
- Notes sent: N (duplicate? yes/no)
- Bio changes: N
- Profile pic changes: N
- Force reveals: N
- Archive/unarchive: N

**App state**:
- Was another set being prepared simultaneously: yes/no
- Was performance mode active: yes/no
- Time since last session: X hours

**Recovery**:
- How long until account worked again: X min / X hours
- Required re-login: yes/no
- Challenge required: yes/no

**Notes / observations**:
(anything unusual you noticed)
```

---

## Incidents

### Incident #1 — 2026-03-12

**Error type**: login_required  
**Error code**: 403  
**Time of error**: 09:53  
**Photo number that failed**: #15  
**Total photos uploaded before error**: 14  

**Session duration**: ~85 min (08:28 → 09:53)  
**Network at time of error**: WiFi  
**Network changes during session**: no  

**Upload rate**:
- Total uploads: 14
- Session duration: 85 min
- Average interval between uploads: ~6 min
- Shortest interval: ~3 min (photos #7→#8, #12→#13)
- Longest interval: ~15 min (photos #10→#11)

**Cooldowns used**: 164–215 seconds  
**Actions used (rate limit counter)**: unknown (not logged before error)

**Other API actions during session**:
- Notes sent: 3 attempts, all failed "already sent" (same text "Odio" repeated — bug fixed after this incident)
- Bio changes: 0
- Profile pic changes: 0
- Force reveals: 0
- Archive/unarchive: 14 (one per uploaded photo)

**App state**:
- Was another set being prepared simultaneously: yes (Photo #1 compressions appearing between uploads)
- Was performance mode active: unknown
- Time since last session: unknown

**Recovery**:
- How long until account worked again: unknown
- Required re-login: unknown
- Challenge required: unknown

**Notes / observations**:
- Duplicate log entries per photo (SetDetailView + InstagramService both logging same event — cosmetic bug, fixed after this incident)
- The 3 repeated note attempts with same text may have contributed to suspicion before the 403

### Incident #2 — 2026-03-12 (follow-up from #1)

**Error type**: login_required (session invalidated by Instagram after incident #1)
**Error code**: 403
**Time of error**: 10:42 (first attempt), 12:23 (second attempt after reopen)
**Photo number that failed**: #1 (immediate, before any upload)
**Total photos uploaded before error**: 0

**Session duration**: 0 (failed on first attempt)
**Network at time of error**: WiFi
**Network changes during session**: no (at time of attempt)

**Upload rate**: N/A — failed immediately

**Other API actions during session**:
- Word reveals attempted: yes, also failing with 403/sessionExpired
- State checks: 403 on all

**App state**:
- Previous incident: #1 (same day, ~45 min earlier)
- Session was already dead from incident #1

**Recovery**:
- Required re-login: YES
- Root cause: Instagram invalidated session token after incident #1's 403

**Notes / observations**:
- Bug found: `login_required` was classified as "bot detection" instead of "session expired"
- This caused misleading bot lockdown UI when the real fix was just re-login
- **Fixed in code**: moved `login_required` from `isBotError` to `isSessionExpired` classifier

---

## Summary Table

| # | Date | Error | Photo # | Duration | Uploads | Avg interval | Net change | Notes |
|---|------|-------|---------|----------|---------|--------------|------------|-------|
| 1 | 2026-03-12 | 403 login_required | #15 | 85 min | 14 | ~6 min | no | 3 duplicate note attempts |
| 2 | 2026-03-12 | 403 login_required | #1 | 0 min | 0 | — | no | Session dead from incident #1, app showed wrong "bot" error |

---

## Patterns Found

*(fill in as more data accumulates)*

- **Possible threshold**: ~14 uploads before trigger (needs more data)
- **Possible time window**: Instagram may track uploads per rolling hour
- **Hypothesis**: Notes spam + upload volume = higher risk

---

## Config at Time of Each Incident

| # | Date | Cooldown range | Rate limit cap | Uniquify | Notes dedup fix |
|---|------|---------------|----------------|----------|-----------------|
| 1 | 2026-03-12 | 160–215s | 55/hr | yes | NO (bug) |

---

*Last updated: 2026-03-12*
