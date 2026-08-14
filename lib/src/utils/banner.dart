/// La signature visuelle de la CLI.
///
/// Un outil qu'on installe par `curl | sh` n'a qu'un seul endroit pour dire son
/// nom : la première commande qu'on tape. Le bandeau n'apparaît donc que là où
/// quelqu'un regarde — `krom init`, et l'écran d'aide d'un `krom` nu — jamais
/// dans une sortie qu'on redirige.
library;

/// Le mot KROM, cinq rangs de blocs pleins.
///
/// Mêmes glyphes que le QR du terminal (`▀`), donc mêmes polices déjà exigées.
/// 28 colonnes : tient dans un terminal étroit sans se replier.
const List<String> kKromWordmark = [
  '██  ██ █████   ████  ██   ██',
  '██ ██  ██  ██ ██  ██ ███ ███',
  '████   █████  ██  ██ ██ █ ██',
  '██ ██  ██ ██  ██  ██ ██   ██',
  '██  ██ ██  ██  ████  ██   ██',
];

/// Largeur du bandeau, pour aligner ce qu'on écrit dessous.
const int kKromWordmarkWidth = 28;
