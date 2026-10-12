import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../application/session_controller.dart';
import '../domain/models.dart';
import 'add_variants_screen.dart';
import 'create_item_screen.dart';
import 'edit_photos_screen.dart';
import 'mono_theme.dart';
import 'auth_screens.dart';
import 'payment_screen.dart';
import 'receipt_preview.dart';
import 'receipt_settings_screen.dart';
import 'return_screen.dart';
import 'stock_screen.dart';
import 'sync_screen.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  int _page = 0;
  String _search = '';
  String? _category, _openingError;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref.read(posProvider.notifier).refresh();
      } catch (_) {
        if (mounted) {
          setState(
            () => _openingError = 'Chargement impossible. Rouvrez l’application sans la désinstaller.',
          );
        }
      }
    });
  }

  bool get _admin => ref.read(currentActorProvider)?.role == Role.admin;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posProvider);
    final me = ref.watch(currentActorProvider);
    ref.listen(posProvider.select((s) => s.message), (_, message) {
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 5),
            ),
          );
      }
    });
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MonoColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'UM',
                style: TextStyle(
                  color: MonoColors.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UNIVERS DU MONO',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'CAISSE',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.3,
                      color: MonoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (me?.role == Role.admin)
            PopupMenuButton<String>(
              tooltip: 'Administration',
              enabled: !state.busy,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onSelected: (choice) => switch (choice) {
                'users' => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UsersScreen()),
                ),
                'stock' => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockScreen()),
                ),
                'receipt' => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReceiptSettingsScreen(),
                  ),
                ),
                _ => _syncSettings(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'users',
                  child: ListTile(
                    leading: Icon(Icons.group_outlined),
                    title: Text('Utilisateurs'),
                  ),
                ),
                PopupMenuItem(
                  value: 'stock',
                  child: ListTile(
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('Stock'),
                  ),
                ),
                PopupMenuItem(
                  value: 'receipt',
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_outlined),
                    title: Text('Ticket et boutique'),
                  ),
                ),
                PopupMenuItem(
                  value: 'sync',
                  child: ListTile(
                    leading: Icon(Icons.tune_rounded),
                    title: Text('Synchronisation'),
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Verrouiller (${me?.name ?? ''})',
            onPressed: state.busy
                ? null
                : ref.read(sessionProvider.notifier).lock,
            icon: const Icon(Icons.lock_outline),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _recetteInfo,
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.science_outlined, size: 16),
                      label: Text(
                        'Recette · ${me?.name ?? ''} · ${ref.read(printerProvider).label}',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Synchroniser maintenant',
                    onPressed: state.busy
                        ? null
                        : ref.read(posProvider.notifier).synchronize,
                    icon: Badge(
                      isLabelVisible: state.pending > 0,
                      label: Text('${state.pending}'),
                      child: const Icon(Icons.sync, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${state.pending} en attente · Dernière synchro : ${state.lastSync == null ? 'jamais' : abidjanDate(state.lastSync!)}',
                  style: const TextStyle(fontSize: 10, color: MonoColors.muted),
                ),
              ),
            ),
            if (state.busy) const LinearProgressIndicator(minHeight: 2),
            if (_openingError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: InlineNotice(_openingError!, error: true),
              ),
            Expanded(
              child: switch (_page) {
                0 => _catalog(state),
                1 => _cart(state),
                _ => _history(state),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Articles',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: state.cart.isNotEmpty,
              label: Text('${state.cartQuantity}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            label: 'Panier',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Historique',
          ),
        ],
      ),
    );
  }

  Widget _catalog(PosState state) {
    final query = _search.trim().toLowerCase();
    final items = state.items
        .where(
          (i) =>
              (_category == null || i.category == _category) &&
              '${i.name} ${i.sku} ${i.label} ${i.category}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final categories = state.items.map((i) => i.category).toSet().toList()
      ..sort();
    // One card per article; its sizes are chosen afterwards.
    final grouped = <String, List<CatalogItem>>{};
    for (final item in items) {
      grouped
          .putIfAbsent(
            item.productId.isEmpty ? item.id : item.productId,
            () => [],
          )
          .add(item);
    }
    final products = grouped.values.toList();
    return CustomScrollView(
      key: const PageStorageKey('catalog'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Le catalogue',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${state.items.length} variante(s) à retrouver ici',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_admin)
                      IconButton.filled(
                        tooltip: 'Créer un article',
                        onPressed: state.busy ? null : _createItem,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(50, 50),
                          backgroundColor: MonoColors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Article, référence, taille…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('Tout'),
                            selected: _category == null,
                            onSelected: (_) => setState(() => _category = null),
                          ),
                        ),
                        for (final category in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: _category == category,
                              onSelected: (_) =>
                                  setState(() => _category = category),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _empty(
                Icons.storefront_outlined,
                state.items.isEmpty
                    ? 'Votre boutique prend vie ici'
                    : 'Aucun résultat',
                state.items.isEmpty
                    ? 'Ajoutez votre premier article, ses photos et son stock. Tout restera accessible hors ligne.'
                    : 'Essayez une autre référence ou une autre catégorie.',
                action: state.items.isEmpty && _admin
                    ? FilledButton.icon(
                        onPressed: state.busy ? null : _createItem,
                        icon: const Icon(Icons.add),
                        label: const Text('Créer mon premier article'),
                      )
                    : null,
              ),
            ),
          ),
        if (items.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverLayoutBuilder(
              builder: (_, constraints) {
                final columns = constraints.crossAxisExtent < 280
                    ? 1
                    : constraints.crossAxisExtent < 600
                    ? 2
                    : 3;
                final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
                return SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => _productCard(products[index], state),
                    childCount: products.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 308 + (scaled > 1 ? (scaled - 1) * 180 : 0),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _productCard(List<CatalogItem> variants, PosState state) {
    final item = variants.first;
    final prices = variants.map((v) => v.price).toList()..sort();
    final stock = variants.fold(0, (sum, v) => sum + v.stock);
    final single = variants.length == 1;
    final colorCount = {for (final v in variants) v.color}.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _details(variants),
            child: SizedBox(
              height: 124,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductPhoto(path: item.photoPaths.firstOrNull, radius: 0),
                  if (item.photoPaths.isNotEmpty)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: MonoColors.ink.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${item.photoPaths.length} photo(s)',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.8,
                      color: MonoColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    single
                        ? item.label
                        : colorCount > 1
                        ? '$colorCount couleurs · ${variants.length} variantes'
                        : '${variants.length} tailles',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: MonoColors.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    prices.first == prices.last
                        ? fcfa(prices.first)
                        : 'Dès ${fcfa(prices.first)}',
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: MonoColors.green,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stock == 0
                              ? 'Épuisé'
                              : variants.any((v) => v.lowStock)
                              ? 'Stock faible : $stock'
                              : 'Stock : $stock',
                          style: TextStyle(
                            fontSize: 10,
                            color: stock == 0 || variants.any((v) => v.lowStock)
                                ? Colors.red.shade800
                                : MonoColors.muted,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: single
                            ? 'Ajouter ${item.name} au panier'
                            : 'Choisir la taille de ${item.name}',
                        onPressed: state.busy || stock == 0
                            ? null
                            : single
                            ? () => ref
                                  .read(posProvider.notifier)
                                  .quantity(item.id, 1)
                            : () => _details(variants),
                        color: MonoColors.green,
                        icon: const Icon(Icons.add_circle, size: 28),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cart(PosState state) {
    if (state.cart.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: _empty(
          Icons.shopping_bag_outlined,
          'Prêt pour la prochaine vente',
          'Retrouvez vos articles dans le catalogue et ajoutez-les au panier.',
          action: FilledButton(
            onPressed: () => setState(() => _page = 0),
            child: const Text('Parcourir les articles'),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SectionLabel(
              'Votre panier',
              subtitle: '${state.cartQuantity} article(s) sélectionné(s)',
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: state.cart.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final entry = state.cart.entries.elementAt(index);
              final item = state.items.firstWhere((i) => i.id == entry.key);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ProductPhoto(
                            path: item.photoPaths.firstOrNull,
                            size: 64,
                            radius: 12,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  item.label,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  fcfa(item.price),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: MonoColors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Quantité',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Diminuer',
                            onPressed: state.busy
                                ? null
                                : () => ref
                                      .read(posProvider.notifier)
                                      .quantity(item.id, -1),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${entry.value}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Augmenter',
                            onPressed: state.busy
                                ? null
                                : () => ref
                                      .read(posProvider.notifier)
                                      .quantity(item.id, 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: MonoColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      fcfa(state.total),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.busy ? null : _payment,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Passer au paiement'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _history(PosState state) => state.sales.isEmpty
      ? Padding(
          padding: const EdgeInsets.all(20),
          child: _empty(
            Icons.receipt_long_outlined,
            'Chaque vente, une trace',
            'Vos ventes et leurs duplicatas apparaîtront ici après le premier encaissement.',
          ),
        )
      : ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SectionLabel(
              'Vos dernières ventes',
              subtitle: 'Les 100 dernières · Heure d’Abidjan',
            ),
            for (final sale in state.sales)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          color: MonoColors.green,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fcfa(sale['total'] as int),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                abidjanDate(sale['occurred_at'] as String),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                sale['number'] as String,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: MonoColors.muted,
                                ),
                              ),
                              if (sale['correction'] != null)
                                const Text(
                                  'Paiement corrigé',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: MonoColors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (sale['returns'] case final Map returns)
                                Text(
                                  returns['complete'] == true
                                      ? (returns['cancelled'] == true
                                            ? 'Annulée · ${fcfa(returns['refunded'] as int)} remboursés'
                                            : 'Entièrement retournée · ${fcfa(returns['refunded'] as int)} remboursés')
                                      : 'Retour partiel · ${fcfa(returns['refunded'] as int)} remboursés',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // One menu keeps the row within the H10's 360 dp.
                        if (_admin)
                          PopupMenuButton<String>(
                            tooltip: 'Actions sur la vente',
                            enabled: !state.busy,
                            icon: const Icon(
                              Icons.more_vert,
                              color: MonoColors.muted,
                            ),
                            onSelected: (action) async {
                              if (action == 'correct') {
                                return _correctPayment(sale);
                              }
                              final done = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReturnScreen(sale),
                                ),
                              );
                              if (done == true && mounted) _receipt();
                            },
                            itemBuilder: (_) => [
                              if ((sale['returns'] as Map?)?['complete'] !=
                                  true)
                                const PopupMenuItem(
                                  value: 'return',
                                  child: Text('Retour ou annulation'),
                                ),
                              const PopupMenuItem(
                                value: 'correct',
                                child: Text('Corriger le paiement'),
                              ),
                            ],
                          ),
                        IconButton(
                          tooltip: 'Aperçu du duplicata',
                          onPressed: state.busy
                              ? null
                              : () async {
                                  await ref
                                      .read(posProvider.notifier)
                                      .duplicate(sale);
                                  if (mounted) _receipt();
                                },
                          icon: const Icon(
                            Icons.print_outlined,
                            color: MonoColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );

  Future<void> _correctPayment(Map<String, dynamic> sale) async {
    final current = (sale['correction'] ?? sale) as Map<String, dynamic>;
    var mode = PaymentMode.values.byName(current['payment_mode'] as String);
    final tendered = TextEditingController(
      text: current['tendered']?.toString() ?? '',
    );
    final reason = TextEditingController();
    final total = sale['total'] as int;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          final preview = previewCash(total, tendered.text);
          return AlertDialog(
            title: Text('Corriger ${sale['number']}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total inchangé : ${fcfa(total)}'),
                  const SizedBox(height: 4),
                  const Text(
                    'Seuls le mode et la somme remise sont corrigés. La vente reste dans l’historique.',
                    style: TextStyle(fontSize: 12, color: MonoColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in PaymentMode.values)
                        ChoiceChip(
                          label: Text(m.label),
                          selected: m == mode,
                          onSelected: (_) => setDialog(() => mode = m),
                        ),
                    ],
                  ),
                  if (mode == PaymentMode.cash) ...[
                    TextField(
                      controller: tendered,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setDialog(() {}),
                      decoration: InputDecoration(
                        labelText: 'Somme réellement remise FCFA',
                        helperText: preview == null
                            ? null
                            : 'Monnaie : ${fcfa(preview.change)}',
                      ),
                    ),
                  ],
                  TextField(
                    controller: reason,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Motif (obligatoire)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await ref
                      .read(posProvider.notifier)
                      .correctPayment(
                        sale['id'] as String,
                        mode,
                        tendered.text,
                        reason.text,
                      );
                  if (ok && context.mounted) Navigator.pop(context);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    // Let the dialog finish closing before releasing its fields.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    tendered.dispose();
    reason.dispose();
  }

  Widget _empty(
    IconData icon,
    String title,
    String subtitle, {
    Widget? action,
  }) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: MonoColors.pale,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 42, color: MonoColors.green),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MonoColors.muted, height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: 24), action],
        ],
      ),
    ),
  );

  void _details(List<CatalogItem> variants) {
    final item = variants.first;
    final colors = {
      for (final v in variants)
        if (v.color != null) v.color!,
    }.toList();
    String? chosen = colors.isEmpty ? null : colors.first;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                SizedBox(
                  height: 260,
                  child: item.photoPaths.isEmpty
                      ? const ProductPhoto()
                      : PageView(
                          children: [
                            for (final path in item.photoPaths)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: ProductPhoto(path: path),
                              ),
                          ],
                        ),
                ),
                if (item.photoPaths.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${item.photoPaths.length} photos · Faites glisser pour les voir',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  item.category.toUpperCase(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                if (_admin)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _editPrices(variants);
                        },
                        icon: const Icon(Icons.sell_outlined, size: 18),
                        label: const Text('Modifier le prix'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            this.context,
                            MaterialPageRoute(
                              builder: (_) => EditPhotosScreen(item),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: const Text('Modifier les photos'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            this.context,
                            MaterialPageRoute(
                              builder: (_) => AddVariantsScreen(variants),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Couleurs / tailles'),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                const SectionLabel('Choisir la variante'),
                if (colors.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final color in colors)
                          ChoiceChip(
                            label: Text(color),
                            selected: chosen == color,
                            onSelected: (_) => setSheet(() => chosen = color),
                          ),
                      ],
                    ),
                  ),
                for (final v in variants)
                  if (colors.length <= 1 || v.color == chosen)
                    Card(
                      child: ListTile(
                        title: Text(v.label),
                        subtitle: Text(
                          '${v.sku} · ${v.stock == 0 ? 'Épuisé' : 'Stock : ${v.stock}'}',
                        ),
                        trailing: Text(
                          fcfa(v.price),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: MonoColors.green,
                          ),
                        ),
                        enabled: v.stock > 0,
                        onTap: () {
                          ref.read(posProvider.notifier).quantity(v.id, 1);
                          Navigator.pop(context);
                        },
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Administrator: one price per size, or the same price for all sizes.
  Future<void> _editPrices(List<CatalogItem> variants) async {
    final fields = {
      for (final v in variants) v.id: TextEditingController(text: '${v.price}'),
    };
    final all = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prix · ${variants.first.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'S’applique aux prochaines ventes. Les ventes passées et leurs duplicatas gardent leur prix.',
                style: TextStyle(fontSize: 12, color: MonoColors.muted),
              ),
              if (variants.length > 1) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: all,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Même prix pour toutes',
                          isDense: true,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        for (final c in fields.values) {
                          c.text = all.text.trim();
                        }
                      },
                      child: const Text('Appliquer'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              for (final v in variants)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: fields[v.id],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '${v.label} (FCFA)',
                      isDense: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref.read(posProvider.notifier).changePrices({
                for (final e in fields.entries) e.key: e.value.text,
              });
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    // Let the dialog finish closing before releasing its fields.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (final c in [...fields.values, all]) {
      c.dispose();
    }
  }

  Future<void> _createItem() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateItemScreen()),
    );
  }

  Future<void> _payment() async {
    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaymentScreen()),
    );
    if (success == true && mounted) {
      setState(() => _page = 2);
      _receipt();
    }
  }

  void _receipt() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Aperçu du ticket'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ref.read(printerProvider).label,
              style: const TextStyle(fontSize: 12, color: MonoColors.muted),
            ),
            const SizedBox(height: 8),
            if (ref.read(posProvider).receipt case final receipt?)
              ReceiptPreview(receipt),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
  void _recetteInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Version de recette'),
      content: const Text(
        'Les ventes sont enregistrées localement. L’imprimante intégrée est pilotée par le service SRPrinter du H10 ; le service n’indique pas si le papier est sorti : vérifiez le ticket et utilisez le duplicata au besoin.\n\nL’authentification de production n’est pas encore activée. Cette version sert aux essais.',
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            await ref.read(posProvider.notifier).printTest();
            if (mounted) _receipt();
          },
          icon: const Icon(Icons.print_outlined),
          label: const Text('Ticket test'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Compris'),
        ),
      ],
    ),
  );

  Future<void> _syncSettings() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SyncScreen()),
  );
}
