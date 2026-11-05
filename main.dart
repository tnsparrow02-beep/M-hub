import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const HubApp());

class HubApp extends StatelessWidget {
  const HubApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF0F7A5C),
          brightness: b,
        );
    return MaterialApp(
      title: 'Mon Hub',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class Link {
  Link(this.name, this.url, this.color);
  String name, url;
  int color;
  Map<String, dynamic> toJson() => {'n': name, 'u': url, 'c': color};
  factory Link.fromJson(Map<String, dynamic> j) => Link(j['n'], j['u'], j['c']);
}

Map<String, List<Link>> defaults() => {
      'accounts': [
        Link('Facebook', 'https://facebook.com', 0xFF1877F2),
        Link('Instagram', 'https://instagram.com', 0xFFD6336C),
        Link('WhatsApp', 'https://wa.me/', 0xFF1FA855),
        Link('TikTok', 'https://tiktok.com', 0xFF161616),
        Link('YouTube', 'https://youtube.com', 0xFFE02424),
        Link('Snapchat', 'https://snapchat.com', 0xFFD8A800),
        Link('Telegram', 'https://web.telegram.org', 0xFF2A9FD6),
      ],
      'apps': [
        Link('Coran', 'https://quran.com', 0xFF0F7A5C),
        Link('Prière', 'https://www.islamicfinder.org/prayer-times/', 0xFF5B4FC4),
        Link('Gmail', 'https://mail.google.com', 0xFFC5392E),
        Link('Maps', 'https://maps.google.com', 0xFF2F8F4E),
      ],
    };

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, List<Link>> data = defaults();
  List<AssetEntity> photos = [];
  bool denied = false;
  Map<String, String> prayers = {};
  String? ayah;
  int tasbih = 0;

  @override
  void initState() {
    super.initState();
    _loadLinks();
    _loadPhotos();
    _loadPrayers();
    _loadAyah();
    _loadTasbih();
  }

  Future<void> _loadLinks() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('hub');
    if (s == null) return;
    final m = jsonDecode(s) as Map<String, dynamic>;
    setState(() {
      data = {
        for (final k in ['accounts', 'apps'])
          k: [for (final e in (m[k] as List)) Link.fromJson(e)]
      };
    });
  }

  Future<void> _saveLinks() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'hub', jsonEncode(data.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))));
  }

  Future<void> _loadPhotos() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      setState(() => denied = true);
      return;
    }
    final paths = await PhotoManager.getAssetPathList(
        onlyAll: true, type: RequestType.image);
    if (paths.isEmpty) return;
    final list = await paths.first.getAssetListRange(start: 0, end: 60);
    setState(() {
      denied = false;
      photos = list;
    });
  }

  static const prayerNames = {
    'Fajr': 'Fajr',
    'Dhuhr': 'Dhohr',
    'Asr': 'Asr',
    'Maghrib': 'Maghrib',
    'Isha': 'Isha',
  };

  Future<void> _loadPrayers() async {
    try {
      final r = await http
          .get(Uri.parse('https://api.aladhan.com/v1/timingsByCity?city=Tunis&country=Tunisia&method=18'))
          .timeout(const Duration(seconds: 10));
      final t = jsonDecode(r.body)['data']['timings'] as Map;
      setState(() => prayers = {for (final k in prayerNames.keys) k: (t[k] as String).substring(0, 5)});
    } catch (_) {}
  }

  Future<void> _loadAyah() async {
    final d = DateTime.now();
    final n = 1 + ((d.year * 366 + d.difference(DateTime(d.year)).inDays) * 37) % 6236;
    try {
      final r = await http
          .get(Uri.parse('https://api.alquran.cloud/v1/ayah/$n/quran-uthmani'))
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(utf8.decode(r.bodyBytes))['data'];
      setState(() => ayah = '${j['text']}\n\n${j['surah']['name']} : ${j['numberInSurah']}');
    } catch (_) {}
  }

  Future<void> _loadTasbih() async {
    final p = await SharedPreferences.getInstance();
    setState(() => tasbih = p.getInt('tasbih') ?? 0);
  }

  Future<void> _bump(int v) async {
    setState(() => tasbih = v);
    final p = await SharedPreferences.getInstance();
    await p.setInt('tasbih', v);
  }

  Widget _card(ColorScheme cs, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      );

  Widget _prayerCard(ColorScheme cs) {
    if (prayers.isEmpty) return const SizedBox.shrink();
    final now = TimeOfDay.now();
    final nm = now.hour * 60 + now.minute;
    var next = 'Fajr';
    for (final e in prayers.entries) {
      final p = e.value.split(':');
      if (int.parse(p[0]) * 60 + int.parse(p[1]) > nm) {
        next = e.key;
        break;
      }
    }
    return _card(
      cs,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Prochaine prière : ${prayerNames[next]} à ${prayers[next]}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final e in prayers.entries)
              Column(children: [
                Text(prayerNames[e.key]!,
                    style: TextStyle(
                        fontSize: 12,
                        color: e.key == next ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: e.key == next ? FontWeight.w700 : FontWeight.w400)),
                const SizedBox(height: 4),
                Text(e.value,
                    style: TextStyle(
                        fontSize: 15,
                        color: e.key == next ? cs.primary : null,
                        fontWeight: e.key == next ? FontWeight.w700 : FontWeight.w400)),
              ]),
          ],
        ),
      ]),
    );
  }

  Widget _ayahCard(ColorScheme cs) {
    if (ayah == null) return const SizedBox.shrink();
    return _card(
      cs,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ayah du jour', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(ayah!, style: const TextStyle(fontSize: 20, height: 1.8)),
        ),
      ]),
    );
  }

  Widget _tasbihCard(ColorScheme cs) => _card(
        cs,
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tasbih', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('$tasbih', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(onPressed: () => _bump(0), icon: const Icon(Icons.refresh)),
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(84, 64), shape: const StadiumBorder()),
            onPressed: () => _bump(tasbih + 1),
            child: const Icon(Icons.add, size: 30),
          ),
        ]),
      );

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir ce lien')));
    }
  }

  Future<void> _add(String key) async {
    final n = TextEditingController(), u = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ajouter un lien'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Nom')),
          TextField(
              controller: u,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Adresse (https://...)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok != true || n.text.trim().isEmpty || u.text.trim().isEmpty) return;
    var url = u.text.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    const pal = [0xFF0F7A5C, 0xFF5B4FC4, 0xFFC5392E, 0xFF2A7FBA, 0xFFB5651D, 0xFF8E3B8E];
    setState(() => data[key]!.add(Link(n.text.trim(), url, pal[DateTime.now().millisecond % pal.length])));
    _saveLinks();
  }

  Future<void> _delete(String key, Link l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Supprimer ${l.name} ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => data[key]!.remove(l));
      _saveLinks();
    }
  }

  Widget _tile(String key, Link l) => GestureDetector(
        onTap: () => _open(l.url),
        onLongPress: () => _delete(key, l),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Color(l.color), borderRadius: BorderRadius.circular(20)),
            child: Text(l.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]),
      );

  Widget _addTile(String key) => GestureDetector(
        onTap: () => _add(key),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 2),
            ),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 6),
          const Text('Ajouter', style: TextStyle(fontSize: 12)),
        ]),
      );

  Widget _section(String title, String key) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [for (final l in data[key]!) _tile(key, l), _addTile(key)],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = DateTime.now().hour;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPhotos,
          child: ListView(padding: const EdgeInsets.all(18), children: [
            Text(h < 5 || h >= 18 ? 'Bonsoir' : 'Bonjour',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            Material(
              color: cs.primary,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _open('https://quran.com'),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Text('قرآن', style: TextStyle(fontSize: 34, color: cs.onPrimary)),
                    const SizedBox(width: 14),
                    Text('Lire le Coran',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onPrimary)),
                  ]),
                ),
              ),
            ),
            _prayerCard(cs),
            _ayahCard(cs),
            _tasbihCard(cs),
            _section('Mes comptes', 'accounts'),
            _section('Mes applications favorites', 'apps'),
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: Text('Mes photos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (denied)
              Card(
                child: ListTile(
                  title: const Text('Accès aux photos refusé'),
                  subtitle: const Text('Autoriser dans les réglages du téléphone'),
                  trailing: TextButton(onPressed: PhotoManager.openSetting, child: const Text('Réglages')),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                itemCount: photos.length,
                itemBuilder: (c, i) => GestureDetector(
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Viewer(photos[i]))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AssetEntityImage(photos[i],
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(300),
                        fit: BoxFit.cover),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Center(
              child: Text('Appui long sur une icône pour la supprimer',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

class Viewer extends StatelessWidget {
  const Viewer(this.asset, {super.key});
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(
            child: AssetEntityImage(asset, isOriginal: true, fit: BoxFit.contain),
          ),
        ),
      );
}
