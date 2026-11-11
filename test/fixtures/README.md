# test/fixtures

`test_cert.pem` / `test_key.pem`: شهادة اختبار موقّعة ذاتيًا لاسم `localhost` فقط (صلاحية 10 سنين، مولّدة بـ openssl).
بتُستخدم في `link_expander_network_test.dart` لإثبات إن الاتصال المثبّت على IP لسه بيتحقق من الشهادة على *اسم الموقع*
(مش على الـ IP). المفتاح الخاص هنا مفتاح اختبار عام مالوش أي قيمة؛ **لا تستخدمه في أي مكان تاني**.

لإعادة توليدها:

```
openssl req -x509 -newkey rsa:2048 -nodes -keyout test_key.pem -out test_cert.pem -days 3650 \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,digitalSignature,keyCertSign,keyEncipherment"
```
