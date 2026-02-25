// Home page
let counter = Obs(0)

fn build() {
  return Scaffold({
      appBar: AppBar({ title: 'Welcome to KromLang' }),
      backgroundColor: '#0044ff'
    },
    Box({ color: "#f5f5f5", width: "infinity", padding: 8 }, [

        Column({ spacing: 24, mainAxisAlignment: "start", crossAxisAlignment: "start" }, [

            Card({
                elevation: 2,
                color: 'white',
                padding: 16,
                borderRadius: 8
              },

              Column({ spacing: 14, crossAxisAlignment: "start" }, [

                  Text('Informations personnels', { fontSize: 14, color: 'black', fontWeight: 'bold' }),

                  TextField({
                      labelText: 'Nom',
                      value: null,
                      onChange: 'onChange'
                  }),

                  TextField({
                      labelText: 'Prénom',
                      value: null,
                      onChange: 'onChange'
                  }),

                  TextField({
                      labelText: 'Numéro de téléphone',
                      value: null,
                      onChange: 'onChange'
                  }),

                  Button('Enregistrer mes informations', {
                      onTap: 'functionName',
                      color: 'green',
                  })

              ])

            )

        ])

    ])
  )
}

fn onChange(value) {
  console.log("Text field changed: " + value)
}

fn counterBuilder() {
  return Text("Count: " + counter.value, {
      fontSize: 48,
      fontWeight: "bold",
      color: "#333"
  })
}

fn onIncrement() {
  counter.set(counter.value + 1)
}

fn onDecrement() {
  counter.set(counter.value - 1)
}
