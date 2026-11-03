import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/forum.dart';

const collectionPreviewBatchSize = 10;

class ThreadCollectionList extends StatefulWidget {
  const ThreadCollectionList({
    super.key,
    required this.links,
    required this.client,
    required this.itemBuilder,
    this.controller,
    this.header,
    this.footer,
    this.onRefresh,
    this.preparePreviews = true,
    this.padding = const EdgeInsets.all(16),
  });

  final List<ForumLink> links;
  final ForumClient client;
  final Widget Function(int index, ForumLink link, ThreadSummary? summary)
  itemBuilder;
  final ScrollController? controller;
  final Widget? header, footer;
  final Future<void> Function()? onRefresh;
  final bool preparePreviews;
  final EdgeInsets padding;

  @override
  State<ThreadCollectionList> createState() => _ThreadCollectionListState();
}

class _ThreadCollectionListState extends State<ThreadCollectionList> {
  late final ScrollController _scroll = widget.controller ?? ScrollController();
  final _summaries = <String, ThreadSummary>{};
  final _failed = <String>{};
  int _ready = 0, _generation = 0;
  bool _loading = false;
  Timer? _deadline;
  Completer<void>? _batchDone;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadNext);
    _loadNext();
  }

  @override
  void didUpdateWidget(ThreadCollectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.preparePreviews != widget.preparePreviews ||
        !listEquals(
          oldWidget.links.map((e) => e.url).toList(),
          widget.links.map((e) => e.url).toList(),
        )) {
      _cancelBatch();
      _ready = 0;
      _loading = false;
      _failed.clear();
      final urls = widget.links.map((e) => e.url).toSet();
      _summaries.removeWhere(
        (url, _) =>
            oldWidget.client != widget.client ||
            oldWidget.preparePreviews != widget.preparePreviews ||
            !urls.contains(url),
      );
      _loadNext();
    }
  }

  @override
  void dispose() {
    _cancelBatch();
    _scroll.removeListener(_maybeLoadNext);
    if (widget.controller == null) _scroll.dispose();
    super.dispose();
  }

  void _cancelBatch() {
    _generation++;
    _deadline?.cancel();
    if (_batchDone?.isCompleted == false) _batchDone!.complete();
    _batchDone = null;
    _deadline = null;
  }

  void _maybeLoadNext() {
    if (mounted && _scroll.hasClients && _scroll.position.extentAfter < 600) {
      _loadNext();
    }
  }

  Future<void> _loadNext({bool retry = false}) async {
    if (_loading || (!retry && _ready >= widget.links.length)) return;
    final generation = _generation;
    final end = math.min(
      _ready + collectionPreviewBatchSize,
      widget.links.length,
    );
    final batch = retry
        ? widget.links
              .take(_ready)
              .where((e) => _failed.isEmpty || _failed.contains(e.url))
              .take(collectionPreviewBatchSize)
        : widget.links.skip(_ready).take(end - _ready);
    final urls = batch.map((e) => e.url).where((url) {
      final uri = forumUri(url);
      return widget.preparePreviews &&
          isForumUri(uri) &&
          threadId(uri) != null &&
          (retry || !_summaries.containsKey(url));
    }).toSet();
    var accepting = true;
    bool active() => mounted && generation == _generation && accepting;
    final results = <String, ThreadSummary>{};
    setState(() => _loading = true);
    final done = Completer<void>();
    _batchDone = done;
    _deadline = Timer(const Duration(seconds: 12), () {
      if (!done.isCompleted) done.complete();
    });
    // Publish whole cards together; late previews must not resize visible rows.
    unawaited(
      Future.wait<void>([
        for (final url in urls)
          () async {
            try {
              final summary = await widget.client.threadSummary(url, active);
              if (active()) results[url] = summary;
            } catch (_) {
              // Keep the original list entry when permissions or networking fail.
            }
          }(),
      ]).then((_) {
        if (!done.isCompleted) done.complete();
      }),
    );
    await done.future;
    accepting = false;
    if (identical(_batchDone, done)) {
      _deadline?.cancel();
      _batchDone = null;
      _deadline = null;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _summaries.addAll(results);
      _failed
        ..removeAll(results.keys)
        ..addAll(urls.where((url) => !results.containsKey(url)));
      if (!retry) _ready = end;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadNext());
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: widget.onRefresh ?? () => _loadNext(retry: true),
    child: ListView.builder(
      controller: _scroll,
      padding: widget.padding,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      itemCount: _ready + 2,
      itemBuilder: (context, index) {
        if (index == 0) return widget.header ?? const SizedBox.shrink();
        if (index <= _ready) {
          final link = widget.links[index - 1];
          return widget.itemBuilder(index - 1, link, _summaries[link.url]);
        }
        return Column(
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_failed.isNotEmpty)
              TextButton(
                onPressed: _loading ? null : () => _loadNext(retry: true),
                child: const Text('部分帖子预览未能加载，点此重试'),
              ),
            if (!_loading && _ready < widget.links.length)
              TextButton(onPressed: _loadNext, child: const Text('加载更多')),
            if (widget.footer != null) widget.footer!,
          ],
        );
      },
    ),
  );
}
