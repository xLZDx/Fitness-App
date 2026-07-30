/// Maps the catalog's coarse muscle tags onto the anatomical chart's elements.
///
/// The chart names real muscles per side (`pectoralis_major_l`,
/// `vastus_medialis_r`, `trapezius_middle_l`, ...); the exercise catalog speaks
/// in groups (`chest`, `quads`, `traps`). This table is the join, kept as data
/// so a test can prove every id here exists in the shipped SVG and every tag the
/// catalog can emit is accounted for.
///
/// Ids are stored WITHOUT the `_l` / `_r` suffix and matched as a prefix, which
/// is also how the numbered segments (`rectus_abdominis_1..4`) are covered
/// without listing each one.
library;

/// Front-view chart. Keys are catalog tags.
const Map<String, List<String>> kFrontMuscleIds = <String, List<String>>{
  'chest': ['pectoralis_major'],
  'shoulders': ['anterior_deltoid', 'lateral_deltoid'],
  'biceps': ['biceps_brachii_caput_breve', 'biceps_brachii_caput_longum'],
  'triceps': [
    'triceps_brachii_caput_laterale',
    'triceps_brachii_caput_longum',
  ],
  'forearms': [
    'brachioradialis',
    'extensor_carpi_radialis_longus',
    'flexor_carpi_radialis',
    'flexor_digitorum_superficialis',
    'palmaris_longus',
    'pronator_teres',
    'pronator_quadratus',
  ],
  'lats': ['latissimus_dorsi'],
  'traps': ['trapezius_upper'],
  'core': ['rectus_abdominis', 'external_oblique'],
  'quads': ['rectus_femoris', 'vastus_lateralis', 'vastus_medialis', 'sartoris'],
  'hamstrings': ['semitendinosus'],
  'glutes': ['gluteus_medius'],
  'calves': ['gastrocnemius'],
  'adductors': ['adductor_longus', 'gracilis', 'pectineus'],
};

/// Back-view chart. Keys are catalog tags.
const Map<String, List<String>> kBackMuscleIds = <String, List<String>>{
  'shoulders': ['posterior_deltoid', 'lateral_deltoid'],
  'triceps': [
    'triceps_brachii_caput_laterale',
    'triceps_brachii_caput_longum',
    'triceps_brachii_caput_mediale',
    'anconeus',
  ],
  'forearms': [
    'brachioradialis',
    'extensor_carpi_ulnaris',
    'extensor_digitorum',
    'flexor_carpi_ulnaris',
  ],
  'lats': ['latissimus_dorsi'],
  // "middle back" in the catalog's vocabulary: the scapular region.
  'back': ['infraspinatus', 'trapezius_middle'],
  'traps': ['trapezius_upper', 'trapezius_middle', 'trapezius_lower'],
  'core': ['external_oblique'],
  'hamstrings': [
    'biceps_femoris',
    'semitendinosus',
    'semimembranosus',
  ],
  'glutes': ['gluteus_maximus', 'gluteus_medius'],
  'calves': ['gastrocnemius'],
  'adductors': ['adductor_magnus'],
};

/// Catalog tags with no shape on either view, and why.
///
/// Listed rather than approximated. `lower_back` means the erector spinae, and
/// this artwork simply does not draw them — colouring the nearest available
/// muscle instead would teach the user something false about their own body.
/// The chart surfaces these as text so the information is not lost.
const Set<String> kTagsWithoutShape = <String>{'lower_back'};

/// Every tag the chart knows how to draw.
Set<String> get kDrawableTags =>
    <String>{...kFrontMuscleIds.keys, ...kBackMuscleIds.keys};
