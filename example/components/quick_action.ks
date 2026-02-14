fn QuickAction(iconName, label, bgColor, onTap) {
  return Box({ borderRadius: 16, width: 85, height: 85, color: "white" }, 
    InkWell({ onTap: onTap, borderRadius: 12 }, 
      Column({ spacing: 8, mainAxisAlignment: "center" }, [
        Box({ width: 42, height: 42, color: bgColor, borderRadius: 16, alignment: "center" }, 
          Icon(iconName, { size: 20, color: "white" })
        ),
        Text(label, { fontSize: 14, color: "black" })
      ])
    )
  )
}
