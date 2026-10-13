# ChatOllamaWeb

Chat con i modelli di [Ollama](https://ollama.com) come pagina web, in locale sul tuo PC e raggiungibile dagli altri dispositivi della rete di casa. Un solo file Python, senza framework: il server usa la libreria standard (`http.server`) e la pagina è incorporata nello script.

## Contenuto del repository

| File | Cosa è |
|---|---|
| `chat_ollama_web.py` | Lo script della chat (versione più recente, con lettore playlist YouTube, **senza** avvio automatico). |
| `installa_chat_ollama.ps1` | Installatore per Windows 11: Python, librerie, Ollama, modello, firewall, icona, avvio automatico. |
| `Installa_Chat_Ollama.bat` | Avvia l'installatore PowerShell aggirando il blocco dei criteri di esecuzione. |
| `ChatOllama_installer.zip` | Pacchetto pronto (bat + ps1 + script con YouTube e avvio automatico). Da usare quando il browser non lascia scaricare `.bat`/`.ps1` singoli. |

## Funzionalità

- **Chat con i modelli di Ollama**, scelti dalla pagina; risposte in streaming con pulsante di stop.
- **Chat salvate** nella cartella `chats/` (compatibili con `chat_ollama.py`), con ricerca, rinomina ed eliminazione.
- **Modifica, elimina e rispondi** sui singoli messaggi: modifica di una domanda, eliminazione di domande e risposte, "Rispondi" sull'ultima domanda rimasta senza risposta.
- **Ricerca web** (DuckDuckGo tramite `ddgs`) con lettura delle prime pagine trovate, e **lettura/riassunto di pagine** web e PDF da un indirizzo.
- **Ricerca video YouTube** ("cercami un video su …"): schede con miniatura e sottotitoli dei primi video per capirne il contenuto.
- **Lettore playlist YouTube** (pulsante ♫): suona la playlist impostata brano per brano, salta quelli non riproducibili fuori da YouTube, abbassa il volume mentre "Leggi a voce" parla.
- **Allegati**: immagini (per i modelli con visione), file di testo, documenti Word/Excel/PDF.
- **Agente sul PC** con strumenti: crea/leggi/elenca file, legge/crea/modifica documenti Word ed Excel, esegue script e comandi di terminale, spegne/riavvia il PC. I file si gestiscono solo dentro `agente_files/` e **ogni azione rischiosa chiede conferma** con un riquadro nella pagina. Le azioni vengono registrate in `log_azioni.txt`.
- **Voce**: dettatura con il microfono e lettura ad alta voce delle risposte (voci del browser).
- **Esportazione** della chat in Markdown o Word (`.docx`); PDF tramite la stampa del browser.
- **Tema chiaro/scuro** e **Impostazioni** dalla pagina (salvate in `impostazioni.json`).
- **Accesso dalla rete**, con codice di accesso facoltativo, e HTTPS con certificato autofirmato (serve al microfono su Chrome).

## Requisiti

- **Python 3.10 o superiore** (l'installatore mette la 3.12).
- **Ollama 0.12.7 o superiore** (serve per i modelli `qwen3-vl`), in esecuzione.
- Un modello con supporto **tools** (per l'agente) e possibilmente **vision** (per le immagini).
- Librerie Python:

  ```
  pip install requests ddgs pypdf python-docx openpyxl cryptography youtube-transcript-api
  ```

  `requests` e `ddgs` si installano da sole al primo avvio se mancano; `youtube-transcript-api` viene installata la prima volta che serve. Le altre servono per PDF, Word, Excel e HTTPS.

## Installazione su Windows 11 (consigliata)

1. Scarica `ChatOllama_installer.zip` ed estrailo in una cartella.
2. Fai doppio clic su `Installa_Chat_Ollama.bat` (chiede i permessi di amministratore).
3. L'installatore esegue 7 passi:
   1. Python (lo installa se manca e lo aggiunge al PATH di sistema);
   2. librerie Python;
   3. Ollama (lo installa o aggiorna se più vecchio di 0.12.7);
   4. modello in base alla RAM, con riserve se il download non riesce:

      | RAM | Modello | Riserve |
      |---|---|---|
      | 8 GB | `qwen3-vl:4b` | `ministral-3:3b`, `qwen3-vl:2b` |
      | 16 GB | `qwen3-vl:8b` | `ministral-3:8b`, `qwen3-vl:4b` |
      | 32 GB | `qwen3-vl:30b` | `mistral-small3.2:24b`, `qwen3-vl:8b` |

   5. prepara lo script impostando `OLLAMA_URL` su `127.0.0.1` e `INDIRIZZO` sull'IP del PC;
   6. regole del firewall (porte 8765-8774) e icona sul desktop;
   7. avvio automatico con Windows (attività pianificata "Chat Ollama").

## Avvio manuale

```
python chat_ollama_web.py
```

Il browser si apre da solo. Nel terminale vengono mostrati l'indirizzo locale, quello di rete e l'eventuale codice di accesso. Per chiudere: Ctrl+C.

## Configurazione

Le impostazioni principali sono costanti in cima a `chat_ollama_web.py`:

| Costante | Predefinito | Significato |
|---|---|---|
| `OLLAMA_URL` | `http://192.168.50.2:11434` | Indirizzo del server Ollama. Se Ollama è sullo stesso PC usa `http://127.0.0.1:11434`. |
| `INDIRIZZO` | `192.168.50.2` | IP su cui ascolta la pagina. `127.0.0.1` = solo questo PC. Se non è un IP del PC, lo script ripiega su `127.0.0.1`. |
| `PORTA` | `8765` | Porta della pagina web. |
| `HTTPS_RETE` | `True` | Usa HTTPS sull'indirizzo di rete (certificato autofirmato in `certificato/`). La prima volta il browser avvisa: "Avanzate" > "Procedi". |
| `CODICE_ACCESSO` | `""` | Codice chiesto ai dispositivi della rete. Vuoto = nessun codice: la pagina non lo chiede. |
| `RICHIEDI_ADMIN` | `False` | `True` = a ogni avvio chiede i permessi di amministratore (servono solo per i comandi di sistema). |
| `CONTESTO` | `16384` | Token di contesto chiesti a Ollama (più alto = più RAM/VRAM). |
| `TEMPERATURA` | `None` | `None` = valore del modello (0-2). |
| `KEEP_ALIVE` | `""` | Quanto tenere il modello in memoria dopo l'uso. |
| `RISULTATI_RICERCA` | `5` | Risultati chiesti al motore di ricerca. |
| `PAGINE_DA_LEGGERE` | `3` | Pagine aperte e lette dopo una ricerca (0 = solo anteprime). |
| `PLAYLIST_YOUTUBE` | `""` | Link della playlist per il pulsante ♫. |

Contesto, temperatura, keep alive, istruzioni extra, parametri di ricerca e playlist si cambiano anche dalla pagina (**Impostazioni**) e vengono salvati in `impostazioni.json`.

## File creati durante l'uso

Lo script crea accanto a sé: `chats/` (conversazioni), `agente_files/` (cartella di lavoro dell'agente), `certificato/` (HTTPS), `impostazioni.json` e `log_azioni.txt`. Sono esclusi dal repository tramite `.gitignore`.

## Sicurezza

- La pagina è raggiungibile da tutti i dispositivi della rete: usala solo su una rete di cui ti fidi.
- Se imposti un codice di accesso, dopo troppi tentativi sbagliati l'accesso viene bloccato per un po'. Senza codice chiunque sia sulla tua rete può usare la chat.
- Il testo delle pagine web viene passato al modello con l'avviso di ignorare eventuali istruzioni che contiene.
- Comandi, script e spegnimento del PC vengono eseguiti solo dopo la conferma nella pagina.
