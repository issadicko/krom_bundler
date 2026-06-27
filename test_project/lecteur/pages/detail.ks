// ============================================================
// Article — GET /posts/:id, puis l'auteur via GET /users/:userId.
// dummyjson.com sert /posts/{id} et /users/{id} pour tous les ids.
// Reçoit `args.id` depuis ui.push("detail", { id }).
// ============================================================

@use "../utils/theme"

let post = Obs({})           // map sentinelle (on évite Obs(null))
let author = Obs("")
let state = Obs("loading")   // loading | ready | error

fn onInit() { load() }

fn load() {
  let id = 1
  if (args != null) { id = args.id }
  state.set("loading")
  author.set("")
  print("[detail] load id=" + id)
  request({ url: BASE + "/posts/" + id }, "onPost", "onErr")
}

fn onPost(res) {
  print("[detail] onPost status=" + res.statusCode)
  if (res.ok) {
    post.set(res.data)
    state.set("ready")
    // 2ᵉ requête : l'auteur de l'article.
    let uid = res.data.userId
    if (uid != null) {
      request({ url: BASE + "/users/" + uid }, "onAuthor", "onAuthorErr")
    }
  } else {
    state.set("error")
  }
}

fn onAuthor(res) {
  if (res.ok) {
    author.set(res.data.firstName + " " + res.data.lastName)
  }
}

fn onAuthorErr(err) { }
fn onErr(err) {
  print("[detail] onErr: " + err.error)
  state.set("error")
}

fn build() {
  return Scaffold({
    appBar: AppBar({ title: "Article", backgroundColor: T.primary }),
    backgroundColor: T.bg
  },
    Obx({ builder: "content" })
  )
}

fn content() {
  let s = state.value
  if (s == "loading") { return loadingView() }
  if (s == "error") { return errorView() }

  let p = post.value
  return ScrollView({ padding: 16 },
    Column({ crossAxisAlignment: "start", spacing: 14 }, [
      Obx({ builder: "authorLine" }),
      Text(p.title, { fontSize: 22, fontWeight: "bold", color: T.text }),
      Row({ spacing: 6 }, p.tags.map(fn(t) { return chip(t) })),
      metaRow(p.reactions.likes, p.views),
      Text(p.body, { fontSize: 15, color: "#334155" })
    ])
  )
}

fn authorLine() {
  let a = author.value
  if (a == "") {
    return Text("Chargement de l'auteur…", { fontSize: 12, color: T.muted })
  }
  return Row({ spacing: 6, crossAxisAlignment: "center" }, [
    Icon("person", { size: 16, color: T.primary }),
    Text("Par " + a, { fontSize: 13, fontWeight: "600", color: T.muted })
  ])
}
