import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';

typedef Json = Map<String, dynamic>;

const ink = Color(0xFF302332);
const coral = Color(0xFFEE7775);
const cream = Color(0xFFFCF8F3);
const muted = Color(0xFF796E78);
const line = Color(0xFFEDE5E5);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.instance.init();
  runApp(const KindredApp());
}

List<Json> jsonList(dynamic value) => (value as List<dynamic>? ?? [])
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

void snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class KindredApp extends StatefulWidget {
  const KindredApp({super.key});
  @override
  State<KindredApp> createState() => _KindredAppState();
}

class _KindredAppState extends State<KindredApp> {
  Json? user;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final result = await Api.instance.me();
      if (mounted) setState(() => user = result['user'] as Json);
    } catch (_) {
      // A missing session opens the sign-in screen.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kindred',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: coral,
          primary: ink,
          surface: cream,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontFamily: 'serif',
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'serif',
            fontSize: 31,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          bodyMedium: TextStyle(fontSize: 15, color: ink, height: 1.45),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: coral, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
      home: loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : user == null
          ? AuthPage(onSignedIn: (value) => setState(() => user = value))
          : HomePage(
              user: user!,
              onUserChanged: (value) => setState(() => user = value),
              onSignedOut: () => setState(() => user = null),
            ),
    );
  }
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.dark = false});
  final bool dark;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: coral,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.favorite_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
      const SizedBox(width: 9),
      Text(
        'kindred',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: 25,
          fontWeight: FontWeight.w700,
          color: dark ? Colors.white : ink,
        ),
      ),
    ],
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.onSignedIn});
  final ValueChanged<Json> onSignedIn;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final city = TextEditingController(text: 'Bengaluru');
  final bio = TextEditingController();
  final prompt = TextEditingController();
  final serverAddress = TextEditingController(text: Api.instance.baseUrl);
  DateTime? birthday;
  String gender = 'woman';
  String lookingFor = 'everyone';
  String intent = 'Long-term relationship';
  bool joining = false;
  bool accepted = false;
  bool busy = false;

  @override
  void dispose() {
    for (final controller in [
      email,
      password,
      name,
      city,
      bio,
      prompt,
      serverAddress,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    if (joining && birthday == null) {
      return snack(context, 'Choose your date of birth.');
    }
    if (joining && !accepted) {
      return snack(
        context,
        'Please accept the community rules and privacy notice.',
      );
    }
    setState(() => busy = true);
    try {
      final result = joining
          ? await Api.instance.signup({
              'email': email.text,
              'password': password.text,
              'name': name.text,
              'city': city.text,
              'birthDate': birthday!.toIso8601String().substring(0, 10),
              'gender': gender,
              'lookingFor': lookingFor,
              'intent': intent,
              'bio': bio.text,
              'prompt': prompt.text,
              'interests': <String>[],
              'acceptTerms': accepted,
            })
          : await Api.instance.login(email.text, password.text);
      widget.onSignedIn(result['user'] as Json);
    } catch (error) {
      if (mounted) snack(context, error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 800;
            return Row(
              children: [
                if (wide)
                  Expanded(
                    child: Container(
                      height: double.infinity,
                      padding: const EdgeInsets.all(58),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4A2C4D), Color(0xFF282032)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Brand(dark: true),
                          const Spacer(),
                          Text(
                            'Make room for\nsomething real.',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(color: Colors.white, fontSize: 58),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Thoughtful connections start with being yourself.',
                            style: TextStyle(
                              color: Color(0xFFE7DCE6),
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'A calmer way to meet.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 72 : 28,
                      vertical: 30,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!wide) ...[
                            const Brand(),
                            const SizedBox(height: 34),
                          ],
                          Text(
                            joining ? 'Create your space.' : 'Welcome back.',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            joining
                                ? 'Be yourself. Meet someone who gets you.'
                                : 'Good to see you again.',
                            style: const TextStyle(color: muted, fontSize: 16),
                          ),
                          const SizedBox(height: 28),
                          Form(
                            key: formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (joining) ...[
                                  TextFormField(
                                    controller: name,
                                    decoration: const InputDecoration(
                                      labelText: 'First name',
                                    ),
                                    validator: (v) =>
                                        (v ?? '').trim().length < 2
                                        ? 'Enter your first name'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: city,
                                    decoration: const InputDecoration(
                                      labelText: 'City',
                                    ),
                                    validator: (v) =>
                                        (v ?? '').trim().length < 2
                                        ? 'Enter your city'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        firstDate: DateTime(1926),
                                        lastDate: DateTime.now(),
                                        initialDate: DateTime(1998),
                                      );
                                      if (date != null) {
                                        setState(() => birthday = date);
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                    ),
                                    label: Text(
                                      birthday == null
                                          ? 'Date of birth · 18+ only'
                                          : '${birthday!.day}/${birthday!.month}/${birthday!.year}',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _drop('I identify as', gender, const {
                                    'woman': 'Woman',
                                    'man': 'Man',
                                    'nonbinary': 'Nonbinary',
                                  }, (v) => setState(() => gender = v)),
                                  const SizedBox(height: 12),
                                  _drop('I want to meet', lookingFor, const {
                                    'everyone': 'Everyone',
                                    'woman': 'Women',
                                    'man': 'Men',
                                    'nonbinary': 'Nonbinary people',
                                  }, (v) => setState(() => lookingFor = v)),
                                  const SizedBox(height: 12),
                                  _drop('I’m here for', intent, const {
                                    'Long-term relationship':
                                        'Long-term relationship',
                                    'Open to possibilities':
                                        'Open to possibilities',
                                    'Getting to know people':
                                        'Getting to know people',
                                  }, (v) => setState(() => intent = v)),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: bio,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'A little about you (optional)',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                TextFormField(
                                  controller: email,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                  ),
                                  validator: (v) => (v ?? '').contains('@')
                                      ? null
                                      : 'Enter a valid email',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: password,
                                  obscureText: true,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    helperText: joining
                                        ? 'At least 10 characters'
                                        : null,
                                  ),
                                  validator: (v) =>
                                      (v ?? '').length < (joining ? 10 : 1)
                                      ? 'Enter your password'
                                      : null,
                                ),
                                if (joining) ...[
                                  const SizedBox(height: 12),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: accepted,
                                    onChanged: (v) =>
                                        setState(() => accepted = v ?? false),
                                    title: const Text(
                                      'I am 18+ and agree to the community rules and privacy notice.',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => showPolicy(context),
                                    child: const Text(
                                      'Read the rules and privacy notice',
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: busy ? null : submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: ink,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 17,
                                    ),
                                  ),
                                  child: Text(
                                    busy
                                        ? 'Please wait…'
                                        : joining
                                        ? 'Create account'
                                        : 'Sign in',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() => joining = !joining),
                              child: Text(
                                joining
                                    ? 'Already have an account? Sign in'
                                    : 'New here? Create an account',
                              ),
                            ),
                          ),
                          if (!joining && !Api.instance.isCloud)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEEE9),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Explore the demo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Sample profiles are labelled. No real people are shown.',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () {
                                      email.text = 'demo@example.com';
                                      password.text = 'DemoPass123!';
                                      submit();
                                    },
                                    child: const Text('Enter demo account →'),
                                  ),
                                ],
                              ),
                            ),
                          if (!Api.instance.isCloud) const SizedBox(height: 16),
                          if (!Api.instance.isCloud)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                'Development server address',
                                style: TextStyle(fontSize: 14),
                              ),
                              subtitle: const Text(
                                'Change this when using a physical phone.',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                              children: [
                                TextField(
                                  controller: serverAddress,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'Server URL',
                                    hintText: 'http://192.168.1.10:3000',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () async {
                                      try {
                                        await Api.instance.configureUrl(
                                          serverAddress.text,
                                        );
                                        if (context.mounted) {
                                          snack(
                                            context,
                                            'Server address saved.',
                                          );
                                        }
                                      } catch (error) {
                                        if (context.mounted) {
                                          snack(context, error.toString());
                                        }
                                      }
                                    },
                                    child: const Text('Save address'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _drop(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.user,
    required this.onUserChanged,
    required this.onSignedOut,
  });
  final Json user;
  final ValueChanged<Json> onUserChanged;
  final VoidCallback onSignedOut;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  List<Json> discover = [];
  List<Json> matches = [];
  List<Json> blocks = [];
  bool loading = true;
  bool acting = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        Api.instance.request('GET', '/api/discover'),
        Api.instance.request('GET', '/api/matches'),
        Api.instance.request('GET', '/api/blocks'),
      ]);
      if (mounted) {
        setState(() {
          discover = jsonList(results[0]['users']);
          matches = jsonList(results[1]['users']);
          blocks = jsonList(results[2]['users']);
          loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => loading = false);
        snack(context, error.toString());
      }
    }
  }

  Future<void> act(Json profile, String action) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      final result = await Api.instance.request(
        'POST',
        '/api/users/${profile['id']}/$action',
      );
      if (!mounted) return;
      setState(() => discover.removeWhere((u) => u['id'] == profile['id']));
      if (result['match'] == true) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('It’s a match ♥'),
            content: Text(
              'You and ${profile['name']} liked each other. Say hello when you’re ready.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Lovely'),
              ),
            ],
          ),
        );
      }
      await refresh();
    } catch (error) {
      if (mounted) snack(context, error.toString());
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> report(Json profile) async {
    final reason = await askReport(context, profile['name'].toString());
    if (reason == null) return;
    try {
      await Api.instance.request('POST', '/api/users/${profile['id']}/report', {
        'reason': reason,
      });
      if (mounted) {
        snack(context, 'Report submitted. Thank you for telling us.');
      }
    } catch (error) {
      if (mounted) snack(context, error.toString());
    }
  }

  Future<void> block(Json profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block ${profile['name']}?'),
        content: const Text('You will no longer see or message each other.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Api.instance.request('POST', '/api/users/${profile['id']}/block');
      await refresh();
      if (mounted) snack(context, 'Profile blocked.');
    } catch (error) {
      if (mounted) snack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = ['Discover', 'Matches', 'My profile', 'Safety'][tab];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cream,
        title: Row(
          children: [
            const Brand(),
            if (MediaQuery.of(context).size.width > 380) ...[
              const SizedBox(width: 15),
              Container(width: 1, height: 23, color: line),
              const SizedBox(width: 15),
              Text(title, style: const TextStyle(fontSize: 16, color: muted)),
            ],
          ],
        ),
        actions: [
          IconButton(
            onPressed: refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: tab,
              children: [
                _discoverPage(),
                _matchesPage(),
                ProfilePage(
                  user: widget.user,
                  onChanged: widget.onUserChanged,
                  onSignedOut: widget.onSignedOut,
                ),
                _safetyPage(),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) {
          setState(() => tab = value);
          if (value == 0 || value == 1 || value == 3) refresh();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Safety',
          ),
        ],
      ),
    );
  }

  Widget _discoverPage() {
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          const Text(
            'Thoughtful connections, one person at a time.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          if (discover.isEmpty)
            _empty(
              Icons.favorite_outline,
              'You’re all caught up',
              'There are no new profiles in your city right now. Check back later or invite someone you know.',
            ),
          if (discover.isNotEmpty) ...[
            ProfileCard(
              profile: discover.first,
              onReport: () => report(discover.first),
              onBlock: () => block(discover.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: acting
                        ? null
                        : () => act(discover.first, 'pass'),
                    icon: const Icon(Icons.close),
                    label: const Text('Pass'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: acting
                        ? null
                        : () => act(discover.first, 'like'),
                    icon: const Icon(Icons.favorite),
                    label: const Text('Like'),
                    style: FilledButton.styleFrom(
                      backgroundColor: coral,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '${discover.length} profile${discover.length == 1 ? '' : 's'} to explore',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _matchesPage() {
    if (matches.isEmpty) {
      return _empty(
        Icons.favorite_border,
        'No matches yet',
        'When you and someone like each other, your conversation starts here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Your connections',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'A good conversation can start simply.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        ...matches.map(
          (profile) => Card(
            color: Colors.white,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: line),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: ProfileAvatar(profile: profile, size: 54),
              title: Text(
                profile['name'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                profile['lastMessage'] == null
                    ? 'Say hello 👋'
                    : profile['lastMessage']['text'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatPage(profile: profile)),
                );
                refresh();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _safetyPage() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Icon(Icons.shield_outlined, color: coral, size: 42),
      const SizedBox(height: 12),
      Text(
        'Your comfort comes first.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 10),
      const Text(
        'You can report or block any profile from their card or your conversation. Reports are reviewed by the pilot operator.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 22),
      _safetyTile(
        Icons.person_off_outlined,
        'Block freely',
        'Blocked people cannot appear in your discovery or chats.',
      ),
      _safetyTile(
        Icons.flag_outlined,
        'Report concerns',
        'Tell us about harassment, fake profiles, scams, or anything unsafe.',
      ),
      _safetyTile(
        Icons.location_off_outlined,
        'City only',
        'Your precise location is never shown on a profile.',
      ),
      const SizedBox(height: 18),
      Text('Blocked profiles', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      if (blocks.isEmpty)
        const Text('No blocked profiles.', style: TextStyle(color: muted)),
      ...blocks.map(
        (profile) => ListTile(
          title: Text(profile['name'].toString()),
          trailing: TextButton(
            onPressed: () async {
              await Api.instance.request(
                'DELETE',
                '/api/blocks/${profile['id']}',
              );
              refresh();
            },
            child: const Text('Unblock'),
          ),
        ),
      ),
      const SizedBox(height: 20),
      TextButton(
        onPressed: () => showPolicy(context),
        child: const Text('Community rules and privacy notice'),
      ),
    ],
  );

  Widget _safetyTile(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: coral),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(body, style: const TextStyle(color: muted)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _empty(IconData icon, String title, String detail) => Center(
    child: Padding(
      padding: const EdgeInsets.all(38),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: coral, size: 54),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(color: muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.onReport,
    required this.onBlock,
  });
  final Json profile;
  final VoidCallback onReport;
  final VoidCallback onBlock;
  @override
  Widget build(BuildContext context) {
    final interests = (profile['interests'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D302332),
            blurRadius: 25,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 310,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF8D4CC), Color(0xFFB898B8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: ProfileAvatar(profile: profile, size: 170, hero: true),
                ),
                if (profile['demo'] == true)
                  Positioned(
                    top: 18,
                    left: 18,
                    child: _chip('SAMPLE PROFILE', Colors.white, ink),
                  ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: ink),
                    color: Colors.white,
                    onSelected: (value) =>
                        value == 'report' ? onReport() : onBlock(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'report',
                        child: Text('Report profile'),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Text('Block profile'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${profile['name']}, ${profile['age']}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const Icon(Icons.favorite_outline, color: coral, size: 20),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${profile['city']}  ·  ${profile['intent']}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 17),
                Text(
                  profile['bio']?.toString().isNotEmpty == true
                      ? profile['bio'].toString()
                      : 'Here to meet someone genuine.',
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
                if (profile['prompt']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text(
                    profile['prompt'].toString(),
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: muted,
                    ),
                  ),
                ],
                if (interests.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: interests
                        .map((e) => _chip(e, const Color(0xFFFFF0EC), ink))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: fg,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .4,
      ),
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    required this.size,
    this.hero = false,
  });
  final Json profile;
  final double size;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final palette = <String, List<Color>>{
      'rose': [const Color(0xFFF3B5AF), const Color(0xFFD47790)],
      'lilac': [const Color(0xFFCDB9E5), const Color(0xFF896DAA)],
      'mint': [const Color(0xFFB4DDCF), const Color(0xFF64A795)],
      'sky': [const Color(0xFFB8D7E4), const Color(0xFF729CB4)],
      'peach': [const Color(0xFFF9D4B1), const Color(0xFFD99078)],
    };
    final colors =
        palette[profile['color']] ??
        [const Color(0xFFEFC2B6), const Color(0xFFB07887)];
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: profile['photo'] == true
            ? FutureBuilder<Uint8List?>(
                future: Api.instance.photo(profile['id'].toString()),
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                    : _fallback(colors),
              )
            : _fallback(colors),
      ),
    );
  }

  Widget _fallback(List<Color> colors) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    alignment: Alignment.center,
    child: Text(
      profile['name'].toString().substring(0, 1).toUpperCase(),
      style: TextStyle(
        fontFamily: 'serif',
        fontSize: hero ? size * .55 : size * .48,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.profile});
  final Json profile;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  List<Json> messages = [];
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final result = await Api.instance.request(
        'GET',
        '/api/messages/${widget.profile['id']}',
      );
      if (mounted) {
        setState(() {
          messages = jsonList(result['messages']);
          loading = false;
        });
      }
    } catch (error) {
      if (mounted) snack(context, error.toString());
    }
  }

  Future<void> send() async {
    if (input.text.trim().isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await Api.instance.request(
        'POST',
        '/api/messages/${widget.profile['id']}',
        {'text': input.text},
      );
      input.clear();
      await refresh();
    } catch (error) {
      if (mounted) snack(context, error.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          ProfileAvatar(profile: widget.profile, size: 36),
          const SizedBox(width: 10),
          Text(widget.profile['name'].toString()),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'report') {
              final reason = await askReport(
                context,
                widget.profile['name'].toString(),
              );
              if (reason != null) {
                await Api.instance.request(
                  'POST',
                  '/api/users/${widget.profile['id']}/report',
                  {'reason': reason},
                );
                if (context.mounted) snack(context, 'Report submitted.');
              }
            } else {
              await Api.instance.request(
                'POST',
                '/api/users/${widget.profile['id']}/block',
              );
              if (context.mounted) Navigator.pop(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'report', child: Text('Report')),
            PopupMenuItem(value: 'block', child: Text('Block')),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
              ? const Center(
                  child: Text(
                    'Start with a simple hello 👋',
                    style: TextStyle(color: muted),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(18),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - index - 1];
                      final mine = message['from'] != widget.profile['id'];
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * .76,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: mine ? ink : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: mine ? null : Border.all(color: line),
                          ),
                          child: Text(
                            message['text'].toString(),
                            style: TextStyle(color: mine ? Colors.white : ink),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'Write a message…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sending ? null : send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.user,
    required this.onChanged,
    required this.onSignedOut,
  });
  final Json user;
  final ValueChanged<Json> onChanged;
  final VoidCallback onSignedOut;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController name;
  late final TextEditingController city;
  late final TextEditingController bio;
  late final TextEditingController prompt;
  late final TextEditingController interests;
  late String gender;
  late String lookingFor;
  late String intent;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.user['name']?.toString() ?? '');
    city = TextEditingController(text: widget.user['city']?.toString() ?? '');
    bio = TextEditingController(text: widget.user['bio']?.toString() ?? '');
    prompt = TextEditingController(
      text: widget.user['prompt']?.toString() ?? '',
    );
    interests = TextEditingController(
      text: (widget.user['interests'] as List<dynamic>? ?? []).join(', '),
    );
    gender = widget.user['gender']?.toString() ?? 'woman';
    lookingFor = widget.user['lookingFor']?.toString() ?? 'everyone';
    intent = widget.user['intent']?.toString() ?? 'Long-term relationship';
  }

  @override
  void dispose() {
    for (final controller in [name, city, bio, prompt, interests]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final result = await Api.instance.request('PATCH', '/api/profile', {
        'name': name.text,
        'city': city.text,
        'bio': bio.text,
        'prompt': prompt.text,
        'gender': gender,
        'lookingFor': lookingFor,
        'intent': intent,
        'interests': interests.text
            .split(',')
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .toList(),
      });
      widget.onChanged(result['user'] as Json);
      if (mounted) snack(context, 'Profile saved.');
    } catch (error) {
      if (mounted) snack(context, error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: Api.instance.isCloud ? 60 : 80,
      maxWidth: Api.instance.isCloud ? 900 : 1600,
    );
    if (image == null) return;
    try {
      final bytes = await image.readAsBytes();
      final mime =
          bytes.length >= 12 &&
              bytes[0] == 0x52 &&
              bytes[1] == 0x49 &&
              bytes[2] == 0x46 &&
              bytes[3] == 0x46 &&
              bytes[8] == 0x57 &&
              bytes[9] == 0x45 &&
              bytes[10] == 0x42 &&
              bytes[11] == 0x50
          ? 'image/webp'
          : bytes.length >= 8 &&
                bytes[0] == 0x89 &&
                bytes[1] == 0x50 &&
                bytes[2] == 0x4e &&
                bytes[3] == 0x47
          ? 'image/png'
          : bytes.length >= 3 &&
                bytes[0] == 0xff &&
                bytes[1] == 0xd8 &&
                bytes[2] == 0xff
          ? 'image/jpeg'
          : null;
      if (mime == null) {
        throw const ApiException('Choose a JPEG, PNG, or WebP photo.');
      }
      final result = await Api.instance.uploadPhoto(bytes, mime);
      widget.onChanged(result['user'] as Json);
      if (mounted) {
        snack(
          context,
          Api.instance.isCloud
              ? 'Photo submitted for review.'
              : 'Photo updated.',
        );
      }
    } catch (error) {
      if (mounted) snack(context, error.toString());
    }
  }

  Future<void> deleteAccount() async {
    final password = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This removes your profile, messages, likes, and photo from this app.',
            ),
            if (!Api.instance.isCloud) const SizedBox(height: 14),
            if (!Api.instance.isCloud)
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Your password'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, password.text),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    password.dispose();
    if (result == null) return;
    try {
      await Api.instance.request('DELETE', '/api/account', {
        'confirm': 'DELETE',
        'password': result,
      });
      widget.onSignedOut();
    } catch (error) {
      if (mounted) snack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text(
        'The real you looks good.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'A few details help someone start a better conversation.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 18),
      Center(
        child: Column(
          children: [
            ProfileAvatar(profile: widget.user, size: 105),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: upload,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add or change photo'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'First name'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: city,
        decoration: const InputDecoration(labelText: 'City'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: bio,
        maxLines: 3,
        maxLength: 500,
        decoration: const InputDecoration(labelText: 'About me'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: prompt,
        maxLines: 2,
        maxLength: 180,
        decoration: const InputDecoration(labelText: 'A conversation starter'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: interests,
        decoration: const InputDecoration(
          labelText: 'Interests, separated by commas',
        ),
      ),
      const SizedBox(height: 12),
      _dropdown('I identify as', gender, const {
        'woman': 'Woman',
        'man': 'Man',
        'nonbinary': 'Nonbinary',
      }, (v) => setState(() => gender = v)),
      const SizedBox(height: 12),
      _dropdown('I want to meet', lookingFor, const {
        'everyone': 'Everyone',
        'woman': 'Women',
        'man': 'Men',
        'nonbinary': 'Nonbinary people',
      }, (v) => setState(() => lookingFor = v)),
      const SizedBox(height: 12),
      _dropdown('I’m here for', intent, const {
        'Long-term relationship': 'Long-term relationship',
        'Open to possibilities': 'Open to possibilities',
        'Getting to know people': 'Getting to know people',
      }, (v) => setState(() => intent = v)),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy ? null : save,
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(16),
        ),
        child: Text(busy ? 'Saving…' : 'Save profile'),
      ),
      const SizedBox(height: 24),
      const Divider(),
      TextButton(
        onPressed: () async {
          await Api.instance.logout();
          widget.onSignedOut();
        },
        child: const Text('Sign out'),
      ),
      TextButton(
        onPressed: deleteAccount,
        child: const Text(
          'Delete account',
          style: TextStyle(color: Colors.red),
        ),
      ),
    ],
  );

  Widget _dropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: options.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

Future<String?> askReport(BuildContext context, String name) async {
  final reason = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Report $name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tell us what happened. Your report is private.'),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Reason for reporting'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, reason.text.trim()),
          child: const Text('Submit'),
        ),
      ],
    ),
  );
  reason.dispose();
  return result?.isNotEmpty == true ? result : null;
}

void showPolicy(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Community & privacy'),
      content: const SingleChildScrollView(
        child: Text(
          'Kindred is for adults aged 18 and older. Be respectful. Do not harass, threaten, impersonate, scam, solicit money, or share anyone’s private or intimate content without consent. Report concerning behavior and block anyone you do not wish to contact.\n\n'
          'The pilot stores your email, profile details, likes, messages, reports, and any photo you upload on the app server. Your profile is shown only to signed-in accounts in your selected city that fit mutual preferences. Your exact location is not collected. You can edit your profile and delete your account in the app. Reports are visible to the pilot operator for safety review.\n\n'
          'This pilot needs stronger age verification, active moderation, and a full legal privacy notice before a public launch.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
