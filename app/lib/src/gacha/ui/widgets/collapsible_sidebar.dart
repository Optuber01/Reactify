import 'dart:ui';
import 'package:flutter/material.dart';

class CollapsibleSidebar extends StatefulWidget {
  const CollapsibleSidebar({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  State<CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<CollapsibleSidebar> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _isCollapsed ? 64 : 320,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar header with collapse button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!_isCollapsed)
                  Expanded(
                    child: Text(
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: _isCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                  icon: Icon(
                    _isCollapsed ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isCollapsed = !_isCollapsed;
                    });
                  },
                ),
              ],
            ),
          ),

          // Sidebar contents
          if (!_isCollapsed)
            Expanded(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.01),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
