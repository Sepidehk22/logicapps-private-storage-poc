# Procedura di creazione e configurazione

[Indice](../README.md) | [Architettura](architecture.md) | [Prove](validation.md)

Eseguire le fasi nell'ordine indicato. Compilare i parametri prima di
utilizzare i comandi e completare la verifica di ogni fase prima di passare
alla successiva.

Se una verifica fallisce, interrompere la procedura e correggere la causa.
Non abilitare Shared Key, accesso pubblico allo storage o Basic Auth SCM
per aggirare un errore.

## 0. Compilare il foglio parametri e approvare la spesa

| Parametro | Valore da registrare |
|---|---|
| Tenant, subscription, resource group nuovo | Da compilare |
| Regione ASE e piano | Regione approvata; esempio Italy North |
| Nome ASE, piano I1v2 Windows e Logic App | Da compilare |
| VNet, subnet ASE/PE/DNS, route verso client | Da compilare |
| IP DNS primario/secondario e ownership delle zone | Da compilare |
| Storage nuovo, user-assigned identity | Da compilare |
| Workspace, Insights, AMPLS nuovi o esistenti | Da compilare |
| Host/URL service-a e service-b | Endpoint di laboratorio oppure aziendali |
| Client per portale/SCM e percorso amministrativo | Da compilare |
| Owner, scadenza, budget, autorizzazione creazione | Da compilare |

**Dove operare:** client amministrativo, prima della creazione.

1. Compilare tutte le righe del foglio parametri.
2. Verificare SKU, quote, policy e disponibilita' nella subscription scelta.
   Completare il preventivo per risorse, durata, rete, storage e Monitor.
3. Ottenere l'approvazione per configurazione, durata e spesa.
4. Verificare i permessi per creare risorse e assegnare ruoli.
5. Predisporre Azure CLI e PowerShell 7 sul client amministrativo.
   Eseguire i comandi DNS/IIS come amministratore sulla VM Windows,
   non sul client Azure CLI.
6. Autenticarsi e selezionare la subscription, sostituendo i parametri:

```powershell
az login --tenant '<tenant-id>' --output none
if ($LASTEXITCODE -ne 0) { throw 'Autenticazione Azure fallita' }
az account set --subscription '<subscription-id>'
if ($LASTEXITCODE -ne 0) { throw 'Selezione subscription fallita' }
az account show --query "{subscription:id,tenant:tenantId}" --output table
if ($LASTEXITCODE -ne 0) { throw 'Verifica contesto Azure fallita' }
```

7. Confrontare tenant e subscription restituiti con il foglio parametri.
8. Non salvare credenziali nella repository. Non usare transcript nelle
   sessioni che contengono segreti.

**Verifica prima di proseguire:** parametri completi, contesto Azure
corretto e approvazioni registrate.

## 1. Resource group, rete e accesso

**Dove operare:** portale Azure, dalla subscription selezionata.

1. Creare un RG dedicato con owner e data di scadenza.
2. Creare VNet e subnet del [piano di rete](architecture.md).
3. Lasciare vuota la subnet ASE e delegarla a
   `Microsoft.Web/hostingEnvironments`.
4. Predisporre NSG, route e collegamento del client amministrativo. Autorizzare
   TCP/UDP 53 verso i DNS e le porte dei servizi/PE.
5. Scegliere un client collegato via VPN/ExpressRoute oppure il browser di
   una VM privata amministrata tramite Bastion. Non assegnare IP pubblico alla VM.
6. Definire il percorso di egress approvato per portale, Entra e dipendenze
   platform. Non aggiungere automaticamente NAT, firewall o gateway.

7. Se si usa Bastion, aprire portale, SCM e designer dal browser della VM
   oppure da un client con routing privato. Non usare il browser del PC
   esterno presumendo che Bastion gli fornisca quel routing.
8. Verificare la connettivita' dal client scelto e il percorso di ritorno.
   Se manca il collegamento privato, interrompere e concordarlo con il team rete.

**Verifica prima di proseguire:** subnet ASE vuota e delegata, regole
approvate e client amministrativo con accesso privato.

## 2. Storage runtime privato

**Dove operare:** portale Azure; PowerShell 7 sul client amministrativo
per il comando di configurazione.

1. Creare uno StorageV2 dedicato. Per il laboratorio selezionare Standard_LRS.
2. Impostare HTTPS obbligatorio e TLS minimo 1.2.
3. Impostare Public network access su Disabled.
4. Disabilitare Allow storage account key access e accesso anonimo Blob.
5. Non abilitare bypass per trusted Microsoft services o accesso pubblico
   temporaneo per creazione e publishing.
6. Sostituire i parametri ed eseguire il comando per confermare Deny/None
   e le impostazioni di sicurezza:

```powershell
az storage account update --resource-group '<rg>' --name '<storage>' --public-network-access Disabled --default-action Deny --bypass None --allow-shared-key-access false --allow-blob-public-access false --https-only true --min-tls-version TLS1_2
if ($LASTEXITCODE -ne 0) { throw 'Configurazione storage fallita' }
```

7. Creare tre Private Endpoint nella subnet PE, uno per ciascun subresource:
   **blob**, **queue**, **table**.
8. Abilitare l'integrazione DNS e collegare le zone alla VNet del resolver:
   `privatelink.blob.core.windows.net`, `privatelink.queue.core.windows.net`,
   `privatelink.table.core.windows.net`.
9. Verificare lo stato Approved delle connessioni.
10. Registrare FQDN e IP privato di ciascun PE dalle configurazioni PE/NIC.
11. Non creare una share Azure Files per il runtime. Non copiare account
    key, SAS o `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`.
12. Rileggere le proprieta' effettive dopo la creazione e dopo l'applicazione
    delle policy, usando il [controllo storage](validation.md#2-controllo-hosting-e-storage).

**Verifica prima di proseguire:** Public Disabled, Shared Key false,
anonymous false, Deny/None, HTTPS/TLS richiesti e tre PE Approved.

## 3. Azure Monitor privato

**Dove operare:** portale Azure, sulle risorse Monitor approvate.

1. Prima di collegare zone o scope condivisi, ottenere l'approvazione
   all'impatto sulle altre applicazioni.
2. Creare workspace Log Analytics e Application Insights workspace-based,
   oppure ottenere approvazione per risorse aziendali esistenti.
3. Creare AMPLS e aggiungere **sia Insights sia il workspace** come scoped resources.
4. Impostare **PrivateOnly per ingestion e query**.
5. Creare il PE AMPLS con subresource `azuremonitor`, stato Approved.
6. Abilitare l'integrazione DNS e collegare le zone generate alla VNet.
   Riutilizzare la stessa zona Blob dello storage: non crearne una seconda.
7. Disabilitare ingestion e query pubbliche anche su Insights e workspace.
   Disabilitare local authentication su Insights per usare Entra ID.
8. Verificare DNS e raggiungibilita' dal client che consultara' log e Workbook.

9. Verificare le zone richieste usando i FQDN/IP effettivi del PE e la
   [documentazione DNS Monitor](https://learn.microsoft.com/azure/azure-monitor/fundamentals/private-link-configure).
   Includere normalmente `privatelink.monitor.azure.com`,
   `privatelink.oms.opinsights.azure.com`, `privatelink.ods.opinsights.azure.com`,
   `privatelink.agentsvc.azure-automation.net` e la zona Blob condivisa.
   Non usare un numero fisso di record o IP come criterio di verifica.

**Verifica prima di proseguire:** Insights e workspace inclusi in AMPLS,
PE Approved, accesso pubblico disabilitato, autenticazione Entra prevista
e risoluzione privata dal client autorizzato.

## 4. Preparare il DNS e i due target di esempio

**Dove operare:** portale Azure per la VM; PowerShell amministratore sulla
VM Windows per DNS e IIS.

1. Scegliere se usare componenti di laboratorio o servizi aziendali.
   Per servizi aziendali configurare
   [rete](architecture.md#5-definire-le-regole-di-rete) e
   [DNS](customer-dns.md#4-collegare-i-resolver-aziendali), registrare
   URL e contratto di salute e non eseguire i comandi IIS seguenti.
   Integrare i target nel workflow dopo la creazione dell'app, alla fase 9.
2. Per il laboratorio creare, dopo l'approvazione di disponibilita' e costi,
   una VM Windows Server privata nella subnet DNS/target.
   Assegnare IP privato statico sulla NIC Azure e non assegnare IP pubblico.
3. Se occorre una regione alternativa, seguire la
   [variante a due VNet](architecture.md).
   Nell'esempio Sweden Central usare DNS/IP `10.61.2.4` e completare peering,
   NSG e link delle zone prima del cambio DNS.
4. Installare DNS, forwarding e record seguendo la
   [procedura del simulatore Windows](customer-dns.md#2-simulatore-windows-in-azure).
5. Prima di eseguire i comandi IIS, sostituire subnet ASE e hostname con
   quelli del foglio parametri. Verificare che nomi dei siti e regole non
   siano gia' presenti.
6. Sulla VM dedicata installare IIS e creare i due siti:

```powershell
$ErrorActionPreference = 'Stop'
$installation = Install-WindowsFeature Web-Server -IncludeManagementTools
if (-not $installation.Success) { throw 'Installazione IIS fallita' }
Import-Module WebAdministration
New-Item -ItemType Directory -Path C:\inetpub\service-a -Force | Out-Null
New-Item -ItemType Directory -Path C:\inetpub\service-b -Force | Out-Null
Set-Content -Path C:\inetpub\service-a\index.html -Value 'service-a healthy'
Set-Content -Path C:\inetpub\service-b\index.html -Value 'service-b healthy'
New-Website -Name service-a -Port 80 -HostHeader svc-a.health.poc.internal -PhysicalPath C:\inetpub\service-a
New-Website -Name service-b -Port 80 -HostHeader svc-b.health.poc.internal -PhysicalPath C:\inetpub\service-b
Stop-Website -Name 'Default Web Site'
New-NetFirewallRule -DisplayName 'PoC HTTP from ASE' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80 -RemoteAddress 10.60.0.0/24
```

7. Verificare il successo di Install-WindowsFeature e l'avvio dei due siti.
8. Autorizzare anche il client di verifica su firewall/NSG e controllare
   HTTP 200 per entrambi gli URL.
9. Mantenere fermo Default Web Site e verificare il codice realmente
   restituito durante il guasto B. Non accettare risposte di fallback.
10. Limitare HTTP alla rete del laboratorio. Per servizi aziendali usare
    HTTPS e certificati attendibili, senza disabilitare la validazione TLS.
11. Non adottare una sola VM per DNS e target come soluzione HA di produzione.

**Verifica prima di proseguire:** DNS risponde, entrambi i target
restituiscono HTTP 200 e l'accesso alla VM resta privato.

## 5. Impostare il DNS VNet e creare ASE interno

**Dove operare:** portale Azure; client privato per le verifiche DNS.

1. Verificare i forwarder del [capitolo DNS](customer-dns.md), la risoluzione
   privata dello storage e la risoluzione dei target.
2. Impostare nelle proprieta' DNS della VNet gli IP del DNS cliente/simulatore.
   Riavviare o rinnovare i client che non hanno ancora applicato il cambio.
3. Creare **App Service Environment v3**, nella regione scelta, subnet ASE
   dedicata, **Internal** access/VIP. Non selezionare hosting esterno.
4. Attendere Provisioning Succeeded e acquisire il VIP interno e il
   **dominio effettivo** dalla risorsa ASE.
5. Configurare i record del dominio ASE, inclusi SCM, come descritto nel
   [capitolo DNS](customer-dns.md#3-dns-dellase-interno).
6. Dal client privato verificare i record della zona ASE verso quel VIP.
   Ripetere il controllo sui FQDN effettivi app/SCM dopo la fase 7.
7. Mantenere ASE sul DNS della VNet. Non aggiungere la VNet Integration
   prevista per un'app multitenant WS1.

**Verifica prima di proseguire:** ASE Provisioning Succeeded, VIP interno,
dominio registrato e zona DNS configurata. Verificare separatamente host e
storage nelle fasi successive.

## 6. Identita' e piano

**Dove operare:** portale Azure, Identity e Access control (IAM).

1. Creare una user-assigned managed identity.
2. Registrare separatamente resource ID, client ID e principal/object ID.
   Usare il resource ID per lo storage host e il client ID per
   l'autenticazione Insights.
3. Assegnare sul solo storage runtime i quattro ruoli richiesti:

| Ruolo | Scope |
|---|---|
| Storage Account Contributor | Storage runtime |
| Storage Blob Data Owner | Storage runtime |
| Storage Queue Data Contributor | Storage runtime |
| Storage Table Data Contributor | Storage runtime |

4. Non sostituire questi ruoli con Contributor generale e non allargare
   lo scope a resource group o subscription. Sottoporre eventuali
   modifiche al modello dei ruoli a valutazione e collaudo separati.
5. Assegnare alla stessa UAMI Monitoring Metrics Publisher su Insights.
6. Assegnare agli operatori, separatamente, i permessi per leggere log e
   Workbook, gestire Logic App e creare il Workbook secondo il modello RBAC
   approvato. Non usare l'identita' runtime come identita' operatore.
7. Attendere la propagazione RBAC e verificare le assegnazioni effettive.
8. Creare nell'ASE un App Service Plan Windows Isolated v2/I1v2:
   una istanza e senza zone redundancy per il laboratorio.
9. Verificare regione e hostingEnvironment del piano.
   Non usare WS1 o un piano multitenant.

**Verifica prima di proseguire:** ID della UAMI registrati, ruoli e scope
corretti, piano Windows I1v2 associato all'ASE.

## 7. Logic App e autenticazione dello storage host

**Dove operare:** PowerShell 7 con Azure CLI sul client amministrativo;
portale Azure dal client privato per la configurazione host.

### 7.1. Creare l'app via ARM

1. Confermare le verifiche delle fasi precedenti.
2. Compilare tutti i parametri del blocco seguente, inclusa la regione.
   Il blocco usa ASE, piano e UAMI nello stesso resource group dell'app.
   Se si usano risorse condivise in altri RG, sostituire i relativi resource
   ID con quelli effettivi prima dell'esecuzione.
3. Verificare che il nome app sia nuovo: la richiesta PUT non deve
   modificare un'app esistente.
4. Eseguire il blocco per creare Logic App Standard con UAMI e storage
   identity-based, e disabilitare Basic Auth SCM/FTP:

```powershell
$ErrorActionPreference = 'Stop'
$subscription = az account show --query id --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Contesto Azure non disponibile' }
$rg = '<rg>'
$appName = '<logic-app-nuova>'
$planName = '<piano-I1v2>'
$aseName = '<ase>'
$identityName = '<uami>'
$storageName = '<storage>'
$location = 'italynorth'
$prefix = "/subscriptions/$subscription/resourceGroups/$rg/providers"
$identityId = "$prefix/Microsoft.ManagedIdentity/userAssignedIdentities/$identityName"
$appId = "$prefix/Microsoft.Web/sites/$appName"
$body = @{
    location = $location
    kind = 'functionapp,workflowapp'
    identity = @{
        type = 'UserAssigned'
        userAssignedIdentities = @{ $identityId = @{} }
    }
    properties = @{
        serverFarmId = "$prefix/Microsoft.Web/serverfarms/$planName"
        hostingEnvironmentProfile = @{ id = "$prefix/Microsoft.Web/hostingEnvironments/$aseName" }
        httpsOnly = $true
        siteConfig = @{
            alwaysOn = $true
            use32BitWorkerProcess = $false
            minTlsVersion = '1.2'
            scmMinTlsVersion = '1.2'
            ftpsState = 'Disabled'
            cors = @{ allowedOrigins = @('https://portal.azure.com'); supportCredentials = $false }
            appSettings = @(
                @{ name = 'APP_KIND'; value = 'workflowApp' }
                @{ name = 'FUNCTIONS_EXTENSION_VERSION'; value = '~4' }
                @{ name = 'FUNCTIONS_WORKER_RUNTIME'; value = 'dotnet' }
                @{ name = 'AzureWebJobsStorage__managedIdentityResourceId'; value = $identityId }
                @{ name = 'AzureWebJobsStorage__credential'; value = 'managedIdentity' }
                @{ name = 'AzureWebJobsStorage__blobServiceUri'; value = "https://$storageName.blob.core.windows.net" }
                @{ name = 'AzureWebJobsStorage__queueServiceUri'; value = "https://$storageName.queue.core.windows.net" }
                @{ name = 'AzureWebJobsStorage__tableServiceUri'; value = "https://$storageName.table.core.windows.net" }
            )
        }
    }
}
$body | ConvertTo-Json -Depth 12 | Set-Content .\logicapp-create.json
az rest --method put --url "https://management.azure.com/$($appId.TrimStart('/'))?api-version=2024-11-01" --body '@.\logicapp-create.json' --output none
if ($LASTEXITCODE -ne 0) { throw 'Creazione ARM della Logic App fallita' }
@{ properties = @{ allow = $false } } | ConvertTo-Json | Set-Content .\publishing-policy.json
foreach ($policy in @('scm', 'ftp')) {
    az rest --method put --url "https://management.azure.com/$($appId.TrimStart('/'))/basicPublishingCredentialsPolicies/$policy`?api-version=2024-11-01" --body '@.\publishing-policy.json' --output none
    if ($LASTEXITCODE -ne 0) { throw "Disabilitazione Basic Auth $policy fallita" }
}
```

5. Verificare Logic App Standard con tipo ARM `functionapp,workflowapp`.
   Non creare un'ulteriore Function App o aggiungere codice Functions.
6. Mantenere il percorso app/SCM sul VIP interno ASE.
   Non disabilitare automaticamente il default endpoint dell'app.
7. Rimuovere i due JSON temporanei dopo la verifica; non pubblicare gli
   identificativi reali.
8. Se si usa il wizard del portale e questo richiede chiavi o share WS1,
   interrompere quel percorso e usare ARM senza cambiare hosting o privacy.

### 7.2. Configurare storage host e Insights

1. Nel portale fermare l'app.
2. Aprire Environment variables/App settings.
3. Confermare i cinque valori storage gia' impostati e aggiungere i due
   valori Insights seguenti:

| Nome | Valore |
|---|---|
| `AzureWebJobsStorage__managedIdentityResourceId` | Resource ID della UAMI |
| `AzureWebJobsStorage__credential` | `managedIdentity` |
| `AzureWebJobsStorage__blobServiceUri` | `https://<storage>.blob.core.windows.net` |
| `AzureWebJobsStorage__queueServiceUri` | `https://<storage>.queue.core.windows.net` |
| `AzureWebJobsStorage__tableServiceUri` | `https://<storage>.table.core.windows.net` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Connection string di Insights, non credenziale storage |
| `APPLICATIONINSIGHTS_AUTHENTICATION_STRING` | `Authorization=AAD;ClientId=<client-id-UAMI>` |

4. Usare i normali FQDN dei servizi, non IP o URL `privatelink`.
5. Mantenere obbligatoria l'autenticazione Entra per Insights.
   Usare la connection string per identificare la risorsa, non come
   alternativa all'autenticazione configurata.
6. Rimuovere l'eventuale `AzureWebJobsStorage` con connection string.
   Non aggiungere content-share WS1 o runtime scale monitoring.
7. Salvare, avviare l'app e verificare host e designer dal client privato.
8. Acquisire i FQDN effettivi app/SCM e verificarli verso il VIP ASE.
9. Registrare e correggere errori di host, DNS o autorizzazione.
   Non considerare il solo messaggio `"AzureWebjobsStorage" app setting is
   not present` una prova di guasto o di corretto funzionamento.

**Verifica prima di proseguire:** UAMI associata, cinque valori storage
corretti, assenza di credenziali Shared Key/content-share, Basic Auth
disabilitata e designer accessibile privatamente.

Riferimenti:
[storage managed identity](https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account),
[Entra per Insights](https://learn.microsoft.com/azure/azure-monitor/app/azure-ad-authentication).

## 8. Telemetria del runtime

**Dove operare:** Kudu/Advanced Tools dal client privato.

1. Aprire Advanced Tools > Go e autenticarsi con Entra.
   In caso di accesso negato, correggere permessi o connettivita';
   non abilitare Basic Auth.
2. Aprire `site\wwwroot\host.json`.
3. Conservare le impostazioni necessarie dell'app e integrare la
   configurazione seguente:

```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle.Workflows",
    "version": "[1, 2.00]"
  },
  "extensions": {
    "workflow": {
      "Settings": {
        "Runtime.ApplicationInsightTelemetryVersion": "v2",
        "Runtime.Backend.HttpOperation.RequestTimeout": "00:00:30"
      }
    }
  },
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": false
      }
    }
  }
}
```

4. Mantenere il runtime supportato per Logic Apps Standard.
   Non usare `host.json` version 2 come impostazione della versione host.
5. Per il laboratorio mantenere sampling disabilitato e timeout HTTP di
   30 secondi. Per la produzione concordare volume, costi, timeout e soglie.
6. Salvare e riavviare l'app.

**Verifica prima di proseguire:** `host.json` valido e host avviato.
Verificare l'ingestion con le run della fase 9 e prima del Workbook.

[Telemetria avanzata Microsoft](https://learn.microsoft.com/azure/logic-apps/enable-enhanced-telemetry-standard-workflows).

## 9. Workflow visuale dei controlli

**Dove operare:** designer Logic App dal client privato.

1. Creare un workflow **Stateful** chiamato `availability`.
2. Aggiungere trigger **Recurrence**, ogni **5 minuti**.
3. Aggiungere l'azione integrata **HTTP**, chiamarla `Check_Service_A`:
   metodo GET, URI `http://svc-a.health.poc.internal/index.html`.
4. Creare un **ramo parallelo dal trigger** con `Check_Service_B`:
   GET `http://svc-b.health.poc.internal/index.html`.
   Non metterlo dopo A: il fallimento A non deve impedire la prova B.
5. Nelle impostazioni di entrambe le azioni impostare Retry policy **None**
   per il laboratorio, mantenendo il limite host di 30 secondi della fase 8.
6. Aggiungere le tracked properties:

| Azione | Proprieta' | Valore/espressione |
|---|---|---|
| A | `service` | `service-a` |
| A | `httpStatus` | `outputs('Check_Service_A')?['statusCode']` |
| B | `service` | `service-b` |
| B | `httpStatus` | `outputs('Check_Service_B')?['statusCode']` |

7. Nell'editor Expression incollare senza `@`.
   Nella definizione JSON usare la forma
   `@outputs('Check_Service_A')?['statusCode']` e l'equivalente per B.
8. Se la UI non mostra Tracked properties, aggiungere `trackedProperties`
   alla singola azione nella vista Code del designer.
9. Mantenere status nullo in caso di DNS/timeout senza risposta HTTP.
   Non sostituirlo con 200.
10. Salvare, eseguire Run e verificare entrambe le azioni e la run history.
11. Attendere almeno tre cicli automatici consecutivi e registrare i run ID.
12. Per il laboratorio assegnare Healthy solo a HTTP 200.
    Per servizi aziendali applicare autenticazione, status e payload
    concordati nel contratto di salute.

**Verifica prima di proseguire:** run Stateful persistite, controlli
indipendenti e tre cicli automatici con entrambe le risposte HTTP 200.

## 10. Log e Workbook

**Dove operare:** Logs del workspace e Azure Monitor > Workbooks dal
client privato, con permessi operatore.

1. Eseguire la [scoperta dello schema](validation.md#5-telemetria-e-workbook).
2. Verificare l'arrivo di campioni corrispondenti alle run e alle due azioni.
   Se mancano dati, interrompere la configurazione del Workbook e correggere
   ingestion, autenticazione, DNS o schema. Non inserire dati simulati.
3. Adattare le query ai campi osservati.
4. Aprire Azure Monitor > Workbooks > New.
5. Selezionare Add query, sorgente Logs e workspace corretto.
6. Filtrare il solo Insights dell'ambiente tramite `_ResourceId`.
7. Incollare la query di stato dopo averne verificato lo schema.
8. Selezionare Grid con colonne service, observedAt, httpStatus, state.
9. Impostare Healthy verde, Failed rosso, Unknown grigio.
10. Aggiungere una query temporale con i campioni, mantenendo visibili gli
    errori; configurare auto-refresh coerente con il ritardo di ingestion.
11. Salvare nel resource group previsto e riaprire con un'identita' di
    sola lettura dalla rete privata.
12. Verificare che dati mancanti o stale producano Unknown, non Healthy.

**Verifica prima di proseguire:** campioni reali presenti, schema confermato,
Workbook salvato e accessibile privatamente, stati e freshness corretti.

## 11. Completare il collaudo

1. Eseguire tutti i [test di accettazione](validation.md): runtime,
   persistenza dopo restart, DNS, privacy storage, guasti e ripristino.
2. Verificare accesso storage OAuth privato riuscito e denial esterno
   autenticato, senza aprire lo storage.
3. Confermare nuove run e nuovi campioni dopo ogni ripristino.
4. Registrare risultati, run ID, UTC ed evidenze nel perimetro autorizzato.
5. Disabilitare il logging dettagliato temporaneo e rimuovere soltanto
   i componenti di test autorizzati.
6. Ottenere l'accettazione sulla base dei risultati completi.
   In presenza di test FAIL o INCOMPLETI, registrare causa e azione richiesta
   senza dichiarare completata la soluzione.
