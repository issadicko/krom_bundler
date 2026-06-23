fn build() {
  return Scaffold({
    appBar: AppBar({ title: "Detail statistiques", backgroundColor: Theme.primary }),
    body: Center(
      Text("Detail des depenses par categorie", { fontSize: 18, color: "black" })
    )
  })
}
