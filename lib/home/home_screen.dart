import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/room_admin.dart';
import '../admin/room_admin_screen.dart';
import '../baby/baby_screen.dart';
import '../l10n/app_localizations.dart';
import '../monitor/monitor_screen.dart';
import '../server/babylink_server.dart';
import '../settings/settings_screen.dart';
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
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: 'Nursery');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.createARoom),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.roomName, hintText: l10n.roomNameHint),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(l10n.create)),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final server = await AppStore.instance.currentServer();
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
            .showSnackBar(SnackBar(content: Text(l10n.createRoomFailed)));
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
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final nameController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addARoom),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.roomLinkOrId),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: l10n.nameOptional),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.add)),
        ],
      ),
    );
    if (ok != true) return;
    final text = controller.text.trim();
    final match = RegExp(r'[0-9a-fA-F]{32}').firstMatch(text);
    if (match == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.invalidRoomLink)));
      }
      return;
    }
    // A pasted link may point at a self-hosted server — honour its host. A bare
    // id joins on the app's current server.
    BabyLinkServer server;
    if (text.contains('://') || (text.contains('/') && text.contains('.'))) {
      try {
        server = BabyLinkServer.parse(text);
      } catch (_) {
        server = await AppStore.instance.currentServer();
      }
    } else {
      server = await AppStore.instance.currentServer();
    }
    await AppStore.instance.addRoom(SavedRoom(
      roomId: match.group(0)!.toLowerCase(),
      ownerToken: null,
      name: nameController.text.trim().isEmpty ? 'BabyLink' : nameController.text.trim(),
      ssid: '',
      serverHost: server.host,
      serverPort: server.port,
      createdAt: DateTime.now(),
    ));
    _load();
  }

  void _share(SavedRoom r) {
    final l10n = AppLocalizations.of(context);
    SharePlus.instance.share(ShareParams(
      text: l10n.shareRoomText(r.roomLink, r.name),
      subject: l10n.shareRoomSubject(r.name),
    ));
  }

  Future<void> _copy(SavedRoom r) async {
    await Clipboard.setData(ClipboardData(text: r.roomLink));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).linkCopied)));
    }
  }

  Future<void> _listen(SavedRoom r) async {
    if (!await _pinGate(r)) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MonitorScreen(room: r)));
  }

  /// Use THIS phone as a baby unit — stream its mic into the room.
  Future<void> _useAsBaby(SavedRoom r) async {
    if (!await _pinGate(r)) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BabyScreen(room: r)));
  }

  void _manage(SavedRoom r) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RoomAdminScreen(room: r)))
        .then((_) => _load());
  }

  /// Gate entry to a PIN-protected room. The owner (holds the token) skips it;
  /// someone who joined by link must enter the PIN. Returns true to proceed.
  Future<bool> _pinGate(SavedRoom r) async {
    if (r.ownerToken != null) return true;
    final admin = RoomAdmin(r);
    bool hasPin;
    try {
      hasPin = await admin.hasPin();
    } catch (_) {
      return true; // can't reach the server to check — don't hard-block
    }
    if (!hasPin) return true;
    while (mounted) {
      final pin = await _promptPin();
      if (pin == null) return false; // cancelled
      final res = await admin.verifyPin(pin);
      if (res == PinVerify.ok) return true;
      if (!mounted) return false;
      final l10n = AppLocalizations.of(context);
      final msg = res == PinVerify.locked
          ? l10n.pinTooManyAttempts
          : l10n.pinMismatch;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (res == PinVerify.locked) return false;
    }
    return false;
  }

  Future<String?> _promptPin() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.enterRoomPin),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.pin),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(l10n.unlock)),
        ],
      ),
    );
  }

  Future<void> _open(SavedRoom r) async {
    final uri = Uri.parse(r.roomLink);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).couldNotOpenLink)));
      }
    }
  }

  Future<void> _delete(SavedRoom r) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeRoomTitle(r.name)),
        content: Text(l10n.removeRoomBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.remove)),
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
    final l10n = AppLocalizations.of(context);
    final rooms = _rooms;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BabyLink'),
        titleTextStyle: Theme.of(context).textTheme.headlineSmall,
        actions: [
          IconButton(
            onPressed: _addByLink,
            icon: const Icon(Icons.add_link_rounded),
            tooltip: l10n.addRoomByLink,
          ),
          IconButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
                .then((_) => _load()),
            icon: const Icon(Icons.settings_rounded),
            tooltip: l10n.settings,
          ),
        ],
      ),
      floatingActionButton: (rooms != null && rooms.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _createRoom,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.createRoom),
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
                      onManage: () => _manage(rooms[i]),
                      onDelete: () => _delete(rooms[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _empty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HeroBadge(emoji: '👶', size: 140),
          Gap.hXl,
          Text(l10n.noRoomsYet, textAlign: TextAlign.center, style: t.headlineMedium),
          Gap.hSm,
          Text(l10n.noRoomsBody, textAlign: TextAlign.center, style: t.bodyLarge),
          Gap.hXl,
          PrimaryButton(l10n.createARoom, icon: Icons.add_rounded, onPressed: _createRoom),
          Gap.hSm,
          TextButton(onPressed: _addByLink, child: Text(l10n.haveRoomLink)),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final SavedRoom room;
  final VoidCallback onListen, onShare, onCopy, onOpen, onAddDevice, onUseAsBaby, onManage, onDelete;
  const _RoomCard({
    required this.room,
    required this.onListen,
    required this.onShare,
    required this.onCopy,
    required this.onOpen,
    required this.onAddDevice,
    required this.onUseAsBaby,
    required this.onManage,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                      color: cs.secondary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.sm)),
                  child: const Center(child: Text('👶', style: TextStyle(fontSize: 22))),
                ),
                Gap.wMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.name, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(hasDevice ? l10n.onSsid(room.ssid) : (needsDevice ? l10n.noDeviceYet : l10n.sharedRoom),
                          style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (v) => switch (v) {
                    'add' => onAddDevice(),
                    'baby' => onUseAsBaby(),
                    'manage' => onManage(),
                    _ => onDelete(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'add', child: Text(l10n.addADevice)),
                    PopupMenuItem(value: 'baby', child: Text(l10n.useThisPhoneAsBaby)),
                    // Only the owner (holds the token) can manage the room.
                    if (room.ownerToken != null)
                      PopupMenuItem(value: 'manage', child: Text(l10n.manageRoom)),
                    PopupMenuItem(value: 'remove', child: Text(l10n.removeRoom)),
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
                    label: Text(l10n.addADevice),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  )
                : FilledButton.icon(
                    onPressed: onListen,
                    icon: const Icon(Icons.hearing_rounded),
                    label: Text(l10n.listen),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
            Gap.hMd,
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    label: Text(l10n.share),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ),
                Gap.wSm,
                _iconAction(context, Icons.copy_rounded, l10n.copy, onCopy),
                Gap.wSm,
                _iconAction(context, Icons.open_in_new_rounded, l10n.openLink, onOpen),
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
