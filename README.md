# Laboratório local estilo ROSA

Kind + `oc` + console OpenShift + Routes. Para testar deploy de imagem (YAML → Service → Route → HTTP).

## Ordem dos scripts

Tudo em `scripts\`. Scripts com `_` são internos; o `02` já chama eles.

### Uma vez (PC novo, Docker Desktop ligado)

```powershell
cd C:\Users\augus\Desktop\openshift
.\scripts\01-install-tools.ps1      # baixa oc e kind
.\scripts\02-create-cluster.ps1     # sobe cluster, console, Routes, OLM
```

Painel: http://console.localtest.me/

### Depois, no dia a dia

```powershell
.\scripts\03-start.ps1              # ligar (depois de reboot ou 07-stop)
.\scripts\07-stop.ps1               # desligar, mantém os dados
.\scripts\08-delete-cluster.ps1     # apagar tudo
```

### Cada app que você for testar

```powershell
.\scripts\04-new-project.ps1 meuprojeto
oc apply -f seu-deployment-e-service.yaml
oc expose svc/NOME --hostname=NOME-meuprojeto.apps.localtest.me
oc get route
curl http://NOME-meuprojeto.apps.localtest.me/
```

Imagem que precisa de root:

```powershell
.\scripts\05-grant-anyuid.ps1 meuprojeto
```

Teste pronto (já validado neste PC):

```powershell
.\scripts\06-demo-deploy.ps1
```

→ http://web-complete-demo.apps.localtest.me/

## URLs

| O quê | URL |
| --- | --- |
| Console | http://console.localtest.me/ |
| Demo | http://hello-demo.apps.localtest.me/ |
| Deploy de exemplo | http://web-complete-demo.apps.localtest.me/ |

Routes: `*.apps.localtest.me`

## O que este lab cobre

`oc apply`, `oc expose` (Route), console, OLM, SCC restricted/anyuid.

`oc new-app` e build a partir de Git não rodam aqui. Use Deployment + Service + `oc expose`.
