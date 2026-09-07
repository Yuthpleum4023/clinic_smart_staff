// INVENTORY_PHASE2_FLUTTER_INTEGRATION_UI_V1
// Admin operational visibility for Generic Integration Framework.
//
// Backend remains authoritative for:
// - admin authorization
// - clinic scope
// - exact item mapping
// - event processing / idempotency
// - stock movement through applyMovement()
//
// This UI never stores connector credentials and never sends clinicId.

import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/inventory_api.dart';

class InventoryIntegrationScreen extends StatefulWidget {
  const InventoryIntegrationScreen({super.key});

  @override
  State<InventoryIntegrationScreen> createState() =>
      _InventoryIntegrationScreenState();
}

class _InventoryIntegrationScreenState
    extends State<InventoryIntegrationScreen> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _connectors = const [];
  Map<String, Map<String, dynamic>> _healthByConnector = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) return error.message;
    return 'โหลดข้อมูลระบบเชื่อมต่อไม่สำเร็จ กรุณาลองใหม่';
  }

  String _s(dynamic value) => (value ?? '').toString().trim();

  int _i(dynamic value) {
    if (value is int) return value;
    return int.tryParse(_s(value)) ?? 0;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final connectors = await InventoryApi.listIntegrationConnectors();
      final healthEntries = await Future.wait(
        connectors.map((connector) async {
          final id = _s(connector['_id']);
          if (id.isEmpty) return MapEntry(id, const <String, dynamic>{});

          try {
            final health = await InventoryApi.getIntegrationConnectorHealth(id);
            return MapEntry(id, health);
          } catch (_) {
            return MapEntry(id, const <String, dynamic>{});
          }
        }),
      );

      if (!mounted) return;

      setState(() {
        _connectors = connectors;
        _healthByConnector = Map<String, Map<String, dynamic>>.fromEntries(
          healthEntries.where((entry) => entry.key.isNotEmpty),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'healthy':
        return 'ปกติ';
      case 'needs_attention':
        return 'ต้องตรวจสอบ';
      case 'processing':
        return 'กำลังประมวลผล';
      case 'observed':
        return 'พบการเชื่อมต่อแล้ว';
      case 'disabled':
        return 'ปิดใช้งาน';
      case 'never_seen':
      default:
        return 'ยังไม่พบข้อมูล';
    }
  }

  IconData _stateIcon(String state) {
    switch (state) {
      case 'healthy':
        return Icons.check_circle_outline;
      case 'needs_attention':
        return Icons.warning_amber_rounded;
      case 'processing':
        return Icons.sync;
      case 'disabled':
        return Icons.pause_circle_outline;
      default:
        return Icons.cloud_outlined;
    }
  }

  Color _stateColor(BuildContext context, String state) {
    final colors = Theme.of(context).colorScheme;
    switch (state) {
      case 'healthy':
        return colors.primary;
      case 'needs_attention':
        return colors.error;
      case 'disabled':
        return colors.outline;
      default:
        return colors.secondary;
    }
  }

  String _fmtDate(dynamic value) {
    final raw = _s(value);
    if (raw.isEmpty) return '-';

    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;

    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Widget _connectorCard(Map<String, dynamic> connector) {
    final id = _s(connector['_id']);
    final health = _healthByConnector[id] ?? const <String, dynamic>{};
    final state = _s(health['state']).isEmpty
        ? 'never_seen'
        : _s(health['state']);
    final counts = _map(health['counts']);
    final connectorHealth = _map(health['connector']);
    final enabled = connector['enabled'] != false;
    final displayName = _s(connector['displayName']);
    final connectorKey = _s(connector['connectorKey']);
    final externalSystem = _s(connector['externalSystem']);
    final type = _s(connector['connectorType']);
    final errorCode = _s(connectorHealth['lastErrorCode']);
    final color = _stateColor(context, state);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: id.isEmpty
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _InventoryConnectorDetailScreen(connector: connector),
                  ),
                );
                if (mounted) await _load();
              },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_stateIcon(state), color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isNotEmpty ? displayName : connectorKey,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (externalSystem.isNotEmpty) externalSystem,
                            if (type.isNotEmpty) type,
                          ].join(' • '),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    avatar: Icon(
                      enabled ? Icons.power_outlined : Icons.power_off_outlined,
                      size: 17,
                    ),
                    label: Text(enabled ? 'เปิดใช้งาน' : 'ปิดใช้งาน'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'สถานะ: ${_stateLabel(state)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniMetric(label: 'ทั้งหมด', value: _i(counts['total'])),
                  _MiniMetric(label: 'สำเร็จ', value: _i(counts['applied'])),
                  _MiniMetric(
                    label: 'ติดปัญหา',
                    value: _i(counts['blocked']) + _i(counts['rejected']),
                  ),
                  _MiniMetric(
                    label: 'กำลังทำ',
                    value: _i(counts['received']) + _i(counts['processing']),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('พบล่าสุด: ${_fmtDate(connectorHealth['lastSeenAt'])}'),
              Text(
                'สำเร็จล่าสุด: '
                '${_fmtDate(connectorHealth['lastSuccessfulSyncAt'])}',
              ),
              if (errorCode.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'ข้อผิดพลาดล่าสุด: $errorCode',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_connectors.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 80),
            Icon(Icons.hub_outlined, size: 52),
            SizedBox(height: 12),
            Text(
              'ยังไม่มีระบบเชื่อมต่อคลังสินค้า\n'
              'เมื่อกำหนด Connector จากฝั่งผู้ดูแลแล้วจะแสดงที่นี่',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'ระบบเชื่อมต่อ',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'ติดตามการรับข้อมูลจากโปรแกรมคลินิกและเหตุการณ์ที่ต้องตรวจสอบ',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ..._connectors.map(_connectorCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ระบบเชื่อมต่อคลัง'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }
}

class _InventoryConnectorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> connector;

  const _InventoryConnectorDetailScreen({required this.connector});

  @override
  State<_InventoryConnectorDetailScreen> createState() =>
      _InventoryConnectorDetailScreenState();
}

class _InventoryConnectorDetailScreenState
    extends State<_InventoryConnectorDetailScreen> {
  bool _loading = true;
  String _error = '';
  String _status = 'blocked';

  Map<String, dynamic> _health = const {};
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _mappings = const [];
  String _reprocessingEventId = '';

  String _s(dynamic value) => (value ?? '').toString().trim();

  int _i(dynamic value) {
    if (value is int) return value;
    return int.tryParse(_s(value)) ?? 0;
  }

  double _d(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_s(value)) ?? 0;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) return error.message;
    return 'โหลดข้อมูลระบบเชื่อมต่อไม่สำเร็จ กรุณาลองใหม่';
  }

  String get _connectorId => _s(widget.connector['_id']);

  String get _title {
    final displayName = _s(widget.connector['displayName']);
    if (displayName.isNotEmpty) return displayName;
    return _s(widget.connector['connectorKey']);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_connectorId.isEmpty) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final results = await Future.wait<dynamic>([
        InventoryApi.getIntegrationConnectorHealth(_connectorId),
        InventoryApi.listIntegrationMappings(_connectorId),
        InventoryApi.listIntegrationEvents(
          connectorId: _connectorId,
          status: _status,
          limit: 50,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _health = Map<String, dynamic>.from(results[0] as Map);
        _mappings = List<Map<String, dynamic>>.from(results[1] as List);
        _events = List<Map<String, dynamic>>.from(results[2] as List);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _changeStatus(String value) async {
    if (_status == value) return;
    setState(() => _status = value);
    await _load();
  }

  String _fmtDate(dynamic value) {
    final raw = _s(value);
    if (raw.isEmpty) return '-';

    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;

    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'received':
        return 'รับแล้ว';
      case 'processing':
        return 'กำลังประมวลผล';
      case 'applied':
        return 'ตัด Stock แล้ว';
      case 'blocked':
        return 'รอแก้ไข';
      case 'rejected':
        return 'ปฏิเสธ';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    final colors = Theme.of(context).colorScheme;
    switch (status) {
      case 'applied':
        return colors.primary;
      case 'blocked':
      case 'rejected':
        return colors.error;
      case 'processing':
        return colors.secondary;
      default:
        return colors.outline;
    }
  }

  Widget _healthCard() {
    final counts = _map(_health['counts']);
    final connector = _map(_health['connector']);
    final blockedCodes = (_health['blockedByErrorCode'] is List)
        ? List<dynamic>.from(_health['blockedByErrorCode'] as List)
        : const <dynamic>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สถานะการเชื่อมต่อ',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniMetric(label: 'ทั้งหมด', value: _i(counts['total'])),
                _MiniMetric(label: 'สำเร็จ', value: _i(counts['applied'])),
                _MiniMetric(label: 'Blocked', value: _i(counts['blocked'])),
                _MiniMetric(label: 'Rejected', value: _i(counts['rejected'])),
              ],
            ),
            const SizedBox(height: 12),
            Text('พบล่าสุด: ${_fmtDate(connector['lastSeenAt'])}'),
            Text(
              'สำเร็จล่าสุด: '
              '${_fmtDate(connector['lastSuccessfulSyncAt'])}',
            ),
            if (blockedCodes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'สาเหตุที่ต้องตรวจสอบ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...blockedCodes.map((raw) {
                final row = _map(raw);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${_s(row['errorCode'])}: ${_i(row['count'])} รายการ',
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mappingCard(Map<String, dynamic> mapping) {
    final active = mapping['active'] != false;
    final numerator = _i(mapping['conversionNumerator']);
    final denominator = _i(mapping['conversionDenominator']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(active ? Icons.link_outlined : Icons.link_off_outlined),
        title: Text(
          '${_s(mapping['externalItemId'])} '
          '(${_s(mapping['externalUnit'])})',
        ),
        subtitle: Text(
          '→ Stock ${_s(mapping['stockItemId'])}\n'
          'หน่วยคลัง: ${_s(mapping['inventoryUnit'])}'
          '${numerator > 0 && denominator > 0 ? ' • แปลง $numerator/$denominator' : ''}',
        ),
        isThreeLine: true,
        trailing: Chip(label: Text(active ? 'ใช้งาน' : 'ปิด')),
      ),
    );
  }

  Future<void> _showEventDetail(Map<String, dynamic> event) async {
    final eventId = _s(event['_id']);
    if (eventId.isEmpty) return;

    try {
      final detail = await InventoryApi.getIntegrationEvent(eventId);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('รายละเอียดเหตุการณ์'),
          content: SingleChildScrollView(
            child: _EventDetailBody(event: detail),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
    }
  }

  Future<void> _reprocess(Map<String, dynamic> event) async {
    final eventId = _s(event['_id']);
    if (eventId.isEmpty || _reprocessingEventId.isNotEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ประมวลผลรายการอีกครั้ง'),
        content: const Text(
          'ควรกดหลังจากแก้ Mapping หรือสาเหตุที่ทำให้รายการติดปัญหาแล้ว\n\n'
          'ระบบจะใช้เหตุการณ์เดิมและกลไก idempotency เดิม '
          'ไม่สร้างรายการตัด Stock ซ้ำหากเคยสำเร็จแล้ว',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ประมวลผลอีกครั้ง'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => _reprocessingEventId = eventId);

    try {
      await InventoryApi.reprocessIntegrationEvent(eventId);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ประมวลผลเหตุการณ์เรียบร้อยแล้ว')),
      );

      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
    } finally {
      if (mounted) {
        setState(() => _reprocessingEventId = '');
      }
    }
  }

  Widget _eventCard(Map<String, dynamic> event) {
    final status = _s(event['status']);
    final errorCode = _s(event['errorCode']);
    final errorMessage = _s(event['errorMessage']);
    final eventId = _s(event['_id']);
    final color = _statusColor(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_s(event['externalItemId'])} '
                    '• ${_d(event['externalQuantity'])} '
                    '${_s(event['externalUnit'])}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  label: Text(_statusLabel(status)),
                  avatar: Icon(
                    status == 'applied'
                        ? Icons.check_circle_outline
                        : status == 'blocked'
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    size: 17,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Event: ${_s(event['externalEventId'])}'
              '${_s(event['externalLineId']).isNotEmpty ? ' / ${_s(event['externalLineId'])}' : ''}',
            ),
            Text('เกิดเมื่อ: ${_fmtDate(event['occurredAt'])}'),
            Text('พยายามประมวลผล: ${_i(event['processingAttempts'])} ครั้ง'),
            if (errorCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                errorCode,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (errorMessage.isNotEmpty) Text(errorMessage),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showEventDetail(event),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('รายละเอียด'),
                ),
                if (status == 'blocked')
                  FilledButton.icon(
                    onPressed: _reprocessingEventId.isNotEmpty
                        ? null
                        : () => _reprocess(event),
                    icon: _reprocessingEventId == eventId
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restart_alt),
                    label: const Text('ประมวลผลอีกครั้ง'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Text(_error, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _healthCard(),
          const SizedBox(height: 12),
          Text(
            'Exact Item Mapping',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_mappings.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('ยังไม่มีการจับคู่สินค้าสำหรับ Connector นี้'),
              ),
            )
          else
            ..._mappings.map(_mappingCard),
          const SizedBox(height: 16),
          Text(
            'Integration Events',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const [
                'blocked',
                'rejected',
                'received',
                'processing',
                'applied',
                '',
              ])
                ChoiceChip(
                  label: Text(value.isEmpty ? 'ทั้งหมด' : _statusLabel(value)),
                  selected: _status == value,
                  onSelected: (_) => _changeStatus(value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_events.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('ไม่พบเหตุการณ์ในสถานะที่เลือก'),
              ),
            )
          else
            ..._events.map(_eventCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? 'รายละเอียด Connector' : _title),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }
}

class _EventDetailBody extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventDetailBody({required this.event});

  String _s(dynamic value) => (value ?? '').toString().trim();

  Widget _row(String label, dynamic value) {
    final text = _s(value);
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          SelectableText(text),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('สถานะ', event['status']),
        _row('External Event ID', event['externalEventId']),
        _row('External Line ID', event['externalLineId']),
        _row('External Item ID', event['externalItemId']),
        _row('หน่วยต้นทาง', event['externalUnit']),
        _row('จำนวนต้นทาง', event['externalQuantity']),
        _row('จำนวนหลังแปลง', event['normalizedQuantity']),
        _row('ประเภทเหตุการณ์', event['eventType']),
        _row('Reference Type', event['referenceType']),
        _row('Reference No.', event['referenceNo']),
        _row('Mapping ID', event['mappingId']),
        _row('Stock Item ID', event['stockItemId']),
        _row('Stock Movement ID', event['stockMovementId']),
        _row('Error Code', event['errorCode']),
        _row('Error', event['errorMessage']),
        _row('Processing Attempts', event['processingAttempts']),
        _row('มี Source Metadata', event['hasSourceMetadata']),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final int value;

  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
