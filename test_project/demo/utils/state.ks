// ============================================================
// État réactif de la démo.
// ============================================================
let selCur = Obs("eur")     // Select
let radio = Obs("std")      // RadioGroup
let chipSel = Obs("all")    // Chip (filtre)
let seg = Obs("month")      // Segmented
let dateVal = Obs("")       // DateField
let progress = Obs(0.4)     // LinearProgress
let removed = Obs(false)    // Swipeable
let vaultVal = Obs("(appuie sur « Lire le coffre »)")  // binding hôte, lu à la demande

fn onCur(v) { selCur.set(v) }
fn onRadio(v) { radio.set(v) }
fn onSeg(v) { seg.set(v) }
fn onDate(v) { dateVal.set(v) }

fn pickChip(k) {
  if (chipSel.value == k) {
    chipSel.set("all")
  } else {
    chipSel.set(k)
  }
}

fn bumpProgress() {
  let v = progress.value + 0.2
  if (v > 1) { v = 0 }
  progress.set(v)
}

fn onRemoved() { removed.set(true) }
