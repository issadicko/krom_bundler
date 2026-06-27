// ============================================================
// Articles — liste via GET /posts (dummyjson.com).
// res.data = { posts: [...], total, skip, limit }
// ============================================================

@use "../utils/theme"

let posts = List([])
let state = Obs("loading")   // loading | ready | error

fn onInit() { load() }

fn load() {
  state.set("loading")
  request({ url: BASE + "/posts?limit=30" }, "onPosts", "onErr")
}

fn onPosts(res) {
  print("[home] onPosts status=" + res.statusCode)
  if (res.ok) {
    posts.clear()
    posts.addAll(res.data.posts)   // le tableau est niché sous .posts
    state.set("ready")
  } else {
    state.set("error")
  }
}

fn onErr(err) {
  print("[home] onErr: " + err.error)
  state.set("error")
}

fn reload() { load() }
fn open(id) { ui.push("detail", { id: id }) }

fn build() {
  return Scaffold({
      appBar: AppBar({
          backgroundColor: T.primary,
          actions: [ IconButton("refresh", { onTap: "reload" }) ],
          elevation: 5
        }, [
          Text("Articles", { fontSize: 20, fontWeight: "bold", color: T.text, color: "white" })
      ]),
      backgroundColor: T.bg
    },
    Obx({ builder: "list" })
  )
}

fn list() {
  let s = state.value
  if (s == "loading") { return loadingView() }
  if (s == "error") { return errorView() }
  return ScrollView({ padding: 12 },
    Column({ spacing: 12 }, posts.value.map(fn(p) { return postCard(p) }))
  )
}

fn postCard(p) {
  return InkWell({ onTap: "open", arg: p.id, borderRadius: 16 },
    Card({ color: T.surface, borderRadius: 16, padding: 14 },
      Column({ crossAxisAlignment: "start", spacing: 10 }, [
          Text(p.title, { fontSize: 16, fontWeight: "bold", color: T.text }),
          Text(excerpt(p.body), { fontSize: 13, color: T.muted }),
          Row({ spacing: 6 }, p.tags.map(fn(t) { return chip(t) })),
          metaRow(p.reactions.likes, p.views)
      ])
    )
  )
}
