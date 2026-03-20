import 'package:flutter/material.dart';
import 'dart:convert';

class WidgetItem {
  final String id;
  final String type; // 'note', 'photo', 'stats', etc.
  final Offset position;
  final Size size;
  final Map<String, dynamic> data;

  final String? userId;

  WidgetItem({
    required this.id,
    this.userId,
    required this.type,
    required this.position,
    required this.size,
    required this.data,
  });

  WidgetItem copyWith({
    Offset? position,
    Size? size,
    Map<String, dynamic>? data,
    String? userId,
  }) {
    return WidgetItem(
      id: id,
      userId: userId ?? this.userId,
      type: type,
      position: position ?? this.position,
      size: size ?? this.size,
      data: data ?? this.data,
    );
  }

  factory WidgetItem.fromMap(Map<String, dynamic> map) {
    return WidgetItem(
      id: map['id'],
      userId: map['user_id'],
      type: map['type'],
      position: Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble()),
      size: Size((map['width'] as num).toDouble(), (map['height'] as num).toDouble()),
      data: map['data'] is String ? (map['data'] as String).isEmpty ? {} : (jsonDecode(map['data']) as Map<String, dynamic>) : map['data'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'x': position.dx,
      'y': position.dy,
      'width': size.width,
      'height': size.height,
      'data': data,
    };
  }
}
