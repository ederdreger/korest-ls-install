# KoreST License — instalação

Instala o **KoreST License** (servidor de licenças do KoreST, By @SpedyNet) num **Ubuntu Server 24.04** com um comando:

```bash
curl -fsSL https://raw.githubusercontent.com/ederdreger/korest-ls-install/main/install.sh | sudo bash
```

O instalador pede na tela o token de leitura do GitHub, o domínio, o e-mail do certificado e a chave privada,
confere tudo e instala o resto sozinho (Docker, KoreST License, certificado HTTPS com renovação automática e
atualizações). Rodar de novo atualiza para a última versão.

Este repositório tem só o `install.sh`. Ele não tem nada secreto: o sistema fica num repositório privado e só é
baixado com o token.
