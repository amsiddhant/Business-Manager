import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../models/entity_comment.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import 'app_card.dart';
import 'confirm_dialog.dart';
import 'initials_avatar.dart';

/// A "Last Activity" card showing a single timestamp — the newest of an
/// entity's comment dates and its audit timestamps.
class LastActivityCard extends StatelessWidget {
  const LastActivityCard({super.key, required this.activityAt});

  final DateTime? activityAt;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Last Activity',
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppDate.format(activityAt),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// A reusable comment thread rendered as a [SectionCard]. Comments are supplied
/// by the parent (embedded on the entity document) and persistence is delegated
/// to [onPost], which receives the freshly-built comment and must save + refresh
/// — this keeps entity-specific save wiring in the screen while the thread owns
/// the input, attribution, ordering, spinner and error handling.
///
/// Callers should invoke this only for viewers permitted to comment; the input
/// is additionally hidden when [canComment] is false so a read-only viewer can
/// still see the history.
class EntityCommentThread extends StatefulWidget {
  const EntityCommentThread({
    super.key,
    required this.comments,
    required this.canComment,
    required this.onPost,
  });

  final List<EntityComment> comments;
  final bool canComment;

  /// Persists [comment] appended to the entity and refreshes data. Throws to
  /// signal failure (surfaced as an error snack).
  final Future<void> Function(EntityComment comment) onPost;

  @override
  State<EntityCommentThread> createState() => _EntityCommentThreadState();
}

class _EntityCommentThreadState extends State<EntityCommentThread> {
  final _controller = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    final user = context.read<AppState>().currentUser;
    if (user == null) return;

    setState(() => _posting = true);
    final comment = EntityComment(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      authorId: user.uid,
      authorName: user.name,
      text: text,
      createdAt: DateTime.now(),
    );
    try {
      await widget.onPost(comment);
      _controller.clear();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = [...widget.comments]..sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    return SectionCard(
      title: 'Comment Thread',
      subtitle: '${comments.length} '
          '${comments.length == 1 ? 'comment' : 'comments'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.canComment) ...[
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(hintText: 'Add a comment…'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _posting ? null : _post,
                icon: _posting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 16),
                label: const Text('Post'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('No comments yet.',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            for (var i = 0; i < comments.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _CommentTile(comment: comments[i]),
            ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final EntityComment comment;

  @override
  Widget build(BuildContext context) {
    final author = comment.authorName.isEmpty ? 'Unknown' : comment.authorName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialsAvatar(name: author, size: 32),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(author,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  if (comment.createdAt != null)
                    Text(AppDate.short(comment.createdAt!),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
              const SizedBox(height: 2),
              Text(comment.text,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The standard right-hand column for a detail screen: a Last Activity card
/// stacked over the comment thread. [onPost] is forwarded to the thread.
class DetailActivityColumn extends StatelessWidget {
  const DetailActivityColumn({
    super.key,
    required this.activityAt,
    required this.comments,
    required this.canComment,
    required this.onPost,
  });

  final DateTime? activityAt;
  final List<EntityComment> comments;
  final bool canComment;
  final Future<void> Function(EntityComment comment) onPost;

  @override
  Widget build(BuildContext context) {
    // Touch DataController so the column rebuilds after a refresh appends a
    // comment (the parent screen watches it too, but this keeps the widget
    // self-consistent when embedded standalone).
    context.watch<DataController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LastActivityCard(activityAt: activityAt),
        const SizedBox(height: AppSpacing.lg),
        EntityCommentThread(
          comments: comments,
          canComment: canComment,
          onPost: onPost,
        ),
      ],
    );
  }
}
