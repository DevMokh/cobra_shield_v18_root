#!/usr/bin/env bash
# يتحقق إن ملف APK موجود وسليم وبيطابق إصدار pubspec.yaml، ومفيش أذونات خطيرة، والتوقيع صحيح.
#
# الاستخدام:  tool/verify_apk.sh <apk> <versionName> <versionCode> <debug|release>
#
# متطلبات: unzip و aapt2 و apksigner (من Android SDK build-tools؛ موجودين على runner ubuntu-24.04).
# أي فحص فاشل = خروج بكود غير صفري = الـ CI بيفشل. مفيش فحص بيتخطّى بصمت.
set -euo pipefail

apk="${1:?usage: verify_apk.sh <apk> <versionName> <versionCode> <debug|release>}"
want_name="${2:?versionName}"
want_code="${3:?versionCode}"
mode="${4:?debug|release}"

fail() { echo "::error::verify_apk: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

case "$mode" in debug|release) ;; *) fail "mode must be debug or release" ;; esac
[ -f "$apk" ] || fail "APK not found: $apk"

size=$(stat -c %s "$apk")
[ "$size" -ge 1000000 ] || fail "APK is suspiciously small ($size bytes)"
ok "file exists ($size bytes)"

unzip -tq "$apk" >/dev/null || fail "APK zip integrity check failed"
ok "zip integrity"

entries=$(unzip -Z1 "$apk")
need() { printf '%s\n' "$entries" | grep -qxF "$1" || fail "missing entry in APK: $1"; ok "entry $1"; }
need AndroidManifest.xml
need classes.dex
need lib/arm64-v8a/libflutter.so
need assets/tessdata/ara.traineddata
need assets/tessdata/eng.traineddata
if [ "$mode" = release ]; then
  need lib/arm64-v8a/libapp.so
else
  need assets/flutter_assets/kernel_blob.bin
fi

# أدوات Android SDK
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
find_tool() {
  local name="$1" p
  if p=$(command -v "$name" 2>/dev/null); then echo "$p"; return; fi
  if [ -n "$sdk" ] && [ -d "$sdk/build-tools" ]; then
    p=$(find "$sdk/build-tools" -name "$name" -type f 2>/dev/null | sort -V | tail -1)
    if [ -n "$p" ]; then echo "$p"; return; fi
  fi
  return 1
}
aapt2=$(find_tool aapt2) || fail "aapt2 not found (Android SDK build-tools required)"
apksigner=$(find_tool apksigner) || fail "apksigner not found (Android SDK build-tools required)"

badging=$("$aapt2" dump badging "$apk")
pkg_line=$(printf '%s\n' "$badging" | grep -m1 '^package:') || fail "no package line in badging"
got_name=$(printf '%s\n' "$pkg_line" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
got_code=$(printf '%s\n' "$pkg_line" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
got_pkg=$(printf '%s\n' "$pkg_line" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
[ "$got_pkg" = "com.cobrashield.cobra_shield" ] || fail "unexpected package id: $got_pkg"
[ "$got_name" = "$want_name" ] || fail "versionName mismatch: APK=$got_name pubspec=$want_name"
[ "$got_code" = "$want_code" ] || fail "versionCode mismatch: APK=$got_code pubspec=$want_code"
ok "package $got_pkg version $got_name+$got_code"

if [ "$mode" = release ]; then
  if printf '%s\n' "$badging" | grep -q '^application-debuggable'; then
    fail "release APK is marked debuggable"
  fi
  ok "not debuggable"
fi

# أذونات: بنطبعها كلها للمراجعة، وبنرفض أي إذن من القائمة الخطيرة (الخصوصية: التطبيق مش محتاج أي منها).
perms=$("$aapt2" dump permissions "$apk" | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" | sort -u)
echo "--- permissions in final APK ---"
printf '%s\n' "$perms"
echo "--------------------------------"
deny='READ_SMS|RECEIVE_SMS|SEND_SMS|READ_CONTACTS|WRITE_CONTACTS|READ_CALL_LOG|ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|ACCESS_BACKGROUND_LOCATION|RECORD_AUDIO|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|QUERY_ALL_PACKAGES|SYSTEM_ALERT_WINDOW|READ_PHONE_STATE|BIND_ACCESSIBILITY_SERVICE'
if printf '%s\n' "$perms" | grep -E "(^|\.)($deny)$"; then
  fail "APK requests a permission the app must not need (see list above)"
fi
printf '%s\n' "$perms" | grep -qx 'android.permission.INTERNET' || fail "INTERNET permission missing"
printf '%s\n' "$perms" | grep -qx 'android.permission.CAMERA' || fail "CAMERA permission missing (QR scanning)"
ok "permissions"

# التوقيع
sig=$("$apksigner" verify --verbose --print-certs "$apk") || fail "apksigner verify failed"
printf '%s\n' "$sig" | head -12
if [ "$mode" = release ]; then
  if printf '%s\n' "$sig" | grep -qi 'Android Debug'; then
    fail "release APK is signed with the Android debug certificate"
  fi
  ok "release signed with a non-debug certificate"
else
  ok "debug APK signature verifies"
fi

sha=$(sha256sum "$apk" | cut -d' ' -f1)
echo "sha256: $sha"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### APK ($mode)"
    echo ""
    echo "- file: \`$(basename "$apk")\` ($size bytes)"
    echo "- version: $got_name+$got_code"
    echo "- sha256: \`$sha\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
echo "verify_apk: ALL CHECKS PASSED"
