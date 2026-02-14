// Fonctions de formatage
fn formatMoney(amount) {
  if (amount >= 0) {
    return "+" + amount + " EUR"
  }
  return amount + " EUR"
}

fn formatDate(date) {
  // Si c'est un timestamp numérique, on le convertit en format lisible
  if (date > 1000000000000) {
    let currentTime = now()
    let diff = currentTime - date
    let days = toInt((diff / 86400000))
    
    if (days == 0) {
      return "Aujourd'hui"
    }
    if (days == 1) {
      return "Hier"
    }
    if (days < 7) {
      return days + " jours"
    }
    return "Il y a " + toInt(days / 7) + " sem."
  }
  return date
}
