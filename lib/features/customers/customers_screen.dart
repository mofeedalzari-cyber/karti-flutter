// نفس تصميم src/routes/app.customers.tsx — عرض المندوب: قائمة زبائنه مع
// الرصيد، وتفاصيل كل زبون (مبيعات + دفعات)، تسجيل دفعة، شحن يدوي، حذف.
// عرض المدير منفصل بـ admin_customers_screen.dart (network_customers RPC).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/format.dart';
import '../auth/profile_provider.dart';
import '../pdf/customer_invoice_pdf.dart' as inv;
import 'customers_providers.dart';
import 'admin_customers_screen.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final isAdmin = profileAsync.value?.role == Role.admin;
    return isAdmin ? const AdminCustomersScreen() : const _MyCustomersView();
  }
}

class _MyCustomersView extends ConsumerStatefulWidget {
  const _MyCustomersView();

  @override
  ConsumerState<_MyCustomersView> createState() => _MyCustomersViewState();
}

class _MyCustomersViewState extends ConsumerState<_MyCustomersView> {
  String _search = '';

  Future<void> _openAddCustomer() async {
    final nameCtrl = TextEditingController();
    final waCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('زبون جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 10),
          TextField(controller: waCtrl, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رقم واتساب')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final networkId = ref.read(profileProvider).value?.networkId;
      await createMyCustomer(name: nameCtrl.text, whatsapp: waCtrl.text, networkId: networkId);
      ref.invalidate(myCustomersListProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إضافة الزبون')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(myCustomersListProvider);
    final salesAsync = ref.watch(myCustomerSalesProvider);
    final paymentsAsync = ref.watch(myCustomerPaymentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الزبائن'),
        actions: [IconButton(icon: const Icon(Icons.person_add_outlined), onPressed: _openAddCustomer)],
      ),
      body: customersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
        data: (customers) {
          final sales = salesAsync.value ?? [];
          final payments = paymentsAsync.value ?? [];
          final q = _search.trim().toLowerCase();
          final filtered = q.isEmpty ? customers : customers.where((c) => c.name.toLowerCase().contains(q) || c.whatsapp.contains(q)).toList();
          final withBalance = filtered.map((c) => (c, computeBalance(c.id, sales, payments))).toList()
            ..sort((a, b) => b.$2.balance.compareTo(a.$2.balance));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(labelText: 'بحث بالاسم أو واتساب', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              Expanded(
                child: withBalance.isEmpty
                    ? const Center(child: Text('لا يوجد زبائن'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: withBalance.length,
                        itemBuilder: (context, i) {
                          final (c, bal) = withBalance[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(c.whatsapp, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
                              trailing: Text(fmtMoney(bal.balance), style: TextStyle(fontWeight: FontWeight.w800, color: bal.balance > 0 ? Colors.orange : Colors.green)),
                              onTap: () => _openDetail(context, c, bal, sales, payments),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, MyCustomer c, CustomerBalance bal, List<CustomerSale> allSales, List<CustomerPayment> allPayments) {
    final sales = allSales.where((s) => s.customerId == c.id).toList();
    final payments = allPayments.where((p) => p.customerId == c.id).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CustomerDetailSheet(customer: c, balance: bal, sales: sales, payments: payments),
    ).then((_) {
      ref.invalidate(myCustomerPaymentsProvider);
      ref.invalidate(myCustomersListProvider);
    });
  }
}

class _CustomerDetailSheet extends ConsumerStatefulWidget {
  final MyCustomer customer;
  final CustomerBalance balance;
  final List<CustomerSale> sales;
  final List<CustomerPayment> payments;
  const _CustomerDetailSheet({required this.customer, required this.balance, required this.sales, required this.payments});

  @override
  ConsumerState<_CustomerDetailSheet> createState() => _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends ConsumerState<_CustomerDetailSheet> {
  Future<void> _recordPayment() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل دفعة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسديد')),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = num.tryParse(amountCtrl.text) ?? 0;
    if (amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً')));
      return;
    }
    try {
      await recordCustomerPayment(customerId: widget.customer.id, amount: amount, note: noteCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تسديد ${fmtMoney(amount)}')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addCharge() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مبلغ (شحن يدوي)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = num.tryParse(amountCtrl.text) ?? 0;
    if (amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً')));
      return;
    }
    try {
      await addManualCharge(customerId: widget.customer.id, amount: amount, note: noteCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إضافة ${fmtMoney(amount)}')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _printInvoice() async {
    final profile = ref.read(profileProvider).value;
    try {
      await inv.printCustomerInvoicePdf(inv.CustomerInvoiceInput(
        networkName: profile?.fullName ?? 'الشبكة',
        adminName: profile?.fullName ?? profile?.username ?? 'المدير',
        customerName: widget.customer.name,
        items: widget.sales
            .map((s) => inv.InvoiceItem(packageName: s.packageName, networkName: s.networkName, cardNumber: s.cardUsername, qty: 1, price: s.price, dateStr: s.soldAt))
            .toList(),
        ledger: widget.payments.map((p) => inv.LedgerEntry(amount: p.amount, note: p.note, dateStr: p.createdAt)).toList(),
        currency: 'ر.س',
        dateStr: DateTime.now().toString().split(' ').first,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الفاتورة: $e')));
    }
  }

  Future<void> _deleteCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الزبون'),
        content: Text('حذف حساب "${widget.customer.name}"؟ المبيعات السابقة تبقى كما هي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deleteMyCustomer(widget.customer.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف حساب الزبون مع بقاء المبيعات كما هي')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            Row(children: [
              Expanded(child: Text(widget.customer.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _deleteCustomer),
            ]),
            Text(widget.customer.whatsapp, textDirection: TextDirection.ltr, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _MiniBalance(label: 'الإجمالي', value: widget.balance.total),
                  _MiniBalance(label: 'المدفوع', value: widget.balance.paid, color: Colors.green),
                  _MiniBalance(label: 'المتبقي', value: widget.balance.balance, color: Colors.orange),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: _recordPayment, icon: const Icon(Icons.payments_outlined, size: 16), label: const Text('تسديد دفعة'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _addCharge, icon: const Icon(Icons.add_card_outlined, size: 16), label: const Text('إضافة مبلغ'))),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _printInvoice, icon: const Icon(Icons.receipt_long_outlined, size: 16), label: const Text('طباعة فاتورة')),
            const SizedBox(height: 20),
            Text('المبيعات (${widget.sales.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...widget.sales.map((s) => ListTile(
                  dense: true,
                  title: Text(s.packageName, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('#${s.transactionNo}', style: const TextStyle(fontSize: 10)),
                  trailing: Text(fmtMoney(s.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                )),
            const SizedBox(height: 20),
            Text('الدفعات (${widget.payments.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...widget.payments.map((p) => ListTile(
                  dense: true,
                  title: Text(p.amount < 0 ? 'شحن يدوي' : 'دفعة', style: const TextStyle(fontSize: 13)),
                  subtitle: p.note != null ? Text(p.note!, style: const TextStyle(fontSize: 10)) : null,
                  trailing: Text(fmtMoney(p.amount.abs()), style: TextStyle(fontWeight: FontWeight.w700, color: p.amount < 0 ? Colors.orange : Colors.green)),
                  onLongPress: () async {
                    await deleteCustomerPayment(p.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

class _MiniBalance extends StatelessWidget {
  final String label;
  final num value;
  final Color? color;
  const _MiniBalance({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(fmtMoney(value), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color), textDirection: TextDirection.ltr),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
    ]);
  }
}
