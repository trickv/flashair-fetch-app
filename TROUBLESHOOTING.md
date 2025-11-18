# Troubleshooting Guide

## Build Issues

### ❌ "Cleartext HTTP traffic not permitted"

**Symptom:** App fails to connect with error message mentioning cleartext HTTP.

**Cause:** Android 9+ blocks HTTP traffic by default.

**Solution:** Network security config is already in place at `android/app/src/main/res/xml/network_security_config.xml`. Make sure:
1. The file exists and is properly formatted
2. `AndroidManifest.xml` includes: `android:networkSecurityConfig="@xml/network_security_config"`
3. Clean and rebuild: `./gradlew clean installDebug`

---

### ❌ "jlink finished with non-zero exit value 1" / JdkImageTransform errors

**Symptom:** Build fails with errors about `jlink`, `JdkImageTransform`, or `androidJdkImage`.

**Cause:** BuildConfig generation triggering incompatible JDK operations.

**Solution:** This was fixed in commit `8eaa8be`. Make sure you have the latest code:
```bash
git pull origin claude/flashair-photo-importer-scaffold-01CVgZ7kXgQGPgsAByW9tSPE
cd android && ./gradlew clean
```

The project now uses `resValue()` instead of `buildConfigField()` for version info.

---

### ❌ Gradle sync fails / Dependencies not downloading

**Symptom:** "Could not resolve dependencies" or network timeouts.

**Cause:** Network connectivity or proxy issues.

**Solutions:**
1. Check internet connection
2. Try: `cd android && ./gradlew --refresh-dependencies`
3. Clear Gradle cache: `rm -rf ~/.gradle/caches/`
4. Check proxy settings if behind corporate firewall

---

### ❌ Tests fail with FAT date/time errors

**Symptom:** `testFATDateTimeDecoding FAILED` with incorrect date values.

**Cause:** FAT date calculation error.

**Solution:** This was fixed in commit `82e8e27`. The correct FAT date for 2018-09-20 is `19764`:
```kotlin
val date = 19764  // (38 << 9) | (9 << 5) | 20
```

If you see this error, pull latest code and run tests again.

---

## Runtime Issues

### ❌ "Connection refused" when tapping Connect button

**Symptom:** App shows error: "Error: Connection refused" or "Make sure mock server is running".

**Cause:** Mock server not running or incorrect host configuration.

**Solutions:**
1. **Start mock server:**
   ```bash
   cd tools/mock-flashair
   python server.py
   ```
   Should see: `Running on http://0.0.0.0:8080`

2. **Check host configuration** in `MainActivity.kt`:
   - For emulator: `val host = "http://10.0.2.2:8080"`
   - For real device + mock server: Use your computer's IP
   - For real FlashAir: `val host = "http://192.168.0.1:8080"` (or FlashAir's IP)

3. **Verify emulator networking:**
   ```bash
   # From inside emulator (adb shell):
   ping 10.0.2.2
   ```

---

### ❌ App shows "0 directories, 0 files" or empty results

**Symptom:** Connection succeeds but no files shown.

**Possible Causes:**
1. **Mock server issue:** Check mock server console for errors
2. **Wrong directory:** FlashAir photos are usually in `/DCIM/100CANON` (or similar), not directly in `/DCIM`
3. **CSV parsing error:** Check logs for parsing exceptions

**Solutions:**
1. Check mock server output - should see HTTP requests logged
2. Try listing subdirectory: Modify code to list `/DCIM/100CANON`
3. Add debug logging to `FlashAirClient.kt`:
   ```kotlin
   println("Response: $responseBody")
   ```

---

### ❌ "Unknown host" errors

**Symptom:** App crashes or shows "UnknownHostException" or "Unable to resolve host".

**Cause:** DNS resolution failure or incorrect hostname.

**Solutions:**
1. Use IP addresses instead of hostnames:
   - ✅ `http://10.0.2.2:8080`
   - ✅ `http://192.168.0.1:8080`
   - ❌ `http://flashair:8080` (DNS may not work)

2. Check network connectivity from emulator

---

## Development Environment Issues

### ❌ Cannot run Gradle tests locally (Claude Code environment)

**Symptom:** `java.net.UnknownHostException` or proxy authentication errors.

**Cause:** Environment uses proxy with JWT authentication that Java/Gradle doesn't handle properly.

**Solution:** **Use GitHub Actions CI instead:**
1. Push your changes
2. Go to: https://github.com/trickv/flashair-fetch-app/actions
3. Wait ~2 minutes for build to complete
4. Check test results in CI logs

Tests work fine in CI - this is purely an environment limitation.

---

### ❌ Git commit hash not showing in app

**Symptom:** App footer shows "Build: dev-build" or empty string.

**Cause:** resValue not generated or not rebuilt after code changes.

**Solutions:**
1. **Full rebuild:**
   ```bash
   cd android
   ./gradlew clean
   ./gradlew installDebug
   ```

2. **Verify git is accessible:** Gradle runs `git rev-parse --short HEAD` at build time

3. **Check build.gradle.kts** has:
   ```kotlin
   val gitCommitId = providers.exec {
       commandLine("git", "rev-parse", "--short", "HEAD")
   }.standardOutput.asText.get().trim()
   resValue("string", "git_commit_id", gitCommitId)
   ```

---

## Mock Server Issues

### ❌ Mock server won't start - "Address already in use"

**Symptom:** `OSError: [Errno 98] Address already in use`

**Cause:** Port 8080 already occupied by another process.

**Solutions:**
1. **Find and kill process:**
   ```bash
   lsof -i :8080
   kill -9 <PID>
   ```

2. **Or change port:** Edit `server.py` and `MainActivity.kt` to use different port

---

### ❌ Mock server starts but no logs appear when app connects

**Symptom:** Server runs but shows no HTTP requests.

**Cause:** App connecting to wrong host/port.

**Solutions:**
1. Verify server listening on correct interface: `http://0.0.0.0:8080`
2. Check app is using `http://10.0.2.2:8080` (for emulator)
3. Test server manually:
   ```bash
   curl http://localhost:8080/command.cgi?op=100&DIR=/DCIM
   ```

---

## FlashAir Hardware Issues (Future)

### ⚠️ Real FlashAir card not tested yet

**When testing with real FlashAir:**

1. **Find FlashAir IP:**
   - Usually `192.168.0.1` or check card documentation
   - Join FlashAir WiFi network first
   - Try: `http://flashair/` in browser

2. **Update app host:**
   ```kotlin
   val host = "http://192.168.0.1:8080"  // Use FlashAir's actual IP
   ```

3. **Handle "no internet" warnings:**
   - FlashAir networks have no internet access
   - Android will show warning - user must acknowledge
   - Future M2 will handle this programmatically

4. **Check FlashAir firmware version:**
   - API may vary between firmware versions
   - See `shared-spec/API.md` for compatibility notes

---

## CI Pipeline Issues

### ❌ CI build failing on GitHub Actions

**Symptom:** Green checkmark not appearing after push.

**Solutions:**
1. **Check actual error message:**
   - Go to Actions tab
   - Click on failed run
   - Read the logs (don't guess!)

2. **Common CI failures:**
   - Unit test failures → Fix test code
   - Lint errors → Run `./gradlew lint` locally (currently non-blocking)
   - Build errors → Check if builds locally first

3. **Verify commit was pushed:**
   ```bash
   git log --oneline -5
   git status
   ```

---

## Getting Help

If you encounter an issue not listed here:

1. **Check logs:** Android Studio Logcat or `adb logcat`
2. **Check CI output:** GitHub Actions logs
3. **Add debug logging:** `println()` statements in Kotlin code
4. **Review documentation:**
   - `DEVELOPMENT.md` - Build instructions
   - `shared-spec/API.md` - FlashAir API details
   - `shared-spec/CSV-FORMAT.md` - CSV parsing spec

5. **Create minimal reproduction:**
   - What steps cause the issue?
   - What error message appears?
   - Does it happen in CI or locally?

---

## Quick Diagnostics

**Is the build working?**
```bash
cd android
./gradlew assembleDebug
# Should complete with BUILD SUCCESSFUL
```

**Are tests passing?**
```bash
cd android
./gradlew test
# Or check: https://github.com/trickv/flashair-fetch-app/actions
```

**Is mock server working?**
```bash
cd tools/mock-flashair
python server.py
# In another terminal:
curl http://localhost:8080/command.cgi?op=100&DIR=/DCIM
# Should return CSV data
```

**Is emulator networking working?**
```bash
adb shell ping -c 3 10.0.2.2
# Should show ping responses
```
