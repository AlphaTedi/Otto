# Otto website

Sito statico: HTML, CSS e un solo file JS. Nessuna build, nessuna dipendenza.

## Avvio in locale

```bash
cd website
python3 -m http.server 8000
```

Apri http://localhost:8000. (Alternativa: `npx serve`.)

## Dove si modifica cosa

| Cosa | Dove |
|---|---|
| Testi e sezioni | `index.html` |
| Colori, font, spaziature, mockup | `css/site.css` (variabili in `:root`) |
| Pannello di Otto (hero interattivo e anteprime nei box) | `js/otto-ui.js` + `css/otto-ui.css` |
| Avvio dell'hero, interruttore layout, occhi del footer | `js/site.js` |
| Privacy policy | `privacy.html` (copia di `docs/privacy.html`, stesso testo) |
| Link di download | cerca `releases/latest` in `index.html` |
| Tip jar | cerca `YOUR_HANDLE` in `index.html` |
| Changelog | sezione `#new` di `index.html` (una `div.entry` per voce) |

## Commenti sul sito (Agentation, solo in locale)

Su `localhost` compare in basso a destra il toolbar di [Agentation](https://agentation.com). Attivalo, clicca un elemento, scrivi il commento; poi **Copy** e incolla il testo in chat a Claude (contiene selettori e posizione). I commenti restano salvati nel browser.

- Si carica solo se l'host è `localhost` / `127.0.0.1` (vedi inizio di `js/site.js`): sul dominio non parte.
- Il bundle è `dev/agentation.js` (React + Agentation 3.1.2). Prima del deploy puoi escludere la cartella `dev/`.
- Licenza di Agentation: PolyForm Shield 1.0.0, va bene per uso di sviluppo.

## Prima di pubblicare

Vedi `PLAN.md`, sezione 8: placeholder, affermazioni da verificare e la nota su `privacy.html`, che deve restare raggiungibile allo stesso percorso.
