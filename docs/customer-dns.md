# Configurare il DNS: laboratorio e resolver aziendali

[Indice](../README.md) | [Creazione](runbook.md) | [Prova runtime](validation.md)

Compilare i parametri DNS e ottenere l'approvazione del responsabile rete
prima di modificare resolver, zone o forwarding.
Eseguire i comandi Windows DNS come amministratore sul server indicato,
non sul client Azure CLI.

## 1. Compilare i parametri e scegliere il percorso

Registrare per ciascun namespace l'autorita', i resolver, gli IP,
la VNet collegata, il TTL e il responsabile.

| Namespace | Configurazione da definire |
|---|---|
| Target aziendali | Mantenere l'autorita' sul DNS aziendale |
| `health.poc.internal`, solo laboratorio | Creare la zona sul server Windows dedicato |
| Dominio effettivo ASE | Usare Azure Private DNS oppure il DNS aziendale, con record app e SCM |
| Blob/Queue/Table | Inoltrare verso Azure e risolvere gli IP dei PE dalle zone private |
| Azure Monitor | Inoltrare verso Azure e risolvere gli IP del PE AMPLS |

1. Per usare resolver aziendali, seguire la sezione 4.
   Non installare un simulatore DNS aggiuntivo.
2. Per un laboratorio autonomo, seguire la sezione 2.
3. In entrambi i percorsi configurare il dominio ASE secondo la sezione 3
   e completare le verifiche della sezione 5.
4. Non sostituire zone aziendali con zone di laboratorio vuote.
   Non creare copie scollegate o discordanti della stessa zona.
5. Per resolver ridondati verificare gli stessi record su entrambi.
   Non usare il secondario per correggere una risposta NXDOMAIN del primario.

## 2. Simulatore Windows in Azure

### 2.1. Preparare la VM dedicata

1. Creare una VM Windows privata secondo il
   [piano di rete](architecture.md), senza IP pubblico.
2. Assegnare sulla NIC Azure un IP privato statico.
   Negli esempi sostituire `10.60.2.4` con l'IP assegnato.
3. Collegare le zone private alla VNet del forwarder.
4. Autorizzare UDP e TCP 53 da ASE e dai client di verifica su NSG e
   firewall Windows. Verificare il percorso di ritorno.
5. Verificare l'accesso amministrativo e l'installazione dei componenti
   usando il resolver Azure iniziale.
6. Non impostare il DNS custom della VNet prima che il servizio DNS risponda.

### 2.2. Installare il servizio e creare i record

Sulla nuova VM dedicata, sostituire IP e namespace prima dell'esecuzione:

```powershell
$ErrorActionPreference = 'Stop'
$installation = Install-WindowsFeature DNS -IncludeManagementTools
if (-not $installation.Success) { throw 'Installazione DNS fallita' }
Set-DnsServerForwarder -IPAddress 168.63.129.16
Add-DnsServerPrimaryZone -Name health.poc.internal -ZoneFile health.poc.internal.dns
Add-DnsServerResourceRecordA -ZoneName health.poc.internal -Name svc-a -IPv4Address 10.60.2.4 -TimeToLive (New-TimeSpan -Seconds 60)
Add-DnsServerResourceRecordA -ZoneName health.poc.internal -Name svc-b -IPv4Address 10.60.2.4 -TimeToLive (New-TimeSpan -Seconds 60)
```

1. Verificare il servizio DNS avviato e il successo dell'installazione.
2. Prima di rieseguire i comandi, controllare se zona e record esistono.
   Non sovrascrivere una configurazione esistente.
3. Usare il forwarder globale verso `168.63.129.16` soltanto sul server
   di laboratorio dedicato in Azure. Non applicarlo al DNS aziendale.
4. In caso di blocco verso Azure DNS, correggere le regole autorizzate.
   Non sostituire il forwarder con un DNS Internet.

### 2.3. Configurare il client DNS della VM

Dopo l'installazione, impostare il client della VM sul proprio servizio.
Sostituire l'IP nel comando:

```powershell
$ErrorActionPreference = 'Stop'
$dnsVmIp = '10.60.2.4'
$interfaces = @(Get-NetIPConfiguration | Where-Object {
    $dnsVmIp -in @($_.IPv4Address.IPAddress)
})
if ($interfaces.Count -ne 1) { throw 'Interfaccia della VM DNS non univoca' }
Set-DnsClientServerAddress -InterfaceIndex $interfaces[0].InterfaceIndex -ServerAddresses 127.0.0.1
Clear-DnsClientCache
Resolve-DnsName svc-a.health.poc.internal
Resolve-DnsName svc-b.health.poc.internal
```

Verificare la risoluzione senza `-Server`, anche per browser e richieste
HTTP della VM. Applicare questa impostazione soltanto al client della VM DNS;
non impostare `127.0.0.1` come DNS VNet o override della Logic App.

### 2.4. Verificare target e storage

Sostituire `<storage>` e l'IP DNS, quindi eseguire:

```powershell
$ErrorActionPreference = 'Stop'
Resolve-DnsName svc-a.health.poc.internal -Server 10.60.2.4
Resolve-DnsName svc-b.health.poc.internal -Server 10.60.2.4
Resolve-DnsName '<storage>.blob.core.windows.net' -Server 10.60.2.4
Resolve-DnsName '<storage>.queue.core.windows.net' -Server 10.60.2.4
Resolve-DnsName '<storage>.table.core.windows.net' -Server 10.60.2.4
```

1. Confrontare gli IP dei target con quelli della VM IIS.
2. Confrontare ciascun IP storage con la NIC del relativo PE Blob/Queue/Table.
   Non accettare un qualsiasi indirizzo privato.
3. Dopo il superamento dei controlli, impostare l'IP del server come DNS
   della VNet ASE e applicare il cambio ai client.
4. Mantenere la Logic App sul DNS della VNet, senza override non approvati.

### 2.5. Configurare un simulatore su VNet remota

Per il [laboratorio interregionale](architecture.md):

1. Creare due VNet non sovrapposte e i peering in entrambe le direzioni.
   Verificare Connected; non presumere routing transitivo.
2. Per l'esempio Sweden Central usare `10.61.2.4` come IP statico della VM.
   Sostituire tutte le occorrenze `10.60.2.4` nei comandi, nei record A
   e nei parametri `-Server`.
3. Collegare le zone storage, Monitor e ASE alla VNet del forwarder remoto
   e alle altre VNet previste. Disabilitare l'autoregistrazione.
4. Inoltrare ad `168.63.129.16` dalla VNet del forwarder Windows.
   Non usare quell'indirizzo Azure come destinazione attraverso il peering.
5. Consentire DNS UDP/TCP 53 e la porta HTTP dei target dalla subnet ASE
   alla VM remota, su NSG e firewall Windows.
6. Predisporre separatamente un client con accesso amministrativo privato.
7. Ripetere i controlli DNS, compresi app e SCM verso il VIP ASE.
   Includere il traffico interregionale nel preventivo e verificare la latenza.

Non aggiungere un Private Resolver se il forwarder Windows previsto e'
gia' raggiungibile e risolve tutte le zone richieste.

## 3. DNS dell'ASE interno

1. Acquisire dalla risorsa ASE il dominio effettivo e il VIP interno.
   Non costruire il suffisso dal nome dell'app.
2. Scegliere un'unica autorita' per la zona ASE.
3. Se si usa Azure Private DNS, creare o riutilizzare la zona del dominio
   ASE e collegarla alla VNet del resolver.
4. Aggiungere i record seguenti:

| Record relativo alla zona ASE | Tipo | Valore |
|---|---|---|
| `@` | A | VIP interno ASE |
| `*` | A | VIP interno ASE |
| `*.scm` | A | VIP interno ASE |

5. Se si usa Windows DNS o altro DNS aziendale, configurare anche il
   namespace `scm` con wildcard o subzona supportate dal prodotto.
6. Se la zona e' in Azure, configurare il forwarding dal DNS aziendale
   verso il resolver che vede la zona privata.
7. Dopo la creazione della Logic App, acquisire i FQDN effettivi app e SCM
   e verificarli dal client privato. Entrambi devono risolvere al VIP interno.
8. Non aggiungere record app `privatelink.azurewebsites.net` per questo
   percorso con VIP interno.
9. Controllare `WEBSITE_DNS_SERVER` e `WEBSITE_DNS_ALT_SERVER`.
   Rimuovere gli override non necessari; documentare quelli approvati.
10. Non usare indirizzi sorgente `172.31.192.0/25` per accedere all'ASE interno.

## 4. Collegare i resolver aziendali

### 4.1. Configurare DNS aziendali in Azure

1. Concordare gli IP di almeno due resolver, routing, peering e NSG.
2. Collegare le zone private alla VNet dei forwarder oppure predisporre
   un Private Resolver inbound raggiungibile.
3. Creare conditional forwarder per i namespace della sezione 4.3.
   Non modificare il forwarding globale dei domini aziendali.
4. Configurare la risoluzione del dominio ASE e dei target aziendali.
5. Verificare ogni FQDN su entrambi i resolver.
6. Impostare gli IP approvati come DNS della VNet ASE.
   Applicare il cambio all'app e ai client nella finestra concordata.

### 4.2. Configurare DNS on-premises

1. Predisporre VPN/ExpressRoute e routing simmetrico, senza sovrapposizioni.
2. Autorizzare UDP/TCP 53 e le porte HTTPS richieste.
3. Creare un Azure DNS Private Resolver inbound endpoint con subnet
   dedicata, oppure usare forwarder Azure privati ridondati.
4. Collegare le zone private alla VNet del componente che risolve in Azure.
5. Configurare sul DNS on-premises i conditional forwarder verso gli
   IP privati inbound/forwarder. Non inoltrare direttamente a `168.63.129.16`.
6. Mantenere authoritative sul DNS aziendale le zone dei target.
7. Se l'app usa i DNS on-premises, verificare che questi risolvano target,
   ASE, storage e Monitor.
8. Se l'app usa Azure DNS, predisporre per i domini on-premises un outbound
   endpoint e forwarding ruleset, collegato alla VNet necessaria.
   Non usare il solo inbound endpoint per la risoluzione verso on-premises.

### 4.3. Configurare i namespace e prevenire loop

1. Inoltrare i namespace pubblici storage verso Azure:
   `blob.core.windows.net`, `queue.core.windows.net`, `table.core.windows.net`.
2. Verificare la catena CNAME fino agli IP dei PE nelle zone private.
3. Per Monitor verificare la
   [tabella DNS Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-dns)
   e configurare i namespace richiesti, normalmente:
   `monitor.azure.com`, `oms.opinsights.azure.com`,
   `ods.opinsights.azure.com`, `agentsvc.azure-automation.net`,
   `blob.core.windows.net`.
4. Verificare anche gli alias effettivi di query e ingestion, inclusi
   gli endpoint `loganalytics.io`/`loganalytics.azure.com` usati.
   Confrontare gli IP finali con quelli del PE AMPLS.
5. Non limitare il controllo ai soli namespace `privatelink`:
   verificare la ricorsione completa dei FQDN usati dall'app.
6. Conservare negli URL applicativi i normali FQDN dei servizi.
   Non sostituirli con IP privati o URL `privatelink` e non usare file hosts.
7. Registrare ogni direzione di forwarding. Non rimandare da Azure outbound
   un namespace al DNS aziendale che lo inoltra allo stesso inbound Azure.
8. Non assegnare al resolver o alla VM DNS ruoli storage data-plane
   per la sola risoluzione dei nomi.

## 5. Dimostrare che il runtime usa quei DNS

### 5.1. Preparare la finestra di verifica

1. Concordare la finestra di logging e l'accesso alle evidenze.
2. Identificare subnet ASE e possibili indirizzi del proxy/resolver ASE.
3. Sincronizzare gli orologi, registrare la timezone e usare UTC nelle evidenze.
4. Sul DNS aziendale abilitare, con il responsabile, log di richieste e
   risposte UDP/TCP con IP sorgente.
5. Sul server Windows di laboratorio eseguire:

```powershell
$ErrorActionPreference = 'Stop'
New-Item -Path C:\poc -ItemType Directory -Force | Out-Null
Set-DnsServerDiagnostics -Queries $true -Answers $true -QuestionTransactions $true -ReceivePackets $true -SendPackets $true -TcpPackets $true -UdpPackets $true -WriteThrough $true -EnableLoggingToFile $true -LogFilePath C:\poc\dns.log
Get-TimeZone
```

Mantenere `QuestionTransactions` per registrare le domande ricevute e
`WriteThrough` per evitare ritardi dovuti al buffering del file.
Non accettare come evidenza un log contenente soltanto risposte.

### 5.2. Correlare DNS ed esecuzioni

1. Eseguire un workflow e annotare run ID, inizio/fine UTC e azioni HTTP.
2. Cercare le richieste dei target provenienti dalla subnet ASE.
   Se la sorgente e' il proxy/resolver ASE, identificarlo e registrarlo.
   Escludere le richieste del PC di verifica e della VM DNS stessa.
3. Registrare FQDN, sorgente, risposta DNS, IP risolto ed esito HTTP.
4. Ripetere con una modifica approvata del solo alias di laboratorio o con
   un alias nuovo per controllare l'effetto della cache.
   Verificare che il workflow utilizzi la nuova risoluzione.
5. Durante un avvio/restart controllato dell'host, cercare anche le query
   Blob/Queue/Table e confrontare le risposte con i relativi PE.
6. Controllare cache, connessioni riutilizzate, override e resolver alternativi.
   Se mancano richieste correlate, registrare INCOMPLETO e ripetere la prova
   controllata; non assegnare PASS al solo workflow riuscito.
7. Eseguire guasto DNS e ripristino secondo la
   [matrice di accettazione](validation.md#4-guasti-e-ripristino).

### 5.3. Chiudere il collaudo DNS

1. Verificare risoluzione e ripristino dei target, app/SCM, storage e Monitor.
2. Conservare run ID, timestamp UTC, log correlati e risultati nel perimetro
   autorizzato. Non pubblicare dati aziendali nella repository.
3. Disabilitare il logging dettagliato al termine della finestra.
   Sul server Windows di laboratorio eseguire:

```powershell
$ErrorActionPreference = 'Stop'
Set-DnsServerDiagnostics -EnableLoggingToFile $false
if ((Get-DnsServerDiagnostics).EnableLoggingToFile) {
    throw 'Logging DNS dettagliato ancora attivo'
}
```

4. Sul DNS aziendale ripristinare le impostazioni di logging concordate.
   Applicare retention e permessi previsti per i log conservati.

## Riferimenti tecnici

- [DNS ASE](https://learn.microsoft.com/azure/app-service/environment/networking).
- [Private Resolver ibrido](https://learn.microsoft.com/azure/dns/private-resolver-hybrid-dns).
