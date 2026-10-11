import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/model/entities/subject.dart';
import 'package:school_manager/view/home_page.dart';

void main() {
  testWidgets('manual lesson form returns the selected subject',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AddLessonDialog(subjects: [
                            Subject(id: 'math', name: 'Matematica'),
                          ])),
                  child: const Text('Apri'),
                )),
      ),
    ));
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    expect(find.text('Nuova lezione'), findsOneWidget);
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Nuova lezione'), findsNothing);
  });
}
