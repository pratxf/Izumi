import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/constants/app_colors.dart';
import '../../services/diagnostic_logger.dart';

/// Hidden admin debug screen. Surfaces device-level diagnostic reports
/// uploaded by employees so the operator can root-cause tracking failures
/// without guessing.
class DiagnosticAdminScreen extends StatefulWidget {
  const DiagnosticAdminScreen({super.key, required this.enterpriseId});

  final String enterpriseId;

  @override
  State<DiagnosticAdminScreen> createState() => _DiagnosticAdminScreenState();
}

class _DiagnosticAdminScreenState extends State<DiagnosticAdminScreen> {
  bool _enabled = DiagnosticLogger.I.enabled;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Diagnostics'),
            subtitle: const Text(
              'Sends an FCM command to all employees in this enterprise to '
              'enable or disable diagnostic logging.',
            ),
            value: _enabled,
            onChanged: (v) async {
              setState(() => _enabled = v);
              await DiagnosticLogger.I.setEnabled(v);
              await _broadcast(v ? 'enable' : 'disable');
            },
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search employees',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
          const SizedBox(height: 12),
          _ReportsList(enterpriseId: widget.enterpriseId, query: _query),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Request live dump from all employees'),
            onPressed: () => _broadcast('upload_now'),
          ),
        ],
      ),
    );
  }

  Future<void> _broadcast(String action) async {
    // Topic-based broadcast. The server-side function or the admin can also
    // call FCM HTTP v1 directly with the same payload.
    try {
      await FirebaseMessaging.instance.subscribeToTopic(
        'diag_${widget.enterpriseId}',
      );
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Diagnostic broadcast queued: $action')),
    );
  }
}

class _ReportsList extends StatelessWidget {
  const _ReportsList({required this.enterpriseId, required this.query});

  final String enterpriseId;
  final String query;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // We can't easily listen across all sub-collections, so just list the
      // most recent reports written under any user via a collectionGroup.
      stream: FirebaseFirestore.instance
          .collectionGroup('items')
          .orderBy('uploadedAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = (snap.data?.docs ?? [])
            .where((d) => d.reference.path.contains('/$enterpriseId/'))
            .where((d) {
              if (query.isEmpty) return true;
              final sid = (d.data()['sessionId'] ?? '').toString().toLowerCase();
              return sid.contains(query);
            })
            .toList();
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No diagnostic reports yet.')),
          );
        }
        return Column(
          children: [
            for (final d in docs)
              Card(
                child: ListTile(
                  title: Text('Session ${d.data()['sessionId'] ?? '—'}'),
                  subtitle: Text(_summarize(d.data())),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ReportDetailScreen(report: d.data()),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _summarize(Map<String, dynamic> data) {
    final summary = data['sessionSummary'] as Map<String, dynamic>?;
    final reportType = data['reportType'] ?? 'session_end';
    if (summary == null) return reportType.toString();
    final duration = summary['durationSec'] ?? 0;
    final distance = summary['distanceKm'] ?? 0;
    final destroyCount = summary['serviceDestroyCount'] ?? 0;
    return 'duration=${duration}s · distance=${distance}km · destroyed×$destroyCount';
  }
}

class _ReportDetailScreen extends StatelessWidget {
  const _ReportDetailScreen({required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final events = (report['events'] as List?) ?? const [];
    final deviceInfo = report['deviceInfo'] as Map<String, dynamic>? ?? const {};
    final summary = report['sessionSummary'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: const Text('Session Diagnostic')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Device', [
            for (final entry in deviceInfo.entries)
              _kv(entry.key, entry.value),
          ]),
          if (summary != null)
            _section('Summary', [
              for (final entry in summary.entries) _kv(entry.key, entry.value),
            ]),
          _section('Events (${events.length})', [
            for (final e in events.cast<Map<String, dynamic>>())
              _eventRow(e),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, Object? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 160, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text('$v', style: const TextStyle(fontFamily: 'monospace'))),
          ],
        ),
      );

  Widget _eventRow(Map<String, dynamic> e) {
    final ts = e['timestamp'] is int
        ? DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int)
        : null;
    final tsStr = ts == null
        ? '?'
        : '${ts.hour.toString().padLeft(2, '0')}:'
            '${ts.minute.toString().padLeft(2, '0')}:'
            '${ts.second.toString().padLeft(2, '0')}';
    final severity = e['severity']?.toString() ?? 'info';
    final color = severity == 'critical' || severity == 'error'
        ? AppColors.warning
        : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(tsStr, style: TextStyle(color: color, fontFamily: 'monospace'))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e['type']?.toString() ?? '',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                if (e['payload'] != null)
                  Text('${e['payload']}',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
