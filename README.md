# Manuale operativo: Logic Apps Standard con storage privato e DNS aziendale

## 1. Preparare parametri e autorizzazioni

1. Identificare tenant, subscription e responsabili rete, sicurezza e applicazione.
2. Compilare il [foglio parametri](docs/runbook.md#0-compilare-il-foglio-parametri-e-approvare-la-spesa)
   con nomi, regioni, subnet, DNS, endpoint, identita' e percorso amministrativo.
3. Verificare SKU, quote, policy ereditate e connettivita' nella subscription.
4. Ottenere l'approvazione per configurazione, durata e budget prima di
   creare risorse a pagamento, compreso ASE.
5. Predisporre il client privato, Azure CLI e PowerShell indicati nel runbook.
6. Usare un resource group dedicato e nomi nuovi.
   Verificare che IP e domini assegnati non si sovrappongano a reti e zone esistenti.

## 2. Eseguire le procedure

Seguire le fasi della tabella. Durante la fase 2, completare la
configurazione DNS nei punti richiamati dal runbook, prima di avviare il runtime.

| Fase | Capitolo | Attivita' da completare |
|---|---|---|
| 1 | [Architettura](docs/architecture.md) | Compilare piano di rete, risorse, DNS e matrice delle porte; approvare il progetto |
| 2 | [Creazione](docs/runbook.md) | Verificare prerequisiti e autorizzazioni; creare risorse, identita', workflow e monitoraggio |
| 2, nei passaggi DNS | [DNS](docs/customer-dns.md) | Configurare resolver, zone e forwarding; verificare la risoluzione privata |
| 3 | [Collaudo](docs/validation.md) | Eseguire i test e registrare evidenze, guasti, ripristino e criteri di accettazione |

Eseguire i comandi soltanto nei terminali indicati, dopo aver sostituito i
parametri di esempio. Se una verifica fallisce, interrompere la procedura
e correggere la causa prima di proseguire.

## 3. Mantenere i vincoli di configurazione

1. Usare Logic Apps Standard su ASE v3 interno e piano Windows Isolated v2.
   Non sostituire il piano con WS1.
2. Mantenere lo storage runtime privato e Shared Key disabilitata dalla
   creazione. Configurare la user-assigned managed identity dello storage
   host seguendo la [procedura ARM](docs/runbook.md#7-logic-app-e-autenticazione-dello-storage-host).
3. Usare i resolver aziendali oppure il simulatore dedicato al laboratorio.
   Verificare la risoluzione dal runtime.
4. Configurare due controlli HTTP privati indipendenti ogni cinque minuti
   e consultare gli esiti tramite Application Insights e Workbook.
5. Non aggiungere Function App separate, SQL o codice custom di telemetria.
6. Non usare eccezioni di policy, storage pubblico o Basic Auth per aggirare errori.
7. Conservare parametri compilati ed evidenze nel perimetro autorizzato.
   Non pubblicare password, token, chiavi, endpoint reali o log aziendali.

## 4. Completare l'accettazione

1. Verificare runtime, persistenza, DNS, storage privato/keyless e accesso
   OAuth privato riuscito con percorso pubblico negato.
2. Verificare dati reali Application Insights, stati del Workbook,
   guasti controllati e nuove evidenze dopo il ripristino.
3. In assenza di dati o con campioni stale, mantenere Unknown.
   Non dichiarare Healthy o accettato un monitoraggio senza evidenze.
4. Compilare il verbale e ottenere l'approvazione dei responsabili.
   Per test FAIL o INCOMPLETI registrare causa e azioni richieste.

## Riferimento tecnico

Consultare la [guida Microsoft per managed identity e storage del runtime](https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account)
per verificare requisiti e configurazione del modello ASE.
