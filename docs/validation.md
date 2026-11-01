# Procedura di collaudo e accettazione

[Indice](../README.md) | [Creazione](runbook.md) | [DNS](customer-dns.md)

Completare la [procedura di creazione](runbook.md) prima del collaudo.
Eseguire i test sull'ambiente da accettare e compilare il verbale.
Non usare risultati di altri ambienti come evidenza.

## Preparare il collaudo

1. Concordare finestra, responsabili, target e operazioni autorizzate.
2. Predisporre un client privato per portale, Logs, Workbook e storage,
   e un client esterno per la prova di accesso pubblico.
3. Verificare permessi operatore, UAMI runtime e Storage Blob Data Reader
   per l'identita' che esegue le letture storage.
4. Sincronizzare gli orologi e registrare i timestamp in UTC.
5. Predisporre il ripristino prima di provocare un guasto.
   Usare solo risorse di laboratorio dedicate o un change aziendale approvato.
6. Conservare le evidenze nel perimetro autorizzato.
   Non pubblicare endpoint reali, credenziali o log aziendali nella repository.
7. Compilare una riga del verbale per ciascun test:

| Test | UTC | Risorsa e origine | Atteso | Ottenuto | Run/request ID ed evidenze | Esito | Responsabile |
|---|---|---|---|---|---|---|---|
| Da compilare | Da compilare | Da compilare | Da compilare | Da compilare | Da compilare | PASS/FAIL/INCOMPLETO | Da compilare |

Assegnare PASS solo con tutte le evidenze richieste.
Assegnare FAIL se il risultato contraddice il criterio di accettazione.
Assegnare INCOMPLETO se la prova o le evidenze non consentono una conclusione.

## 1. Matrice minima

| Test | Origine | Accettazione |
|---|---|---|
| Hosting | Control plane + host | ASE interno, piano Windows Isolated v2, host operativo |
| Storage control plane | Client autorizzato | Public Disabled, Shared Key false, Deny/None, PE Approved |
| Storage privato | Client privato e runtime | IP esatti PE, HTTPS e accesso OAuth autorizzato |
| Persistenza runtime | Logic App | Run Stateful memorizzate, leggibili anche dopo restart |
| DNS storage | Worker ASE + DNS log | Query/risposte dal worker verso DNS concordato, IP PE |
| DNS target | Workflow + DNS log | Nomi risolti dal runtime attraverso DNS cliente |
| Stato nominale | Workflow | Entrambe le azioni 200 in almeno tre cicli consecutivi |
| Ingestion/query | Runtime + client privato | Dati Insights e Workbook accessibili privatamente |
| Fault servizio | Workflow | B Failed e A Healthy, senza dipendenza seriale |
| Fault DNS | Workflow + log DNS | B errore DNS, A continua, nessun falso Healthy |
| Recovery | Workflow | B torna Healthy con evidenza nuova |
| Runtime fermo/dati stale | Workbook | Unknown, non Healthy |
| Denial esterno autenticato | Client senza routing privato | Accesso Blob negato per rete con identita' altrimenti autorizzata |

Riservare almeno 15 minuti di finestra utile dopo l'avvio per osservare
tre cicli automatici, oltre al tempo di ingestion. Verificare i timestamp
delle run; non usare il solo refresh del Workbook per contare i cicli.

## 2. Controllo hosting e storage

**Dove operare:** portale Azure dal client privato; PowerShell sul client
amministrativo autenticato.

1. Verificare ASE Succeeded e VIP Internal.
2. Verificare piano Windows Isolated v2 associato all'ASE e Logic App Running.
3. Aprire il designer ed eseguire un workflow. Non accettare il solo stato Running.
4. Sostituire i parametri ed eseguire il controllo storage:

```powershell
$rg = '<rg>'
$storage = '<storage>'
az storage account show --resource-group $rg --name $storage --query "{public:publicNetworkAccess,sharedKey:allowSharedKeyAccess,anonymous:allowBlobPublicAccess,defaultAction:networkRuleSet.defaultAction,bypass:networkRuleSet.bypass,tls:minimumTlsVersion,https:enableHttpsTrafficOnly}" --output json
if ($LASTEXITCODE -ne 0) { throw 'Lettura proprieta storage fallita' }
```

5. Confrontare il risultato con i valori richiesti:

| Proprieta' | Valore richiesto |
|---|---|
| public | Disabled |
| sharedKey | false |
| anonymous | false |
| defaultAction | Deny |
| bypass | None |
| tls | TLS1_2 |
| https | true |

6. Verificare assenza di eccezioni IP non approvate e tre PE Approved.
7. Verificare UAMI, cinque `AzureWebJobsStorage__...`, assenza della connection
   string `AzureWebJobsStorage` e assenza di credenziali content-share.
8. Confrontare i quattro ruoli e gli scope con la
   [configurazione identity](runbook.md#6-identita-e-piano).
9. Ripetere il controllo prima e dopo i test. Verificare Activity Log e
   policy per rilevare modifiche durante la finestra.
10. Registrare solo le proprieta' necessarie. Non recuperare account key
    o esportare tutte le variabili dell'app.

**Accettazione:** hosting richiesto, workflow eseguibile e tutti i valori
storage/identity conformi prima e dopo il collaudo.

## 3. DNS e runtime storage, non soltanto la VM

### 3.1. Verificare il percorso del client privato

**Dove operare:** client con routing privato, usando l'identita' operatore
autorizzata sullo storage.

1. Risolvere Blob/Queue/Table e confrontare ciascun indirizzo con la NIC del PE.
2. Verificare TCP 443.
3. Verificare l'assegnazione Storage Blob Data Reader all'operatore.
4. Sostituire il nome storage ed eseguire una lettura OAuth:

```powershell
az storage container list --account-name '<storage>' --auth-mode login --output table
if ($LASTEXITCODE -ne 0) { throw 'Lettura storage privata con OAuth fallita' }
```

5. Registrare identita', origine, UTC e risultato.
   Non considerare questa lettura una prova della UAMI runtime.
6. Non assegnare PASS al solo TCP riuscito o a una risposta 403.

**Accettazione:** IP esatti dei PE, HTTPS raggiungibile e lettura OAuth riuscita.

### 3.2. Verificare il runtime e la persistenza

**Dove operare:** run history Logic App e log DNS autorizzati.

1. Eseguire tre run Stateful e verificare input/output salvati di entrambe le azioni.
2. Verificare Shared Key false per tutta la finestra e host storage configurato
   esclusivamente con managed identity.
3. Correlare startup/run con risoluzioni Blob/Queue/Table dai worker ASE
   sui DNS concordati e gli IP del PE.
4. Riavviare una volta l'app nella finestra di manutenzione e verificare
   che le run precedenti siano ancora consultabili e ne vengano scritte di nuove.
5. Per ulteriori log storage, ottenere prima l'approvazione all'ingestion
   e ai relativi costi. Cercare object ID della UAMI, autenticazione OAuth
   e richieste riuscite nei servizi interessati.
6. Se mancano query a causa della cache, eseguire la
   [prova DNS controllata](customer-dns.md#5-dimostrare-che-il-runtime-usa-quei-dns).
7. Registrare separatamente il risultato runtime e quello del client privato.
   Non usare il solo accesso CLI dalla VM per accettare lo storage host.

**Accettazione:** run persistite prima e dopo restart, nuove run scritte,
Shared Key disabilitata e risoluzioni correlate verso i PE.

## 4. Guasti e ripristino

Ottenere l'autorizzazione ai guasti e predisporre il ripristino.
Non fermare servizi o modificare DNS aziendali senza change approvato.

### Guasto HTTP del solo B

**Dove operare:** PowerShell amministratore sulla VM IIS dedicata;
run history e Workbook dal client privato.

1. Verificare una run nominale con A e B a HTTP 200.
2. Annotare UTC e fermare soltanto il sito B:

```powershell
Import-Module WebAdministration
Stop-Website -Name service-b
```

3. Eseguire una run e registrare esiti di entrambe le azioni.
   Verificare B Failed/non 200 e A ancora HTTP 200.
4. Registrare il codice effettivo IIS; non imporre 503 come unico esito di guasto.
5. Ripristinare B anche se il controllo fallisce:

```powershell
Start-Website -Name service-b
```

6. Annotare UTC di ripristino ed eseguire o attendere una nuova run.
7. Verificare B HTTP 200, A HTTP 200 e nuovo campione Healthy.

**Accettazione:** guasto del solo B rilevato, A operativo e nuova evidenza
di recovery. Non accettare il solo sito nuovamente avviato.

### Guasto DNS del solo B

**Dove operare:** DNS Manager sul server dedicato o con il responsabile DNS;
workflow, log DNS e Workbook dal client privato.

1. Salvare record e TTL di `svc-b.health.poc.internal`.
2. Annotare UTC e rimuovere soltanto quel record.
3. Verificare NXDOMAIN. Attendere le cache positive/negative secondo TTL
   oppure usare un alias di laboratorio nuovo, concordato e configurato
   nell'azione B, registrando la modifica.
4. Eseguire una run. Cercare la query dalla subnet/proxy ASE e l'errore DNS di B.
5. Verificare che A continui a funzionare e che B non risulti Healthy.
6. Ripristinare record, TTL ed eventuale URI originale dell'azione B,
   anche in caso di errore del test.
7. Attendere la scadenza della cache negativa e verificare una nuova run:
   DNS corretto, HTTP 200 e nuovo campione Healthy.
8. Non modificare record storage o ASE durante questa prova.

**Accettazione:** errore DNS del solo B correlato al runtime e successivo
ripristino con nuove evidenze, senza interrompere l'host.

### Runtime fermo o pipeline senza dati

**Dove operare:** portale Logic App e Workbook dal client privato.

1. Verificare una run Healthy e il relativo campione.
2. Impostare nel Workbook un time range superiore alla soglia di freshness.
3. Annotare UTC e fermare l'app di laboratorio.
4. Attendere oltre la soglia, 15 minuti nell'esempio KQL.
5. Verificare Unknown; non mantenere Healthy dal campione precedente.
6. Riavviare l'app anche se il test fallisce.
7. Verificare nuova run, nuovo campione e ritorno allo stato corretto.

**Accettazione:** dati stale classificati Unknown e stato aggiornato dopo
il riavvio. Non interpretare Unknown come prova della salute o del guasto
del target.

## 5. Telemetria e Workbook

### 5.1. Verificare lo schema e l'ingestion

**Dove operare:** Logs del workspace dal client privato.

1. Selezionare il workspace collegato a Insights.
2. Sostituire il resource ID ed eseguire la query di scoperta per
   AppRequests con enhanced telemetry v2:

```kusto
AppRequests
| where TimeGenerated > ago(1h)
| where _ResourceId =~ "<resource-id-application-insights>"
| project TimeGenerated, Name, Success, Properties
| take 30
```

3. Verificare Category, workflowName, actionName, trackedProperties e
   campo di correlazione run nei dati ricevuti.
4. Se tabella o proprieta' differiscono, adattare le query allo schema osservato.
   Mantenere il contesto workspace; non usare nomi di colonne di un altro contesto.
5. Se non arrivano campioni, verificare scope, permessi, impostazioni
   telemetry, log host e DNS Monitor prima di proseguire.
   Registrare INCOMPLETO; non interpretare una tabella vuota come assenza di guasti.

### 5.2. Verificare i campioni delle azioni

1. Confermare lo schema nella sezione 5.1.
2. Sostituire il resource ID e, se necessario, i nomi di workflow, azioni e servizi.
3. Eseguire la query:

```kusto
AppRequests
| where TimeGenerated > ago(1h)
| where _ResourceId =~ "<resource-id-application-insights>"
| where tostring(Properties.Category) == "Workflow.Operations.Actions"
| where tostring(Properties.workflowName) == "availability"
| where tostring(Properties.actionName) in ("Check_Service_A", "Check_Service_B")
| extend tracked = todynamic(Properties.trackedProperties)
| extend service = tostring(tracked.service), httpStatus = toint(tracked.httpStatus)
| where service in ("service-a", "service-b")
| extend state = case(
    Success == false, "Failed",
    isnull(Success) or isnull(httpStatus), "Unknown",
    Success == true and httpStatus == 200, "Healthy",
    "Failed")
| project TimeGenerated, service, httpStatus, Success, state, Properties
| order by TimeGenerated desc
```

4. Confrontare i campioni con le azioni della run history.
5. Verificare Failed per un'azione fallita, anche senza status HTTP.
   Per un esito non verificabile mantenere Unknown.
6. Non inserire body, header o credenziali nelle tracked properties.

### 5.3. Verificare stato corrente e freshness

1. Sostituire il resource ID e aggiornare la lista dei servizi attesi.
2. Per il laboratorio mantenere un time range di almeno un'ora e soglia
   di freshness di 15 minuti.
3. Eseguire la query di stato:

```kusto
let expected = datatable(service:string)["service-a", "service-b"];
let latest =
    AppRequests
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ "<resource-id-application-insights>"
    | where tostring(Properties.Category) == "Workflow.Operations.Actions"
    | where tostring(Properties.workflowName) == "availability"
    | where tostring(Properties.actionName) in ("Check_Service_A", "Check_Service_B")
    | extend tracked = todynamic(Properties.trackedProperties)
    | extend service = tostring(tracked.service), httpStatus = toint(tracked.httpStatus)
    | where service in ("service-a", "service-b")
    | extend sampleState = case(
        Success == false, "Failed",
        isnull(Success) or isnull(httpStatus), "Unknown",
        Success == true and httpStatus == 200, "Healthy",
        "Failed")
    | summarize arg_max(TimeGenerated, httpStatus, sampleState) by service
    | project service, observedAt = TimeGenerated, httpStatus, sampleState;
expected
| join kind=leftouter latest on service
| extend state = case(
    isnull(observedAt), "Unknown",
    observedAt < ago(15m), "Unknown",
    sampleState)
| project service, observedAt, httpStatus, state
| order by service asc
```

4. Verificare campioni sani, HTTP fallito, DNS fallito, assenza di dati e recovery.
5. Confermare Unknown per servizi senza campioni o con campioni stale.
6. Salvare il Workbook e riaprirlo dalla rete privata con un'identita'
   operatore di sola lettura.

**Accettazione:** campioni reali correlati alle run, stati corretti,
freshness applicata e accesso privato con permessi di sola lettura.

## 6. Negare lo storage da Internet con una prova valida

**Dove operare:** PowerShell 7 su un client esterno alla rete privata,
senza VPN, route o proxy privato.

1. Mantenere lo storage privato; non aprirlo per la prova.
2. Verificare Storage Blob Data Reader per l'identita' operatore sullo storage.
3. Eseguire prima la lettura privata della sezione 3.1 con la stessa identita'.
4. Verificare che il client esterno usi una risoluzione pubblica del FQDN,
   senza percorso DNS privato. In caso di NXDOMAIN correggere il percorso
   del client di prova, non la configurazione storage.
5. Verificare l'identita' Azure CLI e sostituire il nome storage.
6. Eseguire il comando con token OAuth storage, non ARM:

```powershell
$ErrorActionPreference = 'Stop'
$storage = '<storage>'
$token = az account get-access-token --resource https://storage.azure.com/ --query accessToken --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Impossibile ottenere il token storage del tester'
}
$headers = @{
    Authorization = "Bearer $token"
    'x-ms-version' = '2023-11-03'
    'x-ms-date' = [DateTime]::UtcNow.ToString('R')
}
try {
    $response = Invoke-WebRequest -Uri "https://$storage.blob.core.windows.net/?comp=list" -Headers $headers -SkipHttpErrorCheck
    if ($response.StatusCode -ne 403 -or $response.Content -notmatch '<Code>AuthorizationFailure</Code>') {
        throw "Esito non atteso: HTTP $($response.StatusCode); non provato il denial di rete"
    }
    $response.Headers['x-ms-request-id']
    'Denial esterno osservato: correlare request ID, identita e configurazione di rete'
}
finally {
    $token = $null
    $headers = $null
}
```

7. Registrare origine/IP, UTC, request ID, status e codice errore.
   Allegare la lettura privata riuscita con la stessa identita' e i valori
   control-plane della sezione 2.
8. Non stampare token o header Authorization e non salvarli su file.
9. Non assegnare PASS a AuthenticationFailed, token scaduto, ruolo mancante,
   AuthorizationPermissionMismatch, chiamata anonima, timeout o NXDOMAIN.
10. Se il 403 resta ambiguo, correlare i log storage autorizzati e registrare
    INCOMPLETO.

**Accettazione:** lettura OAuth privata riuscita e percorso pubblico
negato con HTTP 403/AuthorizationFailure per l'identita' autorizzata,
con configurazione di rete ed evidenze coerenti.

### Limiti Bastion e DNS del client esterno

1. Preferire due client con la stessa identita': uno privato e uno esterno.
2. Se occorre un solo client, ottenere l'approvazione per un relay TCP
   temporaneo sulla VM di laboratorio, il tunnel e la relativa rimozione.
3. Usare Bastion Standard con target resource ID della VM e porta dedicata.
   Non usare IP connect direttamente verso Blob PE443: consente solo 22/3389.
4. Limitare NSG e firewall alla porta dedicata dalla sola subnet Bastion.
5. Inoltrare al Blob PE effettivo senza terminare TLS.
   Mantenere hostname, SNI e validazione del certificato originali;
   conservare il bearer solo in memoria sul client.
6. Per la prova esterna usare un client senza percorso DNS privato oppure
   una risoluzione pubblica esplicita limitata alla prova, preservando TLS.
7. Non modificare DNS VNet/app o file hosts per ottenere il risultato atteso.
8. Rimuovere tunnel, relay e sole regole temporanee autorizzate.
   Verificare la rimozione senza alterare RDP o risorse condivise.

## 7. Diagnosi e sign-off

1. Per ogni FAIL o INCOMPLETO identificare il livello da correggere:

| Sintomo | Prima verifica |
|---|---|
| ASE/piano non allocabile | Quote e capacita' esatta della regione/SKU |
| Designer/SCM irraggiungibile | Client privato, VIP, record app/SCM, route/NSG |
| Storage risolve pubblico/NXDOMAIN | Zone/link, forwarder della zona pubblica, VNet del resolver |
| Host non scrive run | UAMI, cinque settings, quattro ruoli, propagation, PE |
| HTTP timeout con DNS corretto | Porta, route, firewall/NSG, health endpoint |
| Run presente ma Workbook vuoto | Telemetry v2, scope/schema, auth Insights, AMPLS/DNS |
| Ultimo Healthy resta dopo stop | Query freshness, servizi attesi e time range |

2. Registrare causa, responsabile e azione correttiva.
   Non usare Shared Key, storage pubblico, egress indiscriminato o Basic Auth SCM.
3. Ripetere il test dopo la correzione e aggiornare il verbale.
4. Verificare tutti i test essenziali PASS, evidenze runtime e recovery.
5. Allegare run nominali, log DNS correlati, configurazione storage/identity,
   guasto B con A operativo, ripristino, Workbook e denial esterno autenticato.
6. Ripristinare i componenti, disabilitare logging temporaneo e verificare
   la rimozione dei soli strumenti di test autorizzati.
7. Ottenere il sign-off dai responsabili applicazione, rete e sicurezza.
   Se rimangono test FAIL o INCOMPLETI, registrare "parzialmente verificata",
   motivi e attivita' richieste; non dichiarare completata l'accettazione.
