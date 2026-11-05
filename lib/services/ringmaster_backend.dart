// App data always uses the current workspace. Auth bootstrap and the support
// session broker are the only code that needs the real administrator client.
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support_delegation.dart';
export 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get ringMasterClient => RingMasterData.client;
