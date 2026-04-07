import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/clinic_logo_api.dart';
import 'package:clinic_smart_staff/api/receipt_api.dart';
import 'package:clinic_smart_staff/screens/social_security_receipt_detail_screen.dart';
import 'package:clinic_smart_staff/widgets/clinic_logo_view.dart';

class SocialSecurityReceiptCreateScreen extends StatefulWidget {
  final String clinicId;

  final String? initialClinicName;
  final String? initialClinicBranchName;
  final String? initialClinicAddress;
  final String? initialClinicPhone;
  final String? initialClinicTaxId;
  final String? initialLogoUrl;

  const SocialSecurityReceiptCreateScreen({
    super.key,
    required this.clinicId,
    this.initialClinicName,
    this.initialClinicBranchName,
    this.initialClinicAddress,
    this.initialClinicPhone,
    this.initialClinicTaxId,
    this.initialLogoUrl,
  });

  @override
  State<SocialSecurityReceiptCreateScreen> createState() =>
      _SocialSecurityReceiptCreateScreenState();
}

class _SocialSecurityReceiptCreateScreenState
    extends State<SocialSecurityReceiptCreateScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _customerNameCtrl = TextEditingController();
  final TextEditingController _customerAddressCtrl = TextEditingController();
  final TextEditingController _serviceMonthCtrl = TextEditingController();
  final TextEditingController _servicePeriodTextCtrl = TextEditingController();

  final TextEditingController _clinicNameCtrl = TextEditingController();
  final TextEditingController _clinicBranchNameCtrl = TextEditingController();
  final TextEditingController _clinicAddressCtrl = TextEditingController();
  final TextEditingController _clinicPhoneCtrl = TextEditingController();
  final TextEditingController _clinicTaxIdCtrl = TextEditingController();
  final TextEditingController _logoUrlCtrl = TextEditingController();

  final TextEditingController _withholderTaxIdCtrl = TextEditingController();

  final TextEditingController _bankAccountNameCtrl = TextEditingController();
  final TextEditingController _bankAccountNumberCtrl = TextEditingController();
  final TextEditingController _paymentReferenceCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  Timer? _draftSaveDebounce;

  bool _submitting = false;
  bool _prefillingClinic = true;
  bool _uploadingLogo = false;
  bool _removingLogo = false;

  String _paymentMethod = 'transfer';
  String _bankName = 'ธนาคารกสิกรไทย';

  final List<String> _paymentMethods = <String>[
    'cash',
    'transfer',
    'cheque',
    'other',
  ];

  final List<String> _bankOptions = <String>[
    'ธนาคารกรุงเทพ',
    'ธนาคารกสิกรไทย',
    'ธนาคารกรุงไทย',
    'ธนาคารไทยพาณิชย์',
    'ธนาคารกรุงศรีอยุธยา',
    'ธนาคารทหารไทยธนชาต',
    'ธนาคารออมสิน',
    'ธนาคารเพื่อการเกษตรและสหกรณ์การเกษตร',
    'ธนาคารยูโอบี',
    'ธนาคารซีไอเอ็มบี ไทย',
    'อื่น ๆ',
  ];

  final List<_ReceiptItemForm> _items = <_ReceiptItemForm>[
    _ReceiptItemForm(),
  ];

  String _profileKey(String clinicId, String field) {
    return 'clinic_profile_${clinicId}_$field';
  }

  List<String> get _bankPickerOptions {
    final current = _bankName.trim();
    final options = <String>[];

    if (current.isNotEmpty && !_bankOptions.contains(current)) {
      options.add(current);
    }

    options.addAll(_bankOptions);
    return options;
  }

  bool get _isTransfer => _paymentMethod == 'transfer';
  bool get _isCheque => _paymentMethod == 'cheque';

  @override
  void initState() {
    super.initState();
    _serviceMonthCtrl.text = _defaultServiceMonth();
    _bootstrapClinicPrefill();
  }

  @override
  void dispose() {
    _draftSaveDebounce?.cancel();

    _customerNameCtrl.dispose();
    _customerAddressCtrl.dispose();
    _serviceMonthCtrl.dispose();
    _servicePeriodTextCtrl.dispose();

    _clinicNameCtrl.dispose();
    _clinicBranchNameCtrl.dispose();
    _clinicAddressCtrl.dispose();
    _clinicPhoneCtrl.dispose();
    _clinicTaxIdCtrl.dispose();
    _logoUrlCtrl.dispose();

    _withholderTaxIdCtrl.dispose();
    _bankAccountNameCtrl.dispose();
    _bankAccountNumberCtrl.dispose();
    _paymentReferenceCtrl.dispose();

    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  String _defaultServiceMonth() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    return '$year-$month';
  }

  String _paymentMethodLabel(String value) {
    switch (value) {
      case 'cash':
        return 'เงินสด';
      case 'transfer':
        return 'โอนเงิน';
      case 'cheque':
        return 'เช็ค';
      case 'other':
        return 'อื่น ๆ';
      default:
        return value;
    }
  }

  void _queueSaveStableFields() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        await _saveStableFields();
      } catch (_) {}
    });
  }

  Future<void> _bootstrapClinicPrefill() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clinicId = widget.clinicId.trim();

      String readScoped(String field) {
        if (clinicId.isEmpty) return '';
        return (prefs.getString(_profileKey(clinicId, field)) ?? '').trim();
      }

      final clinicName =
          (widget.initialClinicName ?? '').trim().isNotEmpty
              ? widget.initialClinicName!.trim()
              : readScoped('name');

      final clinicBranchName =
          (widget.initialClinicBranchName ?? '').trim().isNotEmpty
              ? widget.initialClinicBranchName!.trim()
              : readScoped('branchName');

      final clinicAddress =
          (widget.initialClinicAddress ?? '').trim().isNotEmpty
              ? widget.initialClinicAddress!.trim()
              : readScoped('address');

      final clinicPhone =
          (widget.initialClinicPhone ?? '').trim().isNotEmpty
              ? widget.initialClinicPhone!.trim()
              : readScoped('phone');

      final clinicTaxId =
          (widget.initialClinicTaxId ?? '').trim().isNotEmpty
              ? widget.initialClinicTaxId!.trim()
              : readScoped('taxId');

      final logoUrl =
          (widget.initialLogoUrl ?? '').trim().isNotEmpty
              ? widget.initialLogoUrl!.trim()
              : readScoped('logoUrl');

      final withholderTaxId = readScoped('withholderTaxId');
      final paymentMethod = readScoped('paymentMethod');
      final bankName = readScoped('bankName');
      final accountName = readScoped('bankAccountName');
      final accountNumber = readScoped('bankAccountNumber');
      final paymentReference = readScoped('paymentReference');

      if (!mounted) return;

      setState(() {
        if (_clinicNameCtrl.text.trim().isEmpty && clinicName.isNotEmpty) {
          _clinicNameCtrl.text = clinicName;
        }
        if (_clinicBranchNameCtrl.text.trim().isEmpty &&
            clinicBranchName.isNotEmpty) {
          _clinicBranchNameCtrl.text = clinicBranchName;
        }
        if (_clinicAddressCtrl.text.trim().isEmpty && clinicAddress.isNotEmpty) {
          _clinicAddressCtrl.text = clinicAddress;
        }
        if (_clinicPhoneCtrl.text.trim().isEmpty && clinicPhone.isNotEmpty) {
          _clinicPhoneCtrl.text = clinicPhone;
        }
        if (_clinicTaxIdCtrl.text.trim().isEmpty && clinicTaxId.isNotEmpty) {
          _clinicTaxIdCtrl.text = clinicTaxId;
        }
        if (_logoUrlCtrl.text.trim().isEmpty && logoUrl.isNotEmpty) {
          _logoUrlCtrl.text = logoUrl;
        }
        if (_withholderTaxIdCtrl.text.trim().isEmpty &&
            withholderTaxId.isNotEmpty) {
          _withholderTaxIdCtrl.text = withholderTaxId;
        }

        if (_paymentMethods.contains(paymentMethod)) {
          _paymentMethod = paymentMethod;
        }
        if (_bankOptions.contains(bankName)) {
          _bankName = bankName;
        } else if (bankName.isNotEmpty) {
          _bankName = bankName;
        }

        if (_bankAccountNameCtrl.text.trim().isEmpty && accountName.isNotEmpty) {
          _bankAccountNameCtrl.text = accountName;
        }
        if (_bankAccountNumberCtrl.text.trim().isEmpty &&
            accountNumber.isNotEmpty) {
          _bankAccountNumberCtrl.text = accountNumber;
        }
        if (_paymentReferenceCtrl.text.trim().isEmpty &&
            paymentReference.isNotEmpty) {
          _paymentReferenceCtrl.text = paymentReference;
        }

        _prefillingClinic = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefillingClinic = false;
      });
    }
  }

  Future<void> _saveStableFields() async {
    final clinicId = widget.clinicId.trim();
    if (clinicId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _profileKey(clinicId, 'name'),
      _clinicNameCtrl.text.trim(),
    );
    await prefs.setString(
      _profileKey(clinicId, 'branchName'),
      _clinicBranchNameCtrl.text.trim(),
    );
    await prefs.setString(
      _profileKey(clinicId, 'address'),
      _clinicAddressCtrl.text.trim(),
    );
    await prefs.setString(
      _profileKey(clinicId, 'phone'),
      _clinicPhoneCtrl.text.trim(),
    );
    await prefs.setString(
      _profileKey(clinicId, 'taxId'),
      _clinicTaxIdCtrl.text.trim(),
    );
    await prefs.setString(
      _profileKey(clinicId, 'logoUrl'),
      _logoUrlCtrl.text.trim(),
    );
    await prefs.setString(
      _profileKey(clinicId, 'withholderTaxId'),
      _withholderTaxIdCtrl.text.trim(),
    );
    await prefs.setString(
      _profileKey(clinicId, 'paymentMethod'),
      _paymentMethod,
    );

    if (_isTransfer) {
      await prefs.setString(
        _profileKey(clinicId, 'bankName'),
        _bankName.trim(),
      );
      await prefs.setString(
        _profileKey(clinicId, 'bankAccountName'),
        _bankAccountNameCtrl.text.trim(),
      );
      await prefs.setString(
        _profileKey(clinicId, 'bankAccountNumber'),
        _bankAccountNumberCtrl.text.trim(),
      );
      await prefs.setString(
        _profileKey(clinicId, 'paymentReference'),
        _paymentReferenceCtrl.text.trim(),
      );
    } else if (_isCheque) {
      await prefs.setString(
        _profileKey(clinicId, 'paymentReference'),
        _paymentReferenceCtrl.text.trim(),
      );
    }
  }

  Future<void> _clearSavedPaymentFields() async {
    final clinicId = widget.clinicId.trim();
    if (clinicId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey(clinicId, 'paymentMethod'));
    await prefs.remove(_profileKey(clinicId, 'bankName'));
    await prefs.remove(_profileKey(clinicId, 'bankAccountName'));
    await prefs.remove(_profileKey(clinicId, 'bankAccountNumber'));
    await prefs.remove(_profileKey(clinicId, 'paymentReference'));

    if (!mounted) return;
    setState(() {
      _paymentMethod = 'transfer';
      _bankName = 'ธนาคารกสิกรไทย';
      _bankAccountNameCtrl.clear();
      _bankAccountNumberCtrl.clear();
      _paymentReferenceCtrl.clear();
    });
  }

  Future<void> _confirmClearSavedPaymentFields() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('ล้างข้อมูลการชำระเงินที่จำไว้'),
            content: const Text(
              'ระบบจะล้างวิธีชำระเงิน ธนาคาร ชื่อบัญชี เลขบัญชี และอ้างอิงที่เคยจำไว้ ต้องการดำเนินการหรือไม่',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ล้างข้อมูล'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _clearSavedPaymentFields();
    _showSnack('ล้างข้อมูลการชำระเงินที่จำไว้แล้ว');
  }

  void _handlePaymentMethodChanged(String value) {
    setState(() {
      _paymentMethod = value;

      if (_isTransfer) {
        return;
      }

      _bankAccountNameCtrl.clear();
      _bankAccountNumberCtrl.clear();

      if (!_isCheque) {
        _paymentReferenceCtrl.clear();
      }
    });

    _queueSaveStableFields();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  void _addItem() {
    setState(() {
      _items.add(_ReceiptItemForm());
    });
  }

  void _removeItem(int index) {
    if (_items.length <= 1) {
      _showSnack('ต้องมีอย่างน้อย 1 รายการ', isError: true);
      return;
    }

    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
    });
  }

  double _toDouble(String value, {double fallback = 0}) {
    final normalized = value.trim().replaceAll(',', '');
    final v = double.tryParse(normalized);
    return v ?? fallback;
  }

  String _money(double value) {
    return value.toStringAsFixed(2);
  }

  double _itemGrossAmount(_ReceiptItemForm item) {
    final quantity = _toDouble(item.quantityCtrl.text, fallback: 1);
    final unitPrice = _toDouble(item.unitPriceCtrl.text, fallback: 0);
    final amountInput = _toDouble(item.amountCtrl.text, fallback: -1);
    return amountInput >= 0 ? amountInput : quantity * unitPrice;
  }

  double _itemWithholdingAmount(_ReceiptItemForm item) {
    return _toDouble(item.withholdingTaxCtrl.text, fallback: 0);
  }

  double _itemNetAmount(_ReceiptItemForm item) {
    final net = _itemGrossAmount(item) - _itemWithholdingAmount(item);
    return net < 0 ? 0 : net;
  }

  List<Map<String, dynamic>> _buildItemsPayload() {
    return _items.map((item) {
      final quantity = _toDouble(item.quantityCtrl.text, fallback: 1);
      final unitPrice = _toDouble(item.unitPriceCtrl.text, fallback: 0);
      final amountInput = _toDouble(item.amountCtrl.text, fallback: -1);
      final withholdingTax = _itemWithholdingAmount(item);

      final amount = amountInput >= 0 ? amountInput : quantity * unitPrice;

      return <String, dynamic>{
        'description': item.descriptionCtrl.text.trim(),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'amount': amount,
        'withholdingTaxAmount': withholdingTax,
        'netAmount': amount - withholdingTax < 0 ? 0 : amount - withholdingTax,
      };
    }).toList();
  }

  double _calculateSubtotal() {
    double total = 0;
    for (final item in _items) {
      total += _itemGrossAmount(item);
    }
    return total;
  }

  double _calculateWithholdingTax() {
    double total = 0;
    for (final item in _items) {
      total += _itemWithholdingAmount(item);
    }
    return total;
  }

  double _calculateNetTotal() {
    final net = _calculateSubtotal() - _calculateWithholdingTax();
    return net < 0 ? 0 : net;
  }

  _ReceiptDraftData _buildDraft() {
    return _ReceiptDraftData(
      clinicId: widget.clinicId,
      customerName: _customerNameCtrl.text.trim(),
      customerAddress: _customerAddressCtrl.text.trim(),
      serviceMonth: _serviceMonthCtrl.text.trim(),
      servicePeriodText: _servicePeriodTextCtrl.text.trim(),
      clinicName: _clinicNameCtrl.text.trim(),
      clinicBranchName: _clinicBranchNameCtrl.text.trim(),
      clinicAddress: _clinicAddressCtrl.text.trim(),
      clinicPhone: _clinicPhoneCtrl.text.trim(),
      clinicTaxId: _clinicTaxIdCtrl.text.trim(),
      logoUrl: _logoUrlCtrl.text.trim(),
      withholderTaxId: _withholderTaxIdCtrl.text.trim(),
      paymentMethod: _paymentMethod,
      bankName: _bankName.trim(),
      bankAccountName: _bankAccountNameCtrl.text.trim(),
      bankAccountNumber: _bankAccountNumberCtrl.text.trim(),
      paymentReference: _paymentReferenceCtrl.text.trim(),
      items: _buildItemsPayload(),
      subtotal: _calculateSubtotal(),
      withholdingTaxAmount: _calculateWithholdingTax(),
      netTotal: _calculateNetTotal(),
    );
  }

  Future<void> _pickAndUploadLogo() async {
    if (_uploadingLogo || _removingLogo) return;

    final clinicId = widget.clinicId.trim();
    if (clinicId.isEmpty) {
      _showSnack('ไม่พบ clinicId', isError: true);
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );

      if (picked == null) return;

      setState(() {
        _uploadingLogo = true;
      });

      final result = await ClinicLogoApi.uploadLogo(
        clinicId: clinicId,
        file: File(picked.path),
      );

      final clinic = (result['clinic'] is Map<String, dynamic>)
          ? result['clinic'] as Map<String, dynamic>
          : <String, dynamic>{};

      final logoUrl = (clinic['logoUrl'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _logoUrlCtrl.text = logoUrl;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey(clinicId, 'logoUrl'), logoUrl);

      _showSnack('อัปโหลดโลโก้สำเร็จ');
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadingLogo = false;
      });
    }
  }

  Future<void> _removeLogo() async {
    if (_uploadingLogo || _removingLogo) return;

    final clinicId = widget.clinicId.trim();
    if (clinicId.isEmpty) {
      _showSnack('ไม่พบ clinicId', isError: true);
      return;
    }

    if (_logoUrlCtrl.text.trim().isEmpty) {
      _showSnack('ยังไม่มีโลโก้ให้ลบ', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('ลบโลโก้คลินิก'),
            content: const Text('ยืนยันการลบโลโก้ใช่หรือไม่'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ลบโลโก้'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      setState(() {
        _removingLogo = true;
      });

      await ClinicLogoApi.removeLogo(clinicId: clinicId);

      if (!mounted) return;
      setState(() {
        _logoUrlCtrl.clear();
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey(clinicId, 'logoUrl'), '');

      _showSnack('ลบโลโก้สำเร็จ');
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _removingLogo = false;
      });
    }
  }

  Future<void> _showBankPicker() async {
    FocusScope.of(context).unfocus();

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final banks = _bankPickerOptions;
        final current = _bankName.trim();

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'เลือกธนาคาร',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: banks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final bank = banks[index];
                      final isSelected = bank == current;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        title: Text(
                          bank,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle)
                            : null,
                        onTap: () => Navigator.of(context).pop(bank),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    setState(() {
      _bankName = selected.trim();
    });
    _queueSaveStableFields();
  }

  Future<void> _openPreview() async {
    if (_submitting) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final items = _buildItemsPayload();
    if (items.isEmpty) {
      _showSnack('กรุณาเพิ่มรายการอย่างน้อย 1 รายการ', isError: true);
      return;
    }

    final hasValidItem = items.any((e) {
      final description = (e['description'] ?? '').toString().trim();
      final quantity = (e['quantity'] as num?)?.toDouble() ?? 0;
      return description.isNotEmpty && quantity > 0;
    });

    if (!hasValidItem) {
      _showSnack('กรุณากรอกข้อมูลรายการให้ครบ', isError: true);
      return;
    }

    final subtotal = _calculateSubtotal();
    final withholdingTax = _calculateWithholdingTax();

    if (withholdingTax > subtotal) {
      _showSnack('ภาษีหัก ณ ที่จ่ายรวมต้องไม่มากกว่ายอดรวม', isError: true);
      return;
    }

    await _saveStableFields();

    final draft = _buildDraft();

    final shouldSubmit = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SocialSecurityReceiptPreviewScreen(draft: draft),
      ),
    );

    if (shouldSubmit == true) {
      await _submit();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final items = _buildItemsPayload();
    if (items.isEmpty) {
      _showSnack('กรุณาเพิ่มรายการอย่างน้อย 1 รายการ', isError: true);
      return;
    }

    final subtotal = _calculateSubtotal();
    final withholdingTax = _calculateWithholdingTax();

    if (withholdingTax > subtotal) {
      _showSnack('ภาษีหัก ณ ที่จ่ายรวมต้องไม่มากกว่ายอดรวม', isError: true);
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await _saveStableFields();

      final data = await ReceiptApi.createReceipt(
        clinicId: widget.clinicId,
        customerName: _customerNameCtrl.text.trim(),
        customerAddress: _customerAddressCtrl.text.trim(),
        serviceMonth: _serviceMonthCtrl.text.trim(),
        servicePeriodText: _servicePeriodTextCtrl.text.trim(),
        note: '',
        clinicName: _clinicNameCtrl.text.trim(),
        clinicBranchName: _clinicBranchNameCtrl.text.trim(),
        clinicAddress: _clinicAddressCtrl.text.trim(),
        clinicPhone: _clinicPhoneCtrl.text.trim(),
        clinicTaxId: _clinicTaxIdCtrl.text.trim(),
        logoUrl: _logoUrlCtrl.text.trim(),
        withholderTaxId: _withholderTaxIdCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        bankName: _isTransfer ? _bankName.trim() : '',
        accountName: _isTransfer ? _bankAccountNameCtrl.text.trim() : '',
        accountNumber: _isTransfer ? _bankAccountNumberCtrl.text.trim() : '',
        paymentReference:
            (_isTransfer || _isCheque) ? _paymentReferenceCtrl.text.trim() : '',
        clinicSnapshot: {
          'clinicName': _clinicNameCtrl.text.trim(),
          'clinicBranchName': _clinicBranchNameCtrl.text.trim(),
          'clinicAddress': _clinicAddressCtrl.text.trim(),
          'clinicPhone': _clinicPhoneCtrl.text.trim(),
          'clinicTaxId': _clinicTaxIdCtrl.text.trim(),
          'logoUrl': _logoUrlCtrl.text.trim(),
          'withholderTaxId': _withholderTaxIdCtrl.text.trim(),
        },
        customerSnapshot: {
          'customerName': _customerNameCtrl.text.trim(),
          'customerAddress': _customerAddressCtrl.text.trim(),
        },
        paymentInfo: {
          'method': _paymentMethod,
          'bankName': _isTransfer ? _bankName.trim() : '',
          'accountName': _isTransfer ? _bankAccountNameCtrl.text.trim() : '',
          'accountNumber': _isTransfer ? _bankAccountNumberCtrl.text.trim() : '',
          'transferRef': _isTransfer ? _paymentReferenceCtrl.text.trim() : '',
          'chequeNo': _isCheque ? _paymentReferenceCtrl.text.trim() : '',
        },
        items: items,
        withholdingTaxEnabled: withholdingTax > 0,
        withholdingTaxAmount: withholdingTax,
      );

      final receipt = Map<String, dynamic>.from(
        (data['receipt'] as Map?) ?? <String, dynamic>{},
      );

      final receiptId =
          (receipt['id'] ?? receipt['_id'] ?? '').toString().trim();
      if (receiptId.isEmpty) {
        throw Exception('สร้างใบเสร็จสำเร็จ แต่ไม่พบ receipt id');
      }

      _showSnack('สร้างใบเสร็จเรียบร้อยแล้ว');

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SocialSecurityReceiptDetailScreen(
            receiptId: receiptId,
            clinicId: widget.clinicId,
          ),
        ),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        onChanged: onChanged,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          alignLabelWithHint: maxLines > 1,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    final logoUrl = _logoUrlCtrl.text.trim();
    final clinicName = _clinicNameCtrl.text.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ClinicLogoView(
            logoUrl: logoUrl,
            clinicName: clinicName.isNotEmpty ? clinicName : 'คลินิก',
            size: 88,
          ),
          const SizedBox(height: 10),
          Text(
            logoUrl.isEmpty
                ? 'ยังไม่มีโลโก้ ระบบจะแสดง fallback อัตโนมัติ'
                : 'โลโก้นี้จะถูกใช้ใน preview และ PDF ใบเสร็จ',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_uploadingLogo || _removingLogo)
                      ? null
                      : _pickAndUploadLogo,
                  icon: _uploadingLogo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: Text(
                    _uploadingLogo ? 'กำลังอัปโหลด...' : 'อัปโหลดโลโก้',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      (_uploadingLogo || _removingLogo || logoUrl.isEmpty)
                          ? null
                          : _removeLogo,
                  icon: _removingLogo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _removingLogo ? 'กำลังลบ...' : 'ลบโลโก้',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBankSelector() {
    final value = _bankName.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _showBankPicker,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'ธนาคาร',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.isEmpty ? 'เลือกธนาคาร' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: value.isEmpty ? Colors.black45 : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'วิธีการชำระเงิน',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _submitting ? null : _confirmClearSavedPaymentFields,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('ล้างค่าที่จำไว้'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._paymentMethods.map((method) {
              return RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(_paymentMethodLabel(method)),
                value: method,
                groupValue: _paymentMethod,
                onChanged: (value) {
                  if (value == null) return;
                  _handlePaymentMethodChanged(value);
                },
              );
            }),
            if (_isTransfer) ...[
              const SizedBox(height: 8),
              _buildBankSelector(),
              _buildTextField(
                controller: _bankAccountNameCtrl,
                label: 'ชื่อบัญชี',
                hintText: 'เช่น คลินิกทันตกรรมน้องปลื้ม',
                onChanged: (_) => _queueSaveStableFields(),
              ),
              _buildTextField(
                controller: _bankAccountNumberCtrl,
                label: 'เลขบัญชี',
                hintText: 'เช่น 123-4-56789-0',
                keyboardType: TextInputType.number,
                onChanged: (_) => _queueSaveStableFields(),
              ),
              _buildTextField(
                controller: _paymentReferenceCtrl,
                label: 'อ้างอิง',
                hintText: 'เช่น เลขที่รายการ / หมายเลขอ้างอิง',
                onChanged: (_) => _queueSaveStableFields(),
              ),
            ],
            if (_isCheque) ...[
              const SizedBox(height: 8),
              _buildTextField(
                controller: _paymentReferenceCtrl,
                label: 'เลขที่เช็ค / อ้างอิง',
                hintText: 'เช่น CHQ-0001',
                onChanged: (_) => _queueSaveStableFields(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final gross = _itemGrossAmount(item);
    final withholding = _itemWithholdingAmount(item);
    final net = _itemNetAmount(item);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'รายการที่ ${index + 1}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeItem(index),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  tooltip: 'ลบรายการ',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTextField(
              controller: item.descriptionCtrl,
              label: 'รายละเอียด',
              hintText: 'เช่น เบิกสิทธิค่าทันตกรรมประกันสังคม',
              validator: (v) {
                if ((v ?? '').trim().isEmpty) {
                  return 'กรุณากรอกรายละเอียด';
                }
                return null;
              },
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: item.quantityCtrl,
                    label: 'จำนวน',
                    hintText: '1',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return 'ระบุจำนวน';
                      }
                      final n = double.tryParse(v!.trim().replaceAll(',', ''));
                      if (n == null || n <= 0) {
                        return 'จำนวนไม่ถูกต้อง';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: item.unitPriceCtrl,
                    label: 'ราคาต่อหน่วย',
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return 'ระบุราคา';
                      }
                      final n = double.tryParse(v!.trim().replaceAll(',', ''));
                      if (n == null || n < 0) {
                        return 'ราคาไม่ถูกต้อง';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            _buildTextField(
              controller: item.amountCtrl,
              label: 'จำนวนเงิน',
              hintText: 'ปล่อยว่างได้ ระบบจะคำนวณจาก จำนวน x ราคาต่อหน่วย',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final x = (v ?? '').trim();
                if (x.isEmpty) return null;
                final n = double.tryParse(x.replaceAll(',', ''));
                if (n == null || n < 0) {
                  return 'จำนวนเงินไม่ถูกต้อง';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            _buildTextField(
              controller: item.withholdingTaxCtrl,
              label: 'ภาษีหัก ณ ที่จ่าย (รายการนี้)',
              hintText: 'เช่น 300.00',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                final n = double.tryParse(text.replaceAll(',', ''));
                if (n == null || n < 0) {
                  return 'ยอดภาษีไม่ถูกต้อง';
                }
                if (n > gross) {
                  return 'ภาษีต้องไม่มากกว่ายอดรายการ';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ยอดรายการนี้: ${_money(gross)} บาท',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ภาษีหัก ณ ที่จ่าย: ${_money(withholding)} บาท',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ยอดสุทธิรายการนี้: ${_money(net)} บาท',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithholdingTaxSection() {
    final subtotal = _calculateSubtotal();
    final withholdingTax = _calculateWithholdingTax();
    final netTotal = _calculateNetTotal();

    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สรุปภาษีหัก ณ ที่จ่าย',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            _SummaryRow(
              label: 'รวมเป็นเงิน',
              value: '${_money(subtotal)} บาท',
            ),
            _SummaryRow(
              label: 'ภาษีหัก ณ ที่จ่ายรวม',
              value: '${_money(withholdingTax)} บาท',
            ),
            _SummaryRow(
              label: 'จำนวนเงินสุทธิ',
              value: '${_money(netTotal)} บาท',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _calculateSubtotal();
    final withholdingTax = _calculateWithholdingTax();
    final netTotal = _calculateNetTotal();

    return Scaffold(
      appBar: AppBar(
        title: const Text('สร้างใบเสร็จประกันสังคม'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มรายการ'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            Card(
              elevation: 1.2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ข้อมูลหลัก',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _customerNameCtrl,
                      label: 'ชื่อลูกค้า',
                      hintText: 'เช่น สำนักงานประกันสังคม',
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) {
                          return 'กรุณากรอกชื่อลูกค้า';
                        }
                        return null;
                      },
                    ),
                    _buildTextField(
                      controller: _customerAddressCtrl,
                      label: 'ที่อยู่ลูกค้า',
                      hintText: 'เช่น ที่อยู่หน่วยงานหรือผู้ชำระ',
                      maxLines: 2,
                    ),
                    _buildTextField(
                      controller: _serviceMonthCtrl,
                      label: 'งวดบริการ',
                      hintText: 'เช่น 2026-04',
                      validator: (v) {
                        final x = (v ?? '').trim();
                        if (x.isEmpty) {
                          return 'กรุณากรอกงวดบริการ';
                        }
                        final ok = RegExp(r'^\d{4}-\d{2}$').hasMatch(x);
                        if (!ok) {
                          return 'รูปแบบต้องเป็น YYYY-MM';
                        }
                        return null;
                      },
                    ),
                    _buildTextField(
                      controller: _servicePeriodTextCtrl,
                      label: 'ช่วงบริการ',
                      hintText: 'เช่น ประจำเดือนเมษายน 2026',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 1.2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'ข้อมูลคลินิกสำหรับ PDF',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (_prefillingClinic)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _clinicNameCtrl,
                      label: 'ชื่อคลินิก',
                      hintText: 'เช่น คลินิกของฉัน',
                      onChanged: (_) {
                        if (mounted) setState(() {});
                        _queueSaveStableFields();
                      },
                    ),
                    _buildTextField(
                      controller: _clinicBranchNameCtrl,
                      label: 'สาขา',
                      hintText: 'เช่น สาขาภูเก็ต',
                      onChanged: (_) => _queueSaveStableFields(),
                    ),
                    _buildTextField(
                      controller: _clinicAddressCtrl,
                      label: 'ที่อยู่คลินิก',
                      hintText: 'ถ้ามี',
                      maxLines: 2,
                      onChanged: (_) => _queueSaveStableFields(),
                    ),
                    _buildTextField(
                      controller: _clinicPhoneCtrl,
                      label: 'เบอร์โทรคลินิก',
                      hintText: 'ถ้ามี',
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => _queueSaveStableFields(),
                    ),
                    _buildTextField(
                      controller: _clinicTaxIdCtrl,
                      label: 'เลขผู้เสียภาษีคลินิก',
                      hintText: 'ถ้ามี',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _queueSaveStableFields(),
                    ),
                    _buildTextField(
                      controller: _withholderTaxIdCtrl,
                      label:
                          'เลขประจำตัวผู้เสียภาษีอากรของผู้มีหน้าที่หักภาษี ณ ที่จ่าย',
                      hintText: 'กรอกเลขผู้หักภาษี ณ ที่จ่าย',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _queueSaveStableFields(),
                    ),
                    _buildLogoSection(),
                    Text(
                      'ระบบจะเติมข้อมูลจาก clinic_profile_${widget.clinicId}_... ที่บันทึกจากหน้าตั้งค่าผู้ดูแลคลินิกโดยตรง',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'เมื่อสร้างใบเสร็จ ระบบจะบันทึก logoUrl ไว้ใน clinicSnapshot และ PDF จะใช้ค่านี้อัตโนมัติ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildPaymentMethodSection(),
            const SizedBox(height: 12),
            const Text(
              'รายการใบเสร็จ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...List.generate(_items.length, _buildItemCard),
            const SizedBox(height: 12),
            _buildWithholdingTaxSection(),
            const SizedBox(height: 12),
            Card(
              elevation: 1.2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'สรุป',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label: 'จำนวนรายการ',
                      value: '${_items.length}',
                    ),
                    _SummaryRow(
                      label: 'Subtotal',
                      value: '${_money(subtotal)} บาท',
                    ),
                    _SummaryRow(
                      label: 'ภาษีหัก ณ ที่จ่ายรวม',
                      value: '${_money(withholdingTax)} บาท',
                    ),
                    _SummaryRow(
                      label: 'ยอดสุทธิ',
                      value: '${_money(netTotal)} บาท',
                    ),
                    _SummaryRow(
                      label: 'วิธีชำระเงิน',
                      value: _paymentMethodLabel(_paymentMethod),
                    ),
                    if (_isTransfer)
                      _SummaryRow(
                        label: 'ธนาคาร',
                        value:
                            _bankName.trim().isEmpty ? '-' : _bankName.trim(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _openPreview,
                    icon: const Icon(Icons.preview),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label:
                        Text(_submitting ? 'กำลังบันทึก...' : 'บันทึกใบเสร็จ'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SocialSecurityReceiptPreviewScreen extends StatelessWidget {
  final _ReceiptDraftData draft;

  const SocialSecurityReceiptPreviewScreen({
    super.key,
    required this.draft,
  });

  String _money(num value) => value.toStringAsFixed(2);

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(title),
            ...children,
          ],
        ),
      ),
    );
  }

  String _safeText(String v, {String fallback = '-'}) {
    return v.trim().isEmpty ? fallback : v.trim();
  }

  String _paymentMethodLabel(String value) {
    switch (value) {
      case 'cash':
        return 'เงินสด';
      case 'transfer':
        return 'โอนเงิน';
      case 'cheque':
        return 'เช็ค';
      case 'other':
        return 'อื่น ๆ';
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = draft.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview ใบเสร็จ'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 1.2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ตรวจสอบข้อมูลก่อนบันทึก',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ถ้าข้อมูลยังไม่ถูกต้อง กดย้อนกลับเพื่อแก้ไขได้',
                    style: TextStyle(
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SummaryRow(
                    label: 'จำนวนรายการ',
                    value: '${items.length}',
                  ),
                  _SummaryRow(
                    label: 'Subtotal',
                    value: '${_money(draft.subtotal)} บาท',
                  ),
                  _SummaryRow(
                    label: 'ภาษีหัก ณ ที่จ่ายรวม',
                    value: '${_money(draft.withholdingTaxAmount)} บาท',
                  ),
                  _SummaryRow(
                    label: 'ยอดสุทธิ',
                    value: '${_money(draft.netTotal)} บาท',
                  ),
                ],
              ),
            ),
          ),
          _infoCard(
            title: 'ข้อมูลหลัก',
            children: [
              _PreviewRow(
                label: 'ชื่อลูกค้า',
                value: _safeText(draft.customerName),
              ),
              _PreviewRow(
                label: 'ที่อยู่ลูกค้า',
                value: _safeText(draft.customerAddress),
              ),
              _PreviewRow(
                label: 'งวดบริการ',
                value: _safeText(draft.serviceMonth),
              ),
              _PreviewRow(
                label: 'ช่วงบริการ',
                value: _safeText(draft.servicePeriodText),
              ),
            ],
          ),
          _infoCard(
            title: 'ข้อมูลคลินิกสำหรับ PDF',
            children: [
              _PreviewRow(
                label: 'ชื่อคลินิก',
                value: _safeText(draft.clinicName),
              ),
              _PreviewRow(
                label: 'สาขา',
                value: _safeText(draft.clinicBranchName),
              ),
              _PreviewRow(
                label: 'ที่อยู่',
                value: _safeText(draft.clinicAddress),
              ),
              _PreviewRow(
                label: 'โทร',
                value: _safeText(draft.clinicPhone),
              ),
              _PreviewRow(
                label: 'เลขผู้เสียภาษีคลินิก',
                value: _safeText(draft.clinicTaxId),
              ),
              _PreviewRow(
                label: 'เลขผู้หักภาษี',
                value: _safeText(draft.withholderTaxId),
              ),
              _PreviewRow(
                label: 'Logo URL',
                value: _safeText(draft.logoUrl),
              ),
            ],
          ),
          _infoCard(
            title: 'วิธีการชำระเงิน',
            children: [
              _PreviewRow(
                label: 'วิธีชำระเงิน',
                value: _paymentMethodLabel(draft.paymentMethod),
              ),
              if (draft.paymentMethod == 'transfer') ...[
                _PreviewRow(
                  label: 'ธนาคาร',
                  value: _safeText(draft.bankName),
                ),
                _PreviewRow(
                  label: 'ชื่อบัญชี',
                  value: _safeText(draft.bankAccountName),
                ),
                _PreviewRow(
                  label: 'เลขบัญชี',
                  value: _safeText(draft.bankAccountNumber),
                ),
                _PreviewRow(
                  label: 'อ้างอิง',
                  value: _safeText(draft.paymentReference),
                ),
              ],
              if (draft.paymentMethod == 'cheque')
                _PreviewRow(
                  label: 'เลขที่เช็ค / อ้างอิง',
                  value: _safeText(draft.paymentReference),
                ),
            ],
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 1.2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('รายการใบเสร็จ'),
                  if (items.isEmpty)
                    const Text('ไม่มีรายการ')
                  else
                    ...items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;

                      final description =
                          (item['description'] ?? '').toString().trim();
                      final quantity =
                          (item['quantity'] as num?)?.toDouble() ?? 0;
                      final unitPrice =
                          (item['unitPrice'] as num?)?.toDouble() ?? 0;
                      final amount =
                          (item['amount'] as num?)?.toDouble() ?? 0;
                      final withholdingTax =
                          (item['withholdingTaxAmount'] as num?)?.toDouble() ??
                              0;
                      final netAmount =
                          (item['netAmount'] as num?)?.toDouble() ?? 0;

                      return Container(
                        margin: EdgeInsets.only(
                          bottom: index == items.length - 1 ? 0 : 10,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              description.isEmpty
                                  ? 'รายการที่ ${index + 1}'
                                  : description,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PreviewRow(
                              label: 'จำนวน',
                              value: quantity.toStringAsFixed(2),
                            ),
                            _PreviewRow(
                              label: 'ราคาต่อหน่วย',
                              value: '${_money(unitPrice)} บาท',
                            ),
                            _PreviewRow(
                              label: 'จำนวนเงิน',
                              value: '${_money(amount)} บาท',
                            ),
                            _PreviewRow(
                              label: 'ภาษีหัก ณ ที่จ่าย',
                              value: '${_money(withholdingTax)} บาท',
                            ),
                            _PreviewRow(
                              label: 'สุทธิรายการนี้',
                              value: '${_money(netAmount)} บาท',
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.edit),
                label: const Text('กลับไปแก้ไข'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('ยืนยันและบันทึก'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptItemForm {
  final TextEditingController descriptionCtrl = TextEditingController();
  final TextEditingController quantityCtrl = TextEditingController(text: '1');
  final TextEditingController unitPriceCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController withholdingTaxCtrl = TextEditingController();

  void dispose() {
    descriptionCtrl.dispose();
    quantityCtrl.dispose();
    unitPriceCtrl.dispose();
    amountCtrl.dispose();
    withholdingTaxCtrl.dispose();
  }
}

class _ReceiptDraftData {
  final String clinicId;
  final String customerName;
  final String customerAddress;
  final String serviceMonth;
  final String servicePeriodText;

  final String clinicName;
  final String clinicBranchName;
  final String clinicAddress;
  final String clinicPhone;
  final String clinicTaxId;
  final String logoUrl;

  final String withholderTaxId;
  final String paymentMethod;
  final String bankName;
  final String bankAccountName;
  final String bankAccountNumber;
  final String paymentReference;

  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double withholdingTaxAmount;
  final double netTotal;

  const _ReceiptDraftData({
    required this.clinicId,
    required this.customerName,
    required this.customerAddress,
    required this.serviceMonth,
    required this.servicePeriodText,
    required this.clinicName,
    required this.clinicBranchName,
    required this.clinicAddress,
    required this.clinicPhone,
    required this.clinicTaxId,
    required this.logoUrl,
    required this.withholderTaxId,
    required this.paymentMethod,
    required this.bankName,
    required this.bankAccountName,
    required this.bankAccountNumber,
    required this.paymentReference,
    required this.items,
    required this.subtotal,
    required this.withholdingTaxAmount,
    required this.netTotal,
  });
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}