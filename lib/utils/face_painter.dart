import 'package:flutter/material.dart';

class FacePainter extends CustomPainter {
  final Rect rect;
  final Size imageSize;

  FacePainter({required this.rect, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
// Convert normalized rect (0.0–1.0) to screen coordinates
final scaleX = size.width;
final scaleY = size.height;

final scaledRect = Rect.fromLTRB(
  rect.left * scaleX,
  rect.top * scaleY,
  rect.right * scaleX,
  rect.bottom * scaleY,
);

final textPainter = TextPainter(
  text: TextSpan(
    text: "Face Detected",
    style: TextStyle(color: Colors.white, fontSize: 16),
  ),
  textDirection: TextDirection.ltr,
)..layout();

textPainter.paint(canvas, Offset(scaledRect.left, scaledRect.top - 20));

final paint = Paint()
  ..color = Colors.greenAccent
  ..strokeWidth = 3
  ..style = PaintingStyle.stroke;

canvas.drawRect(scaledRect, paint);
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}

