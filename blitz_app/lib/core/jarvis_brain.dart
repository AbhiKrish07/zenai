// Backward-compatibility shim — jarvis_brain.dart
// The brain was renamed to ZenBrain. This file re-exports everything
// so older imports of 'jarvis_brain.dart' continue to work.
export 'zen_brain.dart';
export 'database.dart';

// Aliases so old code using JarvisBrain() / JarvisDatabase() compiles
import 'zen_brain.dart';
import 'database.dart';

typedef JarvisBrain = ZenBrain;
typedef JarvisDatabase = ZenDatabase;
