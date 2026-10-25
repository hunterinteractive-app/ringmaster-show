import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_session.dart';
import '../../services/convention_sale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ringmaster_page_shell.dart';
import '../../widgets/rm_widgets.dart';
import '../convention_sale_screen.dart';

class ConventionSaleAdminScreen extends StatefulWidget {
  const ConventionSaleAdminScreen({super.key});
  @override
  State<ConventionSaleAdminScreen> createState() =>
      _ConventionSaleAdminScreenState();
}

class _ConventionSaleAdminScreenState extends State<ConventionSaleAdminScreen> {
  final _form = GlobalKey<FormState>();
  final _map = MapController();
  final _fields = <String, TextEditingController>{
    for (final name in [
      'title',
      'venue',
      'address',
      'latitude',
      'longitude',
      'single_bonus',
      'four_bonus',
      'unlimited_bonus_months',
    ])
      name: TextEditingController(),
  };
  bool _loading = true,
      _saving = false,
      _enabled = true,
      _fullDay = true,
      _mapReady = false;
  String? _error, _message;
  String _zone = 'America/Los_Angeles';
  int _revision = 1;
  double _radius = 1;
  LatLng _center = const LatLng(39.4861, -119.7911);
  DateTime _start = DateTime(2026, 10, 26), _end = DateTime(2026, 10, 27);
  static const _zones = [
    'America/Los_Angeles',
    'America/Denver',
    'America/Phoenix',
    'America/Chicago',
    'America/New_York',
    'America/Indiana/Indianapolis',
    'America/Toronto',
    'UTC',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (AppSession.isSupportMode) {
        throw StateError('Exit View As User to edit sale settings.');
      }
      final data = await ConventionSaleService.settings(admin: true);
      if (!mounted) return;
      setState(() {
        for (final name in _fields.keys) {
          _fields[name]!.text = '${data[name]}';
        }
        _enabled = data['enabled'] == true;
        _revision = (data['revision'] as num).toInt();
        _zone = data['time_zone'] as String;
        _radius = (data['radius_miles'] as num).toDouble();
        _center = LatLng(
          (data['latitude'] as num).toDouble(),
          (data['longitude'] as num).toDouble(),
        );
        _start = DateTime.parse(data['starts_local'] as String);
        _end = DateTime.parse(data['ends_local'] as String);
        _fullDay =
            _start.hour == 0 &&
            _start.minute == 0 &&
            _end == DateTime(_start.year, _start.month, _start.day + 1);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Sale settings could not load. Super Admin access and the convention sale database update are required.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setCenter(LatLng point) {
    if (point.latitude.abs() > 85) return;
    setState(() {
      _center = LatLng(point.latitude, ((point.longitude + 180) % 360) - 180);
      _fields['latitude']!.text = _center.latitude.toStringAsFixed(6);
      _fields['longitude']!.text = _center.longitude.toStringAsFixed(6);
    });
  }

  void _fitMap() {
    if (!_mapReady) return;
    const distance = Distance();
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [
          for (final bearing in [0.0, 90.0, 180.0, 270.0])
            distance.offset(_center, _radius * 1609.344, bearing),
        ],
        padding: const EdgeInsets.all(28),
      ),
    );
  }

  Map<String, dynamic> _draft() => {
    'revision': _revision,
    'enabled': _enabled,
    for (final name in ['title', 'venue', 'address'])
      name: _fields[name]!.text.trim(),
    for (final name in ['latitude', 'longitude'])
      name: double.parse(_fields[name]!.text.trim()),
    for (final name in ['single_bonus', 'four_bonus', 'unlimited_bonus_months'])
      name: int.parse(_fields[name]!.text.trim()),
    'radius_miles': _radius,
    'time_zone': _zone,
    'starts_local': DateFormat('yyyy-MM-ddTHH:mm').format(_start),
    'ends_local': DateFormat('yyyy-MM-ddTHH:mm').format(_end),
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    if (!_end.isAfter(_start) ||
        _end.difference(_start) > const Duration(days: 14)) {
      setState(
        () => _error =
            'The end must follow the start, with a sale lasting no more than 14 days.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final saved = await ConventionSaleService.save(_draft());
      if (!mounted) return;
      setState(() {
        _revision = (saved['revision'] as num).toInt();
        _message = _enabled
            ? 'Saved. The convention offer opens and closes automatically at the scheduled times.'
            : 'Saved. The convention sale is paused.';
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().contains('Settings changed')
              ? 'Another admin changed this sale. Reload before saving.'
              : 'Settings could not be saved. Check the dates, time zone and field values, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final old = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: old,
      firstDate: DateTime(2026),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        old.hour,
        old.minute,
      );
      if (start) {
        _start = value;
        if (_fullDay) _end = DateTime(date.year, date.month, date.day + 1);
      } else {
        _end = value;
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final old = start ? _start : _end;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old),
    );
    if (time == null || !mounted) return;
    setState(() {
      final value = DateTime(
        old.year,
        old.month,
        old.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  Widget _field(
    String key,
    String label, {
    bool integer = false,
    int max = 100,
    bool coordinate = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _fields[key],
      maxLength: integer || coordinate
          ? null
          : key == 'title'
          ? 100
          : key == 'venue'
          ? 200
          : 300,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: integer || coordinate
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      validator: (value) {
        if (coordinate) {
          final n = double.tryParse(value ?? '');
          final bound = key == 'latitude' ? 85 : 180;
          return n == null || !n.isFinite || n.abs() > bound
              ? 'Enter a coordinate between -$bound and $bound.'
              : null;
        }
        if (integer) {
          final n = int.tryParse(value ?? '');
          return n == null || n < 0 || n > max
              ? 'Enter a whole number from 0 to $max.'
              : null;
        }
        return (value ?? '').trim().isEmpty ? 'Enter $label.' : null;
      },
      onFieldSubmitted: coordinate
          ? (_) {
              final lat = double.tryParse(_fields['latitude']!.text),
                  lon = double.tryParse(_fields['longitude']!.text);
              if (lat != null &&
                  lon != null &&
                  lat.abs() <= 85 &&
                  lon.abs() <= 180) {
                _setCenter(LatLng(lat, lon));
                _fitMap();
              }
            }
          : null,
      onChanged: coordinate
          ? (_) {
              final lat = double.tryParse(_fields['latitude']!.text),
                  lon = double.tryParse(_fields['longitude']!.text);
              if (lat != null &&
                  lon != null &&
                  lat.isFinite &&
                  lon.isFinite &&
                  lat.abs() <= 85 &&
                  lon.abs() <= 180) {
                setState(() => _center = LatLng(lat, lon));
              }
            }
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Convention token sale',
    subtitle: 'Super Admin',
    showHelpButton: false,
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Set the place. Choose the bonus.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Reuse this page each year. Every qualifying purchase receives the selected bonus; new checkouts require a fresh location check.',
                        style: TextStyle(color: Colors.white, height: 1.5),
                      ),
                      const SizedBox(height: 18),
                      if (_error != null || _message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: RMCard(
                            child: Column(
                              children: [
                                Text(
                                  _error ?? _message!,
                                  style: TextStyle(
                                    color: _error != null
                                        ? AppColors.danger
                                        : AppColors.success,
                                  ),
                                  semanticsLabel: _error ?? _message,
                                ),
                                if (_error != null)
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('Reload saved settings'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      RMCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Enable scheduled sale'),
                              subtitle: const Text(
                                'Turn off to pause new convention checkouts immediately.',
                              ),
                              value: _enabled,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _enabled = v),
                            ),
                            const SizedBox(height: 12),
                            _field('title', 'Sale title'),
                            _field('venue', 'Convention venue'),
                            _field('address', 'Street address and city'),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => launchUrl(
                                  Uri.https('www.openstreetmap.org', '/search', {
                                    'query':
                                        '${_fields['venue']!.text} ${_fields['address']!.text}',
                                  }),
                                ),
                                icon: const Icon(Icons.search),
                                label: const Text(
                                  'Look up venue on OpenStreetMap',
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Pan or zoom the map, then tap to place the convention pin. The shaded circle is the eligible area.',
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 360,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: FlutterMap(
                                  mapController: _map,
                                  options: MapOptions(
                                    initialCenter: _center,
                                    initialZoom: 13,
                                    minZoom: 2,
                                    maxZoom: 18,
                                    onMapReady: () {
                                      _mapReady = true;
                                      _fitMap();
                                    },
                                    onTap: (_, point) => _setCenter(point),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.ringmasterone.show',
                                    ),
                                    CircleLayer(
                                      circles: [
                                        CircleMarker(
                                          point: _center,
                                          radius: _radius * 1609.344,
                                          useRadiusInMeter: true,
                                          color: AppColors.secondaryButton
                                              .withValues(alpha: .16),
                                          borderColor:
                                              AppColors.secondaryButton,
                                          borderStrokeWidth: 3,
                                        ),
                                      ],
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: _center,
                                          width: 44,
                                          height: 44,
                                          child: const Icon(
                                            Icons.location_pin,
                                            color: AppColors.secondaryButton,
                                            size: 42,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SimpleAttributionWidget(
                                      source: const Text(
                                        'OpenStreetMap contributors',
                                        style: TextStyle(
                                          color: AppColors.navy,
                                          fontSize: 11,
                                        ),
                                      ),
                                      backgroundColor: Colors.white,
                                      onTap: () => launchUrl(
                                        Uri.parse(
                                          'https://www.openstreetmap.org/copyright',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Eligible radius: ${_radius.toStringAsFixed(1)} miles',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Slider(
                              value: _radius,
                              min: .1,
                              max: 25,
                              divisions: 249,
                              label: '${_radius.toStringAsFixed(1)} miles',
                              semanticFormatterCallback: (v) =>
                                  '${v.toStringAsFixed(1)} miles',
                              onChanged: (v) => setState(
                                () => _radius = (v * 10).round() / 10,
                              ),
                              onChangeEnd: (_) => _fitMap(),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    'latitude',
                                    'Center latitude',
                                    coordinate: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _field(
                                    'longitude',
                                    'Center longitude',
                                    coordinate: true,
                                  ),
                                ),
                              ],
                            ),
                            OutlinedButton.icon(
                              onPressed: _fitMap,
                              icon: const Icon(Icons.center_focus_strong),
                              label: const Text('Show the full eligible area'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      RMCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Sale date and hours',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _zone,
                              decoration: const InputDecoration(
                                labelText: 'Convention time zone',
                                border: OutlineInputBorder(),
                              ),
                              isExpanded: true,
                              items: {..._zones, _zone}
                                  .map(
                                    (z) => DropdownMenuItem(
                                      value: z,
                                      child: Text(z),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (z) {
                                if (z != null) setState(() => _zone = z);
                              },
                            ),
                            const SizedBox(height: 14),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Full day — midnight through 11:59 PM',
                              ),
                              value: _fullDay,
                              onChanged: (v) => setState(() {
                                _fullDay = v;
                                if (v) {
                                  _start = DateTime(
                                    _start.year,
                                    _start.month,
                                    _start.day,
                                  );
                                  _end = DateTime(
                                    _start.year,
                                    _start.month,
                                    _start.day + 1,
                                  );
                                }
                              }),
                            ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _pickDate(true),
                                  icon: const Icon(Icons.calendar_month),
                                  label: Text(
                                    '${_fullDay ? 'Sale date' : 'Starts'}: ${DateFormat.yMMMd().format(_start)}',
                                  ),
                                ),
                                if (!_fullDay) ...[
                                  OutlinedButton(
                                    onPressed: () => _pickTime(true),
                                    child: Text(
                                      'Start: ${DateFormat.jm().format(_start)}',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _pickDate(false),
                                    icon: const Icon(Icons.calendar_month),
                                    label: Text(
                                      'Ends: ${DateFormat.yMMMd().format(_end)}',
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _pickTime(false),
                                    child: Text(
                                      'Closes at: ${DateFormat.jm().format(_end)}',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Checkout must start during these hours. A checkout already started can be completed within 30 minutes. Times follow the selected convention time zone, including daylight saving time.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      RMCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Bonus on every qualifying purchase',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _field(
                              'single_bonus',
                              'Bonus tokens with a 1-token purchase',
                              integer: true,
                            ),
                            _field(
                              'four_bonus',
                              'Bonus tokens with a 4-token purchase',
                              integer: true,
                            ),
                            _field(
                              'unlimited_bonus_months',
                              'Bonus months with 12-month unlimited',
                              integer: true,
                              max: 24,
                            ),
                            const Text(
                              'Existing unlimited customers keep their remaining time. A new unlimited purchase adds 12 months plus the selected bonus from their current expiration, or from purchase confirmation if access has expired.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                              _saving ? 'Saving…' : 'Save sale settings',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              if (_form.currentState!.validate()) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => ConventionSaleScreen(
                                      previewSettings: {
                                        ..._draft(),
                                        'active': false,
                                      },
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.visibility_outlined,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Preview sale page',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: '${Uri.base.origin}/#/convention-sale',
                                ),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Sale page link copied.'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.link, color: Colors.white),
                            label: const Text(
                              'Copy sale link',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}
