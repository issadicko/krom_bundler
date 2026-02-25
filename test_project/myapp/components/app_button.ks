// Reusable button component
// Named AppButton to avoid conflict with core Button widget
fn AppButton(label, color, onTap) {
  return InkWell({ onTap: onTap, borderRadius: 8 }, [
    Box({ 
      padding: 16, 
      borderRadius: 8, 
      color: color 
    }, [
      Text(label, { 
        fontSize: 16, 
        fontWeight: "bold", 
        color: "white" 
      })
    ])
  ])
}
