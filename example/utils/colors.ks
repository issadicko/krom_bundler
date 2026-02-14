// Palette de couleurs
let colors = {
  primary: "#3B82F6",
  success: "#22C55E",
  danger: "#EF4444",
  warning: "#F59E0B",
  purple: "#8B5CF6",
  pink: "#EC4899"
}

fn getTransactionColor(type) {
  if (type == "income") {
    return colors.success
  }
  return colors.danger
}
