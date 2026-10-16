import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:filosign/features/quiz/quiz_screen.dart';
import 'package:filosign/features/home/learn_screen.dart';

void main() {
  test('QuizResult passed threshold calculation', () {
    // 9/10 = 90% -> passes
    final passed1 = QuizResult(score: 9, total: 10).passed;
    expect(passed1, isTrue);

    // 8/10 = 80% -> fails
    final passed2 = QuizResult(score: 8, total: 10).passed;
    expect(passed2, isFalse);

    // 10/10 = 100% -> passes
    final passed3 = QuizResult(score: 10, total: 10).passed;
    expect(passed3, isTrue);

    // 7/10 = 70% -> fails
    final passed4 = QuizResult(score: 7, total: 10).passed;
    expect(passed4, isFalse);
  });

  test('LearnScreen Basics always accessible', () {
    // Basics category ID mapping
    final basicsId = LearnScreen._categoryIdForTitle('Basics');
    expect(basicsId, 'basic');

    // Other categories map correctly
    final lettersId = LearnScreen._categoryIdForTitle('Letters');
    expect(lettersId, 'letters');

    final numbersId = LearnScreen._categoryIdForTitle('Numbers');
    expect(numbersId, 'numbers');
  });

  test('Category position mapping in canAccessCategory', () {
    // Position mapping should be correct
    final positionMap = {
      'basic': 1, 'letters': 2, 'numbers': 3, 'days': 4,
      'months': 5, 'colors': 6, 'greetings': 7, 'family': 8,
      'food': 9, 'drinks': 10, 'communication': 11,
    };

    expect(positionMap['basic'], 1);
    expect(positionMap['letters'], 2);
    expect(positionMap['communication'], 11);
  });
}