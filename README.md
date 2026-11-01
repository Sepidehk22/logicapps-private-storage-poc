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

## Deployment con template ARM

Per automatizzare la creazione con **DNS aziendale esistente**, seguire la
[procedura ARM](docs/runbook.md#12-deployment-con-template-arm).

1. Scaricare [fondazione](infra/foundation.json) e
   [applicazione](infra/application.json), con i relativi parametri di
   esempio: [fondazione](infra/foundation.parameters.example.json) e
   [applicazione](infra/application.parameters.example.json).
2. Compilare copie locali dei parametri; non pubblicare valori aziendali.
3. Preparare prima la rete con `deployAse=false`, configurare routing e DNS,
   quindi creare ASE con `deployAse=true`.
4. Dopo ASE Ready, usare dominio e VIP effettivi per il template applicazione.
5. Eseguire validazione ARM e what-if nella subscription di destinazione
   prima di ogni passaggio.
6. Distribuire il [codice availability](logicapp/availability/workflow.json)
   seguendo la [procedura di pubblicazione](docs/runbook.md#13-pubblicare-il-workflow-availability).
   Configurare Workbook e collaudare.

Usare questi template solo per risorse dedicate in un nuovo resource group
su Azure pubblico. Non includono VM, Bastion, gateway, peering, password,
workflow o Workbook. Non modificano policy o DNS server aziendali; i link
alle VNet dei resolver richiedono approvazione e permessi.
Non usare questi template per aggiornare un'app esistente: le impostazioni
applicative vengono definite integralmente dal template.

I sorgenti [foundation.bicep](infra/foundation.bicep) e
[application.bicep](infra/application.bicep) permettono di rigenerare i JSON.
Verificare deployment e funzionamento nella subscription di destinazione:
la compilazione non certifica capacita', connettivita' o ingestion della telemetria.

## Codice del controllo availability

1. Configurare gli URL dei due servizi nelle app settings
   `AVAILABILITY_SERVICE_A_URL` e `AVAILABILITY_SERVICE_B_URL`.
   Con ARM compilare `serviceAUrl` e `serviceBUrl` nei parametri applicazione.
2. Usare i sorgenti [workflow.json](logicapp/availability/workflow.json),
   [host.json](logicapp/host.json) e [parameters.json](logicapp/parameters.json).
   Mantenere gli URL fuori dal codice condiviso e non inserirvi credenziali.
3. Eseguire lo [script di pubblicazione](scripts/Publish-Availability.ps1)
   dal client privato con Entra, seguendo il runbook.
4. Verificare tre run automatiche, entrambi gli esiti HTTP, persistenza,
   telemetria, guasti e ripristino secondo il collaudo.

Il workflow esegue due GET indipendenti ogni cinque minuti, senza retry.
Per il laboratorio il timeout HTTP e' 30 secondi e Healthy richiede HTTP 200.
Non sostituisce un test del payload o un monitoraggio da punti esterni all'ASE.
