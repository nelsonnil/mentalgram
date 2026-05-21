# Vault - Anti-Bot Protection Guide

## How the Protection System Works

Vault includes a multi-layer protection system designed to make your activity look like a regular Instagram user. Here's everything you need to know.

---

## Protection Layers

### 1. Device Identity
The app creates a unique device ID the first time you open it. This ID is stored securely in the iPhone's Keychain (survives app reinstalls). Instagram uses this to recognize your "device."

**Important:** Never reset your Device ID while using your main account. Only reset it if you're switching to a different account on the same phone.

### 2. App Version Disguise
The app identifies itself as a recent version of Instagram (v390). This is critical because Instagram knows which versions are active. An old version is an immediate red flag.

### 3. Header Consistency
Every request sent to Instagram includes 22+ headers that match exactly what the real Instagram app sends. This includes connection speed, bandwidth data, session tracking, and device information. All request types (upload, archive, unarchive) send the same set of headers.

### 4. Timing Protection

| Action | Delay | Why |
|--------|-------|-----|
| Between photo uploads | 130-200 seconds (random) | Instagram has a ~120s minimum cooldown |
| Before archiving a photo | 3-6.5 seconds | Simulates human interaction speed |
| Before unarchiving (performance) | 2-3.3 seconds | Faster for magic tricks, safe for small bursts |
| Before configuring uploaded photo | 3-8 seconds | Varies each time to avoid patterns |
| Between reveal letters (secret input) | 1 second | Short burst, max 5-6 photos |

All delays include random "jitter" so they're never exactly the same twice.

### 5. Rate Limiting
The app tracks how many actions you've performed in the last hour. Instagram allows roughly 60 actions/hour. The app stops at 55 as a safety margin and will show a warning if you approach the limit.

### 6. Duplicate Photo Protection
When uploading the same photo to different banks (Word/Number Reveal), the app automatically makes each copy visually unique by:
- Modifying 15-30 invisible pixels
- Varying JPEG compression quality slightly

This means Instagram sees different files each time, not the same image repeated.

### 7. Network Change Detection
If your connection switches (WiFi to Cellular or vice versa), the app automatically pauses uploads and waits for the network to stabilize before continuing.

### 8. Exponential Backoff
If errors occur, the app waits progressively longer between retries: 2s → 4s → 8s → 16s → up to 5 minutes. This prevents rapid-fire retries that Instagram would flag.

### 9. Session Warm-Up
Before heavy operations like uploads, the app can simulate "opening Instagram" by making a lightweight request first (like loading your feed). This mimics natural user behavior.

---

## What To Do If Something Goes Wrong

### "Session Expired"

**What happened:** Instagram invalidated your login session.

**What to do:**
1. Go to Settings
2. Long press on the version number to reveal the login button
3. Log in again
4. Wait 15-30 minutes before starting uploads again
5. If this happens repeatedly, wait 24 hours before trying again

**Prevention:**
- Don't log in from different locations (always use your home WiFi)
- Don't log out and log in frequently
- Keep the app session alive as long as possible

---

### "Rate Limited" or "Please wait X minutes"

**What happened:** You've made too many requests in a short period.

**What to do:**
1. Stop all activity immediately
2. Wait the full time shown (don't try to rush it)
3. The app will show a countdown - wait until it reaches zero
4. Resume uploads after the countdown finishes

**Prevention:**
- Don't upload more than 15-20 photos in one session
- Space your upload sessions throughout the day
- Don't archive/unarchive photos manually while uploads are running

---

### "Bot Detection" / Lockdown Mode

**What happened:** Instagram flagged your account for automated behavior.

**What to do:**
1. The app enters "Lockdown Mode" automatically (15 minutes)
2. During lockdown, the app will NOT make any requests to Instagram
3. DO NOT open the real Instagram app during this time
4. Wait for the full lockdown timer to expire
5. After lockdown, wait an additional 15-30 minutes before resuming

**If you see "We suspect automated behavior" on Instagram:**
1. Stop using Vault for 24-48 hours
2. Open the real Instagram app normally from your phone
3. Use Instagram normally (scroll, like a few posts) for a day
4. This "cleans" your activity pattern
5. After 24-48 hours, resume Vault usage with small batches

**Prevention:**
- Never upload more than 20 photos in a single day
- Use WiFi only (avoid cellular data for uploads)
- Don't switch between WiFi and cellular during uploads
- Avoid uploading at unusual hours (3-6 AM)

---

### "Network Error" / "Cannot Parse Response"

**What happened:** The connection to Instagram was interrupted.

**What to do:**
1. Check your WiFi/cellular connection
2. The app will show a recovery section - wait for it
3. Once connection is stable, use the retry button
4. If it keeps failing, pause uploads and try again later

**Prevention:**
- Use a stable WiFi connection for uploads
- Don't move around (changing cell towers) during uploads
- Keep the phone charged and screen on (the app disables sleep during uploads)

---

### "Photo Rejected"

**What happened:** Instagram rejected the photo file.

**What to do:**
1. You can "Skip" the photo and continue with the next one
2. Or "Replace" the photo with a different one
3. The upload will continue from where it stopped

**Prevention:**
- Use JPEG photos (not PNG, HEIC, or other formats)
- Photos should be under 500KB (the app compresses automatically)
- Avoid extremely small images (under 320px)
- Avoid images with unusual aspect ratios

---

## Recommended Usage Patterns

### Daily Limits (Safe Zone)

| Activity | Safe daily limit |
|----------|-----------------|
| Photo uploads | 15-20 photos |
| Archive actions | 30-40 photos |
| Unarchive actions | 20-30 photos |
| Profile picture changes | 1-2 per day |
| Comments | 10-15 per day |
| Total actions per hour | Under 55 |

### Best Practices for Uploads

1. **Upload in small batches:** 10-15 photos, then take a break of 1-2 hours
2. **Use WiFi:** Always upload on a stable WiFi connection
3. **Don't multitask:** Let the app finish before doing other Instagram activities
4. **Keep screen on:** The app disables screen sleep during uploads, don't override this
5. **Don't close the app:** Stay in the set detail view during uploads
6. **Morning/afternoon:** Upload between 9 AM and 9 PM (normal usage hours)

### Best Practices for Performance (Magic Tricks)

1. **Warm up first:** Open the app a few minutes before your performance
2. **WiFi preferred:** If possible, use WiFi during performances
3. **Max 5-6 reveals:** The word reveal is designed for words up to 5-6 letters
4. **Total time:** A 5-letter word takes approximately 15-25 seconds to reveal
5. **One trick at a time:** Don't do multiple reveals in quick succession
6. **Wait between tricks:** If doing multiple performances, wait 10-15 minutes between reveals

### Switching Accounts

1. Log out from current account in Settings
2. Go to Settings → Debug → Reset Device ID
3. Wait 2-3 minutes
4. Log in with the new account
5. **Never** reset Device ID while staying on the same account

---

## Understanding the Status Indicators

### Upload Status Colors

| Color | Meaning |
|-------|---------|
| Purple | Uploading in progress |
| Green | Successfully uploaded/archived |
| Yellow | Waiting (cooldown between photos) |
| Red | Error occurred |
| Gray | Paused or pending |

### Lockdown Indicator

When the app border turns red and shows "Lockdown Mode," this means:
- All API requests are blocked
- A countdown timer shows time remaining
- This is for your protection - don't try to bypass it
- The app will resume automatically when the timer expires

---

## Quick Troubleshooting

| Problem | First thing to try |
|---------|-------------------|
| Uploads stuck | Check WiFi connection, then pause and resume |
| "Session expired" | Log in again, wait 15 min before uploading |
| "Rate limited" | Wait for the countdown timer to finish |
| App shows lockdown | Wait for the full 15-minute timer |
| Photos uploading slowly | Normal - delays are intentional for safety |
| Same photo rejected twice | Try replacing it with a slightly different version |
| Network keeps disconnecting | Switch to a more stable WiFi network |
| Instagram shows "automated behavior" | Stop for 24-48 hours, use Instagram normally |
| App feels slow after error | Exponential backoff - delays increase after errors, will reset after success |

---

## Version History of Protection System

- **v1.0:** Basic upload with fixed delays
- **v1.1:** Added network change detection, cooldown system
- **v1.2:** Added lockdown mode, 3-layer bot protection
- **v1.3:** Header consistency fix, variable cooldowns, image uniquification
- **v1.4 (Current):** Full header suite (22+ headers), rate limiting, exponential backoff, session warm-up, Pigeon session tracking, bandwidth simulation, MID capture, app version update

---

*Last updated: February 2026*
