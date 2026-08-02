import 'package:flutter/material.dart';

/// Minimal markdown rendering for LLM chat replies -- just **bold** and
/// "- "/"* " bullet lists, mirroring the web client's FormattedText.jsx.
/// Not a general markdown parser on purpose: these two rules are all the
/// chat system prompts are instructed to use.
class FormattedText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FormattedText(this.text, {super.key, this.style});

  static final _boldPattern = RegExp(r'\*\*(.+?)\*\*');
  static final _bulletPattern = RegExp(r'^\s*[-*]\s+(.*)');

  List<InlineSpan> _inlineSpans(String line) {
    final spans = <InlineSpan>[];
    int last = 0;
    for (final match in _boldPattern.allMatches(line)) {
      if (match.start > last) spans.add(TextSpan(text: line.substring(last, match.start)));
      spans.add(TextSpan(text: match.group(1), style: const TextStyle(fontWeight: FontWeight.bold)));
      last = match.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    List<String>? currentList;

    void flushList() {
      final list = currentList;
      if (list != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: list
                .map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: style),
                          Expanded(child: Text.rich(TextSpan(style: style, children: _inlineSpans(item)))),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ));
        currentList = null;
      }
    }

    for (final line in text.split('\n')) {
      final match = _bulletPattern.firstMatch(line);
      if (match != null) {
        (currentList ??= []).add(match.group(1)!);
      } else {
        flushList();
        if (line.isEmpty) {
          children.add(const SizedBox(height: 6));
        } else {
          children.add(Text.rich(TextSpan(style: style, children: _inlineSpans(line))));
        }
      }
    }
    flushList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}
