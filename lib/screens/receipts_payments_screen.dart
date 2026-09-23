import 'package:flutter/material.dart';
import '../models.dart';
import '../storage.dart';
import '../date_utils.dart';

class ReceiptsPaymentsScreen extends StatefulWidget {
  const ReceiptsPaymentsScreen({super.key});
  @override
  State<ReceiptsPaymentsScreen> createState() => _ReceiptsPaymentsScreenState();
}

class _ReceiptsPaymentsScreenState extends State<ReceiptsPaymentsScreen> with SingleTickerProviderStateMixin {
  final _storage = AppStorage();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<FinancialTransaction> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final x = await _storage.loadFinancialTransactions(); x.sort((a,b)=>b.createdAtMs.compareTo(a.createdAtMs)); if(mounted)setState(()=>_items=x..sort((a,b)=>b.createdAtMs.compareTo(a.createdAtMs))); }

  Future<void> _newTransaction(String kind) async {
    final accounts = await _storage.loadAccounts();
    final result = await showDialog<bool>(context: context, builder: (_) => _TransactionDialog(kind: kind, accounts: accounts, storage: _storage));
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final receipts = _items.where((e)=>e.kind=='receipt').toList();
    final payments = _items.where((e)=>e.kind=='payment').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('دریافت و پرداخت'),
        actions: [
          FilledButton.icon(onPressed: ()=>_newTransaction('receipt'), icon: const Icon(Icons.download_rounded), label: const Text('دریافت جدید')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: ()=>_newTransaction('payment'), icon: const Icon(Icons.upload_rounded), label: const Text('پرداخت جدید')),
          const SizedBox(width: 12),
        ],
        bottom: TabBar(controller: _tabs, tabs: [Tab(text:'دریافت‌ها (${toPersianDigits(receipts.length.toString())})'), Tab(text:'پرداخت‌ها (${toPersianDigits(payments.length.toString())})')]),
      ),
      body: TabBarView(controller: _tabs, children: [_list(receipts), _list(payments)]),
    );
  }

  Widget _list(List<FinancialTransaction> items) {
    if(items.isEmpty) return const Center(child: Text('هنوز رکوردی ثبت نشده است.'));
    return ListView.builder(padding: const EdgeInsets.all(18), itemCount: items.length, itemBuilder: (_,i){
      final x=items[i];
      return Card(child: ListTile(
        leading: CircleAvatar(child: Icon(x.kind=='receipt'?Icons.download_rounded:Icons.upload_rounded)),
        title: Text('${x.title} — ${toPersianDigits(_money(x.amount))} ریال', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${x.date} • ${x.settlement=='cash'?'نقدی':'نسیه'}\n${x.description}'),
        isThreeLine: true,
        trailing: Text('سند ${toPersianDigits(x.voucherId.isEmpty?'—':x.voucherId.substring(0, x.voucherId.length>8?8:x.voucherId.length))}'),
      ));
    });
  }
  String _money(int n)=>n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_)=>',');
}

class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({required this.kind, required this.accounts, required this.storage});
  final String kind; final List<AccountNode> accounts; final AppStorage storage;
  @override State<_TransactionDialog> createState()=>_TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  final _amount=TextEditingController(); final _title=TextEditingController(); final _desc=TextEditingController();
  String _date=todayJalali(); String _settlement='cash'; String _category='other'; AccountNode? _counter; AccountNode? _cashBank;

  List<AccountNode> get tafsili=>widget.accounts.where((a)=>a.level==AccountLevel.tafsili).toList()..sort((a,b)=>a.code.compareTo(b.code));
  List<AccountNode> get cashBank=>tafsili.where((a)=>a.parentId=='m_cash_bank').toList();
  List<AccountNode> get paymentCounter=>tafsili.where((a)=>a.group==AccountGroup.expense || a.id=='t_inventory_goods').toList();
  List<AccountNode> get receiptCounter=>tafsili.where((a)=>a.group==AccountGroup.revenue || a.id=='t_customers').toList();
  List<AccountNode> get counterOptions=>widget.kind=='payment'?paymentCounter:receiptCounter;

  @override void initState(){super.initState(); if(cashBank.isNotEmpty)_cashBank=cashBank.first; if(counterOptions.isNotEmpty)_counter=counterOptions.first; _applyCategory(_category);}
  void _applyCategory(String value){ _category=value; final id = widget.kind=='payment' ? {'salary':'t_salary','rent':'t_rent','purchase':'t_inventory_goods','other':'t_misc_expense'}[value] : {'customer':'t_customers','sales':'t_sales_goods','other':'t_other_revenue'}[value]; if(id!=null){ final found=_find(id); if(found!=null)_counter=found; } }
  @override void dispose(){_amount.dispose();_title.dispose();_desc.dispose();super.dispose();}

  int get amount=>int.tryParse(_amount.text.replaceAll(',','').trim())??0;
  AccountNode? _find(String id)=>widget.accounts.where((a)=>a.id==id).isEmpty?null:widget.accounts.firstWhere((a)=>a.id==id);

  Future<void> _save() async {
    if(amount<=0 || _counter==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('مبلغ و حساب مقابل را کامل کنید.')));return;}
    if(_cashBank==null && _settlement=='cash'){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('حساب صندوق یا بانک را انتخاب کنید.')));return;}
    final vouchers=await widget.storage.loadVouchers();
    final id=DateTime.now().microsecondsSinceEpoch.toString();
    final date=_date.trim();
    final sourceCash=_settlement=='cash'?_cashBank:null;
    late final List<VoucherLine> lines;
    late final VoucherType vtype;
    if(widget.kind=='payment'){
      vtype=VoucherType.payment;
      final creditAccount=sourceCash ?? _find('t_suppliers');
      if(creditAccount==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('حساب پرداختنی پیش‌فرض پیدا نشد.')));return;}
      lines=[VoucherLine(id:'${id}a',accountId:_counter!.id,description:_title.text.trim(),debit:amount), VoucherLine(id:'${id}b',accountId:creditAccount.id,description:_title.text.trim(),credit:amount)];
    } else {
      vtype=VoucherType.receipt;
      final destination=_cashBank;
      if(destination==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('حساب دریافت وجه را انتخاب کنید.')));return;}
      lines=[VoucherLine(id:'${id}a',accountId:destination.id,description:_title.text.trim(),debit:amount), VoucherLine(id:'${id}b',accountId:_counter!.id,description:_title.text.trim(),credit:amount)];
    }
    final voucher=Voucher(id:id,number:0,date:date,description:_desc.text.trim().isEmpty?_title.text.trim():_desc.text.trim(),reference:'${widget.kind}-${id.substring(id.length-6)}',type:vtype,status:VoucherStatus.permanent,lines:lines);
    vouchers.add(voucher); await widget.storage.saveVouchers(renumberVouchersByDate(vouchers));
    final tx=FinancialTransaction(id:id,date:date,kind:widget.kind,title:_title.text.trim().isEmpty?(widget.kind=='payment'?'پرداخت':'دریافت'):_title.text.trim(),description:_desc.text.trim(),amount:amount,settlement:_settlement,sourceAccountId:widget.kind=='payment'?(sourceCash?.id??''):(destinationId()),counterAccountId:_counter!.id,voucherId:id);
    final txs=await widget.storage.loadFinancialTransactions(); txs.add(tx); await widget.storage.saveFinancialTransactions(txs);
    if(mounted) Navigator.pop(context,true);
  }
  String destinationId()=>_cashBank?.id??'';

  @override Widget build(BuildContext context){
    final isPayment=widget.kind=='payment';
    return AlertDialog(
      title: Text(isPayment?'ثبت پرداخت و ایجاد سند خودکار':'ثبت دریافت و ایجاد سند خودکار'),
      content: SizedBox(width:620, child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,children:[
        Row(children:[Expanded(child:TextField(controller:_title,decoration:InputDecoration(labelText:isPayment?'عنوان پرداخت':'عنوان دریافت'))),const SizedBox(width:10),Expanded(child:TextField(readOnly:true,decoration:InputDecoration(labelText:'تاریخ سند',hintText:_date)))]),
        const SizedBox(height:10),
        TextField(controller:_amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مبلغ (ریال)',prefixIcon:Icon(Icons.payments_outlined))),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:_category,decoration:const InputDecoration(labelText:'نوع عملیات'),items:(widget.kind=='payment'?const [DropdownMenuItem(value:'salary',child:Text('حقوق و دستمزد')),DropdownMenuItem(value:'rent',child:Text('اجاره')),DropdownMenuItem(value:'purchase',child:Text('خرید کالا')),DropdownMenuItem(value:'other',child:Text('هزینه متفرقه'))]:const [DropdownMenuItem(value:'customer',child:Text('دریافت از مشتری')),DropdownMenuItem(value:'sales',child:Text('دریافت بابت فروش')),DropdownMenuItem(value:'other',child:Text('سایر درآمدها'))]),onChanged:(v)=>setState(()=>_applyCategory(v!))),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:_settlement,decoration:const InputDecoration(labelText:'نوع تسویه'),items:const [DropdownMenuItem(value:'cash',child:Text('نقدی / بانک')),DropdownMenuItem(value:'credit',child:Text('نسیه / حساب پرداختنی'))],onChanged:(v)=>setState(()=>_settlement=v!)),
        const SizedBox(height:10),
        DropdownButtonFormField<AccountNode>(value:_counter,decoration:InputDecoration(labelText:isPayment?'هزینه / حساب مقابل':'حساب مقابل دریافت'),items:counterOptions.map((a)=>DropdownMenuItem(value:a,child:Text('${a.code} — ${a.name}'))).toList(),onChanged:(v)=>setState(()=>_counter=v)),
        const SizedBox(height:10),
        DropdownButtonFormField<AccountNode>(value:_cashBank,decoration:InputDecoration(labelText:isPayment?'صندوق / بانک پرداخت':'صندوق / بانک دریافت'),items:cashBank.map((a)=>DropdownMenuItem(value:a,child:Text('${a.code} — ${a.name}'))).toList(),onChanged:(v)=>setState(()=>_cashBank=v)),
        const SizedBox(height:10),
        TextField(controller:_desc,maxLines:2,decoration:const InputDecoration(labelText:'شرح')),
        const SizedBox(height:14),
        Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.grey.shade100,borderRadius:BorderRadius.circular(10)),child:Text(isPayment?'سند خودکار: ${_counter?.name??'—'} بدهکار ← ${_settlement=='cash'?(_cashBank?.name??'صندوق/بانک'):'حساب‌های پرداختنی'} بستانکار':'سند خودکار: ${_cashBank?.name??'صندوق/بانک'} بدهکار ← ${_counter?.name??'حساب مقابل'} بستانکار')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ثبت و ایجاد سند'))],
    );
  }
}
