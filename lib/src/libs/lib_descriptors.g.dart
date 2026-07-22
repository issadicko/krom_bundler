// GENERATED — ne pas éditer à la main.
// Source : krom_lib_*/krom_lib.json
// Régénérer : dart run tool/embed_lib_descriptors.dart

/// Les composants et modules de chaque lib de domaine embarquée,
/// indexés par pack de capacité.
const Map<String, KromLibDescriptor> kKromLibDescriptors = {
  'charts': KromLibDescriptor(
    pack: 'charts',
    version: '1.0.0',
    components: ['AreaChart', 'ChartLegend', 'DonutChart', 'LineChart', 'ScatterChart', 'Sparkline', 'StackedBarChart'],
    modules: {'charts': ['formatNumber', 'niceScale', 'palette', 'percent']},
  ),
  'media': KromLibDescriptor(
    pack: 'media',
    version: '1.1.0',
    components: ['CameraButton', 'MediaGrid', 'MediaThumb', 'PhotoView'],
    modules: {'media': ['captureImage', 'pickImage', 'pickMultiple', 'pickVideo', 'toBase64']},
  ),
  'forms': KromLibDescriptor(
    pack: 'forms',
    version: '1.2.0',
    components: ['CurrencyField', 'Field', 'FieldError', 'FormBody', 'FormWizard', 'MaskedField', 'PhoneField', 'RatingField', 'SignaturePad', 'SubmitButton'],
    modules: {'forms': ['digits', 'email', 'group', 'luhn', 'maxLength', 'minLength', 'phone', 'pickContact', 'range', 'required', 'validate']},
  ),
};

/// Ce qu'une lib de domaine expose au script d'une mini-app.
class KromLibDescriptor {
  const KromLibDescriptor({
    required this.pack,
    required this.version,
    required this.components,
    required this.modules,
  });

  /// Le pack déclaré dans le `requires` du manifeste.
  final String pack;

  /// Version de la lib dont ce descripteur a été extrait.
  final String version;

  /// Noms des composants, utilisables comme des widgets.
  final List<String> components;

  /// Namespaces exposés, et les méthodes de chacun.
  final Map<String, List<String>> modules;
}
