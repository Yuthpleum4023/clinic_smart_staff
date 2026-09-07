// INVENTORY_PHASE1_FLUTTER_V2
// lib/screens/inventory/inventory_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/inventory_api.dart';
import 'package:clinic_smart_staff/models/inventory_item_model.dart';
import 'package:clinic_smart_staff/screens/inventory/inventory_integration_screen.dart';

enum _InventoryListFilter { active, lowStock, inactive }

class InventoryScreen extends StatefulWidget {
  final String role;

  const InventoryScreen({super.key, required this.role});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _loading = true;
  String _error = '';
  List<InventoryItem> _items = const <InventoryItem>[];

  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  int _loadGeneration = 0;
  String _updatingItemId = '';

  _InventoryListFilter _filter = _InventoryListFilter.active;

  bool get _helperMode => widget.role.trim().toLowerCase() == 'helper';

  // INVENTORY_ADMIN_ITEM_UI_V2
  // INVENTORY_SERVER_ITEM_CODE_UI_V2
  // UX mirror only. Backend admin authorization remains authoritative.
  bool get _adminMode {
    switch (widget.role.trim().toLowerCase()) {
      case 'admin':
      case 'clinic':
      case 'clinic_admin':
      case 'clinicadmin':
      case 'owner':
        return true;
      default:
        return false;
    }
  }

  // UX mirror only. Backend requireRole remains authoritative.
  bool get _consumeMode {
    switch (widget.role.trim().toLowerCase()) {
      case 'admin':
      case 'clinic':
      case 'clinic_admin':
      case 'clinicadmin':
      case 'owner':
      case 'employee':
      case 'staff':
      case 'emp':
        return true;
      default:
        return false;
    }
  }

  int get _lowStockCount =>
      _items.where((item) => item.lowStockActive && item.active).length;

  @override
  void initState() {
    super.initState();
    if (_helperMode) {
      _loading = false;
    } else {
      _load();
    }
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) return error.message;
    return 'โหลดข้อมูลคลังสินค้าไม่สำเร็จ กรุณาลองใหม่';
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();

    setState(() {});

    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _clearSearch() async {
    if (_searchController.text.isEmpty) return;

    _searchDebounce?.cancel();
    _searchController.clear();

    setState(() {});

    await _load();
  }

  Future<void> _selectFilter(_InventoryListFilter filter) async {
    if (_filter == filter) return;

    setState(() {
      _filter = filter;
    });

    await _load();
  }

  Future<void> _load() async {
    if (_helperMode) return;

    final generation = ++_loadGeneration;

    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }

    bool? active;
    bool? lowStock;

    switch (_filter) {
      case _InventoryListFilter.active:
        active = true;
        break;
      case _InventoryListFilter.lowStock:
        lowStock = true;
        break;
      case _InventoryListFilter.inactive:
        active = false;
        break;
    }

    try {
      final items = await InventoryApi.listItems(
        search: _searchController.text,
        active: active,
        lowStock: lowStock,
      );

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _openCreateItem() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateInventoryItemDialog(),
    );

    if (!mounted || created != true) return;

    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('เพิ่มสินค้าในคลังเรียบร้อยแล้ว')),
    );
  }

  Future<void> _openThreshold(InventoryItem item) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InventoryThresholdDialog(item: item),
    );

    if (!mounted || changed != true) return;

    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('อัปเดตระดับแจ้งเตือนของ ${item.name} แล้ว')),
    );
  }

  Future<void> _openStockIn(InventoryItem item) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StockInDialog(item: item),
    );

    if (!mounted || changed != true) return;

    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('รับ ${item.name} เข้าคลังเรียบร้อยแล้ว')),
    );
  }

  Future<void> _openConsume(InventoryItem item) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConsumeInventoryDialog(item: item),
    );

    if (!mounted || changed != true) return;

    await _load();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('บันทึกการเบิก ${item.name} เรียบร้อยแล้ว')),
    );
  }

  Future<void> _setItemActive(InventoryItem item, bool active) async {
    if (!_adminMode || _updatingItemId.isNotEmpty) {
      return;
    }

    final verb = active ? 'เปิดใช้งานอีกครั้ง' : 'เลิกใช้งาน';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$verbสินค้า'),
        content: Text(
          active
              ? 'ต้องการเปิดใช้งาน "${item.name}" อีกครั้งใช่หรือไม่'
              : 'ต้องการเลิกใช้งาน "${item.name}" ใช่หรือไม่\n\n'
                    'ประวัติ Stock Card จะยังคงอยู่และสามารถเปิดใช้งานกลับได้ภายหลัง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(verb),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _updatingItemId = item.id;
      _error = '';
    });

    try {
      await InventoryApi.setItemActive(stockItemId: item.id, active: active);

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? 'เปิดใช้งาน ${item.name} อีกครั้งแล้ว'
                : 'เลิกใช้งาน ${item.name} แล้ว',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _messageFor(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingItemId = '';
        });
      }
    }
  }

  Future<void> _openIntegration() async {
    if (!_adminMode) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InventoryIntegrationScreen()),
    );
  }

  Future<void> _openStockCard(InventoryItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _InventoryStockCardScreen(item: item)),
    );
  }

  String _fmtQty(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();

    var text = value.toStringAsFixed(3);
    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  Widget _summaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'คลังสินค้า',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                _searchDebounce?.cancel();
                _load();
              },
              decoration: InputDecoration(
                labelText: 'ค้นหาสินค้า',
                hintText: 'ชื่อสินค้า, รหัส INV หรือหมวดหมู่',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'ล้างคำค้นหา',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('ใช้งานอยู่'),
                  selected: _filter == _InventoryListFilter.active,
                  onSelected: (_) => _selectFilter(_InventoryListFilter.active),
                ),
                ChoiceChip(
                  label: const Text('ใกล้หมด'),
                  selected: _filter == _InventoryListFilter.lowStock,
                  onSelected: (_) =>
                      _selectFilter(_InventoryListFilter.lowStock),
                ),
                ChoiceChip(
                  label: const Text('เลิกใช้งาน'),
                  selected: _filter == _InventoryListFilter.inactive,
                  onSelected: (_) =>
                      _selectFilter(_InventoryListFilter.inactive),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CountTile(
                    label: 'รายการที่แสดง',
                    value: _items.length.toString(),
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CountTile(
                    label: 'ใกล้หมดในผลลัพธ์',
                    value: _lowStockCount.toString(),
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(InventoryItem item) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final subtitle = <String>[
      if (item.sku.isNotEmpty) 'SKU: ${item.sku}',
      if (item.category.isNotEmpty) item.category,
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name.isEmpty ? 'ไม่ระบุชื่อสินค้า' : item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(subtitle, style: TextStyle(color: muted)),
                      ],
                    ],
                  ),
                ),
                if (item.active && item.lowStockActive) const _LowStockBadge(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'คงเหลือ ${_fmtQty(item.currentQty)} ${item.unit}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
            const SizedBox(height: 3),
            Text(
              item.lowStockAlertEnabled
                  ? 'ระดับแจ้งเตือน: ${_fmtQty(item.minimumQty)} ${item.unit}'
                  : 'ปิดการแจ้งเตือนสินค้าใกล้หมด',
              style: TextStyle(color: muted),
            ),
            if (!item.active) ...[
              const SizedBox(height: 6),
              Text(
                'รายการนี้ไม่ได้เปิดใช้งาน',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: item.active ? () => _openStockIn(item) : null,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('เพิ่ม Stock'),
                ),
                if (_consumeMode)
                  OutlinedButton.icon(
                    onPressed: item.active && item.currentQty > 0
                        ? () => _openConsume(item)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('เบิกใช้'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _openStockCard(item),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Stock Card'),
                ),
                if (_adminMode && item.active)
                  OutlinedButton.icon(
                    onPressed: () => _openThreshold(item),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('ตั้งระดับแจ้งเตือน'),
                  ),
                if (_adminMode)
                  OutlinedButton.icon(
                    onPressed: _updatingItemId.isNotEmpty
                        ? null
                        : () => _setItemActive(item, !item.active),
                    icon: Icon(
                      item.active
                          ? Icons.archive_outlined
                          : Icons.restore_outlined,
                    ),
                    label: Text(
                      item.active ? 'เลิกใช้งาน' : 'เปิดใช้งานอีกครั้ง',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_helperMode) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Helper ไม่มีสิทธิ์ใช้งานคลังสินค้าของคลินิก',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty && _items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองใหม่'),
              ),
            ),
          ],
        ),
      );
    }

    final visible = _items;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          _summaryCard(),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Text(
                    _searchController.text.trim().isNotEmpty
                        ? 'ไม่พบสินค้าที่ตรงกับคำค้นหา'
                        : switch (_filter) {
                            _InventoryListFilter.active =>
                              'ยังไม่มีสินค้าใช้งานอยู่ในคลัง',
                            _InventoryListFilter.lowStock =>
                              'ไม่มีสินค้าที่อยู่ในสถานะใกล้หมด',
                            _InventoryListFilter.inactive =>
                              'ไม่มีสินค้าที่เลิกใช้งาน',
                          },
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_adminMode &&
                      _filter == _InventoryListFilter.active &&
                      _searchController.text.trim().isEmpty) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openCreateItem,
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('เพิ่มสินค้า'),
                    ),
                  ],
                ],
              ),
            )
          else
            ...visible.map(_itemCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('คลังสินค้า'),
        actions: [
          if (_adminMode)
            IconButton(
              tooltip: 'ระบบเชื่อมต่อ',
              onPressed: _openIntegration,
              icon: const Icon(Icons.sync_alt_outlined),
            ),
          if (_adminMode)
            IconButton(
              tooltip: 'เพิ่มสินค้า',
              onPressed: _openCreateItem,
              icon: const Icon(Icons.add_box_outlined),
            ),
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _helperMode ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _CountTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LowStockBadge extends StatelessWidget {
  const _LowStockBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'ใกล้หมด',
        style: TextStyle(
          color: colors.onErrorContainer,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

// INVENTORY_ADMIN_ITEM_UI_V2
class _CreateInventoryItemDialog extends StatefulWidget {
  const _CreateInventoryItemDialog();

  @override
  State<_CreateInventoryItemDialog> createState() =>
      _CreateInventoryItemDialogState();
}

class _CreateInventoryItemDialogState
    extends State<_CreateInventoryItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _minimumQty;

  bool _alertEnabled = true;
  bool _submitting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _category = TextEditingController();
    _unit = TextEditingController();
    _minimumQty = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _minimumQty.dispose();
    super.dispose();
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) return error.message;
    return 'เพิ่มสินค้าไม่สำเร็จ กรุณาลองใหม่';
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final minimumQty = double.tryParse(
      _minimumQty.text.trim().replaceAll(',', ''),
    );

    if (name.isEmpty) {
      setState(() => _error = 'กรุณาระบุชื่อสินค้า');
      return;
    }

    if (unit.isEmpty) {
      setState(() => _error = 'กรุณาระบุหน่วยสินค้า');
      return;
    }

    if (minimumQty == null || !minimumQty.isFinite || minimumQty < 0) {
      setState(() => _error = 'ระดับแจ้งเตือนต้องไม่น้อยกว่า 0');
      return;
    }

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await InventoryApi.createItem(
        name: name,
        category: _category.text,
        unit: unit,
        minimumQty: minimumQty,
        lowStockAlertEnabled: _alertEnabled,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เพิ่มสินค้าในคลัง'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'ชื่อสินค้า *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const InputDecorator(
              decoration: InputDecoration(
                labelText: 'รหัสสินค้า',
                border: OutlineInputBorder(),
              ),
              child: Text(
                'ระบบจะสร้างให้อัตโนมัติ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'หมวดหมู่',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'หน่วย *',
                hintText: 'เช่น กล่อง, ชิ้น, ขวด',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minimumQty,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'แจ้งเตือนเมื่อเหลือไม่เกิน',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('เปิดแจ้งเตือนสินค้าใกล้หมด'),
              value: _alertEnabled,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _alertEnabled = value),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'รหัสสินค้าและยอดเริ่มต้นสร้างโดยระบบ '
                'ยอดคงเหลือเปลี่ยนผ่านรายการ Stock เท่านั้น',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('เพิ่มสินค้า'),
        ),
      ],
    );
  }
}

class _InventoryThresholdDialog extends StatefulWidget {
  final InventoryItem item;

  const _InventoryThresholdDialog({required this.item});

  @override
  State<_InventoryThresholdDialog> createState() =>
      _InventoryThresholdDialogState();
}

class _InventoryThresholdDialogState extends State<_InventoryThresholdDialog> {
  late final TextEditingController _minimumQty;
  late bool _alertEnabled;

  bool _submitting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _minimumQty = TextEditingController(
      text: _fmtInitial(widget.item.minimumQty),
    );
    _alertEnabled = widget.item.lowStockAlertEnabled;
  }

  static String _fmtInitial(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  @override
  void dispose() {
    _minimumQty.dispose();
    super.dispose();
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) return error.message;
    return 'อัปเดตระดับแจ้งเตือนไม่สำเร็จ กรุณาลองใหม่';
  }

  Future<void> _submit() async {
    final minimumQty = double.tryParse(
      _minimumQty.text.trim().replaceAll(',', ''),
    );

    if (minimumQty == null || !minimumQty.isFinite || minimumQty < 0) {
      setState(() => _error = 'ระดับแจ้งเตือนต้องไม่น้อยกว่า 0');
      return;
    }

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await InventoryApi.updateThreshold(
        stockItemId: widget.item.id,
        minimumQty: minimumQty,
        lowStockAlertEnabled: _alertEnabled,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ตั้งระดับแจ้งเตือน • ${widget.item.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _minimumQty,
            autofocus: true,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'แจ้งเตือนเมื่อเหลือไม่เกิน',
              suffixText: widget.item.unit,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('เปิดแจ้งเตือนสินค้าใกล้หมด'),
            value: _alertEnabled,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _alertEnabled = value),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}

class _StockInDialog extends StatefulWidget {
  final InventoryItem item;

  const _StockInDialog({required this.item});

  @override
  State<_StockInDialog> createState() => _StockInDialogState();
}

class _StockInDialogState extends State<_StockInDialog> {
  late final TextEditingController _quantity;
  late final TextEditingController _referenceNo;
  late final TextEditingController _lotNo;
  late final TextEditingController _supplier;
  late final TextEditingController _reason;
  late final TextEditingController _note;

  bool _submitting = false;
  String _error = '';

  String? _idempotencyKey;
  String? _idempotencyFingerprint;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController();
    _referenceNo = TextEditingController();
    _lotNo = TextEditingController();
    _supplier = TextEditingController();
    _reason = TextEditingController(text: 'รับสินค้าเข้าคลัง');
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _referenceNo.dispose();
    _lotNo.dispose();
    _supplier.dispose();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  void _payloadChanged(String _) {
    _idempotencyKey = null;
    _idempotencyFingerprint = null;
    if (_error.isNotEmpty) {
      setState(() => _error = '');
    }
  }

  String _fingerprint(double quantity) {
    return <String>[
      widget.item.id,
      quantity.toString(),
      _referenceNo.text.trim(),
      _lotNo.text.trim(),
      _supplier.text.trim(),
      _reason.text.trim(),
      _note.text.trim(),
    ].join('|');
  }

  String _keyForFingerprint(String fingerprint) {
    if (_idempotencyKey != null && _idempotencyFingerprint == fingerprint) {
      return _idempotencyKey!;
    }

    final key =
        'flutter-stockin-${widget.item.id}-${DateTime.now().microsecondsSinceEpoch}';

    _idempotencyKey = key;
    _idempotencyFingerprint = fingerprint;
    return key;
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) return error.message;
    return 'เพิ่ม Stock ไม่สำเร็จ กรุณาลองใหม่';
  }

  Future<void> _submit() async {
    final rawQuantity = _quantity.text.trim().replaceAll(',', '');
    final quantity = double.tryParse(rawQuantity);

    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      setState(() => _error = 'กรุณาระบุจำนวนรับเข้าที่มากกว่า 0');
      return;
    }

    final fingerprint = _fingerprint(quantity);
    final key = _keyForFingerprint(fingerprint);

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await InventoryApi.stockIn(
        stockItemId: widget.item.id,
        quantity: quantity,
        idempotencyKey: key,
        referenceNo: _referenceNo.text,
        lotNo: _lotNo.text,
        supplier: _supplier.text,
        reason: _reason.text,
        note: _note.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('เพิ่ม Stock • ${widget.item.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _quantity,
              autofocus: true,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: _payloadChanged,
              decoration: InputDecoration(
                labelText: 'จำนวนรับเข้า *',
                suffixText: widget.item.unit,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referenceNo,
              enabled: !_submitting,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'เลขที่เอกสาร / อ้างอิง',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lotNo,
              enabled: !_submitting,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'Lot No.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supplier,
              enabled: !_submitting,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'ผู้จำหน่าย',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              enabled: !_submitting,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'เหตุผล',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_submitting,
              maxLines: 2,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึกรับเข้า'),
        ),
      ],
    );
  }
}

class _ConsumeInventoryDialog extends StatefulWidget {
  final InventoryItem item;

  const _ConsumeInventoryDialog({required this.item});

  @override
  State<_ConsumeInventoryDialog> createState() =>
      _ConsumeInventoryDialogState();
}

class _ConsumeInventoryDialogState extends State<_ConsumeInventoryDialog> {
  late final TextEditingController _quantity;
  late final TextEditingController _reason;
  late final TextEditingController _referenceNo;
  late final TextEditingController _lotNo;
  late final TextEditingController _note;

  bool _submitting = false;
  String _error = '';

  String? _idempotencyKey;
  String? _idempotencyFingerprint;

  @override
  void initState() {
    super.initState();

    _quantity = TextEditingController();
    _reason = TextEditingController();
    _referenceNo = TextEditingController();
    _lotNo = TextEditingController();
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    _referenceNo.dispose();
    _lotNo.dispose();
    _note.dispose();

    super.dispose();
  }

  String _fmtQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    var text = value.toStringAsFixed(3);

    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }

    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }

    return text;
  }

  void _payloadChanged(String _) {
    _idempotencyKey = null;
    _idempotencyFingerprint = null;

    if (_error.isNotEmpty) {
      setState(() {
        _error = '';
      });
    }
  }

  String _fingerprint(double quantity) {
    return <String>[
      widget.item.id,
      quantity.toString(),
      _reason.text.trim(),
      _referenceNo.text.trim(),
      _lotNo.text.trim(),
      _note.text.trim(),
    ].join('|');
  }

  String _keyForFingerprint(String fingerprint) {
    if (_idempotencyKey != null && _idempotencyFingerprint == fingerprint) {
      return _idempotencyKey!;
    }

    final key =
        'flutter-consume-'
        '${widget.item.id}-'
        '${DateTime.now().microsecondsSinceEpoch}';

    _idempotencyKey = key;
    _idempotencyFingerprint = fingerprint;

    return key;
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) {
      if (error.code == 'INSUFFICIENT_STOCK') {
        return 'จำนวนที่เบิกมากกว่ายอดคงเหลือในคลัง';
      }

      return error.message;
    }

    return 'บันทึกการเบิกไม่สำเร็จ กรุณาลองใหม่';
  }

  Future<void> _submit() async {
    final rawQuantity = _quantity.text.trim().replaceAll(',', '');

    final quantity = double.tryParse(rawQuantity);

    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      setState(() {
        _error = 'กรุณาระบุจำนวนเบิกที่มากกว่า 0';
      });

      return;
    }

    if (quantity > widget.item.currentQty) {
      setState(() {
        _error =
            'จำนวนที่เบิกมากกว่ายอดคงเหลือ '
            '${_fmtQty(widget.item.currentQty)} '
            '${widget.item.unit}';
      });

      return;
    }

    final reason = _reason.text.trim();

    if (reason.isEmpty) {
      setState(() {
        _error = 'กรุณาระบุเหตุผลในการเบิกใช้';
      });

      return;
    }

    final fingerprint = _fingerprint(quantity);

    final key = _keyForFingerprint(fingerprint);

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await InventoryApi.consume(
        stockItemId: widget.item.id,
        quantity: quantity,
        idempotencyKey: key,
        reason: reason,
        referenceNo: _referenceNo.text,
        lotNo: _lotNo.text,
        note: _note.text,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('เบิกใช้ • ${widget.item.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'คงเหลือ '
                '${_fmtQty(widget.item.currentQty)} '
                '${widget.item.unit}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              autofocus: true,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: _payloadChanged,
              decoration: InputDecoration(
                labelText: 'จำนวนเบิก *',
                suffixText: widget.item.unit,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              enabled: !_submitting,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'เหตุผล *',
                hintText: 'เช่น ใช้รักษาผู้ป่วย',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referenceNo,
              enabled: !_submitting,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'เลขที่อ้างอิง',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lotNo,
              enabled: !_submitting,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'Lot No.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_submitting,
              maxLines: 2,
              onChanged: _payloadChanged,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึกการเบิก'),
        ),
      ],
    );
  }
}

class _InventoryStockCardScreen extends StatefulWidget {
  final InventoryItem item;

  const _InventoryStockCardScreen({required this.item});

  @override
  State<_InventoryStockCardScreen> createState() =>
      _InventoryStockCardScreenState();
}

class _InventoryStockCardScreenState extends State<_InventoryStockCardScreen> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _card;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _messageFor(Object error) {
    if (error is InventoryApiException) return error.message;
    return 'โหลด Stock Card ไม่สำเร็จ กรุณาลองใหม่';
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }

    try {
      final card = await InventoryApi.getOperationalStockCard(widget.item.id);
      if (!mounted) return;
      setState(() {
        _card = card;
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

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _movementList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];

    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _text(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value)) ?? 0;
  }

  String _fmtQty(dynamic value) {
    final number = _number(value);
    if (number == number.roundToDouble()) return number.toInt().toString();

    var text = number.toStringAsFixed(3);
    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  String _fmtDate(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return '';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _movementLabel(String type) {
    switch (type) {
      case 'stock_in':
        return 'รับเข้า';
      case 'manual_consumption':
        return 'เบิกออก';
      case 'adjustment':
        return 'ปรับยอด';
      case 'reversal':
        return 'กลับรายการ';
      default:
        return type.isEmpty ? 'รายการเคลื่อนไหว' : type;
    }
  }

  String _delta(dynamic value) {
    final number = _number(value);
    final qty = _fmtQty(number);
    return number > 0 ? '+$qty' : qty;
  }

  Widget _summary(Map<String, dynamic> card) {
    final summary = _map(card['summary']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.name,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              'ยอดยกมา: ${_fmtQty(card['openingBalance'])} ${widget.item.unit}',
            ),
            Text(
              'ยอดคงเหลือ: ${_fmtQty(card['closingBalance'])} ${widget.item.unit}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Divider(height: 24),
            Text(
              'รับเข้า ${_fmtQty(summary['stockInQty'])} • '
              'เบิกออก ${_fmtQty(summary['consumptionQty'])} • '
              'ปรับยอด ${_fmtQty(summary['adjustmentNetQty'])}',
            ),
            if (card['truncated'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'แสดงรายการบางส่วนจากทั้งหมด '
                  '${_text(card['totalCount'])} รายการ',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _movementCard(Map<String, dynamic> movement) {
    final type = _text(movement['type']);
    final referenceNo = _text(movement['referenceNo']);
    final performedByName = _text(movement['performedByName']);
    final reason = _text(movement['reason']);
    final note = _text(movement['note']);
    final timestamp = _fmtDate(movement['occurredAt'] ?? movement['createdAt']);

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _movementLabel(type),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${_delta(movement['quantityDelta'])} ${widget.item.unit}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'คงเหลือหลังรายการ: '
              '${_fmtQty(movement['balanceAfter'])} ${widget.item.unit}',
            ),
            if (referenceNo.isNotEmpty) Text('อ้างอิง: $referenceNo'),
            if (performedByName.isNotEmpty) Text('ผู้บันทึก: $performedByName'),
            if (reason.isNotEmpty) Text('เหตุผล: $reason'),
            if (note.isNotEmpty) Text('หมายเหตุ: $note'),
            if (timestamp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  timestamp,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
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

    if (_error.isNotEmpty && _card == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      );
    }

    final card = _card ?? <String, dynamic>{};
    final movements = _movementList(card['movements']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          _summary(card),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Text(
              'รายการเคลื่อนไหว',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'ยังไม่มีรายการเคลื่อนไหว',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...movements.map(_movementCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Card'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }
}
