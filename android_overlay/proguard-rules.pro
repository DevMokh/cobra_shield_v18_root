# مكتبة google_mlkit_text_recognition بتشير لكلاسات لغات اختيارية
# (صيني/ياباني/كوري/ديفاناجاري) مش مضمّنة في التطبيق. لازم نقول لـ R8 يتجاهلها.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Tesseract4Android (قراءة النص العربي): الكود الأصلي (JNI) بيوصل لحقول وكلاسات
# بالاسم، فلازم R8 ما يغيّرهاش أو يشيلها.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }
-dontwarn com.googlecode.tesseract.android.**
-dontwarn com.googlecode.leptonica.android.**
