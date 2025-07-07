# TensorFlow Lite GPU delegate rules
-keep class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.** { *; }

# You might also need these for general TensorFlow Lite usage
-dontwarn org.tensorflow.lite.**