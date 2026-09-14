import 'package:supabase/supabase.dart';

const waveEmailLeadHours = [1, 2, 5, 10, 15, 20, 24, 48, 72];
const waveCheckinSheetNote =
    'This check-in sheet includes only your animals in this wave. '
    'If you have animals entered in other waves, you’ll receive a separate '
    'check-in sheet as each wave’s check-in approaches. You can view all '
    'your entries anytime in the Entries tab of your account.';

String waveLeadLabel(int hours) => hours < 48
    ? '$hours ${hours == 1 ? 'hour' : 'hours'}'
    : '${hours ~/ 24} days';

class ShowWave {
  ShowWave({
    required this.id,
    required this.number,
    this.checkinStart,
    this.checkinEnd,
    this.showDate,
    this.checkoutDate,
    this.emailLeadHours = 24,
  });
  final String id;
  int number;
  // Calendar values in the show's timezone. The database converts to UTC.
  DateTime? checkinStart;
  DateTime? checkinEnd;
  DateTime? showDate;
  DateTime? checkoutDate;
  int emailLeadHours;
  String get name => 'Wave $number';
  factory ShowWave.fromJson(Map<String, dynamic> json) => ShowWave(
    id: json['id'].toString(),
    number: (json['wave_number'] as num).toInt(),
    checkinStart: DateTime.tryParse('${json['checkin_start_local'] ?? ''}'),
    checkinEnd: DateTime.tryParse('${json['checkin_end_local'] ?? ''}'),
    showDate: DateTime.tryParse('${json['show_date'] ?? ''}'),
    checkoutDate: DateTime.tryParse('${json['checkout_date'] ?? ''}'),
    emailLeadHours: (json['email_lead_hours'] as num?)?.toInt() ?? 24,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'wave_number': number,
    'checkin_start_local': checkinStart?.toIso8601String(),
    'checkin_end_local': checkinEnd?.toIso8601String(),
    'show_date': showDate?.toIso8601String().substring(0, 10),
    'checkout_date': checkoutDate?.toIso8601String().substring(0, 10),
    'email_lead_hours': emailLeadHours,
  };
}

class WaveBreed {
  WaveBreed({
    required this.species,
    required this.name,
    this.waveId,
    this.hasEntries = false,
  });
  final String species;
  final String name;
  final bool hasEntries;
  String? waveId;
  factory WaveBreed.fromJson(Map<String, dynamic> json) => WaveBreed(
    species: json['species'].toString(),
    name: json['breed_name'].toString(),
    waveId: json['wave_id']?.toString(),
    hasEntries: json['has_entries'] == true,
  );
  Map<String, dynamic> toJson() => {
    'species': species,
    'breed_name': name,
    'wave_id': waveId,
  };
}

class ShowWaveSchedule {
  ShowWaveSchedule({
    required this.enabled,
    required this.timezone,
    required this.waves,
    required this.breeds,
    this.activeWaveId,
    this.canConfigure = false,
  });
  bool enabled;
  final String timezone;
  final List<ShowWave> waves;
  final List<WaveBreed> breeds;
  final String? activeWaveId;
  final bool canConfigure;
  factory ShowWaveSchedule.fromJson(Map<String, dynamic> json) =>
      ShowWaveSchedule(
        enabled: json['enabled'] == true,
        timezone: '${json['timezone'] ?? 'America/Indiana/Indianapolis'}',
        waves: (json['waves'] as List? ?? [])
            .map((v) => ShowWave.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        breeds: (json['breeds'] as List? ?? [])
            .map((v) => WaveBreed.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        activeWaveId: json['active_wave_id']?.toString(),
        canConfigure: json['can_configure'] == true,
      );
  String? validate() {
    if (!enabled) return null;
    if (waves.isEmpty) return 'Add at least one wave.';
    for (final wave in waves) {
      if (wave.checkinStart == null ||
          wave.checkinEnd == null ||
          wave.showDate == null ||
          wave.checkoutDate == null) {
        return 'Complete all dates and check-in times for ${wave.name}.';
      }
      if (!wave.checkinEnd!.isAfter(wave.checkinStart!)) {
        return '${wave.name} must end check-in after it starts.';
      }
      final startDate = DateTime(
        wave.checkinStart!.year,
        wave.checkinStart!.month,
        wave.checkinStart!.day,
      );
      if (startDate.isAfter(wave.showDate!)) {
        return '${wave.name} must check in on or before its show date.';
      }
      if (wave.checkoutDate!.isBefore(wave.showDate!)) {
        return '${wave.name} must check out on or after its show date.';
      }
    }
    final sorted = [...waves]
      ..sort((a, b) => a.checkinStart!.compareTo(b.checkinStart!));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].checkinStart!.isBefore(sorted[i - 1].checkinEnd!)) {
        return 'Wave check-in windows cannot overlap.';
      }
    }
    return null;
  }
}

class ShowWaveScheduleService {
  ShowWaveScheduleService(this.client);
  final SupabaseClient client;
  Future<ShowWaveSchedule> load(String showId) async {
    final data = await client.rpc(
      'get_show_wave_schedule',
      params: {'p_show_id': showId},
    );
    return ShowWaveSchedule.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> save(String showId, ShowWaveSchedule schedule) async {
    final error = schedule.validate();
    if (error != null) throw StateError(error);
    await client.rpc(
      'save_show_wave_schedule',
      params: {
        'p_show_id': showId,
        'p_enabled': schedule.enabled,
        'p_waves': schedule.waves.map((w) => w.toJson()).toList(),
        'p_breeds': schedule.breeds.map((b) => b.toJson()).toList(),
      },
    );
  }
}
