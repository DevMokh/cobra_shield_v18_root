#!/usr/bin/env python3
"""
يولّد lib/core/psl_data.dart من ملف Public Suffix List الرسمي.

الاستخدام:
    python3 tool/gen_psl.py <public_suffix_list.dat> [--date YYYY-MM-DD] > lib/core/psl_data.dart

القائمة الرسمية تُسحب من https://publicsuffix.org/list/public_suffix_list.dat
(مرخّصة MPL-2.0؛ نص الترخيص يُحفظ في رأس الملف المولَّد). لتحديث القائمة داخل التطبيق:
نزّل الملف الجديد وأعد تشغيل هذا السكربت ثم شغّل الاختبارات (test/public_suffix_test.dart).
"""
import argparse
import sys


def parse(path):
    section = None
    icann, private = [], []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("// ===BEGIN ICANN"):
                section = "icann"
                continue
            if line.startswith("// ===BEGIN PRIVATE"):
                section = "private"
                continue
            if line.startswith("// ===END"):
                section = None
                continue
            if not line or line.startswith("//"):
                continue
            rule = line.split()[0].lower()
            if section == "icann":
                icann.append(rule)
            elif section == "private":
                private.append(rule)
    return icann, private


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dat")
    ap.add_argument("--date", default="unknown")
    args = ap.parse_args()
    icann, private = parse(args.dat)
    if len(icann) < 5000 or len(private) < 1000:
        print("ERROR: suspiciously small rule set; refusing to generate", file=sys.stderr)
        return 1
    for r in icann + private:
        if "'''" in r or "\\" in r or "$" in r:
            print(f"ERROR: unsupported character in rule {r!r}", file=sys.stderr)
            return 1
    out = []
    out.append("// GENERATED FILE - DO NOT EDIT. Regenerate with tool/gen_psl.py.")
    out.append("//")
    out.append("// Data: Public Suffix List (https://publicsuffix.org/list/), Mozilla Foundation and contributors,")
    out.append("// distributed under the Mozilla Public License 2.0 (https://mozilla.org/MPL/2.0/).")
    out.append("// This file contains the rules of the list unmodified (comments removed, one rule per line).")
    out.append("")
    out.append(f"/// تاريخ لقطة القائمة المضمّنة (YYYY-MM-DD).")
    out.append(f"const String kPslSnapshotDate = '{args.date}';")
    out.append("")
    out.append(f"/// عدد القواعد: ICANN={len(icann)}، PRIVATE={len(private)}.")
    out.append(f"const int kPslIcannCount = {len(icann)};")
    out.append(f"const int kPslPrivateCount = {len(private)};")
    out.append("")
    out.append("/// قواعد قسم ICANN (واحدة في كل سطر).")
    out.append("const String kPslIcannRules = r'''")
    out.extend(icann)
    out.append("''';")
    out.append("")
    out.append("/// قواعد قسم PRIVATE (استضافات ومنصات مثل github.io).")
    out.append("const String kPslPrivateRules = r'''")
    out.extend(private)
    out.append("''';")
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
