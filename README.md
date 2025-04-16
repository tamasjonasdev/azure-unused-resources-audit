🧾 Leírás

Ez a PowerShell szkript egy Azure Automation Account környezetében futtatható, és célja, hogy az Azure előfizetésekben található nem használt vagy költséget termelő erőforrásokat (például nem hozzárendelt IP-címeket, leállított, de nem dealokált VM-eket stb.) összegyűjtse, majd egy részletes jelentést küldjön e-mailben.

Ellenőrzött erőforrástípusok:

- Hozzá nem rendelt Public IP-címek

- Hozzá nem rendelt Managed Diszkek

- Hozzá nem rendelt Network Interface-ek

- Nem használt Network Security Group-ok

- Leállított, de nem dealokált virtuális gépek

Ez segít az Azure környezet költséghatékony karbantartásában és az "elfelejtett" erőforrások kiszűrésében.

⚙️ Használat / Beállítás
1. Előfeltételek
Azure Automation Account létrehozva

PowerShell Runbook létrehozva és a szkript feltöltve

A Runbook System Assigned Managed Identity jogosultsággal rendelkezik, és minden célzott előfizetésben hozzá van rendelve a megfelelő szerepkörrel:

Reader

Network Contributor (a NIC és NSG olvasásához)

A következő PowerShell modulok telepítve az Automation Account alá:

Az.Accounts

Az.Network

Az.Compute

💡 Fontos: a modulokat az Automation Account → Modules menüpontban tudod hozzáadni. Célszerű ugyanazon verzióból (vagy egymással kompatibilisből) használni őket.

2. Automation Variables létrehozása

- Név	Típus	Leírás
- SmtpServer	String	SMTP szerver címe (pl. smtp.office365.com)
- SmtpPort	String	SMTP port (pl. 587)
- SmtpFrom	String	Feladó e-mail címe
- SmtpTo	String	Címzett(ek) e-mail címe(i), vesszővel elválasztva
- CompanyName	String	Cégnév, megjelenik a riportban és tárgyban
- SubscriptionIds	String	Az ellenőrizni kívánt előfizetés ID-k, vesszővel vagy pontosvesszővel elválasztva

3. Credential létrehozása

- Név Típus	Leírás
- SmtpCredential	PSCredential	Az SMTP szerver hitelesítéséhez szükséges felhasználónév és jelszó

4. Runbook futtatása
A Runbook kézzel vagy ütemezve is futtatható. Sikeres futás után a megadott e-mail cím(ek)re részletes riport érkezik a nem használt vagy költséget termelő Azure erőforrásokról.
