import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Markdown rendering for LLM chat replies, mirroring the web client's
/// FormattedText.jsx. The models routinely produce more than the **bold**
/// + "- " bullets the system prompts ask for -- headings, numbered lists,
/// tables, links, inline code -- and the old two-rule renderer showed all of
/// those as raw symbols. GitHub-flavored markdown (the package default) adds
/// tables, strikethrough and autolinks. Raw HTML in the text is never
/// rendered as markup, and images are never loaded.
///
/// Re-parsed on every StreamingFormattedText tick, so a half-revealed reply
/// renders as whatever markdown it forms so far -- harmless, since an
/// unclosed "**" just shows as text until its closing pair arrives.
class FormattedText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FormattedText(this.text, {super.key, this.style});

  static Future<void> _openLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    // Only real web/mail links -- never an app-internal or file scheme an
    // LLM happened to write.
    if (uri == null || !const {'http', 'https', 'mailto'}.contains(uri.scheme)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final base = style ?? TextStyle(color: AppColors.dmText);
    final size = base.fontSize ?? 14.0;
    final soft = AppColors.dmTextSoft;
    final codeBg = Colors.black.withValues(alpha: isAppDarkMode ? 0.22 : 0.06);
    final border = AppColors.dmBubbleBorder;
    // Chat-sized headings -- a model's "# Title" shouldn't render at
    // page-title size inside a bubble.
    TextStyle heading(double scale) => base.copyWith(fontSize: size * scale, fontWeight: FontWeight.w700, height: 1.3);
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base.copyWith(height: 1.45),
      h1: heading(1.12),
      h2: heading(1.08),
      h3: heading(1.02),
      h4: heading(1.0),
      h5: heading(0.95),
      h6: heading(0.95),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      a: base.copyWith(color: AppColors.dmAccent, decoration: TextDecoration.underline),
      listBullet: base.copyWith(color: soft),
      listIndent: 20,
      blockSpacing: 8,
      code: base.copyWith(fontFamily: 'monospace', fontSize: size * 0.88, backgroundColor: codeBg),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(8)),
      blockquote: base.copyWith(color: soft),
      blockquotePadding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.dmAccent, width: 3)),
      ),
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base.copyWith(fontSize: size * 0.94),
      tableBorder: TableBorder.all(color: border),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      // Wide tables scroll sideways inside the bubble rather than squeezing
      // every column to unreadable widths.
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: text,
      // Shrink-wraps to the content, so a one-word reply keeps a small
      // bubble instead of stretching to the bubble's max width.
      fitContent: true,
      // The models write single newlines meaning "new line", not the
      // markdown-spec "same paragraph" -- keep them as visible breaks.
      softLineBreak: true,
      styleSheet: _styleSheet(context),
      onTapLink: (_, href, __) => _openLink(href),
      imageBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
