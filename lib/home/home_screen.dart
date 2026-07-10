import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../baby/baby_screen.dart';
import '../monitor/monitor_screen.dart';
import '../server/babylink_server.dart';
import '../setup/screens/scan_screen.dart';
import '../setup/setup_session.dart';
import '../store/app_store.dart';
import '../theme.dart';
import '../widgets/hero_badge.dart';
import '../widgets/primary_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedRoom>? _rooms;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rooms = await AppStore.instance.loadRooms();
    if (mounted) setState(() => _rooms = rooms);
  }

  /// Create a room (name only — the server makes the id), like the web. Adding
  /// a device is a separate step from the room's card.
  Future<void> _createRoom() async {
    final controller = TextEditingController(text: 'Nursery');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a room'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Room name', hintText: 'Nursery'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      const server = BabyLinkServer();
      final room = await server.createRoom(name);
      await AppStore.instance.addRoom(SavedRoom(
        roomId: room.roomId,
        ownerToken: room.ownerToken,
        name: name,
        ssid: '', // no device yet
        serverHost: server.host,
        serverPort: server.port,
        createdAt: DateTime.now(),
      ));
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Couldn’t create the room. Check your connection.')));
      }
    }
  }

  /// Provision a BabyLink device into an existing room (the BLE wizard).
  Future<void> _addDevice(SavedRoom r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScanScreen(session: SetupSession(targetRoom: r)),
    ));
    _load();
  }

  /// Add a room you already have (paste a link or 32-char room id). Lets a
  /// second phone join to listen without running setup.
  Future<void> _addByLink() async {
    final controller = TextEditingController();
    final nameController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Room link or ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final match = RegExp(r'[0-9a-fA-F]{32}').firstMatch(controller.text);
    if (match == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('That doesn’t look like a BabyLink room link')));
      }
      return;
    }
    await AppStore.instance.addRoom(SavedRoom(
      roomId: match.group(0)!.toLowerCase(),
      ownerToken: null,
      name: nameController.text.trim().isEmpty ? 'BabyLink' : nameController.text.trim(),
      ssid: '',
      serverHost: 'babylink.itvoodoo.at',
      serverPort: 443,
      createdAt: DateTime.now(),
    ));
    _load();
  }

  void _share(SavedRoom r) {
    SharePlus.instance.share(ShareParams(
      text: 'Join ${r.name} on BabyLink 👶\nOpen this link and choose Parent (to listen) or Baby (to add a camera/mic):\n${r.roomLink}',
      subject: 'BabyLink — ${r.name}',
    ));
  }

  Future<void> _copy(SavedRoom r) async {
    await Clipboard.setData(ClipboardData(text: r.roomLink));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
    }
  }

  void _listen(SavedRoom r) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MonitorScreen(room: r)));
  }

  /// Use THIS phone as a baby unit — stream its mic into the room.
  void _useAsBaby(SavedRoom r) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BabyScreen(room: r)));
  }

  Future<void> _open(SavedRoom r) async {
    final uri = Uri.parse(r.roomLink);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the link')));
      }
    }
  }

  Future<void> _delete(SavedRoom r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${r.name}?'),
        content: const Text('This removes it from this phone. The room keeps running for anyone who already has the link.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await AppStore.instance.deleteRoom(r.roomId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BabyLink'),
        titleTextStyle: Theme.of(context).textTheme.headlineSmall,
        actions: [
          IconButton(
            onPressed: _addByLink,
            icon: const Icon(Icons.add_link_rounded),
            tooltip: 'Add a room by link',
          ),
        ],
      ),
      floatingActionButton: (rooms != null && rooms.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _createRoom,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create room'),
            )
          : null,
      body: rooms == null
          ? const Center(child: CircularProgressIndicator())
          : rooms.isEmpty
              ? _empty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 96),
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => Gap.hMd,
                    itemBuilder: (_, i) => _RoomCard(
                      room: rooms[i],
                      onListen: () => _listen(rooms[i]),
                      onShare: () => _share(rooms[i]),
                      onCopy: () => _copy(rooms[i]),
                      onOpen: () => _open(rooms[i]),
                      onAddDevice: () => _addDevice(rooms[i]),
                      onUseAsBaby: () => _useAsBaby(rooms[i]),
                      onDelete: () => _delete(rooms[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _empty(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HeroBadge(emoji: '👶', size: 140),
          Gap.hXl,
          Text('No rooms yet', textAlign: TextAlign.center, style: t.headlineMedium),
          Gap.hSm,
          Text('Create a room, then add your BabyLink device to it.',
              textAlign: TextAlign.center, style: t.bodyLarge),
          Gap.hXl,
          PrimaryButton('Create a room', icon: Icons.add_rounded, onPressed: _createRoom),
          Gap.hSm,
          TextButton(onPressed: _addByLink, child: const Text('I already have a room link')),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final SavedRoom room;
  final VoidCallback onListen, onShare, onCopy, onOpen, onAddDevice, onUseAsBaby, onDelete;
  const _RoomCard({
    required this.room,
    required this.onListen,
    required this.onShare,
    required this.onCopy,
    required this.onOpen,
    required this.onAddDevice,
    required this.onUseAsBaby,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    // A room we provisioned via BLE records its WiFi. A room we own (created it,
    // so we hold the token) but haven't provisioned yet expects a device next —
    // make "Add a device" its primary action. A room added by link (no token,
    // someone else's) is there to listen to.
    final hasDevice = room.ssid.isNotEmpty;
    final needsDevice = !hasDevice && room.ownerToken != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.sm)),
                  child: const Center(child: Text('👶', style: TextStyle(fontSize: 22))),
                ),
                Gap.wMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.name, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(hasDevice ? 'on ${room.ssid}' : (needsDevice ? 'No device yet' : 'Shared room'),
                          style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (v) => switch (v) {
                    'add' => onAddDevice(),
                    'baby' => onUseAsBaby(),
                    _ => onDelete(),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('Add a device')),
                    PopupMenuItem(value: 'baby', child: Text('Use this phone as a baby')),
                    PopupMenuItem(value: 'remove', child: Text('Remove room')),
                  ],
                ),
              ],
            ),
            Gap.hMd,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: Radii.rMd,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: t.labelMedium!.color),
                  Gap.wSm,
                  Expanded(
                    child: Text(room.roomLink,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                  ),
                ],
              ),
            ),
            Gap.hMd,
            needsDevice
                ? FilledButton.icon(
                    onPressed: onAddDevice,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a device'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  )
                : FilledButton.icon(
                    onPressed: onListen,
                    icon: const Icon(Icons.hearing_rounded),
                    label: const Text('Listen'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
            Gap.hMd,
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    label: const Text('Share'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ),
                Gap.wSm,
                _iconAction(context, Icons.copy_rounded, 'Copy', onCopy),
                Gap.wSm,
                _iconAction(context, Icons.open_in_new_rounded, 'Open', onOpen),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(BuildContext context, IconData icon, String tip, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            side: BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: Radii.rMd),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
